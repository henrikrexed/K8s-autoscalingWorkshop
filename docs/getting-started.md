# 1. Getting Started

This page gets your Dynatrace tokens ready and your GitHub fork configured. It takes about **10 minutes**.

## Gather Details: Tenant ID & Environment

You'll need access to a Dynatrace tenant. If you don't have one, [sign up for a free 15-day trial](https://dt-url.net/observable-trial).

Make a note of your Dynatrace tenant ID — it's the first part of your URL. In the examples below, `abc12345` is the tenant ID:

```text
https://abc12345.live.dynatrace.com
https://abc12345.apps.dynatrace.com
```

You'll record the tenant ID (e.g. `abc12345`) in your Codespace secret as `DT_ENVIRONMENT_ID`.

!!! info "Live vs Apps URL"
    The classic `.live.dynatrace.com` URL is what the OTel collector and the Dynatrace Operator use for OTLP ingestion and the operator API. The newer `.apps.dynatrace.com` URL is the Platform (apps) endpoint you'll use in your browser to open the notebook and workflow. The bootstrap script constructs the correct URL automatically from `DT_ENVIRONMENT_ID` + `DT_ENVIRONMENT_TYPE`.

## Gather Details: Environment Type

Make a note of your "environment type" based on your URL.

If you're unsure, use `live`.

| URL                              | Environment Type |
|----------------------------------|------------------|
| `abc12345.apps.dynatrace.com`    | live             |
| `abc12345.live.dynatrace.com`    | live             |
| `abc12345.sprint.dynatracelabs.com` | sprint        |
| `abc12345.dev.dynatracelabs.com` | dev              |

## Gather Details: Create Dynatrace API Tokens

This workshop needs **two** tokens, generated in Dynatrace under **Settings → Access tokens → Generate new token**.

### Operator token (`DT_OPERATOR_TOKEN`)

This token is used by the Dynatrace Operator to install the OneAgent CSI driver, deploy the ActiveGate, and configure entities/settings.

Grant these scopes:

- `Create ActiveGate tokens` (`activeGateTokenManagement.create`)
- `Read entities` (`entities.read`)
- `Read Settings` (`settings.read`)
- `Write Settings` (`settings.write`)
- `Access problem and event feed, metrics and topology` (`DataExport`)
- `Read configuration` (`ReadConfig`)
- `Write configuration` (`WriteConfig`)
- `PaaS integration — installer downloader` (`InstallerDownload`)

Copy the token — you'll need it in a moment.

### Ingest token (`DT_API_TOKEN`)

This token is what the in-cluster OpenTelemetry Collector uses to ship traces / metrics / logs via OTLP.

Grant these scopes:

- `Ingest metrics` (`metrics.ingest`)
- `Ingest logs` (`logs.ingest`)
- `Ingest events` (`events.ingest`)
- `Ingest OpenTelemetry traces` (`openTelemetryTrace.ingest`)
- `Read metrics` (`metrics.read`)

Copy this token too.

!!! warning "Keep the tokens private"
    These tokens grant write access to your tenant. Treat them like passwords. The Codespace secret mechanism encrypts them and never displays them after creation.

## Gather Details: Create a GitHub Personal Access Token

The Dynatrace workflow needs a **GitHub connection** to commit optimized manifests and open pull requests against your fork. This connection uses a GitHub Personal Access Token (PAT).

1. Go to [github.com/settings/tokens?type=beta](https://github.com/settings/tokens?type=beta) (fine-grained tokens)
2. Click **Generate new token**
3. Give it a name (e.g. `dynatrace-resource-optimizer`)
4. Under **Repository access**, select **Only select repositories** and pick your fork of `K8s-autoscalingWorkshop`
5. Under **Permissions → Repository permissions**, grant:
    - `Contents` — **Read and write** (to commit patched manifests)
    - `Pull requests` — **Read and write** (to open PRs)
6. Click **Generate token** and copy it

You'll use this token when configuring the GitHub connection in Dynatrace (during the workshop).

!!! tip "Classic tokens work too"
    If you prefer a classic PAT, go to [github.com/settings/tokens](https://github.com/settings/tokens) and create one with the `repo` scope. Fine-grained tokens are recommended because they limit access to a single repository.

## Fork the Repository

Go to [github.com/henrikrexed/K8s-autoscalingWorkshop](https://github.com/henrikrexed/K8s-autoscalingWorkshop) and click **Fork** in the top-right corner.

You should end up with `https://github.com/<your-username>/K8s-autoscalingWorkshop`.

!!! tip "Why fork?"
    The Dynatrace workflow opens pull requests against the repository that owns the running pods — it learns which repo from annotations on each Deployment. When the Codespace boots, a bootstrap script auto-detects you're running on your fork and rewrites those annotations to point at your fork, so the workflow opens PRs in **your** repo, not in the upstream.

## Configure the Codespace secrets

On **your fork**, go to:

**Settings → Secrets and variables → Codespaces → New repository secret**

Create these secrets:

| Secret                | Required? | Example value                          | What it is                                              |
|-----------------------|-----------|----------------------------------------|----------------------------------------------------------|
| `DT_ENVIRONMENT_ID`   | yes       | `abc12345`                             | Your Dynatrace tenant identifier (the first part of the URL) |
| `DT_ENVIRONMENT_TYPE` | yes       | `live`                                 | Environment type: `live`, `sprint`, or `dev`             |
| `DT_OPERATOR_TOKEN`   | yes       | `dt0c01.···`                           | The Operator token you generated above                   |
| `DT_API_TOKEN`        | yes       | `dt0c01.···`                           | The Ingest token you generated above                     |
| `OTEL_SERVICE_PREFIX` | optional  | `REX-`                                 | Prepended to every `OTEL_SERVICE_NAME` (e.g. `REX-cart`) so multiple workshop attendees can share one tenant without colliding on service names. Leave unset for vanilla names. |

!!! info "Codespace secrets, not Actions secrets"
    Make sure you're under **Secrets and variables → Codespaces**, not under **Actions**. Codespace secrets are injected as environment variables into the Codespace container; Actions secrets are not.

## Start the Workshop

When all four required secrets are set, click **Code → Create codespace on main** on your fork.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/henrikrexed/K8s-autoscalingWorkshop){ .md-button .md-button--primary }

The Codespace will:

1. Install `kind`, `kubectl`, `helm`, `yq`, `jq`
2. Detect your fork via `$GITHUB_REPOSITORY` and rewrite + push the resource-optimization annotations on every demo workload
3. Create a single-node `kind` cluster (named after your `$CODESPACE_NAME` for uniqueness)
4. Install the Dynatrace Operator + apply the DynaKube
5. Deploy the OpenTelemetry Collector (DaemonSet, with filelog receiver and cumulativetodelta processor)
6. Deploy the `otel-demo-light` workload (frontend, cart, checkout, payment, product-catalog, postgres, valkey, k6 load generator)

The resource-optimization **notebook** is pre-provisioned on the trial
Dynatrace tenant. The **workflow** needs to be imported from the template
file included in this repo — you'll do that in the next step.

Watch the terminal — when you see the green summary, [continue to the Workshop page](workshop.md).
