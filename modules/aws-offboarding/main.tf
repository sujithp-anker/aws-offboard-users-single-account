data "aws_ssoadmin_instances" "main" {}

resource "null_resource" "search_and_destroy_users" {
  for_each = toset(var.user_list)

  triggers = {
    user = each.value
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      
      # 1. INSTALLER WITH TIMEOUT AND ERROR HANDLING
      if [ ! -f "$(pwd)/aws-cli-bin/aws" ]; then
        if mkdir "install_lock" 2>/dev/null; then
          # Ensure we cleanup if something goes wrong
          trap 'rmdir install_lock 2>/dev/null' EXIT
          
          echo "Installing AWS CLI for Alpine..."
          # Download the V2 CLI specifically for Linux x86_64
          curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
          unzip -q awscliv2.zip
          
          # Use the 'dist' folder directly - it's more reliable than the installer script
          mkdir -p aws-cli-bin
          cp -r aws/dist/* aws-cli-bin/
          
          rm -rf aws awscliv2.zip
          touch "install_complete"
          rmdir "install_lock"
        else
          echo "Waiting for AWS CLI installation..."
          # Wait up to 60 seconds
          MAX_WAIT=30
          COUNT=0
          while [ ! -f "install_complete" ] && [ $COUNT -lt $MAX_WAIT ]; do 
            sleep 2
            COUNT=$((COUNT+1))
          done
        fi
      fi

      # 2. DEFINE BINARY (Use the absolute path to the main binary)
      # In some Alpine setups, we need to call the interpreter directly
      AWS_BIN="$(pwd)/aws-cli-bin/aws"
      chmod +x $AWS_BIN

      # 3. SETUP VARIABLES
      USERNAME="${each.value}"
      ID_STORE="${tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]}"

      echo "--- Processing Offboarding for: $USERNAME ---"

      # 4. IAM DELETION
      IAM_CHECK=$($AWS_BIN iam get-user --user-name "$USERNAME" --query 'User.UserName' --output text 2>/dev/null || echo "NOT_FOUND")
      
      if [ "$IAM_CHECK" = "$USERNAME" ]; then
        echo "Found IAM User. Deleting Keys..."
        KEYS=$($AWS_BIN iam list-access-keys --user-name "$USERNAME" --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
        for key in $KEYS; do
          $AWS_BIN iam delete-access-key --user-name "$USERNAME" --access-key-id $key
        done
        $AWS_BIN iam delete-user --user-name "$USERNAME"
        echo "IAM User $USERNAME deleted."
      else
        echo "IAM User $USERNAME not found."
      fi

      # 5. SSO DELETION
      USER_ID=$($AWS_BIN identitystore list-users \
        --identity-store-id $ID_STORE \
        --filters AttributePath=UserName,AttributeValue="$USERNAME" \
        --query "Users[0].UserId" --output text 2>/dev/null || echo "None")

      if [ "$USER_ID" != "None" ] && [ "$USER_ID" != "" ]; then
        echo "Found SSO User ID: $USER_ID. Deleting..."
        $AWS_BIN identitystore delete-user --identity-store-id $ID_STORE --user-id $USER_ID
        echo "SSO User $USERNAME deleted."
      else
        echo "SSO User $USERNAME not found in Identity Center."
      fi
    EOT
  }
}