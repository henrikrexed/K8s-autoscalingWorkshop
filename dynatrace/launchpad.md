# 🎯 K8s Autoscaling Workshop

> Optimize your Kubernetes cluster with a Dynatrace **Workflow** + **DQL** — driven entirely from a GitHub Codespace, with PRs landing back in your repo.

---

## What you'll do today

In the next ~45 minutes you'll:

1. **Stand up a Kubernetes cluster** inside a GitHub Codespace (`kind`, single-node)
2. **Deploy `opentelemetry-demo-light`** — 5 microservices, postgres, valkey, k6 load generator — into that cluster
3. **Send every trace, metric and log to this tenant** via an OpenTelemetry Collector (filelog receiver for pod logs, cumulative-to-delta processor for metric ingestion)
4. **Install the Dynatrace Operator** with a DynaKube CR for K8s monitoring (ActiveGate-only — no OneAgent injection into the demo workloads)
5. **Run a Workflow** that uses DQL on Smartscape to find workloads where latency correlates with resource usage, computes new CPU/memory requests based on 7-day p95, and **opens a PR against your fork** with the proposed manifest changes
6. **Merge the PR + watch the optimization land** — the cluster reconciles to the new requests, the gap between request and actual usage shrinks

---

## ⚙️ Codespace secrets — what you set, what we provide

The Codespace bootstrap reads four values from GitHub Codespace secrets. **Settings → Secrets and variables → Codespaces** on your fork.

### 🔑 Tokens (provided by your workshop host)

You'll receive these in the chat or via the workshop landing page. **Paste them verbatim** as Codespace secrets — don't regenerate them yourself.

| Codespace secret | What it does |
|---|---|
| `DT_API_TOKEN` | Operator token — lets the Dynatrace Operator install the ActiveGate, configure entities, and read/write settings |
| `DT_INGEST_TOKEN` | Ingest token — the OTel Collector authenticates with this for metrics / logs / OpenTelemetry traces |

### 📝 Variables you define yourself

| Codespace secret | Example | What it does |
|---|---|---|
| `DT_TENANT_URL` | `https://abc12345.live.dynatrace.com` | The Dynatrace tenant URL (see below — the same URL you used to land on this page, just without `/ui/...`) |
| `OTEL_SERVICE_PREFIX` | `REX-` | A **short, unique prefix** (3-6 chars) appended to every service name so your traces don't collide with your neighbour's. End it with a `-` so service names render as `REX-cart`, `REX-checkout`, etc. |

> 💡 Pick a prefix that's recognisable to you (your initials work well). If you skip `OTEL_SERVICE_PREFIX`, every attendee's services would land as plain `cart`, `checkout`, `frontend`, … and overlap on the tenant.

---

## 🌐 Dynatrace environment

| Property | Value |
|---|---|
| **Tenant URL** | `<this tenant — paste it into `DT_TENANT_URL`>` |
| **Environment type** | `live` |
| **Notebook** | `Smartscape Resource allocation` (already deployed — find it in the Notebooks app) |
| **Workflow** | `Smart Resource Optimizer` (already deployed — find it in the Workflows app) |

The notebook + workflow are **pre-provisioned**. You don't need to run any `dtctl` commands locally.

---

## 🏗️ Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│  🐙  YOUR GITHUB FORK — K8s-autoscalingWorkshop                 │
│      Codespace secrets:                                         │
│        DT_TENANT_URL · DT_API_TOKEN · DT_INGEST_TOKEN           │
│        OTEL_SERVICE_PREFIX  (e.g. "REX-")                       │
└─────────────────────┬───────────────────────────────────▲───────┘
                      │ open Codespace                    │
                      ▼                                   │
