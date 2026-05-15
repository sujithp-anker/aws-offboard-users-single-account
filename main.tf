locals {
  iam_user_list  = compact(split(",", replace(var.iam_users, " ", "")))
  sso_email_list = compact(split(",", replace(var.sso_emails, " ", "")))
}

module "user_offboarding" {
  source    = "./modules/aws-offboarding"
  iam_list  = local.iam_user_list
  sso_list  = local.sso_email_list
  region    = var.region
}