#!/usr/bin/env bash
# Bootstrap script — runs once after the Codespace is created.
#
# Reads DT_ENVIRONMENT_ID / DT_ENVIRONMENT_TYPE / DT_OPERATOR_TOKEN /
# DT_API_TOKEN from Codespace secrets (set in GitHub → Settings →
# Codespaces → Repository secrets) and runs the end-to-end deployment:
#   1. creates a single-node kind cluster
#   2. installs the Dynatrace Operator + DynaKube
#   3. deploys the OpenTelemetry Collector wired to Dynatrace
#   4. deploys opentelemetry-demo-light into the cluster
#
# The resource-optimization notebook is pre-provisioned on the trial
# Dynatrace tenant. The workflow template is imported by each attendee
# via the Dynatrace Workflows UI.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Repo root: $REPO_ROOT"

missing=()
[[ -z "${DT_ENVIRONMENT_ID:-}"   ]] && missing+=("DT_ENVIRONMENT_ID")
[[ -z "${DT_ENVIRONMENT_TYPE:-}" ]] && missing+=("DT_ENVIRONMENT_TYPE")
[[ -z "${DT_OPERATOR_TOKEN:-}"   ]] && missing+=("DT_OPERATOR_TOKEN")
[[ -z "${DT_API_TOKEN:-}"        ]] && missing+=("DT_API_TOKEN")

if (( ${#missing[@]} > 0 )); then
  cat <<EOF

##############################################################################
# Codespace secrets not set: ${missing[*]}
#
# This Codespace expects four repository-level Codespace secrets:
#   - DT_ENVIRONMENT_ID    Dynatrace tenant identifier (e.g. abc12345)
#   - DT_ENVIRONMENT_TYPE  Environment type: live, sprint, or dev
#   - DT_OPERATOR_TOKEN    Operator token (installer download, settings,
#                          entities, ActiveGate token creation)
#   - DT_API_TOKEN         Data-ingest token (metrics.ingest, logs.ingest,
#                          openTelemetryTrace.ingest)
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

# --- Construct tenant URL from environment ID + type ----------------------
DT_ENVIRONMENT_TYPE="${DT_ENVIRONMENT_TYPE,,}"   # lowercase
if [[ "$DT_ENVIRONMENT_TYPE" == "live" ]]; then
  DT_TENANT_URL="https://${DT_ENVIRONMENT_ID}.live.dynatrace.com"
else
  DT_TENANT_URL="https://${DT_ENVIRONMENT_ID}.${DT_ENVIRONMENT_TYPE}.dynatracelabs.com"
fi
echo "==> Resolved tenant URL: $DT_TENANT_URL"

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
  --dturl           "$DT_TENANT_URL" \
  --dtoperatortoken "$DT_OPERATOR_TOKEN" \
  --dtingesttoken   "$DT_API_TOKEN"
