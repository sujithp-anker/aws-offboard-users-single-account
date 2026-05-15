variable "Users" {
  type        = string
  description = "Comma-separated list of usernames to remove (e.g., john.doe, jane.smith)"
}

variable "cross_account_role_arn" {
  type        = string
  description = "The ARN of the IAM role to assume in the target account"
}

variable "region" {
  type    = string
  default = "us-east-1"
}