provider "aws" {
  region = var.region

  dynamic "assume_role" {
    for_each = var.cross_account_role_arn != "" ? [1] : []
    content {
      role_arn     = var.cross_account_role_arn
      session_name = "GaiaOffboardingSession"
    }
  }
}