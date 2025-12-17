# zama-protocol-pause

A Helm chart for deploying a Kubernetes CronJob to pause the Zama Protocol on both Ethereum and Gateway networks in emergency situations.

## Overview

This chart deploys a CronJob that can execute pause transactions on:
- Ethereum ACL Contract (on Ethereum Mainnet/Testnet)
- Gateway Config Contract (on Zama Gateway Mainnet/Testnet/Devnet)

The CronJob is configured to be suspended by default and uses an invalid schedule (`0 0 31 2 *`) to prevent automatic execution.
It is designed to be manually triggered only in emergency situations.

## Prerequisites

- Access to RPC endpoints for both Ethereum and Gateway networks
- A wallet with pause permissions configured via AWS KMS or private key

## Usage

### Manual Trigger

To manually trigger the pause operation:

```bash
kubectl create job --from=cronjob/zama-protocol-pause zama-pause-$(date +%s) -n zama-protocol
```

### Dry Run

To test without sending transactions, install with `--set dryRun=true`.
Then trigger the job manually.

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `network` | Network environment (devnet/testnet/mainnet) | `mainnet` |
| `dryRun` | Enable dry-run mode (no transactions sent) | `false` |

### Wallet Configuration

The chart supports two wallet authentication methods:

#### AWS KMS (Recommended)

```yaml
serviceAccount:
  name: "zama-protocol-pause" # Should be bound to an IRSA that can sign txs with the AWS-KMS key

wallet:
  awsKMS:
    enabled: true
    configmap:
      name: pauser
      key: AWS_KMS_KEY_ID
```

#### Private Key (Fallback)

```yaml
wallet:
  awsKMS:
    enabled: false
  secret:
    name: pauser-wallet
    key: private-key
```

### Network Configuration

Contract addresses are pre-configured for each network: **Devnet**, **Testnet**: and **Mainnet**.

### RPC Endpoints

RPC URLs must be provided via the environment variables:

```yaml
env:
  - name: GATEWAY_RPC_URL
    valueFrom:
      secretKeyRef:
        name: rpcs
        key: gateway-rpc-url
  - name: ETHEREUM_RPC_URL
    valueFrom:
      secretKeyRef:
        name: rpcs
        key: ethereum-rpc-url
```

**Note**: It is highly recommended to use authenticated RPC endpoints instead of public ones for reliability.

## Security Considerations

- The CronJob is suspended by default to prevent accidental execution
- Uses an invalid cron schedule as an additional safeguard
- Supports AWS KMS for secure key management
- Requires specific pause permissions on the PauserSet contracts of Host and Gateway networks.
- Set `backoffLimit: 0` to prevent automatic retries on failure

## Values

See [values.yaml](values.yaml) for the complete list of configurable parameters.
