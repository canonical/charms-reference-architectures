
variable "cos" {
  description = "Configuration for the Charmed Observability Stack (COS)"
  type = object({
    model  = optional(string, "k8s")
    channel = optional(string, "2/edge")
    use_tls = optional(bool, false)
  })
  default = {
    model   = "k8s"
    channel = "2/edge"
    use_tls = false
  }
}

variable "etcd" {
  description = "etcd app definition"
  type = object({
    app_name          = optional(string, "etcd")
    model             = optional(string, "vm")
    base              = optional(string, "ubuntu@24.04")
    config            = optional(map(string), {})
    channel           = optional(string, "3.6/edge")
    revision          = optional(string, null)
    units             = optional(number, 3)
    constraints       = optional(string, "arch=amd64")
    machines          = optional(set(string), null)
    storage           = optional(map(string), {})
    endpoint_bindings = optional(map(string), {})
    expose            = optional(bool, false)
  })
}


variable "backups-integrator" {
  description = "Configuration for the backup integrator"
  type = object({
    storage_type = optional(string, "s3")
    config       = map(string)
    channel      = optional(string, "latest/edge")
    base         = optional(string, "ubuntu@22.04")
    revision     = optional(string, null)
    constraints  = optional(string, "arch=amd64")
    machines     = optional(set(string), [])
  })

  validation {
    condition     = contains(["s3", "azure-storage"], var.backups-integrator.storage_type)
    error_message = "backup-integrator allows one of the values: 's3', 'azure' for storage_type."
  }

  validation {
    condition     = length(var.backups-integrator.machines) <= 1
    error_message = "Machine count should be at most 1"
  }
}

variable "grafana-agent" {
  description = "Configuration for the grafana-agent"
  type = object({
    channel     = optional(string, "1/stable")
    revision    = optional(string, null)
    base        = optional(string, "ubuntu@24.04")
    constraints = optional(string, "arch=amd64")
    config      = optional(map(string), {})
  })
  default = {
    channel = "1/stable"
  }
}
