variable "prefix" {
  description = "Name prefix for all resources."
  type        = string
  default     = "locally-demo"
}

variable "location" {
  description = "Locally region name (e.g. berlin)."
  type        = string
  default     = "berlin"
}

variable "image" {
  description = "The arena game image the container app runs, pulled from Docker Hub. The default is a multi-arch build (linux/amd64 and linux/arm64) of github.com/tombuildsstuff/web-arena-game."
  type        = string
  default     = "docker.io/tombuildsstuff/web-arena-game:2.0.0"
}

variable "cpu" {
  description = "vCPU allocation for the container. Must pair with memory per Azure Container Apps rules (e.g. 0.5 vCPU -> 1Gi)."
  type        = number
  default     = 0.5
}

variable "memory" {
  description = "Memory allocation for the container. Must pair with cpu (e.g. 0.5 vCPU -> 1Gi)."
  type        = string
  default     = "1Gi"
}

variable "log_retention_days" {
  description = "Log Analytics workspace retention in days."
  type        = number
  default     = 30
}
