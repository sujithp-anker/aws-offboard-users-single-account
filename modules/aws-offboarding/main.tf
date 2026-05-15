data "aws_ssoadmin_instances" "main" {}

locals {
  identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]
}

import {
  for_each = toset(var.user_list)
  id       = each.value
  to       = aws_iam_user.offboarded[each.key]
}

resource "aws_iam_user" "offboarded" {
  for_each = toset(var.user_list)
  name     = each.value
  
  force_destroy = true
}

data "aws_identitystore_user" "lookup" {
  for_each          = toset(var.user_list)
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = each.value
    }
  }
}

import {
  for_each = data.aws_identitystore_user.lookup
  id       = "${local.identity_store_id}/${each.value.user_id}"
  to       = aws_identitystore_user.offboarded[each.key]
}

resource "aws_identitystore_user" "offboarded" {
  for_each          = data.aws_identitystore_user.lookup
  identity_store_id = local.identity_store_id
  user_name         = each.value.user_name
  
  display_name = each.value.display_name
  name {
    given_name  = each.value.name[0].given_name
    family_name = each.value.name[0].family_name
  }
}