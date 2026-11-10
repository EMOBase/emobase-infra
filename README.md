# EMOBase infrastructure (one per server)

Shared services for an EMOBase deployment server:

| Service | Purpose |
| --- | --- |
| `mysql` | One MySQL 8.0 instance for the portal, Keycloak and every species' Directus |
| `keycloak` | One Keycloak 24 instance with the shared portal realm and optional dedicated species realms |

Each server that hosts EMOBase runs its own `emobase-infra`. It provides one
MySQL and one Keycloak for every portal/species stack on **that server**. The
portal and species Directus join the shared Docker network and reach MySQL as
`mysql:3306`; services on the network reach Keycloak as `keycloak:8080`.
Keycloak also has its own browser-facing URL (`KEYCLOAK_PUBLIC_URL`), so species
authentication does not depend on the portal.

Running one MySQL and one Keycloak per server, instead of one pair per stack, is
what makes several species fit on one machine. Elasticsearch is still per stack.

```
Browser ──► portal :9080        Browser ──► Keycloak :8081
              │                               (KEYCLOAK_PUBLIC_URL)
              │
portal/species services ──► keycloak:8080 (shared network or public URL)
species Directus ─────────► mysql:3306

┌─────────────────────────────────────────────────────────┐
│ emobase-infra (one per server)                          │
│  keycloak :8081 ──► public auth endpoint                │
│  mysql :3306                                            │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- Docker Engine 24+ with Compose v2
- `python3` for the Keycloak helper scripts (`allow-origin.sh`, `create-realm.sh`)
- The Keycloak public URL decided before the first start
- The portal URL, if this server runs a portal

## Quick start

1. Generate `.env`:

   ```bash
   ./init.sh \
     --portal-server https://portal.example.org \
     --keycloak-public-url https://auth.example.org/keycloak
   ```

   For a local trial, `./init.sh --local` uses
   `http://localhost:8081/keycloak`. The script reads
   `../emobase-portal-deploy/.env` automatically when that checkout exists,
   otherwise use `--portal-server`. It generates all secrets.

2. Start the shared services and wait for their health checks:

   ```bash
   docker compose up -d --wait
   ```

3. Deploy the portal with
   [`emobase-portal-deploy`](https://github.com/EMOBase/emobase-portal-deploy). Its `init.sh` reads
   `MYSQL_ROOT_PASSWORD`, `KEYCLOAK_PUBLIC_URL`, `KEYCLOAK_INTERNAL_URL`,
   `KEYCLOAK_REALM`, `KEYCLOAK_CLIENT_ID` and `KEYCLOAK_CLIENT_SECRET` from this
   `.env`, so the two stacks cannot drift.

The Keycloak admin console is at `${KEYCLOAK_PUBLIC_URL}/admin/`, using
`KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD` from this `.env`. The seeded
realm user (`COCO_USERNAME` / `COCO_PASSWORD`) can sign in to every portal and
species site on this server; its password is temporary and must be changed on
first login.

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
   [`emobase-deploy/README.md`](https://github.com/EMOBase/emobase-deploy/blob/dev/README.md).

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
| `KEYCLOAK_PUBLIC_URL` | Browser-facing Keycloak issuer for the portal and species |
| `KEYCLOAK_INTERNAL_URL` | Container-facing Keycloak URL on the shared network |
| `KEYCLOAK_HOST_PORT` | Host port where Keycloak is published |
| `KEYCLOAK_REALM` | Portal and shared-realm species |
| `KEYCLOAK_CLIENT_ID` | Portal and shared-realm species |
| `KEYCLOAK_CLIENT_SECRET` | Portal and shared-realm species |
| `COCO_USERNAME` / `COCO_PASSWORD` | Shared-realm seed user |
| `PORTAL_PUBLIC_SERVER` | Initial portal redirect origin (if this server runs a portal) |
| `EMOBASE_INFRA_NETWORK` | External Docker network name |

Keep `PORTAL_PUBLIC_SERVER` equal to the portal's `PUBLIC_SERVER` when this
server runs a portal. On a species-only server it can be any initial origin
(for example the first species URL); additional origins are added with
`scripts/allow-origin.sh`.

## Local trial

```bash
./init.sh --local
docker compose up -d --wait
```

This uses `http://localhost:9080` as the portal URL and
`http://localhost:8081/keycloak` as the Keycloak URL. Then follow the local
walkthrough in the
[EMOBase deployment guide](https://github.com/EMOBase/emobase-docs/blob/main/DEPLOYMENT.md#local-setup-no-public-server).
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

This destroys this server's databases and all local Keycloak users:

```bash
docker compose down -v
```

Only do this when the data can be lost.

## Notes

- The MySQL port is not published on the host. Attach administration or backup
  containers to the `emobase-infra` network, or use `docker compose exec`.
- Run one `emobase-infra` per server. MySQL and Keycloak are not shared between
  servers; a species on another server uses that server's own infra.
- Keycloak is published on `KEYCLOAK_HOST_PORT` and has its own public URL
  (`KEYCLOAK_PUBLIC_URL`). Put a TLS reverse proxy in front in production.
- `keycloak/ibb-realm.json` uses Keycloak's environment substitution for
  `${PORTAL_PUBLIC_SERVER}`, `${KEYCLOAK_REALM}`, `${KEYCLOAK_CLIENT_ID}`,
  `${KEYCLOAK_CLIENT_SECRET}`, `${COCO_USERNAME}` and `${COCO_PASSWORD}`.
