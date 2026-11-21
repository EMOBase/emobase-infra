# EMOBase infrastructure (one per server)

Runtime services for an EMOBase deployment server:

| Service | Purpose |
| --- | --- |
| `mysql` | One MySQL 8.0 instance for Keycloak, the portal and every species' Directus |
| `keycloak` | One Keycloak 24 instance; realms are owned by the portal and species stacks |
| `elasticsearch` | One Elasticsearch 8.17 instance for the portal and every species' search indices |

Each server that hosts EMOBase runs its own `emobase-infra`. It provides one
MySQL, Keycloak and Elasticsearch for every portal/species stack on **that
server**. The portal and species stacks join the shared Docker network and
reach MySQL as `mysql:3306`, Keycloak as `keycloak:8080` and Elasticsearch as
`elasticsearch:9200`. Keycloak is also reachable at `KEYCLOAK_PUBLIC_URL`.

Infra owns no realm or application database. Keycloak starts with only its
`master` realm; the portal and species stacks create and own the realms,
clients, users and databases they need. Elasticsearch is shared: each stack
writes only indices under its own prefix.

```
Browser ──► portal :9080        Browser ──► Keycloak :8181
              │                               (KEYCLOAK_PUBLIC_URL)
              │
portal/species services ──► keycloak:8080 (shared network or public URL)
species Directus ─────────► mysql:3306
portal/species services ──► elasticsearch:9200 (shared network)
species es-proxy ─────────► elasticsearch:9200 (local alias es)
```

Elasticsearch is not published on the LAN. Its host port is bound to
`127.0.0.1` for administration and backup only. Species application services
reach it through a local `es-proxy` sidecar, so they are not attached to the
shared network. The proxy isolates networks; it does not restrict which indices
a species container can query.

## Prerequisites

- Docker Engine 24+ with Compose v2
- `python3` for the Keycloak helper scripts (`create-realm.sh`,
  `allow-origin.sh`, `create-database.sh`)
- The Keycloak public URL decided before the first start

## Quick start

```bash
./init.sh
docker compose up -d --wait
```

Then deploy the portal and species stacks. Infra creates no realm or
application database.

- [Deployment guide](https://github.com/EMOBase/emobase-docs/blob/main/DEPLOYMENT.md)
- [Operations](https://github.com/EMOBase/emobase-docs/blob/main/OPERATIONS.md)
- [`init.sh` reference](INIT.md)
- [Realm ownership](https://github.com/EMOBase/emobase-docs/blob/main/REALMS.md)
- [Backups](BACKUP.md)

The Keycloak admin console is at `${KEYCLOAK_PUBLIC_URL}/admin/`, using
`KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD` from this `.env`.

Elasticsearch is at `http://127.0.0.1:${ELASTICSEARCH_HOST_PORT:-9202}` on the
Docker host (loopback only).

## Keycloak realms

Infra owns no realm. Portal and species stacks own their realms and credentials.
The generic helpers are `scripts/create-realm.sh`,
`scripts/delete-realm.sh` and `scripts/allow-origin.sh`.

`delete-realm.sh --yes REALM` is used by `emobase prune` after the owning
checkout has been removed. It refuses to delete the `master` realm.

See [Realm ownership](https://github.com/EMOBase/emobase-docs/blob/main/REALMS.md)
for the menu, flags and migration rules.

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

## Elasticsearch

The portal writes `genomics-*` indices
(`EMOBASE_GENOMICS_ELASTICSEARCH__INDEX_PREFIX`). Each species stack writes
`<prefix>-*` indices; the species checkout's `init.sh` sets its
`EMOBASE_ES_INDEX_PREFIX`, and the deploy Compose file maps it to each
service's index-prefix property.

To delete one species' indices after retiring a site:

```bash
./scripts/delete-es-indices.sh --yes tcas
```

The helper deletes only `<prefix>-*`; other species and the portal are
untouched. `emobase species remove --purge` and `emobase prune` call it
automatically after the stack is gone.

Do not change a prefix after the first start unless you also migrate or delete
the old indices: the services would create a second, empty set.

## Environment values shared with the deploy stacks

The deploy stacks' `init.sh` reads these from this `.env`:

| Variable | Used by |
| --- | --- |
| `MYSQL_ROOT_PASSWORD` | Portal genomics API/workers and species Directus |
| `KEYCLOAK_PUBLIC_URL` | Browser-facing Keycloak issuer for the portal and species |
| `KEYCLOAK_INTERNAL_URL` | Container-facing Keycloak URL; fixed to `http://keycloak:8080/keycloak` on the shared network |
| `KEYCLOAK_HOST_PORT` | Host port where Keycloak is published |
| `ELASTICSEARCH_HOST_PORT` | Loopback-only host port for Elasticsearch administration |
| `EMOBASE_INFRA_NETWORK` | External Docker network name |

Realm names, client credentials and seed users are not part of infra `.env`.

## Local development

```bash
./init.sh --local
docker compose up -d --wait
```

This starts Keycloak at `http://localhost:8181/keycloak`. For the full local
walkthrough including the portal and species stacks, see the
[Local development guide](https://github.com/EMOBase/emobase-docs/blob/main/DEVELOPMENT.md).

## Backups

See [BACKUP.md](BACKUP.md) for the MySQL dump, the Elasticsearch snapshot
procedure and the volumes to keep.

## Updating

```bash
git pull
docker compose pull
docker compose up -d --wait
```

MySQL, Keycloak and Elasticsearch images are pinned by tag in `compose.yml`.
Change the tag explicitly to upgrade. Back up MySQL and Elasticsearch before a
major-version upgrade.

## Reset

This destroys this server's databases, all local Keycloak realms/users and all
Elasticsearch indices:

```bash
docker compose down -v
```

Only do this when the data can be lost.

## Notes

- MySQL has no host port, and Elasticsearch binds only
  `127.0.0.1:${ELASTICSEARCH_HOST_PORT}` for administration. Attach
  administration or backup containers to the `emobase-infra` network, or use
  `docker compose exec`.
- Keycloak is published on `KEYCLOAK_HOST_PORT` and has its own public URL
  (`KEYCLOAK_PUBLIC_URL`). Put a TLS reverse proxy in front in production.
- All stacks share one Elasticsearch. Index prefixes keep their data separate;
  they are not an authorization boundary.
