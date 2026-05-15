data "aws_ssoadmin_instances" "main" {}

# 1. SHARED INSTALLER: This ensures CLI is installed once before anything else runs
resource "null_resource" "aws_cli_install" {
  provisioner "local-exec" {
    command = "if ! command -v aws &> /dev/null; then apk add --no-cache aws-cli; fi"
  }
}

# --- PART 1: IAM CLEANUP ---
resource "null_resource" "iam_cleanup" {
  for_each = toset(var.iam_list)
  depends_on = [null_resource.aws_cli_install] # Wait for installer

  triggers = {
    user = each.value
  }

  provisioner "local-exec" {
    command = <<EOT
      USERNAME="${each.value}"
      echo "--- IAM OFFBOARDING: $USERNAME ---"
      
      if aws iam get-user --user-name "$USERNAME" &>/dev/null; then
        echo "User found. Removing access keys..."
        KEYS=$(aws iam list-access-keys --user-name "$USERNAME" --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
        for key in $KEYS; do aws iam delete-access-key --user-name "$USERNAME" --access-key-id $key; done
        
        echo "Deleting IAM User..."
        aws iam delete-user --user-name "$USERNAME"
        echo "IAM Success."
      else
        echo "IAM User $USERNAME not found, skipping."
      fi
    EOT
  }
}

# --- PART 2: SSO CLEANUP ---
resource "null_resource" "sso_cleanup" {
  for_each = toset(var.sso_list)
  depends_on = [null_resource.aws_cli_install] # Wait for installer

  triggers = {
    email = each.value
  }

  provisioner "local-exec" {
    command = <<EOT
      EMAIL="${each.value}"
      ID_STORE="${tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]}"
      
      echo "--- SSO OFFBOARDING: $EMAIL ---"

      # Search Identity Center by UserName (Email)
      USER_ID=$(aws identitystore list-users --identity-store-id $ID_STORE \
        --filters AttributePath=UserName,AttributeValue="$EMAIL" \
        --query "Users[0].UserId" --output text 2>/dev/null || echo "None")

      if [ "$USER_ID" != "None" ] && [ "$USER_ID" != "" ]; then
        echo "SSO User ID $USER_ID found. Deleting..."
        aws identitystore delete-user --identity-store-id $ID_STORE --user-id $USER_ID
        echo "SSO Success."
      else
        echo "Email $EMAIL not found in SSO Identity Center, skipping."
      fi
    EOT
  }
}