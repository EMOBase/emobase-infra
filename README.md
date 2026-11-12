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
Keycloak is also reachable at `KEYCLOAK_PUBLIC_URL`.

Each server runs one MySQL and one Keycloak for all of its stacks. Elasticsearch
runs per stack.

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
   ./init.sh
   ```

   The script asks in order for the portal URL, shared Docker network, Keycloak
   host port, browser-facing and container-facing Keycloak URLs, shared realm
   and client ID. Every question shows a default; press Enter to accept it.
   The script reads `../emobase-portal-deploy/.env` automatically when that
   checkout exists. It generates all secrets.

   For a local trial, `./init.sh --local` uses
   `http://localhost:8081/keycloak`. For automation, pass the matching flags
   or `--yes` to accept every default without prompting.

2. Start the shared services and wait for their health checks:

   ```bash
   docker compose up -d --wait
   ```

3. Deploy the portal and species stacks. Their `init.sh` reads the shared
   values from this `.env`; see the
   [deployment guide](https://github.com/EMOBase/emobase-docs/blob/main/DEPLOYMENT.md)
   for the full order.

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

## Species database and realm

During species deployment, this stack provides:

```bash
./scripts/create-database.sh directus_tcas
./scripts/allow-origin.sh https://tcas.example.org   # shared realm
./scripts/create-realm.sh --realm ibb_tcas --origin https://tcas.example.org  # dedicated realm
```

Use the same database name as `DIRECTUS_DB_DATABASE` in the species `.env`.
The [deployment guide](https://github.com/EMOBase/emobase-docs/blob/main/DEPLOYMENT.md)
covers the full species setup order.

To remove a species database after retiring a site:

```bash
./scripts/drop-database.sh directus_tcas
```

Delete a dedicated realm in the Keycloak admin console when it is no longer
needed.

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

This starts Keycloak at `http://localhost:8081/keycloak`. For the full local
walkthrough including the portal and species stacks, see the
[EMOBase deployment guide](https://github.com/EMOBase/emobase-docs/blob/main/DEPLOYMENT.md#local-setup-no-public-server).

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
