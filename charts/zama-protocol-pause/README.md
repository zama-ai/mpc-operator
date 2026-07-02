# zama-protocol-pause

A Helm chart for deploying Kubernetes CronJobs to pause the Zama Protocol on its host chains and Gateway networks in emergency situations.

## Overview

This chart deploys CronJobs that can execute pause transactions on:
- Host-chain ACL Contracts, one per entry in `hostChains` (e.g. Ethereum, Polygon)
- Gateway Config Contract (on Zama Gateway Mainnet/Testnet/Devnet)
- Zama Token mint on Ethereum (configured under `ethereumToken`)

### Adding a host chain

Host chains are data-driven: append an entry to `hostChains` in `values.yaml`. No template changes are needed.

```yaml
hostChains:
  - name: arbitrum
    displayName: Arbitrum
    rpcUrlEnv: ARBITRUM_RPC_URL      # env var declared under `env:` below
    aclPauseMethodId: "0x8456cb59"   # pause() selector
    aclContractAddress:
      devnet: "0x..."
      testnet: "0x..."
      mainnet: "0x..."               # empty/absent => pause skipped for that network
```

Then add the matching `ARBITRUM_RPC_URL` entry to the `env:` list.

Zama token mint pause is Ethereum-only and configured separately under `ethereumToken` (`tokenAddress` / `tokenPauserSetWrapperAddress` per network).

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

In dry-run mode (`--set dryRun=true`, the default) no real transactions are sent.
Instead each chain is forked locally with `anvil` and the pause is simulated
against the fork. This validates that the pauser is authorized, funded, and that
the call succeeds, without touching the real chain.

By default the configured wallet (KMS or private key) signs the pause against
the fork, so the same wallet used in production is exercised. Set
`dryRunPauserImpersonationAddress` to instead impersonate a specific address
(via `anvil_impersonateAccount`), which lets you run a dry-run without any wallet
/ KMS access.
Then trigger the job manually.

Run a dry run with the operator's pauser address (from AWS-KMS config in cluster):
```
helm upgrade --install pause-dry-run . -n zama-protocol --set fullnameOverride=pause-dry-run --set dryRun=true --set network=testnet                                                                                                                                                                                               
```

Run a dry run with Zama's impersonated Testnet pauser address:
```
helm upgrade --install pause-dry-run . -n zama-protocol --set fullnameOverride=pause-dry-run --set dryRun=true --set network=testnet --set dryRunPauserImpersonationAddress=0xb7D919BDC506E23BE2f34E9dBa25B2Af4C5141f0                                                                                                                                                                                                   
```

To start a dry-run pause job:
```
kubectl create job --from=cronjob/pause-dry-run-contracts zama-pause-dryrun-$(date +%s) -n zama-protocol
kubectl create job --from=cronjob/pause-dry-run-token-mint zama-token-dryrun-$(date +%s) -n zama-protocol                                                                                                   
kubectl logs -f -l app.kubernetes.io/name=pause-dry-run -n zama-protocol    
```

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
  # Only needed on networks that also pause Polygon.
  - name: POLYGON_RPC_URL
    valueFrom:
      secretKeyRef:
        name: rpcs
        key: polygon-rpc-url
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
