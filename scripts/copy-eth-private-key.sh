#!/bin/bash

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
SOURCE_SECRET_NAME="${SOURCE_SECRET_NAME}"
DEST_SECRET_NAME="${DEST_SECRET_NAME}"
DEST_REGION="${DEST_REGION}"

print_status "Copying secret: $SOURCE_SECRET_NAME -> $DEST_SECRET_NAME"

# Step 1: Pull secret from first account
print_status "Step 1: Pulling secret from source (e.g., current) AWS account..."
SOURCE_SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "$SOURCE_SECRET_NAME" \
    --query 'SecretString' \
    --output text)

if [ -z "$SOURCE_SECRET_VALUE" ]; then
    print_error "Failed to retrieve source secret"
    exit 1
fi

print_status "Secret retrieved successfully"

# Step 2: Switch to second account credentials
print_status "Step 2: Switching to destination account credentials..."

if [ -z "${ENV_AWS_ACCESS_KEY_ID:-}" ] || [ -z "${ENV_AWS_SECRET_ACCESS_KEY:-}" ]; then
    print_error "ENV_AWS_ACCESS_KEY_ID and ENV_AWS_SECRET_ACCESS_KEY must be set"
    exit 1
fi

export AWS_ACCESS_KEY_ID=$ENV_AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$ENV_AWS_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN=${ENV_AWS_SESSION_TOKEN:-}

print_status "Credentials switched"

# Step 3: Create secret in second account
print_status "Step 3: Creating secret in destination AWS account..."

aws secretsmanager create-secret \
    --name "$DEST_SECRET_NAME" \
    --secret-string "$SOURCE_SECRET_VALUE" \
    --region "$DEST_REGION"

print_status "Secret created successfully in $DEST_REGION"
print_status "Done!"