# OVERVIEW
In order to execute the `create-encrypt-backup.sh` script, the dependencies and environment variables defined below must be completed

## Dependencies

1. Install `Foundry`       - https://getfoundry.sh/
2. Install `1Password` CLI - https://developer.1password.com/docs/cli/get-started/#install
3. Install `Age`           - https://github.com/FiloSottile/age

```
# Foundry
curl -L https://foundry.paradigm.xyz | bash
source /home/cloudshell-user/.bashrc
foundryup

# 1Password
sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
sudo sh -c 'echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=\"https://downloads.1password.com/linux/keys/1password.asc\"" > /etc/yum.repos.d/1password.repo'
sudo dnf check-update -y 1password-cli && sudo dnf install 1password-cli

# Age
curl -sSfLO https://github.com/FiloSottile/age/releases/download/v1.2.1/age-v1.2.1-linux-amd64.tar.gz
tar -xzf age-v1.2.1-linux-amd64.tar.gz
sudo mv age/age age/age-keygen /usr/local/bin/
sudo chmod +x /usr/local/bin/age /usr/local/bin/age-keygen
rm -rf age age-v1.2.1-linux-amd64.tar.gz
```

## Create 1Password Service Account 

A 1Password Service Account needs to be created which grants at least write access to a secure Vault within 1Password for storing the Age private keys. Documentation below:

https://developer.1password.com/docs/service-accounts/get-started/

## Clone repo and make script executable

```
git clone https://github.com/zama-ai/mpc-operator.git
cd mpc-operator
git checkout <commit hash | tag>
cd scripts
chmod +x create-and-backup-eth-key.sh create-age-keypair.sh
```

## Usage

To generate an Age keypair and upload it to 1Password:

```
export OP_SERVICE_ACCOUNT_TOKEN= # 1Password Service Account token
export OP_VAULT=                 # Name of the 1Password Vault where Age private key will be saved
export OP_TITLE=                 # Name of the Age private key secret stored in 1Password
./create-age-keypair.sh
```

To generate the Ethereum private key and upload it to AWS secret manager:
```
export SECRET_NAME=          # Name of the AWS Secrets Manager secret to store the encrypted Ethereum private key backup
./create-and-backup-eth-key.sh
```

To generate the Ethereum private key, encrypt it with the Age public key and upload it to AWS secret manager:
```
export AWS_KMS_KEY_ID=       # ID of AWS KMS Key for storing the Ethereum private key
export SECRET_NAME=          # Name of the AWS Secrets Manager secret to store the encrypted Ethereum private key backup
exoprt AGE_PUBLIC_KEY=       # Age public key to encrypt the Ethereum private key at rest
./create-and-backup-eth-key.sh
```
