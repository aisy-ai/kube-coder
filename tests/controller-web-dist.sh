#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="charts/workspace-controller/web-dist/index.html"

cd "$repo_root"

if ! git ls-files --error-unmatch "$bundle" >/dev/null 2>&1; then
  echo "$bundle must be tracked so GitOps/Argo receives the controller SPA" >&2
  exit 1
fi

if [ ! -s "$bundle" ]; then
  echo "$bundle is missing or empty; run 'make controller-web'" >&2
  exit 1
fi

bytes="$(wc -c < "$bundle")"
if [ "$bytes" -gt 1000000 ]; then
  echo "$bundle is $bytes bytes and exceeds the safe ConfigMap limit" >&2
  exit 1
fi

render="$(
  helm template test-wc charts/workspace-controller \
    -f charts/workspace-controller/tests/test-values.yaml \
    --show-only templates/controller-web-configmap.yaml
)"
if grep -F -- 'SPA not built. Run' <<<"$render" >/dev/null; then
  echo "workspace-controller chart rendered the placeholder instead of the SPA" >&2
  exit 1
fi
