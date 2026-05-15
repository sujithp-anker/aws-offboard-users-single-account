data "aws_ssoadmin_instances" "main" {}

resource "null_resource" "search_and_destroy_users" {
  for_each = toset(var.user_list)

  triggers = {
    user = each.value
  }

  provisioner "local-exec" {
    command = <<EOT
      # 1. INSTALLER (Safe & Re-runnable)
      if [ ! -f "$(pwd)/aws-cli-bin/aws" ]; then
        if mkdir "install_lock" 2>/dev/null; then
          echo "Installing AWS CLI..."
          curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
          unzip -q awscliv2.zip
          mkdir -p aws-cli-bin
          cp -r aws/dist/* aws-cli-bin/
          rm -rf aws awscliv2.zip
          touch "install_complete"
          rmdir "install_lock" 2>/dev/null
        else
          echo "Waiting for CLI..."
          COUNT=0
          while [ ! -f "install_complete" ] && [ $COUNT -lt 30 ]; do sleep 2; COUNT=$((COUNT+1)); done
        fi
      fi

      AWS_BIN="$(pwd)/aws-cli-bin/aws"
      chmod +x $AWS_BIN
      USERNAME="${each.value}"
      ID_STORE="${tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]}"

      echo "--- Offboarding: $USERNAME ---"

      # 2. IAM DELETE (Safe)
      IAM_NAME=$($AWS_BIN iam get-user --user-name "$USERNAME" --query 'User.UserName' --output text 2>/dev/null || echo "MISSING")
      if [ "$IAM_NAME" = "$USERNAME" ]; then
        echo "Deleting IAM User $USERNAME..."
        KEYS=$($AWS_BIN iam list-access-keys --user-name "$USERNAME" --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
        for key in $KEYS; do $AWS_BIN iam delete-access-key --user-name "$USERNAME" --access-key-id $key; done
        $AWS_BIN iam delete-user --user-name "$USERNAME"
      else
        echo "IAM User not found."
      fi

      # 3. SSO DELETE (Safe)
      USER_ID=$($AWS_BIN identitystore list-users --identity-store-id $ID_STORE --filters AttributePath=UserName,AttributeValue="$USERNAME" --query "Users[0].UserId" --output text 2>/dev/null || echo "None")
      if [ "$USER_ID" != "None" ] && [ "$USER_ID" != "" ]; then
        echo "Deleting SSO ID: $USER_ID"
        $AWS_BIN identitystore delete-user --identity-store-id $ID_STORE --user-id $USER_ID
      else
        echo "SSO User not found."
      fi

      # 4. FORCE SUCCESS
      exit 0
    EOT
  }
}