resource "aws_iam_user" "offboarded" {
  for_each      = toset(var.user_list)
  name          = each.value
  force_destroy = true 
}

data "aws_ssoadmin_instances" "main" {}

resource "null_resource" "sso_offboarding" {
  for_each = toset(var.user_list)

  triggers = {
    user = each.value
  }

  provisioner "local-exec" {
    command = <<EOT
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