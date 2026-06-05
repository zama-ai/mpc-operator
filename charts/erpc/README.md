# eRPC Helm Chart

Standalone Helm chart for the [eRPC](https://github.com/erpc/erpc) proxy, providing RPC load balancing, failover, and caching. Extracted from the optional eRPC component of the FHEVM `listener` chart.

## Prerequisites

- Helm 3.x
- Kubernetes 1.24+
- For `metrics.serviceMonitor.enabled`: the Prometheus Operator CRDs

## Quick Start

```bash
helm install erpc charts/erpc -n erpc --create-namespace
```

## Configuration

### Config merge strategy

eRPC config is built from a **base profile file + deep-merge** pattern. Canonical config files are bundled in the chart under `config/`. The ConfigMap template loads the selected profile with `.Files.Get` and applies overrides with `mergeOverwrite`.

```
charts/erpc/config/
  erpc-base.yaml     # minimal defaults, no networks/upstreams
  erpc-public.yaml   # public nodes, listener-indexer tuned
```

> **Note on storage:** unlike the FHEVM `listener` chart (which symlinks these files from a `listener/config/` source dir), this chart stores the config files **as real files** inside `config/`. The files live outside `templates/` because anything under `templates/` is rendered as a Go template and would break raw YAML. When the upstream eRPC config changes, copy the updated file into `config/` and bump `Chart.yaml` version.

Merge order (last wins):

| Layer | Source | Purpose |
|-------|--------|---------|
| 1. Base profile | `config/<baseConfig>` | Bundled profile (`erpc-base.yaml` by default) |
| 2. Overrides | `values.yaml` -> `config` | Partial deep-merged overrides |

### Config profiles

Select a profile with `baseConfig`:

| Profile | File | Use case |
|---------|------|----------|
| `erpc-base.yaml` | Minimal defaults | Standalone eRPC for generic apps (default) |
| `erpc-public.yaml` | Public nodes, listener-tuned | Listener clusters using public RPC endpoints |

```yaml
baseConfig: erpc-base.yaml   # or erpc-public.yaml
```

### Adding a new profile

1. Copy the config file into `charts/erpc/config/erpc-<profile>.yaml`
2. Bump `Chart.yaml` version
3. Deploy with `--set baseConfig=erpc-<profile>.yaml`

### Partial overrides

Use `config` to deep-merge overrides on top of the base profile without replacing the whole config:

```yaml
baseConfig: erpc-public.yaml
config:
  logLevel: info
  server:
    maxTimeout: 60s
```

### Full replacement

To bypass the bundled profile entirely, use `--set-file`:

```bash
helm install erpc charts/erpc \
  --set-file configFile=path/to/custom-erpc.yaml
```

This ignores both `baseConfig` and `config` overrides.

### Autoscaling

Enable a HorizontalPodAutoscaler (`autoscaling/v2`) to scale eRPC on CPU and/or memory utilization. Requires a metrics-server in the cluster, and the container must declare matching resource requests (it does by default — see `resources`), since utilization targets are computed against requests. When enabled, the Deployment's `replicas` field is omitted so the HPA owns the replica count.

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80   # optional
```

### Metrics

Enable a `ServiceMonitor` to scrape the eRPC Prometheus metrics port (`4001`):

```yaml
metrics:
  serviceMonitor:
    enabled: true
```

## Values Reference

| Key | Default | Description |
|-----|---------|-------------|
| `image.repository` | `ghcr.io/erpc/erpc` | eRPC container image |
| `image.tag` | `""` (uses appVersion) | Image tag override |
| `replicas` | `1` | eRPC replica count (ignored when `autoscaling.enabled`) |
| `autoscaling.enabled` | `false` | Create a HorizontalPodAutoscaler (`autoscaling/v2`) |
| `autoscaling.minReplicas` / `autoscaling.maxReplicas` | `1` / `5` | HPA replica bounds |
| `autoscaling.targetCPUUtilizationPercentage` | `80` | Target average CPU utilization |
| `autoscaling.targetMemoryUtilizationPercentage` | `""` | Target average memory utilization (empty = disabled) |
| `autoscaling.behavior` | `{}` | Optional HPA scaleUp/scaleDown policies |
| `args` | `[/config/erpc.yaml]` | Container args (config-file path) |
| `baseConfig` | `erpc-base.yaml` | Base eRPC config profile in `config/` |
| `config` | `{}` | Partial overrides deep-merged on top of base profile |
| `configFile` | `""` | Full config replacement (via `--set-file`) |
| `service.type` | `ClusterIP` | Service type |
| `service.httpPort` | `4000` | eRPC HTTP port |
| `service.metricsPort` | `4001` | eRPC Prometheus metrics port |
| `serviceAccount.create` | `true` | Create a ServiceAccount |
| `podSecurityContext` | nonroot + `seccompProfile: RuntimeDefault` | Pod-level security context |
| `securityContext` | readOnlyRoot + capDropAll + `seccompProfile: RuntimeDefault` | Container-level security context |
| `metrics.serviceMonitor.enabled` | `false` | Create a Prometheus ServiceMonitor |
| `resources` | 250m/256Mi req, 1/512Mi limit | Resource requests/limits |
| `nodeSelector` / `tolerations` / `affinity` | `{}` / `[]` / `{}` | Scheduling constraints |

## License

This software is distributed under the **BSD-3-Clause-Clear** license.
