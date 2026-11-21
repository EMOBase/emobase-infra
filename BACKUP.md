# Backup and restore

Infra owns the shared MySQL and Elasticsearch data for every stack on the
server. Back them up together: Keycloak realms, the portal genomics data and
every Directus database live in MySQL, while the searchable biological data
lives in Elasticsearch.

The portal and species files are covered in the
[cross-repo backup guide](https://github.com/EMOBase/emobase-docs/blob/main/BACKUP.md).

## MySQL

### Back up

From `infra/`:

```bash
docker compose exec -T mysql \
  sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --all-databases' \
  > emobase-mysql-$(date +%F).sql
```

`--single-transaction` gives a consistent snapshot of the InnoDB tables without
locking the server. The dump includes Keycloak, the portal database and every
Directus database.

### Restore

The import must run while Keycloak, the portal and the species stacks are
stopped, but MySQL must be running.

1. Stop all application stacks with `emobase down`.
2. Start only MySQL:

   ```bash
   cd infra
   docker compose up -d --wait mysql
   ```

3. Import the dump:

   ```bash
   docker compose exec -T mysql \
     sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
     < emobase-mysql-DATE.sql
   ```

4. If you are restoring only MySQL, start the stacks with `emobase up`. For a
   full restore, continue with Elasticsearch first.

The dump replaces the tables it contains. Databases created after the backup
remain. For a clean restore, replace the `mysql-data` volume before step 3:

```bash
docker compose stop mysql
docker compose rm -f mysql
docker volume rm emobase-infra_mysql-data
docker compose up -d --wait mysql
```

This is destructive. The volume names assume the default project name
(`emobase-infra`); check `docker volume ls` if it was changed.

## Elasticsearch

### Back up

From `infra/`, with the Elasticsearch container running. The snapshot
repository is `./es_bk`. The container runs as UID 1000, so make the bind mount
writable first, then register the repository and take a snapshot:

```bash
sudo chown -R 1000:1000 es_bk

curl -X PUT "http://127.0.0.1:${ELASTICSEARCH_HOST_PORT:-9202}/_snapshot/emobase" \
  -H "Content-Type: application/json" \
  -d '{"type":"fs","settings":{"location":"/es-bk","compress":true}}'

curl -X PUT "http://127.0.0.1:${ELASTICSEARCH_HOST_PORT:-9202}/_snapshot/emobase/full_$(date +%F)?wait_for_completion=true" \
  -H "Content-Type: application/json" \
  -d '{"indices":"*","include_global_state":true}'
```

The snapshot files are written to `es_bk/` on the host. Keep that directory
with the backup. `9202` is the default port; adjust it if
`ELASTICSEARCH_HOST_PORT` was changed.

### Restore

A snapshot can only restore into a cluster that does not already have those
indices open. For a full restore:

1. Keep the application stacks stopped; if they are running, run `emobase down`.
2. Copy the backed-up `es_bk/` directory back to `infra/es_bk/`.
3. Stop Elasticsearch, remove its data volume and start an empty cluster:

   ```bash
   cd infra
   docker compose stop elasticsearch
   docker compose rm -f elasticsearch
   docker volume rm emobase-infra_es-data
   docker compose up -d --wait elasticsearch
   ```

   This is destructive and uses the default project name; check
   `docker volume ls` if it was changed.

4. Make `es_bk` writable and register the repository in the new cluster:

   ```bash
   sudo chown -R 1000:1000 es_bk

   curl -X PUT "http://127.0.0.1:${ELASTICSEARCH_HOST_PORT:-9202}/_snapshot/emobase" \
     -H "Content-Type: application/json" \
     -d '{"type":"fs","settings":{"location":"/es-bk","compress":true}}'
   ```

5. Restore the snapshot:

   ```bash
   curl -X POST "http://127.0.0.1:${ELASTICSEARCH_HOST_PORT:-9202}/_snapshot/emobase/full_DATE/_restore?wait_for_completion=true" \
     -H "Content-Type: application/json" \
     -d '{"indices":"*","include_global_state":true}'
   ```

6. When following the full cross-repo restore, stop here: start the stacks only
   after the files and volumes are restored. If you are restoring databases
   only, run `emobase up`.

`include_global_state` also restores index templates and cluster state. Use
`false` if you only want the indices; then recreate the templates with
`es:migrate`.

If you keep the existing cluster instead of replacing its data volume, delete or
close the conflicting indices first. To restore only some indices, replace
`"indices": "*"` with a pattern such as `"genomics-*"`.

## What to keep with the database backups

- This checkout's `.env` (secrets and endpoints)
- The `mysql-data` and `es-data` volumes, if you copy volumes instead of using
  the logical dump and snapshot
- The contents of `es_bk/`
