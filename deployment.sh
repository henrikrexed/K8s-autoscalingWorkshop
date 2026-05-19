#!/usr/bin/env bash
###############################################################################
# Resource-optimization demo bootstrap.
#
# What it does, in order:
#   1. Creates a single-node kind cluster (idempotent — skipped if it exists)
#   2. Installs the Dynatrace Operator + DynaKube CR
#        - ActiveGate with kubernetes-monitoring + routing capabilities
#        - OneAgent applicationMonitoring scoped to namespaces with oneagent=true
#   3. Deploys the OpenTelemetry Collector wired to your Dynatrace tenant
#   4. Deploys the opentelemetry-demo-light application (namespace labeled
#      oneagent=false, so it's observed via OTLP, NOT via OneAgent injection)
#
# The notebook is pre-provisioned on the trial Dynatrace tenant. The
# workflow template is imported by each attendee via the Workflows UI.
#
# Parameters (also read from environment variables of the same name):
#   --clustername        name of the kind cluster (default: obs-optim)
#   --dturl              Dynatrace tenant URL  (e.g. https://abc12345.live.dynatrace.com)
#                        — OR supply --dtenvironmentid + --dtenvironmenttype instead
#   --dtenvironmentid    Dynatrace environment identifier (e.g. abc12345)
#   --dtenvironmenttype  Environment type: live | sprint | dev
#   --dtoperatortoken    Operator token (installer, settings, entities, token mgmt)
#   --dtingesttoken      Data-ingest token (metrics.ingest, openTelemetryTrace.ingest)
#
# Usage:
#   ./deployment.sh --clustername obs-optim \
#                   --dtenvironmentid "$DT_ENVIRONMENT_ID" \
#                   --dtenvironmenttype "$DT_ENVIRONMENT_TYPE" \
#                   --dtoperatortoken "$DT_OPERATOR_TOKEN" \
#                   --dtingesttoken "$DT_API_TOKEN"
###############################################################################

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# --- cluster name derivation ------------------------------------------------
# In a GitHub Codespace, $CODESPACE_NAME is set automatically (e.g.
#   "henrikrexed-shiny-spork-x73r9pqgrcv544r"). We sanitize it to a valid
# kind cluster name:
#   - lowercase
#   - replace anything outside [a-z0-9.-] with "-"
#   - collapse adjacent dashes
#   - strip leading/trailing dashes
#   - cap at 40 chars (kind appends "-control-plane" -> ~14 chars; Docker
#     container names max out at 64 chars, so this keeps headroom)
# Outside a Codespace, fall back to a stable default.
derive_cluster_name() {
  local raw="${CODESPACE_NAME:-}"
  if [[ -z "$raw" ]]; then
    echo "obs-optim"
    return
  fi
  local sanitized
  sanitized=$(printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9.-]/-/g; s/-+/-/g; s/^-+//; s/-+$//')
  sanitized="${sanitized:0:40}"
  sanitized="${sanitized%-}"
  echo "${sanitized:-obs-optim}"
}

# --- defaults from env ------------------------------------------------------
CLUSTERNAME="${CLUSTER_NAME:-$(derive_cluster_name)}"
DTURL="${DT_TENANT_URL:-}"
DT_ENV_ID="${DT_ENVIRONMENT_ID:-}"
DT_ENV_TYPE="${DT_ENVIRONMENT_TYPE:-live}"
DTOPERATORTOKEN="${DT_OPERATOR_TOKEN:-}"
DTINGESTTOKEN="${DT_API_TOKEN:-}"

# otel-demo-light manifests are vendored under otel-demo-light/ in this repo.
# (No runtime clone — splitting per-Service / per-workload files lets the
# smart-resource-optimizer workflow patch a single Deployment file via the
# GitHub Contents API without churning Service definitions.)

