data "aws_ssoadmin_instances" "main" {}

resource "null_resource" "search_and_destroy_users" {
  for_each = toset(var.user_list)

  triggers = {
    user = each.value
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      
      # 1. Singleton Installer Logic (Prevents parallel race conditions)
      # We use a directory as a primitive lock
      if [ ! -d "aws-cli-bin" ]; then
        if mkdir "install_lock" 2>/dev/null; then
          echo "Installing AWS CLI..."
          curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
          unzip -q awscliv2.zip
          mkdir -p aws-cli-bin
          # Move the actual binary to a known location
          mv aws/dist/* aws-cli-bin/
          rm -rf aws awscliv2.zip install_lock
        else
          # Wait for the other process to finish the installation
          echo "Waiting for AWS CLI installation to complete..."
          while [ ! -d "aws-cli-bin" ]; do sleep 2; done
        fi
      fi

      # Add the new bin folder to PATH
      export PATH=$PATH:$(pwd)/aws-cli-bin

      # 2. Setup Variables
      USERNAME="${each.value}"
      ID_STORE="${tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]}"

      echo "--- Processing Offboarding for: $USERNAME ---"

      # 3. Handle IAM User Deletion
      # We use 'aws' directly from our bin folder
      IAM_CHECK=$(aws iam get-user --user-name "$USERNAME" --query 'User.UserName' --output text 2>&1 || true)
      
      if [ "$IAM_CHECK" = "$USERNAME" ]; then
        echo "Found IAM User. Deleting Access Keys and User..."
        KEYS=$(aws iam list-access-keys --user-name "$USERNAME" --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
        for key in $KEYS; do
          aws iam delete-access-key --user-name "$USERNAME" --access-key-id $key
        done
        aws iam delete-user --user-name "$USERNAME"
        echo "IAM User $USERNAME deleted successfully."
      else
        echo "IAM User $USERNAME not found, skipping."
      fi

      # 4. Handle SSO / Identity Center Deletion
      USER_ID=$(aws identitystore list-users \
        --identity-store-id $ID_STORE \
        --filters AttributePath=UserName,AttributeValue="$USERNAME" \
        --query "Users[0].UserId" --output text)

      if [ "$USER_ID" != "None" ] && [ "$USER_ID" != "" ]; then
        echo "Found SSO User ID: $USER_ID. Deleting..."
        aws identitystore delete-user --identity-store-id $ID_STORE --user-id $USER_ID
        echo "SSO User $USERNAME deleted successfully."
      else
        echo "SSO User $USERNAME not found in Identity Store, skipping."
      fi
    EOT
  }
}