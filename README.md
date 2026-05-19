# K8s Autoscaling Workshop

<p align="center"><img src="image/logo.png" width="40%" alt="Observe & Resolve logo" /></p>

This repository spins up the **resource optimization** workshop entirely from a
GitHub Codespace. It provisions a single-node [kind](https://kind.sigs.k8s.io)
cluster inside the Codespace, deploys
[`opentelemetry-demo-light`](https://github.com/henrikrexed/opentelemetry-demo-light)
as the workload, and ships all telemetry to your Dynatrace tenant through an
OpenTelemetry Collector. The resource-optimization **notebook** and
**workflow** are pre-provisioned on the trial tenant you've been invited to —
nothing to install on the Dynatrace side.

📖 **Full workshop docs:** https://henrikrexed.github.io/K8s-autoscalingWorkshop/

<p align="center"><img src="image/Smartscape_horizontal.png" width="40%" alt="Smartscape" /></p>

## What's deployed

| Component | Location | Purpose |
|---|---|---|
| `kind` cluster | inside the Codespace | k8s control plane + node |
| Dynatrace Operator + DynaKube | namespace `dynatrace` | ActiveGate (Kubernetes monitoring), namespace-scoped OneAgent injection |
| OpenTelemetry Collector (DaemonSet) | namespace `otel-collector` | OTLP from the demo, pod logs via filelog, cumulative-to-delta metrics, exports to Dynatrace |
| `opentelemetry-demo-light` | namespace `otel-demo` | the demo microservice application (lighter fork of the OTel demo) |
| Notebook *Smartscape Resource allocation* | Dynatrace tenant (pre-provisioned) | DQL extracting workloads where latency correlates with resource usage |
| Workflow *Smart Resource Optimizer* | Dynatrace tenant (pre-provisioned) | adjusts CPU/memory requests, opens a PR against your fork, optionally posts to Slack |

## Workshop flow

1. **Fork** `henrikrexed/K8s-autoscalingWorkshop` to your own GitHub account.
2. **Configure Codespace secrets** on your fork (see below).
3. **Open a Codespace** on your fork — `main` branch.

The bootstrap script does the rest:

- Detects `$GITHUB_REPOSITORY` (your fork) and the current branch
- Rewrites the `resource-optimization.dynatrace.com/github-repo`,
  `github-rep`, and `github-branch` annotations on every workload in
  `otel-demo-light/` to point at your fork
- Auto-commits and pushes the rewrite so the repo and the running cluster
  stay in sync (the workflow reads the live pod's annotation and patches
  the matching file on GitHub — they have to agree)
- Creates a kind cluster (named after your `$CODESPACE_NAME`)
- Installs the Dynatrace Operator + DynaKube
- Deploys the OTel Collector and the demo
- Substitutes your `OTEL_SERVICE_PREFIX` into the `shared-env` ConfigMap
  so every service name lands in Dynatrace with your prefix

## Codespace secrets

Set these under **Settings → Secrets and variables → Codespaces → New repository secret** on your fork:

| Secret | Required? | Example | What it is |
|---|---|---|---|
| `DT_TENANT_URL`       | required | `https://abc12345.live.dynatrace.com` | Your Dynatrace tenant URL |
| `DT_API_TOKEN`        | required | `dt0c01....` | Operator token (entities + settings + ActiveGate token creation + PaaS installer) |
| `DT_INGEST_TOKEN`     | required | `dt0c01....` | Ingest token (metrics, logs, events, OpenTelemetry traces) |
| `OTEL_SERVICE_PREFIX` | optional | `REX-` | Prepended to every `OTEL_SERVICE_NAME` so attendees sharing a tenant don't collide on service names |

## Open the demo

When the bootstrap finishes, port **8080** is auto-forwarded — click **PORTS** in the bottom panel of VS Code, then the globe icon next to *8080*, to open the demo's frontend in a browser.

## Manual run

If you need to (re)run the deploy by hand inside the Codespace:

```bash
bash deployment.sh \
  --dturl         "$DT_TENANT_URL" \
  --dtapitoken    "$DT_API_TOKEN" \
  --dtingesttoken "$DT_INGEST_TOKEN"
```

To rebuild the cluster from scratch:

```bash
kind delete cluster --name "$CLUSTER_NAME"
bash .devcontainer/bootstrap.sh
```

## How telemetry flows

```
opentelemetry-demo-light pods (namespace otel-demo, oneagent=false)
        │  OTLP/gRPC                  Pod logs:
        ▼                             /var/log/pods/*/*/*.log
otel-collector (DaemonSet, namespace otel-collector)
   receivers: otlp, filelog
   processors: k8sattributes, resourcedetection, cumulativetodelta, batch
        │  OTLP/HTTP   Authorization: Api-Token <DT_INGEST_TOKEN>
        ▼
${DT_TENANT_URL}/api/v2/otlp
```

The Dynatrace Operator + ActiveGate provide K8s API monitoring (Smartscape entities, events). OneAgent injection is namespace-scoped via the DynaKube's `namespaceSelector: oneagent=true` — the `otel-demo` namespace is labeled `oneagent=false`, so it's observed via OTLP only, not via code-module injection.

## Layout

```
.
├── .devcontainer/
│   ├── devcontainer.json          Codespace definition
│   ├── install-tools.sh           installs kind, yq, jq
│   ├── rewrite-annotations.sh     rewrites resource-opt annotations for the fork
│   └── bootstrap.sh               runs deployment.sh with Codespace secrets
├── kind/
│   └── cluster.yaml               single-node kind config (port 8080 forwarded)
├── opentelemetry/
│   ├── otel-collector-rbac.yaml
│   └── otel-collector.yaml        DaemonSet exporting OTLP → Dynatrace
├── otel-demo-light/
│   ├── kustomization.yaml         lists every file below
│   ├── namespace.yaml             oneagent=false label
│   ├── shared-env.yaml            ConfigMap with the common OTel env + service prefix
│   ├── <service>.yaml             Deployment / StatefulSet per service
│   ├── <service>_svc.yaml         Service per service
│   ├── postgres-init.yaml         init-SQL for postgres
│   └── load-generator-otel.yaml   k6 driver
├── dynatrace/
│   ├── dynatrace-namespace.yaml
│   └── dynakube.yaml              DynaKube CR (placeholders rendered at deploy time)
├── docs/                          MkDocs Material site (deployed to GitHub Pages)
├── mkdocs.yml
├── deployment.sh                  end-to-end bootstrap
└── README.md
```

## Troubleshooting

```bash
# pods
kubectl get pods -A

# collector logs
kubectl -n otel-collector logs ds/otel-collector -f

# demo pods
kubectl -n otel-demo get pods

# DynaKube status
kubectl -n dynatrace get dynakube dynakube -o yaml
```

If the bootstrap fails because the Codespace secrets aren't set, the
Codespace prints which ones are missing and exits cleanly — set them, then
run `bash .devcontainer/bootstrap.sh` manually.
