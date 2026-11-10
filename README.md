# EMOBase shared infrastructure

Shared services for an EMOBase deployment server:

| Service | Purpose |
| --- | --- |
| `mysql` | One MySQL 8.0 instance for the portal, Keycloak and every species' Directus |
| `keycloak` | One Keycloak 24 instance with the shared portal realm and optional dedicated species realms |

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
- `python3` for the Keycloak helper scripts (`allow-origin.sh`, `create-realm.sh`)
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
   `MYSQL_ROOT_PASSWORD`, `KEYCLOAK_REALM`, `KEYCLOAK_CLIENT_ID` and
   `KEYCLOAK_CLIENT_SECRET` from this `.env`, so the two stacks cannot drift.

The Keycloak admin console is at
`<PORTAL_PUBLIC_SERVER>/ibb/keycloak/admin/`, using `KEYCLOAK_ADMIN` and
`KEYCLOAK_ADMIN_PASSWORD` from this `.env`. The seeded realm user
(`COCO_USERNAME` / `COCO_PASSWORD`) can sign in to every portal and species
site; its password is temporary and must be changed on first login.

## Keycloak realm strategy

The portal always uses the shared realm from this `.env` (`KEYCLOAK_REALM`,
default `ibb`) and its client (`KEYCLOAK_CLIENT_ID`, default `ibb-client`).
Each species can choose one of two models during `emobase-deploy/init.sh`:

- **Shared realm** — reuse the portal's realm. One team manages users for the
  portal and every species. Register the species origin once:

  ```bash
  ./scripts/allow-origin.sh https://tcas.example.org
  ```

- **Dedicated realm** — create a separate realm with its own client and seed
  `coco` user. Use this when different people manage each website. The species
  `init.sh` creates it automatically, or you can do it manually:

  ```bash
  ./scripts/create-realm.sh --realm ibb_tcas --origin https://tcas.example.org
  ```

  A dedicated realm has its own users and administrators. The portal realm is
  unaffected.

## Adding a species

1. Create its own Directus database:

   ```bash
   ./scripts/create-database.sh directus_tcas
   ```

   Use the same name as `DIRECTUS_DB_DATABASE` in the species `.env`.
   `emobase-deploy/init.sh` derives `directus_<species>` automatically.

2. Run the species `init.sh`. It prompts for the Keycloak realm strategy:

   - choose shared and then run `allow-origin.sh` for the species URL;
   - choose dedicated and the realm/client/user are created for you.

3. Start the species stack. See
   [`../emobase-deploy/README.md`](../emobase-deploy/README.md).

To remove a species database after retiring a site:

```bash
./scripts/drop-database.sh directus_tcas
```

This permanently deletes the database and asks for confirmation. Delete a
dedicated realm in the Keycloak admin console if it is no longer needed.

## Environment values shared with the deploy stacks

The deploy stacks' `init.sh` reads these from this `.env`:

| Variable | Used by |
| --- | --- |
| `MYSQL_ROOT_PASSWORD` | Portal genomics API/workers and species Directus |
| `KEYCLOAK_REALM` | Portal and shared-realm species |
| `KEYCLOAK_CLIENT_ID` | Portal and shared-realm species |
| `KEYCLOAK_CLIENT_SECRET` | Portal and shared-realm species |
| `COCO_USERNAME` / `COCO_PASSWORD` | Shared-realm seed user |
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
If the local species uses the shared realm, register its origin before signing
in; a dedicated realm is configured by the species `init.sh`:

```bash
./scripts/allow-origin.sh http://localhost:9090
```

## Backups

The MySQL data volume contains the portal genomics data, the Keycloak realm and
every species' Directus data. Back up the whole instance:

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
