locals {
  user_map = { for u in var.user_list : u => u }
}

import {
  for_each = local.user_map
  id       = each.value
  to       = aws_iam_user.offboarded[each.key]
}

resource "aws_iam_user" "offboarded" {
  for_each      = local.user_map
  name          = each.value
  force_destroy = true 
}

data "aws_ssoadmin_instances" "main" {}

resource "null_resource" "sso_offboarding" {
  for_each = local.user_map

  triggers = {
    user = each.value
  }

  provisioner "local-exec" {
    command = <<EOT
      # Check if AWS CLI exists, if not, download portable version
      if ! command -v aws &> /dev/null; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -q awscliv2.zip
        ./aws/install -i ./aws-cli -b ./bin
        export PATH=$PATH:$(pwd)/bin
      fi

      ID_STORE="${tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]}"
      
      USER_ID=$(aws identitystore list-users \
        --identity-store-id $ID_STORE \
        --filters AttributePath=UserName,AttributeValue=${each.value} \
        --query "Users[0].UserId" --output text)

      if [ "$USER_ID" != "None" ] && [ "$USER_ID" != "" ]; then
        echo "Deleting SSO User: ${each.value} ($USER_ID)"
        aws identitystore delete-user --identity-store-id $ID_STORE --user-id $USER_ID
      else
        echo "SSO User ${each.value} not found, skipping."
      fi
    EOT
  }
}