┌─────────────────────────────────────────────────────────┼───────┐
│  💻 GITHUB CODESPACE                                    │       │
│                                                         │       │
│  ┌───────────────────────────────────────────────────┐  │       │
│  │  KIND CLUSTER  (named after $CODESPACE_NAME)      │  │       │
│  │                                                   │  │       │
│  │  ┌─────────────────────────────────────────────┐  │  │       │
│  │  │ 📦  otel-demo namespace  (oneagent=false)    │  │  │       │
│  │  │  frontend · cart · checkout · payment ·     │  │  │       │
│  │  │  product-catalog · postgres · valkey · k6   │  │  │       │
│  │  └─────────────────┬──────────────────────────┘  │  │       │
│  │                    │  OTLP/gRPC                   │  │       │
│  │                    ▼                              │  │       │
│  │  ┌─────────────────────────────────────────────┐  │  │       │
│  │  │ 📡  otel-collector namespace  (DaemonSet)    │  │  │       │
│  │  │   • OTLP receiver                            │  │  │       │
│  │  │   • filelog receiver  (/var/log/pods)        │  │  │       │
│  │  │   • k8sattributes + cumulativetodelta procs  │  │  │       │
│  │  └─────────────────┬──────────────────────────┘  │  │       │
│  │                    │  OTLP/HTTP + DT_INGEST_TOKEN │  │       │
│  │  ┌─────────────────────────────────────────────┐  │  │       │
│  │  │ 🔭  dynatrace namespace                      │  │  │       │
│  │  │   Operator + DynaKube + ActiveGate           │  │  │       │
│  │  │   (Kubernetes monitoring; no OneAgent in     │  │  │       │
│  │  │    otel-demo — that ns is oneagent=false)    │  │  │       │
│  │  └─────────────────┬──────────────────────────┘  │  │       │
│  │                    │  K8s API events + DT_API_TOKEN │       │
│  └────────────────────┼─────────────────────────────┘  │       │
└───────────────────────┼─────────────────────────────────┼───────┘
                        ▼                                 │
┌─────────────────────────────────────────────────────────┼───────┐
│  📊  DYNATRACE TENANT                                   │       │
│       traces · metrics · logs · K8s entities            │       │
│                                                         │       │
│      📓  Notebook                                       │       │
│          Smartscape Resource allocation                 │       │
│                │                                        │       │
│                │  DQL: workloads where                  │       │
│                │  latency ↔ resource usage              │       │
│                ▼                                        │       │
│      🤖  Workflow                                       │       │
│          Smart Resource Optimizer                       │       │
│            • runs DQL on Smartscape                     │       │
│            • computes new requests from 7-day p95       │       │
│            • patches manifest in your fork ────────────▶│       │
│            • opens a Pull Request ─────────────────────▶│ 🔁 PR │
└─────────────────────────────────────────────────────────┴───────┘
```

**How telemetry flows:**

- The **otel-demo-light** pods emit OTLP/gRPC to the cluster-local Collector
- The **OTel Collector** (DaemonSet, one pod per node) enriches with `k8sattributes`, converts cumulative metrics to delta, then exports OTLP/HTTP to this tenant
- The **Dynatrace Operator + ActiveGate** independently populate Smartscape with Kubernetes API events (deployments, replicasets, pods, …)
- The **Workflow** queries Smartscape via DQL, reads the `resource-optimization.dynatrace.com/*` annotations off each live pod to find the right file in your fork, and opens a PR via the GitHub Contents API

---

## 🚀 Quick start

1. **Fork** [`henrikrexed/K8s-autoscalingWorkshop`](https://github.com/henrikrexed/K8s-autoscalingWorkshop) into your own GitHub account.
2. **On your fork**, go to *Settings → Secrets and variables → Codespaces* and add the four secrets above.
3. **Click *Code → Create codespace on main*** on your fork.
4. The Codespace runs the bootstrap automatically — watch the terminal for the green summary.
5. Open this tenant's **Notebook** and **Workflow** apps, then run the workflow.

📖 Full walk-through: <https://henrikrexed.github.io/K8s-autoscalingWorkshop/>

---

## 🛟 Need help during the workshop?

- 🐛 *Pod stuck pending?* `kubectl get pods -A` and look at events
- 📭 *No traces in this tenant?* Check the collector logs: `kubectl -n otel-collector logs ds/otel-collector --tail 100`
- 🔁 *Bootstrap failed?* Re-run it: `bash .devcontainer/bootstrap.sh` (idempotent)
- 🙋 *Stuck?* Ask in the workshop chat — include your `OTEL_SERVICE_PREFIX` so we can find your services in Smartscape

Happy optimizing! 🎉
