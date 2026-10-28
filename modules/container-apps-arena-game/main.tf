terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

# Endpoints, credentials and subscription are supplied by `locally run` via
# ARM_* environment variables (ARM_ENVIRONMENT=custom, ARM_RESOURCE_MANAGER_ENDPOINT,
# ARM_CLIENT_ID/SECRET, ARM_SUBSCRIPTION_ID, ...). Run this with:
#     locally run terraform apply
provider "azurerm" {
  features {}
}

locals {
  # Storage account names are 3-24 lowercase alphanumerics, so strip any hyphens
  # from the prefix. They're also globally unique, so "aca" keeps this one from
  # clashing with the other arena game examples deployed with the same prefix.
  storage_account_name = "${replace(var.prefix, "-", "")}acasa"

  # Where the persistent leaderboard share is mounted inside the container.
  leaderboard_mount_path = "/mnt/leaderboard"
}

resource "azurerm_resource_group" "arena" {
  name     = "${var.prefix}-rg"
  location = var.location
}

# ---------------------------------------------------------------------------
# Log Analytics — the workspace the Container App Environment ships console logs
# to. Furnace forwards each container's stdout/stderr to this workspace (keyed by
# the environment's Log Analytics customer id), so they are KQL-queryable as
# ContainerAppConsoleLogs_CL, in addition to Furnace's own log page:
#   ContainerAppConsoleLogs_CL | order by TimeGenerated desc
# The workspace is a real, queryable resource in Locally (Dashboard ->
# Monitoring -> Workspaces).
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "arena" {
  name                = "${var.prefix}-law"
  resource_group_name = azurerm_resource_group.arena.name
  location            = azurerm_resource_group.arena.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
}

# ---------------------------------------------------------------------------
# Container App Environment — the managed environment the app runs in.
# log_analytics_workspace_id (+ logs_destination) is the faithful wiring; see
# the Log Analytics note above for what actually carries logs today.
# ---------------------------------------------------------------------------
resource "azurerm_container_app_environment" "arena" {
  name                       = "${var.prefix}-env"
  resource_group_name        = azurerm_resource_group.arena.name
  location                   = azurerm_resource_group.arena.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.arena.id
  logs_destination           = "log-analytics"
}

# ---------------------------------------------------------------------------
# Storage — an Azure Files share that persists the leaderboard, the same way the
# App Service example does. The share is registered on the environment as a
# named storage, then mounted into the container through a template volume.
# Furnace resolves the volume -> environment storage -> (account, share) chain
# and bind-mounts the REAL emulated share (the same directory the Storage
# emulator materialises it under: <configDir>/storage/files/<account>/<share>),
# so the container's writes ARE the share's bytes — persistent across revision
# restarts and shareable across replicas. (The access key is required by the
# provider but unused: the emulated mount is a shared host directory, not an SMB
# session.)
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "arena" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.arena.name
  location                 = azurerm_resource_group.arena.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_share" "arena" {
  name               = "leaderboard"
  storage_account_id = azurerm_storage_account.arena.id
  quota              = 1
}

resource "azurerm_container_app_environment_storage" "arena" {
  name                         = "leaderboard"
  container_app_environment_id = azurerm_container_app_environment.arena.id
  account_name                 = azurerm_storage_account.arena.name
  share_name                   = azurerm_storage_share.arena.name
  access_key                   = azurerm_storage_account.arena.primary_access_key
  access_mode                  = "ReadWrite"
}

# ---------------------------------------------------------------------------
# Container App — the arena game as a single custom container.
#
# The image is the published web-arena-game build, pulled straight from Docker
# Hub (it's public, so there's no registry or credentials). The server listens
# on :3000 and serves both HTTP and the /ws
# WebSocket on the same origin — external ingress with target_port = 3000 and
# transport = "auto" is reverse-proxied by Furnace, which tunnels the WebSocket
# upgrade. The client connects to /ws same-origin, so no BASE_URL is needed for
# gameplay.
# ---------------------------------------------------------------------------
resource "azurerm_container_app" "arena" {
  name                         = "${var.prefix}-arena"
  resource_group_name          = azurerm_resource_group.arena.name
  container_app_environment_id = azurerm_container_app_environment.arena.id
  revision_mode                = "Single"

  template {
    container {
      name   = "arena"
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      # Persist the leaderboard onto the mounted Azure Files share. The server
      # reads LEADERBOARD_FILE at startup.
      env {
        name  = "LEADERBOARD_FILE"
        value = "${local.leaderboard_mount_path}/leaderboard.json"
      }

      volume_mounts {
        name = "leaderboard"
        path = local.leaderboard_mount_path
      }
    }

    # The AzureFile volume references the environment storage by name; Furnace
    # resolves that to the (account, share) and bind-mounts the emulated share.
    volume {
      name         = "leaderboard"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.arena.name
    }
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
