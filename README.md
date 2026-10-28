```
ooooo                                      oooo  oooo              
`888'                                      `888  `888              
 888          .ooooo.   .ooooo.   .oooo.    888   888  oooo    ooo 
 888         d88' `88b d88' `"Y8 `P  )88b   888   888   `88.  .8'
 888         888   888 888        .oP"888   888   888    `88..8'
 888       o 888   888 888   .o8 d8(  888   888   888     `888'
o888ooooood8 `Y8bod8P' `Y8bod8P' `Y888""8o o888o o888o     .8'
                                                       .o..P'
                                                       `Y8P'
```

# Arena Game on Locally (Azure Container Apps)

Terraform that deploys [web-arena-game](https://github.com/tombuildsstuff/web-arena-game)
— a real-time 3D multiplayer strategy game — to a local [Locally](https://locally.build)
emulator as an Azure Container App:

- `azurerm_resource_group`
- `azurerm_log_analytics_workspace` + `azurerm_container_app_environment`
- `azurerm_storage_account` + `azurerm_storage_share` +
  `azurerm_container_app_environment_storage` — an Azure Files share, mounted into the
  container to persist the leaderboard
- `azurerm_container_app` — the game as a single custom container (a Go WebSocket
  server with the Three.js client embedded), served over external HTTPS ingress on
  port 3000, with the share mounted at `/mnt/leaderboard`

The game is one self-contained container with no database or cache, which makes it a
clean fit for a single Container App.

## The image

The game is published to Docker Hub as
[`tombuildsstuff/web-arena-game`](https://hub.docker.com/r/tombuildsstuff/web-arena-game),
a multi-arch build for `linux/amd64` and `linux/arm64`. The container app pulls
`tombuildsstuff/web-arena-game:2.0.0` straight from Docker Hub. It's a public image, so
there's no Container Registry or credentials involved, and nothing is built on your
machine. Pass `-var image=...` to run a different tag or a build of your own.

## Run

Locally must be running with the `microsoft-app`, `microsoft-operationalinsights`, and
`microsoft-storage` plugins installed. Then:

```bash
cd environments/locally
locally run terraform init
locally run terraform apply
```

`locally run` injects the `ARM_*` custom-environment credentials/endpoints so the
azurerm provider targets Locally instead of real Azure. Override defaults via `-var`
or a `terraform.tfvars` (see `modules/container-apps-arena-game/variables.tf`).

Open the `arena_url` output in a browser and pick **Play vs AI** or **Join Queue**.

## How the WebSocket works

The game is real-time over a `/ws` WebSocket (20 ticks/second state sync) — the HTTP
routes alone only serve the landing page, health, leaderboard, and static assets.

Furnace serves container apps through `httputil.NewSingleHostReverseProxy`, which
tunnels the `Connection: Upgrade` handshake, so the WebSocket connects straight
through external ingress. `target_port = 3000` matches the server's listen port, and
the client opens `/ws` on the same origin it was served from, so no `BASE_URL` is
needed for gameplay.

## Logs

The container's stdout/stderr is visible today on **Furnace's own log page** — this
works whether or not a Log Analytics workspace exists.

The config also creates a Log Analytics workspace and wires it to the environment
(`log_analytics_workspace_id` + `logs_destination`). That is the faithful Azure
Container Apps shape, and the workspace is a real resource in Locally
(Dashboard → Monitoring → Workspaces).

Furnace forwards the container's console logs to that workspace via Log Analytics'
HTTP Data Collector, so they are queryable in **Dashboard → Monitoring → Telemetry**:

```kql
ContainerAppConsoleLogs_CL | order by TimeGenerated desc
```

(Requires a Furnace build that includes the log-forwarding support.)

## Leaderboard (persistent)

The server writes its leaderboard to `LEADERBOARD_FILE`, which this config sets to
`/mnt/leaderboard/leaderboard.json` — a path backed by an Azure Files share mounted into
the container. The share is registered on the environment as a named storage
(`azurerm_container_app_environment_storage`) and mounted through a template `volume` +
the container's `volume_mounts`. Furnace resolves the volume → environment storage →
(account, share) chain and bind-mounts the **real emulated share**: the same directory the
Storage emulator materialises the share under, so the container's writes are the share's
bytes — the leaderboard survives revision restarts and `--rm` removal, and is shared across
replicas. (It is the same emulated share the App Service example mounts, so both flavours
persist to one store.)

## What works today vs. pending

| Piece | Status |
|-------|--------|
| Container app runs the custom image | ✅ works |
| External HTTPS ingress | ✅ works |
| WebSocket gameplay (`/ws`) | ✅ works (Furnace reverse proxy) |
| Container logs visible (Furnace log page) | ✅ works |
| Logs queryable in Log Analytics / Monitoring → Telemetry | ✅ works (`ContainerAppConsoleLogs_CL`) |
| Leaderboard persistence across restarts | ✅ works (Azure Files volume mount) |
| GitHub OAuth login | ⏳ follow-up (needs a registered OAuth app + `BASE_URL`) |

## Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `prefix` | `locally-demo` | Name prefix for all resources |
| `location` | `berlin` | Locally region |
| `image` | `docker.io/tombuildsstuff/web-arena-game:2.0.0` | The image the container app runs |
| `cpu` | `0.5` | vCPU allocation (pairs with `memory`) |
| `memory` | `1Gi` | Memory allocation (pairs with `cpu`) |
| `log_retention_days` | `30` | Log Analytics retention |

## Outputs

- `arena_url` — public HTTPS URL of the game
- `resource_group` — the resource group name
- `log_analytics_workspace_name` — the paired workspace (Monitoring → Workspaces)
