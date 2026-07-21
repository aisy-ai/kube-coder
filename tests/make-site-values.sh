#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
site_values="deployments/aisy-dev/site-values.yaml"

output="$(make -C "$repo_root" -n deploy \
  USER=example-user \
  SITE_VALUES="$site_values" \
  DEPOT_PROJECT_ID=test-project-id \
  | perl -0pe 's/\\\n\s*/ /g')"

base_command="$(printf '%s\n' "$output" | grep '^helm upgrade base-infrastructure ')"
workspace_command="$(printf '%s\n' "$output" | grep '^helm upgrade example-user-workspace ')"

for command in "$base_command" "$workspace_command"; do
  grep -F -- "-f $site_values" <<<"$command" >/dev/null
  grep -F -- '--set build.depot.projectId=test-project-id' <<<"$command" >/dev/null
done

grep -F -- '-f ./deployments/example-user/values.yaml' <<<"$workspace_command" >/dev/null
if grep -F -- '-f ./deployments/example-user/values.yaml' <<<"$base_command" >/dev/null; then
  echo "base-infrastructure must not receive per-user values" >&2
  exit 1
fi
