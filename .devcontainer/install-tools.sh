#!/usr/bin/env bash
# Installs CLIs that aren't covered by devcontainer features:
#   - kind (kubernetes-in-docker)
#   - dtctl (Dynatrace CLI for notebooks / workflows)
#   - yq, jq

set -euo pipefail

echo "==> Installing system packages (jq, yq, curl)"
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends jq curl ca-certificates

# yq (mikefarah)
if ! command -v yq >/dev/null 2>&1; then
  echo "==> Installing yq"
  YQ_VERSION="v4.44.3"
  sudo curl -fsSL -o /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
  sudo chmod +x /usr/local/bin/yq
fi

# kind
if ! command -v kind >/dev/null 2>&1; then
  echo "==> Installing kind"
  KIND_VERSION="v0.23.0"
  sudo curl -fsSL -o /usr/local/bin/kind \
    "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
  sudo chmod +x /usr/local/bin/kind
fi

# dtctl is intentionally NOT installed — the resource-optimization notebook
# is pre-provisioned on the trial tenant and the workflow is imported by
# each attendee via the Dynatrace Workflows UI.

echo "==> Versions"
docker version --format '{{.Client.Version}}' || true
kubectl version --client --output=yaml || true
helm version --short || true
kind version || true
jq --version
yq --version

echo "==> Tool install complete"
