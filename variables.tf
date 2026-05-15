variable "iam_users" {
  type        = string
  description = "Comma-separated list of IAM usernames (e.g., mohit, service-account-1)"
  default     = ""
}

variable "sso_emails" {
  type        = string
  description = "Comma-separated list of SSO Emails (e.g., john.doe@ankercloud.com)"
  default     = ""
}

variable "cross_account_role_arn" {
  type        = string
  description = "Optional: IAM role to assume."
  default     = ""
}

variable "region" {
  type    = string
  default = "us-east-1"
}