# --- parse flags ------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --clustername)       CLUSTERNAME="$2";      shift 2;;
    --dturl)             DTURL="$2";            shift 2;;
    --dtenvironmentid)   DT_ENV_ID="$2";        shift 2;;
    --dtenvironmenttype) DT_ENV_TYPE="$2";      shift 2;;
    --dtoperatortoken)   DTOPERATORTOKEN="$2";  shift 2;;
    --dtingesttoken)     DTINGESTTOKEN="$2";    shift 2;;
    # legacy aliases (old secret names)
    --dtapitoken)        DTOPERATORTOKEN="$2";  shift 2;;
    -h|--help)
      sed -n '1,40p' "$0"; exit 0;;
    *) echo "warn: ignoring unsupported option $1"; shift;;
  esac
done

# --- resolve tenant URL from environment ID + type if --dturl not given ----
if [[ -z "$DTURL" && -n "$DT_ENV_ID" ]]; then
  DT_ENV_TYPE="${DT_ENV_TYPE,,}"  # lowercase
  if [[ "$DT_ENV_TYPE" == "live" ]]; then
    DTURL="https://${DT_ENV_ID}.live.dynatrace.com"
  else
    DTURL="https://${DT_ENV_ID}.${DT_ENV_TYPE}.dynatracelabs.com"
  fi
fi

# --- pre-flight -------------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' is required"; exit 1; }; }
need docker
need kind
need kubectl
need helm
need jq
need git

[ -n "$DTURL" ]            || { echo "error: --dturl or --dtenvironmentid is required"; exit 1; }
[ -n "$DTOPERATORTOKEN" ]  || { echo "error: --dtoperatortoken / DT_OPERATOR_TOKEN is required"; exit 1; }
[ -n "$DTINGESTTOKEN" ]    || { echo "error: --dtingesttoken / DT_API_TOKEN is required"; exit 1; }

# Strip trailing slash from tenant URL
DTURL="${DTURL%/}"
DT_OTLP_ENDPOINT="${DTURL}/api/v2/otlp"

echo "=============================================================================="
echo "  Cluster        : $CLUSTERNAME"
echo "  Dynatrace URL  : $DTURL"
echo "  OTLP endpoint  : $DT_OTLP_ENDPOINT"
echo "  Demo manifests : $(pwd)/otel-demo-light/ (vendored, kustomize)"
echo "=============================================================================="

###############################################################################
# 1. kind cluster
###############################################################################
if kind get clusters 2>/dev/null | grep -qx "$CLUSTERNAME"; then
  echo "==> kind cluster '$CLUSTERNAME' already exists, reusing"
else
  echo "==> Creating kind cluster '$CLUSTERNAME'"
  kind create cluster --name "$CLUSTERNAME" --config kind/cluster.yaml --wait 180s
fi

kubectl cluster-info --context "kind-$CLUSTERNAME" >/dev/null
kubectl config use-context "kind-$CLUSTERNAME"

echo "==> Waiting for nodes to be Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=300s

###############################################################################
# 2. Dynatrace Operator + DynaKube (Kubernetes monitoring via ActiveGate)
###############################################################################
echo "==> Installing Dynatrace Operator via Helm"
helm upgrade dynatrace-operator oci://public.ecr.aws/dynatrace/dynatrace-operator \
  --version 1.9.0 \
  --create-namespace --namespace dynatrace \
  --install \
  --atomic

echo "==> Waiting for dynatrace-operator webhook to be ready"
kubectl -n dynatrace wait pod \
  --for=condition=ready \
  --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook \
  --timeout=300s

# Token secret consumed by the DynaKube. apiToken drives the operator
# (entities/settings/PaaS), dataIngestToken pipes metrics/traces directly
# from the ActiveGate into the tenant.
kubectl -n dynatrace create secret generic dynakube \
  --from-literal=apiToken="$DTOPERATORTOKEN" \
  --from-literal=dataIngestToken="$DTINGESTTOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# Render TENANTURL_TOREPLACE + CLUSTER_NAME_TO_REPLACE in the DynaKube CR.
# Cross-platform sed: GNU `sed -i` differs from BSD `sed -i ''`.
sed_inplace() {
  if [[ "$(uname -s)" == "Darwin" ]]; then sed -i '' "$@"; else sed -i "$@"; fi
}
sed_inplace "s,TENANTURL_TOREPLACE,$DTURL,"           dynatrace/dynakube.yaml
sed_inplace "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME," dynatrace/dynakube.yaml

