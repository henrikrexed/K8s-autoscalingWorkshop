#!/usr/bin/env bash
# Rewrites the resource-optimization annotations in otel-demo-light/*.yaml
# to point at the FORK the Codespace is running from, so the smart-resource-
# optimizer workflow opens PRs against the attendee's fork (not the upstream
# henrikrexed/K8s-autoscalingWorkshop).
#
# Detection order:
#   1. $GITHUB_REPOSITORY      — set automatically inside a GitHub Codespace
#      and inside GitHub Actions: "<owner>/<repo>"
#   2. `git remote get-url origin` — fallback for plain local clones
#
# Branch detection:
#   `git rev-parse --abbrev-ref HEAD` (current branch the Codespace is on)
#
# Annotations rewritten on every Deployment/StatefulSet (both top-level
# metadata AND pod-template metadata):
#   - resource-optimization.dynatrace.com/github-repo
#   - resource-optimization.dynatrace.com/github-rep    (truncated key used by the workflow's DQL)
#   - resource-optimization.dynatrace.com/github-branch
#
# The github-path annotation is NOT touched — paths are relative to the
# repo root and identical across forks.
#
# Idempotent: if values already match the detected fork/branch, no changes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ─── detect repo ────────────────────────────────────────────────────────────
DETECTED_REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "$DETECTED_REPO" ]]; then
  origin=$(git remote get-url origin 2>/dev/null || true)
  if [[ -n "$origin" ]]; then
    # Accept SSH ("git@github.com:owner/repo.git") and HTTPS
    # ("https://github.com/owner/repo.git") forms.
    DETECTED_REPO=$(printf '%s' "$origin" \
      | sed -E 's|^git@github\.com:||; s|^https?://github\.com/||; s|\.git$||')
  fi
fi

