data "aws_ssoadmin_instances" "main" {}

resource "null_resource" "search_and_destroy_users" {
  for_each = toset(var.user_list)

  triggers = {
    user = each.value
  }

  provisioner "local-exec" {
    command = <<EOT
      # 1. NATIVE ALPINE INSTALLER
      if ! command -v aws &> /dev/null; then
        if mkdir "install_lock" 2>/dev/null; then
          echo "Installing AWS CLI via Alpine Package Manager..."
          # Install python3 and aws-cli (v1) which works perfectly on Alpine
          apk add --no-cache aws-cli
          touch "install_complete"
          rmdir "install_lock"
        else
          echo "Waiting for CLI..."
          COUNT=0
          while [ ! -f "install_complete" ] && [ $COUNT -lt 30 ]; do sleep 2; COUNT=$((COUNT+1)); done
        fi
      fi

      USERNAME="${each.value}"
      ID_STORE="${tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]}"

      echo "--- DELETING: $USERNAME ---"
      
      # 2. IAM DELETE (Using native 'aws' command now)
      if aws iam get-user --user-name "$USERNAME" &>/dev/null; then
        echo "User $USERNAME found in IAM. Cleaning up..."
        KEYS=$(aws iam list-access-keys --user-name "$USERNAME" --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
        for key in $KEYS; do 
          aws iam delete-access-key --user-name "$USERNAME" --access-key-id $key
        done
        aws iam delete-user --user-name "$USERNAME"
        echo "IAM User $USERNAME deleted successfully."
      else
        echo "IAM User $USERNAME not found."
      fi

      # 3. SSO DELETE
      USER_ID=$(aws identitystore list-users --identity-store-id $ID_STORE --filters AttributePath=UserName,AttributeValue="$USERNAME" --query "Users[0].UserId" --output text 2>/dev/null || echo "None")

      if [ "$USER_ID" != "None" ] && [ "$USER_ID" != "" ]; then
        echo "SSO User found ($USER_ID). Deleting..."
        aws identitystore delete-user --identity-store-id $ID_STORE --user-id $USER_ID
        echo "SSO User $USERNAME deleted successfully."
      else
        echo "SSO User $USERNAME not found in Identity Store."
      fi

      exit 0
    EOT
  }
}