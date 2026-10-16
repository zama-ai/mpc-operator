# mpc-operator-check

A Helm chart running pre-install/pre-upgrade check Jobs against an MPC party deployment (kms-core, kms-connector and KMS keys), and printing the configuration to share with Zama governance.

## Prerequisites

All Jobs run with the least privilege `mpc-party-check` service account (`serviceAccount.name`). It is created with its IRSA role and RBAC by the [terraform-mpc-modules](https://github.com/zama-ai/terraform-mpc-modules) `mpc-party` module (`create_check_service_account = true`, the default). The chart itself does not create any RBAC.

| Job | Kubernetes API | AWS |
| --- | -------------- | --- |
| `kms-core` | `get`/`list` pods, services, deployments, statefulsets and nodes; pod logs | `s3:ListBucket` on the public and private vault buckets |
| `kms-connector` | pod logs | none |
| `kms-keys` | none (`automountServiceAccountToken: false`) | `kms:GetPublicKey` on the kms-connector tx sender key |

> **Cross-account KMS keys**
>
> When the kms-connector tx sender key lives in another AWS account (`kms_use_cross_account_kms_key = true`), its key policy must also allow `kms:GetPublicKey` for the check IRSA role, otherwise the `kms-keys` Job fails.

## Usage

```bash
helm upgrade --install mpc-operator-check oci://hub.zama.org/zama-protocol/zama-ai/mpc-operator/charts/mpc-operator-check \
  --version 2.0.0 -n kms-decentralized
```

Each run creates Jobs suffixed with the release revision (for example `mpc-operator-check-kms-core-3`), so a check can be rerun right away. Jobs and their logs are kept for `job.ttlSecondsAfterFinished` seconds (300 by default), whether they succeed or fail:

```bash
kubectl logs -n kms-decentralized -l app.kubernetes.io/instance=mpc-operator-check,mpc-operator-check/revision=<revision> --all-containers --tail=-1
```

## Cleaning 1.x resources

To remove the cluster-wide RBAC left over by 1.x runs (Helm only deleted it when all checks succeeded):

```bash
kubectl delete clusterrolebinding mpc-operator-check --ignore-not-found
kubectl delete clusterrole mpc-operator-check-resource-reader --ignore-not-found
```

## Verify permissions

```bash
SA=system:serviceaccount:kms-decentralized:mpc-party-check
kubectl auth can-i get secrets -n kms-decentralized --as=$SA                  # no
kubectl auth can-i list pods -n kube-system --as=$SA                          # no
kubectl auth can-i list nodes --as=$SA                                        # yes
kubectl auth can-i get pods --subresource=log -n kms-decentralized --as=$SA   # yes
kubectl get clusterrolebinding mpc-operator-check                             # NotFound
```
