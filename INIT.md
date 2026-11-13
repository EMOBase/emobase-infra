# `init.sh` reference

`init.sh` generates `emobase-infra/.env`. It configures the MySQL/Keycloak
runtime only. It does not create a Keycloak realm or an application database.

## Quick run

```bash
./init.sh
```

Every question shows a default. Press Enter to accept it.

## Prompt order

| Question | Default |
| --- | --- |
| Shared Docker network | `emobase-infra` |
| Keycloak host port | `8081` |
| Browser-facing Keycloak URL | detected host IPv4, or localhost with `--local` |
| Container-facing Keycloak URL | `http://keycloak:8080/keycloak` |

The browser-facing URL must end with `/keycloak`.

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
EMOBASE_INFRA_NETWORK=...
MYSQL_ROOT_PASSWORD=...
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=...
KEYCLOAK_JAVA_OPTS="-Xms256m -Xmx768m"
```

`MYSQL_ROOT_PASSWORD` and `KEYCLOAK_ADMIN_PASSWORD` are generated. No realm,
client, `coco` user or application database is created here.

## Flags

| Flag | Meaning |
| --- | --- |
| `--local` | Use localhost for the Keycloak URL |
| `--keycloak-public-url URL` | Browser-facing Keycloak base URL |
| `--keycloak-internal-url URL` | Keycloak URL used by containers |
| `--keycloak-host-port PORT` | Host port for Keycloak |
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
./init.sh --keycloak-public-url http://192.168.64.5:8081/keycloak
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
   application database.
3. Deploy species stacks. They join an existing realm or create their own.

See [DEPLOYMENT.md](https://github.com/EMOBase/emobase-docs/blob/main/DEPLOYMENT.md)
for the full order and
[REALMS.md](https://github.com/EMOBase/emobase-docs/blob/main/REALMS.md) for
realm ownership.
