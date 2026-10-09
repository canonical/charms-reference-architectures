# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "aws_region" {
  description = "AWS region of the bucket and the IAM user. null: the aws provider's default (AWS_REGION or the CLI profile)."
  type        = string
  default     = null
}

variable "cos_model" {
  description = "Name of the model created for COS Lite."
  type        = string
  default     = "cos"
}

variable "external_access" {
  description = "Expose Valkey's TLS ports on the units' public IPs, reachable only from allowed_cidrs. vpc_id is the VPC the controller puts models in: its private subnets are kept out of the Valkey model. extra_sans adds names or IPs, such as those public IPs, to every unit's server certificate. null: not exposed."
  type = object({
    allowed_cidrs = list(string)
    vpc_id        = string
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

variable "s3_bucket" {
  description = "Name of the S3 bucket created for Valkey backups."
  type        = string
}

variable "s3_key_version" {
  description = "Version of the IAM access key handed to s3-integrator. Increment to rotate it."
  type        = number
  default     = 1

  validation {
    condition     = var.s3_key_version >= 1 && floor(var.s3_key_version) == var.s3_key_version
    error_message = "s3_key_version must be a whole number of at least 1."
  }
}

variable "s3_path" {
  description = "Object prefix inside the bucket where Valkey writes backups."
  type        = string
  default     = "valkey"
}

variable "valkey_model" {
  description = "Name of the model created for Valkey, its integrators and self-signed-certificates."
  type        = string
  default     = "valkey"
}
