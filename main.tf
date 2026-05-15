locals {
  user_list = compact(split(",", replace(var.Users, " ", "")))
}

module "user_offboarding" {
  source    = "./modules/aws-offboarding"
  user_list = local.user_list
  
  region                 = var.region
  cross_account_role_arn = var.cross_account_role_arn
}