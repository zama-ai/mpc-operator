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

generate_age_keypair() {
  print_status "Generating age keypair"

  age-keygen -o age-private.key
  export AGE_PUBLIC_KEY=$(age-keygen -y age-private.key)
}


# Save age private key to 1Password
save_to_1password() {
    print_status "Saving age private key to 1Password..."

    # Check if OP_VAULT is set
    if [ -z "${OP_VAULT:-}" ]; then
        OP_VAULT="Private"
        print_warning "OP_VAULT not set. Using default: $OP_VAULT"
    fi

    if [ -z "${OP_TITLE:-}" ]; then
        OP_TITLE="KMS Connector Age Private Key"
        print_warning "OP_TITLE not set. Using default: $OP_TITLE"
    fi


    # Check if user is signed in to 1Password
    if ! op account get &>/dev/null; then
        print_error "Not signed in to 1Password. Please run: eval \$(op signin)"
        exit 1
    fi

    # Create 1Password item
    op document create age-private.key \
      --title="$OP_TITLE" \
      --vault="$OP_VAULT" \
      --tags "age-keypair"

    print_status "Age private key saved to 1Password successfully"
}


# Cleanup function
cleanup() {
    print_status "Cleaning up all files..."
    rm -f age-private.key
    print_status "All files deleted - check that secrets was safely stored in 1Password"
}

# Main execution
main() {
    generate_age_keypair
    save_to_1password
    cleanup

    echo ""
    print_status "Secrets stored in:"
    print_status "  ✓ 1Password - Age private key"
}

# Run main function
main "$@"