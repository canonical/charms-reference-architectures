# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "cos_model" {
  description = "Name of the model created for COS Lite."
  type        = string
  default     = "cos"
}

variable "external_access" {
  description = "Expose Valkey's TLS ports on the units' public IPs, reachable only from allowed_cidrs. extra_sans adds names or IPs, such as those public IPs, to every unit's server certificate. null: not exposed."
  type = object({
    allowed_cidrs = list(string)
    extra_sans    = optional(list(string), [])
  })
  default = null

  validation {
    condition = var.external_access == null || (
      length(var.external_access.allowed_cidrs) > 0 &&
      alltrue([for c in var.external_access.allowed_cidrs : can(cidrhost(c, 0))])
    )
    error_message = "external_access.allowed_cidrs must hold at least one valid CIDR, such as 203.0.113.4/32."
  }
}

variable "gcp_project" {
  description = "GCP project that holds the bucket and the service account. null: the google provider's default (GOOGLE_PROJECT)."
  type        = string
  default     = null
}

variable "gcs_bucket" {
  description = "Name of the GCS bucket created for Valkey backups."
  type        = string

  # gcs-integrator accepts a narrower set than GCS itself.
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.gcs_bucket))
    error_message = "gcs_bucket must be 3-63 characters and contain only lowercase letters, digits, and hyphens."
  }
}

variable "gcs_key_version" {
  description = "Version of the service-account key handed to gcs-integrator. Increment to rotate: a generated key is replaced, and a supplied key is pushed again."
  type        = number
  default     = 1

  validation {
    condition     = var.gcs_key_version >= 1 && floor(var.gcs_key_version) == var.gcs_key_version
    error_message = "gcs_key_version must be a whole number of at least 1."
  }
}

variable "gcs_location" {
  description = "GCS bucket location, a region or a multi-region."
  type        = string
  default     = "US"
}

variable "gcs_path" {
  description = "Object prefix inside the bucket where Valkey writes backups."
  type        = string
  default     = "valkey"
}

variable "gcs_service_account_email" {
  description = "Email of an existing service account to use instead of creating one. Set it together with gcs_service_account_key. null: create a service account and a key."
  type        = string
  default     = null
}

variable "gcs_service_account_key" {
  description = "JSON key of gcs_service_account_email. Supply through TF_VAR_gcs_service_account_key, at plan and at apply. Never written to state."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null

  validation {
    condition     = (var.gcs_service_account_key == null) == (var.gcs_service_account_email == null)
    error_message = "Set gcs_service_account_email and gcs_service_account_key together, or leave both unset to create a service account."
  }
}

variable "k8s_cloud" {
  description = "Kubernetes cloud on the controller that hosts the COS Lite model."
  type        = string
}

variable "k8s_credential" {
  description = "Controller credential for k8s_cloud. null: a credential named like k8s_cloud, which is what juju add-k8s creates."
  type        = string
  default     = null
}

variable "machine_cloud" {
  description = "Machine cloud that hosts the Valkey model. null: the controller's default cloud."
  type        = string
  default     = null
}

variable "machine_credential" {
  description = "Controller credential for machine_cloud. null: the controller's default credential for that cloud."
  type        = string
  default     = null
}

variable "risk" {
  description = "Risk level of the Valkey, COS Lite and integrator channels (edge, beta, candidate or stable)."
  type        = string
  default     = "edge"
}

variable "valkey_model" {
  description = "Name of the model created for Valkey, its integrators and self-signed-certificates."
  type        = string
  default     = "valkey"
}
