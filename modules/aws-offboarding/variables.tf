variable "user_list" {
  type        = list(string)
  description = "List of users to search and destroy"
}

variable "cross_account_role_arn" {
  type    = string
  default = ""
}

variable "region" {
  type    = string
}