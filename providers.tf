provider "aws" {
  region = var.region
  assume_role {
    role_arn = var.cross_account_role_arn
  }
}