if [[ -z "$DETECTED_REPO" || "$DETECTED_REPO" != */* ]]; then
  echo "rewrite-annotations: could not detect GitHub repo — leaving annotations unchanged."
  echo "  GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-(unset)}"
  echo "  git remote origin=$(git remote get-url origin 2>/dev/null || echo "(no git remote)")"
  exit 0
fi

NEW_REPO_URL="github.com/${DETECTED_REPO}"

# ─── detect branch ──────────────────────────────────────────────────────────
NEW_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
# Detached HEAD (e.g. fresh container checkout) → fall back to default branch
if [[ "$NEW_BRANCH" == "HEAD" ]]; then
  NEW_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null \
    || git ls-remote --symref origin HEAD 2>/dev/null \
       | awk '/^ref:/ {sub("refs/heads/", "", $2); print $2; exit}' \
    || echo "main")
fi
NEW_BRANCH="${NEW_BRANCH:-main}"

# ─── current values (idempotency check) ─────────────────────────────────────
CURRENT_REPO_URL=$(grep -hoE 'github\.com/[^"]+' otel-demo-light/*.yaml 2>/dev/null \
  | sort -u | head -n1 || true)
CURRENT_BRANCH=$(grep -hoE 'github-branch: *"[^"]+"' otel-demo-light/*.yaml 2>/dev/null \
  | head -n1 | sed -E 's/.*"([^"]+)".*/\1/' || true)

if [[ "$CURRENT_REPO_URL" == "$NEW_REPO_URL" && "$CURRENT_BRANCH" == "$NEW_BRANCH" ]]; then
  echo "rewrite-annotations: annotations already point at ${NEW_REPO_URL}@${NEW_BRANCH} — nothing to do."
  exit 0
fi

echo "rewrite-annotations:"
echo "  fork:    ${NEW_REPO_URL}      (was ${CURRENT_REPO_URL:-unknown})"
echo "  branch:  ${NEW_BRANCH}        (was ${CURRENT_BRANCH:-unknown})"

# ─── cross-platform sed ─────────────────────────────────────────────────────
sed_inplace() {
  if [[ "$(uname -s)" == "Darwin" ]]; then sed -i '' "$@"; else sed -i "$@"; fi
}

# Escape `/` in repo URL for sed (the URL doesn't contain `|`, our separator,
# but it does contain `/` we'd otherwise have to escape if we used `/` as
# the sed delimiter).
CHANGED_FILES=()
for f in otel-demo-light/*.yaml; do
  # Only rewrite files that actually carry the annotation.
  grep -q 'resource-optimization.dynatrace.com/github' "$f" || continue

  before=$(cat "$f")

  # Rewrite the repo URL (handles BOTH github-repo and github-rep — the
  # truncated key the workflow's DQL queries).
  sed_inplace -E \
    "s|github\\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+|${NEW_REPO_URL}|g" \
    "$f"

  # Rewrite the branch annotation — quoted, with optional leading indent.
  sed_inplace -E \
    "s|(resource-optimization\\.dynatrace\\.com/github-branch:[[:space:]]*)\"[^\"]+\"|\\1\"${NEW_BRANCH}\"|g" \
    "$f"

  if [[ "$before" != "$(cat "$f")" ]]; then
    CHANGED_FILES+=("$f")
  fi
done

if (( ${#CHANGED_FILES[@]} == 0 )); then
  echo "rewrite-annotations: done. No files needed changes."
  exit 0
fi

echo "rewrite-annotations: rewrote ${#CHANGED_FILES[@]} files."

# ─── auto-commit + push so the fork matches the cluster state ───────────────
# When the smart-resource-optimizer workflow fires, it goes to GitHub to
# read+patch the file referenced by the live pod's annotation. The pod
# annotation (post-rewrite) points at the fork; we want GitHub to actually
# *have* the same annotation in the file at that path. So commit+push.
#
# Skip entirely if:
#   - $AUTO_COMMIT_ANNOTATIONS=false (opt-out)
#   - we don't appear to be in a Codespace (no $CODESPACE_NAME)
#   - the working tree has unrelated uncommitted changes (don't bundle them)
#   - no push permission (we log and continue — demo still works locally)
if [[ "${AUTO_COMMIT_ANNOTATIONS:-true}" != "true" ]]; then
  echo "rewrite-annotations: AUTO_COMMIT_ANNOTATIONS=false — leaving changes uncommitted."
  exit 0
fi

if [[ -z "${CODESPACE_NAME:-}" && -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "rewrite-annotations: not in a Codespace — leaving changes uncommitted."
  echo "  (Run 'git add otel-demo-light/*.yaml && git commit && git push' yourself if you want the fork repo to match.)"
  exit 0
fi

# Refuse to auto-commit if the user has other uncommitted work — we'd
# bundle it into our commit and surprise them.
unrelated=$(git status --porcelain -- ':!otel-demo-light/*.yaml' 2>/dev/null | grep -v '^?? ' || true)
if [[ -n "$unrelated" ]]; then
  echo "rewrite-annotations: detected unrelated uncommitted changes — skipping auto-commit."
  echo "  Stage them yourself, or run with AUTO_COMMIT_ANNOTATIONS=false."
  exit 0
fi

echo "==> Committing annotation rewrite to ${DETECTED_REPO}@${NEW_BRANCH}"
git -c user.name="codespace-bootstrap" \
    -c user.email="codespace-bootstrap@users.noreply.github.com" \
    add -- otel-demo-light/*.yaml
git -c user.name="codespace-bootstrap" \
    -c user.email="codespace-bootstrap@users.noreply.github.com" \
    commit -m "chore(bootstrap): point resource-optimization annotations at ${DETECTED_REPO}@${NEW_BRANCH}" \
  || { echo "rewrite-annotations: nothing to commit (already up to date)."; exit 0; }

if git push origin "HEAD:${NEW_BRANCH}"; then
  echo "rewrite-annotations: pushed to origin/${NEW_BRANCH}."
else
  echo "rewrite-annotations: push failed (no permission?). Cluster will still work — but"
  echo "  the smart-resource-optimizer workflow will see a mismatch between the live pod"
  echo "  annotations and the repo file when it goes to open a PR."
fi
