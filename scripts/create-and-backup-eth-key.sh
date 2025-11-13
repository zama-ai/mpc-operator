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
    
    echo "$PRIVATE_KEY" > kms-connector-wallet.key
    
    if [ ! -s kms-connector-wallet.key ]; then
        print_error "Failed to create keypair"
        exit 1
    fi
    
    print_status "Keypair created successfully"
}

# Step 2: Convert private key to PKCS#8 DER format and import to KMS
import_to_kms() {
    print_status "Step 2: Converting and importing key to AWS KMS..."
    
    # Check if AWS_KMS_KEY_ID is set
    if [ -z "${AWS_KMS_KEY_ID:-}" ]; then
        print_error "AWS_KMS_KEY_ID environment variable is not set"
        exit 1
    fi
    
    print_status "Using KMS Key ID: $AWS_KMS_KEY_ID"
    
    # Convert private key to PKCS#8 DER format
    echo "302e0201010420$(cat kms-connector-wallet.key | cut -c3-)a00706052b8104000a" | \
        xxd -r -p | openssl ec -inform DER -out private-key.pem 2>/dev/null
    
    openssl pkcs8 -topk8 -outform der -nocrypt -in private-key.pem -out private-key.der
    
    # Get KMS import parameters
    aws kms get-parameters-for-import \
        --key-id "$AWS_KMS_KEY_ID" \
        --wrapping-algorithm RSAES_OAEP_SHA_256 \
        --wrapping-key-spec RSA_4096 > key-import-params.json
    
    # Extract public key and import token
    jq -r '.PublicKey' key-import-params.json | base64 -d > WrappingPublicKey.bin
    jq -r '.ImportToken' key-import-params.json | base64 -d > ImportToken.bin
    
    # Encrypt the key material
    openssl pkeyutl -encrypt \
        -in private-key.der \
        -inkey WrappingPublicKey.bin \
        -keyform DER \
        -pubin \
        -pkeyopt rsa_padding_mode:oaep \
        -pkeyopt rsa_oaep_md:sha256 \
        -out EncryptedKeyMaterial.bin
    
    # Import the key material
    aws kms import-key-material \
        --key-id "$AWS_KMS_KEY_ID" \
        --encrypted-key-material fileb://EncryptedKeyMaterial.bin \
        --import-token fileb://ImportToken.bin \
        --expiration-model KEY_MATERIAL_DOES_NOT_EXPIRE
    
    print_status "Key imported to KMS successfully"
}

# Step 3: Generate age keypair and encrypt wallet key
encrypt_with_age() {
    print_status "Step 3: Encrypting wallet key with age..."
    
    # Encrypt the wallet key with age
    cat kms-connector-wallet.key | age -r "$AGE_PUBLIC_KEY" > kms-connector-wallet.key.age
    
    if [ ! -f kms-connector-wallet.key.age ]; then
        print_error "Failed to encrypt key with age"
        exit 1
    fi
    
    print_status "Key encrypted successfully with age"
}

# Step 4: Save encrypted key to AWS Secrets Manager
save_to_secrets_manager() {
    print_status "Step 4: Saving encrypted key to AWS Secrets Manager..."
    
    # Check if SECRET_NAME is set
    if [ -z "${SECRET_NAME:-}" ]; then
        SECRET_NAME="kms-connector-wallet-encrypted-key"
        print_warning "SECRET_NAME not set. Using default: $SECRET_NAME"
    fi
    
    # Read the encrypted file content
    ENCRYPTED_CONTENT=$(base64 -i kms-connector-wallet.key.age)
    
    # Create or update the secret
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" &>/dev/null; then
        print_status "Secret exists, updating..."
        aws secretsmanager update-secret \
            --secret-id "$SECRET_NAME" \
            --secret-string "$ENCRYPTED_CONTENT"
    else
        print_status "Creating new secret..."
        aws secretsmanager create-secret \
            --name "$SECRET_NAME" \
            --secret-string "$ENCRYPTED_CONTENT"
    fi
    
    print_status "Secret saved successfully"
}

# Cleanup function
cleanup() {
    print_status "Cleaning up all files..."
    rm -f private-key.pem private-key.der key-import-params.json \
          WrappingPublicKey.bin ImportToken.bin EncryptedKeyMaterial.bin \
          kms-connector-wallet.key kms-connector-wallet.key.age
    print_status "All files deleted - secrets are safely stored in AWS"
}

# Main execution
main() {
    print_status "Starting KMS Connector Wallet Setup"
    echo ""
    
    create_keypair
    import_to_kms
    encrypt_with_age
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
    print_status "  ✓ AWS KMS - Key material"
    print_status "  ✓ AWS Secrets Manager - Encrypted wallet key"
}

# Run main function
main "$@"