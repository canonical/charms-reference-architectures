# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "aws_region" {
  description = "AWS region of the bucket, the IAM user and the Elastic IPs. null: the aws provider's default (AWS_REGION or the CLI profile)."
  type        = string
  default     = null
}

variable "cos_model" {
  description = "Name of the model created for COS Lite."
  type        = string
  default     = "cos"
}

variable "k8s_cloud" {
  description = "Kubernetes cloud that hosts both models. null: the controller's default cloud."
  type        = string
  default     = null
}

variable "k8s_credential" {
  description = "Controller credential for k8s_cloud. null: a credential named like k8s_cloud, which is what juju add-k8s creates."
  type        = string
  default     = null
}

variable "load_balancer" {
  description = "Expose the Valkey primary on an internet-facing NLB with one Elastic IP per subnet, reachable only from allowed_cidrs. eks_cluster names the cluster behind k8s_cloud. subnet_ids are public subnets of its VPC, at most one per availability zone. null: no load balancer."
  type = object({
    allowed_cidrs = list(string)
    eks_cluster   = string
    subnet_ids    = list(string)
  })
  default = null

  validation {
    condition = var.load_balancer == null || (
      length(var.load_balancer.allowed_cidrs) > 0 &&
      alltrue([for c in var.load_balancer.allowed_cidrs : can(cidrhost(c, 0))])
    )
    error_message = "load_balancer.allowed_cidrs must hold at least one valid CIDR, such as 203.0.113.4/32."
  }

  validation {
    condition     = var.load_balancer == null || length(var.load_balancer.subnet_ids) > 0
    error_message = "load_balancer.subnet_ids must hold at least one public subnet ID."
  }
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
