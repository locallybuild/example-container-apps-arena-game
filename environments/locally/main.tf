module "container-apps-arena-game" {
  source = "../../modules/container-apps-arena-game"

  prefix   = "locally-demo"
  location = "berlin"
}

output "arena_url" {
  value = module.container-apps-arena-game.arena_url
}
