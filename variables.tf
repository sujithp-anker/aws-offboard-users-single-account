variable "Users" {
  type        = string
  description = "Comma-separated list of usernames to remove"
}

variable "cross_account_role_arn" {
  type        = string
  description = "Optional: IAM role to assume. Leave empty to use Gaia credentials directly."
  default     = "" 
}

variable "region" {
  type    = string
  default = "us-east-1"
}