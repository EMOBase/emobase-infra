# EMOBase shared infrastructure

Shared services for an EMOBase deployment server:

| Service | Purpose |
| --- | --- |
| `mysql` | One MySQL 8.0 instance for the portal, Keycloak and every species' Directus |
| `keycloak` | One Keycloak 24 instance with the shared `ibb` realm and `ibb-client` |

`emobase-portal-deploy` and each `emobase-deploy` species checkout run their
application containers only. They no longer start their own MySQL or Keycloak.
The portal joins the Docker network created by this stack and reaches both
services as `mysql:3306` and `keycloak:8080`. Species Directus joins it for
MySQL; species web/Quarkus services reach Keycloak through the portal origin,
so several species can share the network without their service names colliding.

Running one MySQL and one Keycloak instead of one pair per stack is what makes
several species fit on a single server. Elasticsearch is still per stack.

```
                    ┌──────────────────────────────┐
Browser ───────────►│ emobase-portal-deploy :9080  │
                    │  nginx ──► /ibb/keycloak/ ───┼──┐
                    └──────────────────────────────┘  │
                           ▲                          │ shared network
                           │ Keycloak via portal      │ (emobase-infra)
                    ┌──────┴───────────────────────┐  │
                    │ emobase-deploy :9090         │  │
                    │  UI / Quarkus ───────────────┘  │
                    │  Directus ──────────────────────┼──► mysql
                    └──────────────────────────────┘  │
                                                      ▼
                    ┌─────────────────────────────────────────┐
                    │ emobase-infra                           │
                    │  keycloak :8080  ◄──────────────────────┘
                    │  mysql :3306    ◄── species Directus    │
                    └─────────────────────────────────────────┘
```

The portal nginx is the only public entrypoint for Keycloak, at
`<PORTAL_PUBLIC_SERVER>/ibb/keycloak/`. Species sites use the portal's public
issuer and therefore redirect to the portal origin during login.

## Prerequisites

- Docker Engine 24+ with Compose v2
- `python3` for the optional `scripts/allow-origin.sh` helper
- The public portal URL decided before the first start

## Quick start

1. Generate `.env`:

   ```bash
   ./init.sh --portal-server https://portal.example.org
   ```

   The script reads `../emobase-portal-deploy/.env` automatically when that
   checkout exists, otherwise use `--portal-server`. It generates all secrets.

2. Start the shared services and wait for their health checks:

   ```bash
   docker compose up -d --wait
   ```

3. Deploy the portal with
   [`../emobase-portal-deploy`](../emobase-portal-deploy). Its `init.sh` reads
   `MYSQL_ROOT_PASSWORD` and `KEYCLOAK_CLIENT_SECRET` from this `.env`, so the
   two stacks cannot drift.

The Keycloak admin console is at
`<PORTAL_PUBLIC_SERVER>/ibb/keycloak/admin/`, using `KEYCLOAK_ADMIN` and
`KEYCLOAK_ADMIN_PASSWORD` from this `.env`. The seeded realm user
(`COCO_USERNAME` / `COCO_PASSWORD`) can sign in to every portal and species
site; its password is temporary and must be changed on first login.

## Adding a species

Each species deployment needs:

1. Its own Directus database:

   ```bash
   ./scripts/create-database.sh directus_tcas
   ```

   Use the same name as `DIRECTUS_DB_DATABASE` in the species `.env`.
   `emobase-deploy/init.sh` derives `directus_<species>` automatically.

2. Its public origin registered as a valid Keycloak redirect:

   ```bash
   ./scripts/allow-origin.sh https://tcas.example.org
   ```

   This updates `ibb-client` in the shared `ibb` realm. Run it once per species,
   before users sign in there. It is safe to run repeatedly.

Then run the species `init.sh` and start its stack. See
[`../emobase-deploy/README.md`](../emobase-deploy/README.md).

To remove a species database after retiring a site:

```bash
./scripts/drop-database.sh directus_tcas
```

This permanently deletes the database and asks for confirmation.

## Environment values shared with the deploy stacks

The deploy stacks' `init.sh` reads these from this `.env`:

| Variable | Used by |
| --- | --- |
| `MYSQL_ROOT_PASSWORD` | Portal genomics API/workers and species Directus |
| `KEYCLOAK_CLIENT_SECRET` | Portal, species UI and Quarkus services |
| `PORTAL_PUBLIC_SERVER` | Confirms the portal URL and Keycloak issuer |
| `EMOBASE_INFRA_NETWORK` | External Docker network name |

Keep `PORTAL_PUBLIC_SERVER` exactly equal to the portal's `PUBLIC_SERVER`
(scheme, host, port, no trailing slash).

## Local trial

```bash
./init.sh --local
docker compose up -d --wait
```

This uses `http://localhost:9080` as the portal URL. Then follow the local
walkthrough in
[`../emobase-portal-deploy/DEPLOYMENT.md`](../emobase-portal-deploy/DEPLOYMENT.md).
Before signing in to the local species site, register its origin:

```bash
./scripts/allow-origin.sh http://localhost:9090
```

## Migrating an existing deployment

This change moves shared state into new volumes. Before removing the old
containers, dump the databases you want to keep:

```bash
# Old portal stack (genomics + its Keycloak realm)
cd ../emobase-portal-deploy
docker compose exec -T mysql \
  sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --databases emobase_genomics keycloak' \
  > portal.sql

# Old species stack (Directus)
cd ../emobase-deploy
docker compose exec -T mysql \
  sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --databases directus' \
  > directus.sql
```

Start this stack, then import the dumps with
`docker compose exec -T mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" < file.sql`.
The old per-stack Keycloak databases cannot be merged automatically: keep one
realm (usually the portal's) or recreate users, and register each species origin
with `scripts/allow-origin.sh`.

## Backups

The MySQL data volume now contains the portal genomics data, the Keycloak
realm and every species' Directus data. Back up the whole instance:

```bash
docker compose exec -T mysql \
  sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases' \
  > emobase-mysql-$(date +%F).sql
```

Also keep this repository's `.env` (secrets) and the `mysql-data` volume.

Keycloak configuration (realm, users created after import) lives in MySQL. The
`keycloak/ibb-realm.json` file is only imported when the realm does not exist;
later changes belong in the admin console.

## Updating

```bash
git pull
docker compose pull
docker compose up -d --wait
```

MySQL and Keycloak images are pinned by tag in `compose.yml`. Change the tag
explicitly to upgrade. Back up MySQL before a major-version upgrade.

## Reset

This destroys the shared databases and all Keycloak users:

```bash
docker compose down -v
```

Only do this when the data can be lost.

## Notes

- The MySQL port is not published on the host. Attach administration or backup
  containers to the `emobase-infra` network, or use `docker compose exec`.
- To let a deploy stack on another Docker host use this MySQL/Keycloak, publish
  the ports and change `EMOBASE_GENOMICS_MYSQL__HOST` / the Keycloak URL in that
  stack. The default setup assumes one Docker host.
- `keycloak/ibb-realm.json` uses Keycloak's environment substitution for
  `${PORTAL_PUBLIC_SERVER}`, `${KEYCLOAK_CLIENT_SECRET}`, `${COCO_USERNAME}`
  and `${COCO_PASSWORD}`.
