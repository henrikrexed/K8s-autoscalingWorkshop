#!/usr/bin/env bash
# Bootstrap script — runs once after the Codespace is created.
#
# Reads DT_TENANT_URL / DT_API_TOKEN / DT_INGEST_TOKEN from Codespace secrets
# (set in GitHub → Settings → Codespaces → Repository secrets) and runs the
# end-to-end deployment:
#   1. creates a single-node kind cluster
#   2. installs the Dynatrace Operator + DynaKube
#   3. deploys the OpenTelemetry Collector wired to Dynatrace
#   4. deploys opentelemetry-demo-light into the cluster
#
# The resource-optimization notebook + workflow are pre-provisioned on the
# trial Dynatrace tenant — no dtctl step here.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Repo root: $REPO_ROOT"

missing=()
[[ -z "${DT_TENANT_URL:-}"   ]] && missing+=("DT_TENANT_URL")
[[ -z "${DT_API_TOKEN:-}"    ]] && missing+=("DT_API_TOKEN")
[[ -z "${DT_INGEST_TOKEN:-}" ]] && missing+=("DT_INGEST_TOKEN")

if (( ${#missing[@]} > 0 )); then
  cat <<EOF

##############################################################################
# Codespace secrets not set: ${missing[*]}
#
# This Codespace expects three repository-level Codespace secrets:
#   - DT_TENANT_URL    e.g. https://abc12345.live.dynatrace.com
#   - DT_API_TOKEN     operator/automation token (read+write settings, workflows, notebooks)
#   - DT_INGEST_TOKEN  data-ingest token (metrics.ingest, logs.ingest, openTelemetryTrace.ingest)
#
# Set them at:
#   https://github.com/<owner>/<repo>/settings/secrets/codespaces
#
# Then rebuild this Codespace, OR run manually:
#   bash deployment.sh
##############################################################################

EOF
  exit 0
fi

# Rewrite the resource-optimization annotations in otel-demo-light/*.yaml
# to point at THIS fork (so the smart-resource-optimizer workflow files PRs
# against the attendee's repo, not the upstream workshop). Idempotent.
echo "==> Codespace name:    ${CODESPACE_NAME:-(not in a Codespace)}"
echo "==> GitHub repository: ${GITHUB_REPOSITORY:-(unset)}"
bash .devcontainer/rewrite-annotations.sh

# If CLUSTER_NAME is set in the environment (rare), honour it. Otherwise let
# deployment.sh derive it from $CODESPACE_NAME — same logic, single source.
bash deployment.sh \
  ${CLUSTER_NAME:+--clustername "$CLUSTER_NAME"} \
  --dturl        "$DT_TENANT_URL" \
  --dtapitoken   "$DT_API_TOKEN" \
  --dtingesttoken "$DT_INGEST_TOKEN"
