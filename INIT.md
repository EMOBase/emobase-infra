# `init.sh` reference

`init.sh` generates the checkout's `.env`. It configures the
MySQL/Keycloak/Elasticsearch runtime only. It does not create a Keycloak realm,
an application database or any Elasticsearch index.

## Quick run

```bash
./init.sh
```

Every question shows a default. Press Enter to accept it. An invalid
interactive answer is rejected and the question is asked again. Values passed
as flags are validated once; an invalid flag stops the script.

## Prompt order

| Question | Default |
| --- | --- |
| Shared Docker network | `emobase-infra` |
| Keycloak host port | `8181` |
| Elasticsearch host port | `9202` |
| Browser-facing Keycloak URL | detected host IPv4, or localhost with `--local` |

The browser-facing URL must end with `/keycloak`.

`KEYCLOAK_INTERNAL_URL` is not asked for: it is always
`http://keycloak:8080/keycloak`, because infra's own Compose service is
`keycloak` on the shared network. Pass `--keycloak-internal-url` only to
override it for an unusual setup.

Without `--local`, the default browser URL uses the machine's primary IPv4
address. This is the address used for the default route, not necessarily a
public NAT address. Enter the public IP or domain when the server is behind NAT.

With `--local`, the browser URL uses `localhost`.

## Generated values

The script writes:

```dotenv
KEYCLOAK_PUBLIC_URL=...
KEYCLOAK_INTERNAL_URL=...
KEYCLOAK_HOST_PORT=...
ELASTICSEARCH_HOST_PORT=...
EMOBASE_INFRA_NETWORK=...
MYSQL_ROOT_PASSWORD=...
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=...
KEYCLOAK_JAVA_OPTS="-Xms256m -Xmx768m"
ELASTICSEARCH_JAVA_OPTS="-Xms512m -Xmx512m"
ELASTICSEARCH_MEM_LIMIT=1g
```

`MYSQL_ROOT_PASSWORD` and `KEYCLOAK_ADMIN_PASSWORD` are generated. No realm,
client, `coco` user, application database or index is created here.

`ELASTICSEARCH_HOST_PORT` is bound to `127.0.0.1` only, for administration and
backup. Applications always use `elasticsearch:9200` on the shared network.
Raise `ELASTICSEARCH_JAVA_OPTS` and `ELASTICSEARCH_MEM_LIMIT` together when the
server has enough RAM; keep the limit above the heap size.

## Flags

| Flag | Meaning |
| --- | --- |
| `--local` | Use localhost for the Keycloak URL |
| `--keycloak-public-url URL` | Browser-facing Keycloak base URL |
| `--keycloak-internal-url URL` | Override the fixed container-facing Keycloak URL (default `http://keycloak:8080/keycloak`) |
| `--keycloak-host-port PORT` | Host port for Keycloak |
| `--elasticsearch-host-port PORT` | Loopback-only host port for Elasticsearch |
| `--infra-network NAME` | Shared Docker network |
| `-y`, `--yes` | Accept defaults without prompting |
| `-f`, `--force` | Overwrite an existing `.env` |
| `-p`, `--print` | Print the file instead of writing it |
| `-h`, `--help` | Show help |

## Examples

Local trial:

```bash
./init.sh --local
```

Server with a direct IP:

```bash
./init.sh --keycloak-public-url http://192.168.64.5:8181/keycloak
```

Server with TLS:

```bash
./init.sh --keycloak-public-url https://auth.example.org/keycloak
```

Unattended:

```bash
./init.sh --yes
```

## What to do next

1. Start infra:

   ```bash
   docker compose up -d --wait
   ```

2. Deploy the portal. It owns its Keycloak realm and creates the first
   application database. It writes indices under the `genomics` prefix.
3. Deploy species stacks. They join an existing realm or create their own, and
   write indices under their own `EMOBASE_ES_INDEX_PREFIX`.

See [DEPLOYMENT.md](https://github.com/EMOBase/emobase-docs/blob/main/DEPLOYMENT.md)
for the full order and
[REALMS.md](https://github.com/EMOBase/emobase-docs/blob/main/REALMS.md) for
realm ownership.