echo "==> Applying DynaKube custom resource"
kubectl apply -f dynatrace/dynakube.yaml

###############################################################################
# 3. OpenTelemetry Collector → Dynatrace
###############################################################################
echo "==> Deploying OpenTelemetry Collector"
kubectl apply -f opentelemetry/otel-collector-rbac.yaml

# Credentials secret consumed by the DaemonSet via envFrom
kubectl -n otel-collector create secret generic dynatrace-credentials \
  --from-literal=endpoint="$DT_OTLP_ENDPOINT" \
  --from-literal=api-token="$DTINGESTTOKEN" \
  --from-literal=cluster-name="$CLUSTERNAME" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f opentelemetry/otel-collector.yaml

echo "==> Waiting for otel-collector DaemonSet to be ready"
kubectl -n otel-collector rollout status daemonset/otel-collector --timeout=300s

###############################################################################
# 4. opentelemetry-demo-light
#
# The manifests are vendored into otel-demo-light/ as one file per Service
# and one file per workload — same layout as
# https://github.com/Observe-Resolve/resource-optimization/tree/master/hipster-shop
# so the smart-resource-optimizer workflow can patch a single Deployment file
# in GitHub without churning Service definitions. Annotations on every
# workload tell the workflow exactly which file to update.
###############################################################################
# OTEL_SERVICE_PREFIX is an optional Codespace secret that lets multiple
# workshop attendees share one Dynatrace tenant. If set (e.g. "REX-"),
# every demo pod will report its OTEL_SERVICE_NAME as "$(PREFIX)cart"
# instead of plain "cart", so traces and entities don't collide.
#
# We render the placeholder in shared-env.yaml here (instead of templating
# the whole kustomization) so re-running deployment.sh refreshes the value
# without touching the rest of the manifests.
OTEL_SERVICE_PREFIX="${OTEL_SERVICE_PREFIX:-}"
echo "==> Setting OTEL_SERVICE_PREFIX='${OTEL_SERVICE_PREFIX}' in shared-env ConfigMap"
sed_inplace "s|OTEL_SERVICE_PREFIX_TO_REPLACE|${OTEL_SERVICE_PREFIX}|g" \
  otel-demo-light/shared-env.yaml

echo "==> Applying otel-demo-light manifests"
kubectl apply -k otel-demo-light/

# Restore the placeholder in shared-env.yaml so the file in git stays
# parameterised (next bootstrap re-renders cleanly).
sed_inplace "s|OTEL_SERVICE_PREFIX: \"${OTEL_SERVICE_PREFIX}\"|OTEL_SERVICE_PREFIX: \"OTEL_SERVICE_PREFIX_TO_REPLACE\"|" \
  otel-demo-light/shared-env.yaml

# Point demo-light at our cluster-local collector. The OpenTelemetry demo
# convention is an OTEL_EXPORTER_OTLP_ENDPOINT env on each deployment.
echo "==> Re-pointing demo telemetry at the in-cluster OTel collector"
for dep in $(kubectl -n otel-demo get deploy -o name) $(kubectl -n otel-demo get statefulset -o name); do
  kubectl -n otel-demo set env "$dep" \
    OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector.otel-collector.svc.cluster.local:4317" \
    OTEL_EXPORTER_OTLP_PROTOCOL="grpc" 2>/dev/null || true
done

echo "==> Waiting for demo pods to come up (best-effort, 5 min)"
kubectl -n otel-demo wait --for=condition=Available --all deployments --timeout=300s || true

###############################################################################
# Done
#
# The resource-optimization notebook is pre-provisioned on the trial
# Dynatrace tenant. The workflow is imported by each attendee.
###############################################################################
cat <<EOF

==============================================================================
  ✅ Resource-optimization demo deployed.

  kubectl --context kind-$CLUSTERNAME get pods -A

  Frontend → http://localhost:8080  (forwarded from kind nodePort 30080)

  Telemetry is flowing to: $DTURL
==============================================================================
EOF
