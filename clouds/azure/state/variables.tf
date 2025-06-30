
variable "RESOURCE_GROUP_NAME" {
  description = "The name of the Azure resource group"
  type        = string
  default     = "tfstate-rg" # Default resource group name
}

variable "REGION" {
  type    = string
  default = "eastus"
}

variable "AZURE_SUBSCRIPTION_ID" {
  type      = string
  sensitive = true
}

variable "STORAGE_ACCOUNT_NAME" {
  description = "The name of the Azure storage account for Terraform state"
  type        = string
  default     = "tfstate" # Default storage account name. A random suffix will be added to ensure uniqueness.
}
