#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
site="$repo_root/deployments/aisy-dev/site-values.yaml"

check_user() {
  local slug="$1" github_login="$2"
  local values="$repo_root/deployments/$slug/values.yaml"
  local render

  render="$(helm template "$slug-workspace" "$repo_root/charts/workspace" \
    -f "$site" \
    -f "$values" \
    --set build.depot.projectId=test-project-id)"

  grep -F -- "namespace: ws-$slug" <<<"$render" >/dev/null
  grep -F -- "host: $slug.coder.shadw.stream" <<<"$render" >/dev/null
  grep -F -- 'image: "780193927358.dkr.ecr.eu-west-1.amazonaws.com/kube-coder:devlaptop-v1.35.0"' <<<"$render" >/dev/null
  grep -F -- "--github-user=$github_login" <<<"$render" >/dev/null
  grep -F -- 'secretName: kube-coder-ecr' <<<"$render" >/dev/null
  grep -F -- 'cidr: "169.254.20.10/32"' <<<"$render" >/dev/null
  grep -F -- 'external-dns.alpha.kubernetes.io/cloudflare-proxied: "false"' <<<"$render" >/dev/null
  if grep -F -- 'external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"' <<<"$render" >/dev/null; then
    echo "workspace $slug must terminate TLS directly on the ACM-backed ALB" >&2
    exit 1
  fi
}

check_user aidan aidan-aisy
check_user shlomie ShlomieLiberow

# The pre-deploy validator must render with the same site overlay and
# deploy-time Depot project ID that `make deploy` passes to Helm. Otherwise it
# falls back to the chart's basic-auth defaults and rejects this OAuth2 setup.
validate_output="$(
  SITE_VALUES="$site" \
    DEPOT_PROJECT_ID=test-project-id \
    "$repo_root/scripts/validate-user.sh" aidan
)"
grep -F -- 'validate-user: OK' <<<"$validate_output" >/dev/null
