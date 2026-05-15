variable "user_list" {
  type        = list(string)
  description = "Cleaned list of usernames to be offboarded"
}

variable "cross_account_role_arn" {
  type        = string
  description = "The ARN of the IAM role to assume in the target account"
}

variable "region" {
  type        = string
  description = "AWS region for the operations"
}