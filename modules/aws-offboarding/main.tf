data "aws_ssoadmin_instances" "main" {}

resource "null_resource" "search_and_destroy_users" {
  for_each = toset(var.user_list)

  triggers = {
    user = each.value
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      
      # 1. ROBUST INSTALLER LOGIC
      # We use a 'done' file as the ultimate signal that installation is finished
      if [ ! -f "$(pwd)/aws-installed/bin/aws" ]; then
        if mkdir "install_lock" 2>/dev/null; then
          echo "Downloading Bundled AWS CLI (this may take a minute)..."
          curl -s "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
          unzip -q awscli-bundle.zip
          
          echo "Executing bundled installer..."
          # Install to a local directory in the workspace
          ./awscli-bundle/install -i $(pwd)/aws-installed -b $(pwd)/aws-installed/bin
          
          rm -rf awscli-bundle awscli-bundle.zip
          touch "install_complete"
          rmdir "install_lock"
        else
          echo "Waiting for another process to finish AWS CLI installation..."
          while [ ! -f "install_complete" ]; do sleep 5; done
        fi
      fi

      # 2. DEFINE ABSOLUTE PATH
      AWS_BIN="$(pwd)/aws-installed/bin/aws"

      # 3. SETUP VARIABLES
      USERNAME="${each.value}"
      ID_STORE="${tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]}"

      echo "--- Processing Offboarding for: $USERNAME ---"

      # 4. IAM DELETION
      # Use absolute path and redirect stderr to avoid shell 'not found' crashes
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