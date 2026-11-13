# EMOBase infrastructure (one per server)

Runtime services for an EMOBase deployment server:

| Service | Purpose |
| --- | --- |
| `mysql` | One MySQL 8.0 instance for Keycloak, the portal and every species' Directus |
| `keycloak` | One Keycloak 24 instance; realms are owned by the portal and species stacks |

Each server that hosts EMOBase runs its own `emobase-infra`. It provides one
MySQL and one Keycloak for every portal/species stack on **that server**. The
portal and species stacks join the shared Docker network and reach MySQL as
`mysql:3306`; services on the network reach Keycloak as `keycloak:8080`.
Keycloak is also reachable at `KEYCLOAK_PUBLIC_URL`.

Infra owns no application data. Keycloak starts with only its `master` realm;
the portal and species stacks create and own the realms, clients, users and
databases they need.

```
Browser ──► portal :9080        Browser ──► Keycloak :8081
              │                               (KEYCLOAK_PUBLIC_URL)
              │
portal/species services ──► keycloak:8080 (shared network or public URL)
species Directus ─────────► mysql:3306
```

## Prerequisites

- Docker Engine 24+ with Compose v2
- `python3` for the Keycloak helper scripts (`create-realm.sh`,
  `allow-origin.sh`, `create-database.sh`)
- The Keycloak public URL decided before the first start

## Quick start

1. Generate `.env`:

   ```bash
   ./init.sh
   ```

   The script asks for the shared Docker network, Keycloak host port and the
   browser-facing and container-facing Keycloak URLs. Every question shows a
   default; press Enter to accept it. It generates the MySQL root and Keycloak
   admin secrets. It does not ask for or create a realm.

   Without `--local`, URLs default to the detected host IPv4 address. If this
   server is behind NAT, enter its public IP or domain instead.

2. Start the shared services and wait for their health checks:

   ```bash
   docker compose up -d --wait
   ```

3. Deploy the portal and species stacks. Their `init.sh` reads the shared MySQL
   and Keycloak URLs from this `.env`; see the
   [deployment guide](https://github.com/EMOBase/emobase-docs/blob/main/DEPLOYMENT.md)
   for the full order.

The Keycloak admin console is at `${KEYCLOAK_PUBLIC_URL}/admin/`, using
`KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD` from this `.env`.

## Keycloak realms

Infra deliberately owns no realm. The portal creates the first realm with its
own values. A species can then join any realm with local credentials or create
a new independent realm. The realm owner stores the realm/client/seed
credentials in its own `.env`.

The infra scripts are generic helpers used by the owning stack:

```bash
./scripts/create-realm.sh \
  --realm emobase-portal \
  --origin https://portal.example.org \
  --client-id emobase-portal-client \
  --client-secret "$KEYCLOAK_CLIENT_SECRET" \
  --coco-username coco \
  --coco-password "$COCO_PASSWORD"

./scripts/allow-origin.sh \
  --realm emobase-portal \
  --client-id emobase-portal-client \
  https://tcas.example.org
```

`create-realm.sh` creates or updates a realm/client and is idempotent.
`allow-origin.sh` only adds another origin to an existing client.

## Databases

Infra creates only the `keycloak` database. The portal and species create their
own databases:

```bash
./scripts/create-database.sh emobase_genomics
./scripts/create-database.sh directus_tcas
```

Use the matching database names from the portal/species `.env` files. To remove
a species database after retiring a site:

```bash
./scripts/drop-database.sh directus_tcas
```

## Environment values shared with the deploy stacks

The deploy stacks' `init.sh` reads these from this `.env`:

| Variable | Used by |
| --- | --- |
| `MYSQL_ROOT_PASSWORD` | Portal genomics API/workers and species Directus |
| `KEYCLOAK_PUBLIC_URL` | Browser-facing Keycloak issuer for the portal and species |
| `KEYCLOAK_INTERNAL_URL` | Container-facing Keycloak URL on the shared network |
| `KEYCLOAK_HOST_PORT` | Host port where Keycloak is published |
| `EMOBASE_INFRA_NETWORK` | External Docker network name |

Realm names, client credentials and seed users are not part of infra `.env`.

## Local trial

```bash
./init.sh --local
docker compose up -d --wait
```

This starts Keycloak at `http://localhost:8081/keycloak`. For the full local
walkthrough including the portal and species stacks, see the
[EMOBase deployment guide](https://github.com/EMOBase/emobase-docs/blob/main/DEPLOYMENT.md#local-setup-no-public-server).

## Backups

The MySQL data volume contains the portal genomics data, Keycloak realms/users
and every species' Directus data. Back up the whole instance:

```bash
docker compose exec -T mysql \
  sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases' \
  > emobase-mysql-$(date +%F).sql
```

Also keep this repository's `.env` (secrets) and the `mysql-data` volume.

## Updating

```bash
git pull
docker compose pull
docker compose up -d --wait
```

MySQL and Keycloak images are pinned by tag in `compose.yml`. Change the tag
explicitly to upgrade. Back up MySQL before a major-version upgrade.

## Reset

This destroys this server's databases and all local Keycloak realms/users:

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
- Keycloak starts with only the `master` realm. The portal/species stacks create
  and own application realms.
