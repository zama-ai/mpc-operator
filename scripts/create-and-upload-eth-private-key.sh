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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Step 1: Create Ethereum keypair
create_keypair() {
    print_status "Step 1: Creating Ethereum keypair..."
    
    WALLET_JSON=$(cast wallet new --json)
    PRIVATE_KEY=$(echo "$WALLET_JSON" | jq -r ".[0].private_key")
    PUBLIC_KEY=$(echo "$WALLET_JSON" | jq -r ".[0].address")
    
    echo "$PRIVATE_KEY" > wallet.key
    
    if [ ! -s wallet.key ]; then
        print_error "Failed to create keypair"
        exit 1
    fi
    
    print_status "Keypair created successfully"
}

# Step 2: Save key to AWS Secrets Manager
save_to_secrets_manager() {
    print_status "Step 2: Saving key to AWS Secrets Manager..."
    
    # Check if SECRET_NAME is set
    if [ -z "${SECRET_NAME:-}" ]; then
        print_warning "SECRET_NAME not set."
        exit 1
    fi
    
    CONTENT=$(base64 -i wallet.key)
    
    # Create or update the secret
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" &>/dev/null; then
        print_status "Secret exists, updating..."
        aws secretsmanager update-secret \
            --secret-id "$SECRET_NAME" \
            --secret-string "$CONTENT"
    else
        print_status "Creating new secret..."
        aws secretsmanager create-secret \
            --name "$SECRET_NAME" \
            --secret-string "$CONTENT"
    fi
    
    print_status "Secret saved successfully"
}

# Cleanup function
cleanup() {
    print_status "Cleaning up all files..."
    rm -f wallet.key
    print_status "All files deleted - secrets are safely stored in AWS"
}

# Main execution
main() {
    print_status "Starting Wallet Setup"
    echo ""
    
    create_keypair
    save_to_secrets_manager
    cleanup
    
    echo ""
    print_status "==================================="
    print_status "Setup completed successfully!"
    print_status "==================================="
    echo ""
    print_status "Ethereum Public Address: $PUBLIC_KEY"
    echo ""
    print_status "Secrets stored in:"
    print_status "  ✓ AWS Secrets Manager - Wallet key"
}

# Run main function
main "$@"