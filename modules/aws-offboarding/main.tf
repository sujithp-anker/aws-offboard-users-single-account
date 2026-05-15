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
          COUNT=0
          while [ ! -f "install_complete" ] && [ $COUNT -lt 30 ]; do sleep 2; COUNT=$((COUNT+1)); done
        fi
      fi

      # 2. PREPARE ENVIRONMENT
      AWS_BIN="$(pwd)/aws-cli-bin/aws"
      chmod +x $AWS_BIN
      
      # FIX FOR ALPINE: Tell the binary where its libraries are
      export LD_LIBRARY_PATH=$(pwd)/aws-cli-bin:$LD_LIBRARY_PATH
      
      USERNAME="${each.value}"
      ID_STORE="${tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]}"

      echo "--- DEBUG START: $USERNAME ---"
      
      # 3. VERBOSE IAM DELETE
      echo "Checking IAM for $USERNAME..."
      # Removing 2>/dev/null so we can see actual AccessDenied or other errors
      IAM_USER_DATA=$($AWS_BIN iam get-user --user-name "$USERNAME" --query 'User.UserName' --output text)
      
      if [ "$?" -eq 0 ]; then
        echo "User $USERNAME exists in IAM. Attempting deletion..."
        
        # List and delete keys - capturing errors
        KEYS=$($AWS_BIN iam list-access-keys --user-name "$USERNAME" --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
        for key in $KEYS; do 
          echo "Deleting key $key..."
          $AWS_BIN iam delete-access-key --user-name "$USERNAME" --access-key-id $key
        done
        
        # Delete the user
        $AWS_BIN iam delete-user --user-name "$USERNAME"
        echo "Command executed. Verifying..."
        $AWS_BIN iam get-user --user-name "$USERNAME" || echo "CONFIRMED: IAM User is gone."
      else
        echo "IAM Search failed or User not found."
      fi

      # 4. VERBOSE SSO DELETE
      echo "Checking SSO Identity Store for $USERNAME..."
      USER_ID=$($AWS_BIN identitystore list-users --identity-store-id $ID_STORE --filters AttributePath=UserName,AttributeValue="$USERNAME" --query "Users[0].UserId" --output text)

      if [ "$USER_ID" != "None" ] && [ "$USER_ID" != "" ]; then
        echo "Found SSO User ID: $USER_ID. Deleting..."
        $AWS_BIN identitystore delete-user --identity-store-id $ID_STORE --user-id $USER_ID
        echo "SSO Delete command sent."
      else
        echo "SSO User $USERNAME not found in store $ID_STORE."
      fi

      echo "--- DEBUG END: $USERNAME ---"
      exit 0
    EOT
  }
}