#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

generator="openssl rand -hex 16"

for script in scripts/new-user.sh scripts/provision-user.sh; do
  if ! grep -F -- "$generator" "$script" >/dev/null; then
    echo "$script must generate an exact 32-character raw cookie secret" >&2
    exit 1
  fi
done

if grep -F -- 'openssl rand -base64 32' scripts/new-user.sh scripts/provision-user.sh >/dev/null; then
  echo "44-character base64 cookie secret generator is not allowed" >&2
  exit 1
fi

if grep -Eq '16\|24\|32\|44|24/32/44|base64-encoded forms' scripts/validate-user.sh; then
  echo "validate-user.sh must not accept 44-character cookie secrets" >&2
  exit 1
fi

grep -F -- '16|24|32)' scripts/validate-user.sh >/dev/null

for _ in $(seq 1 20); do
  secret="$(openssl rand -hex 16)"
  if [ "${#secret}" -ne 32 ] || [[ ! "$secret" =~ ^[0-9a-f]{32}$ ]]; then
    echo "cookie secret generator produced an invalid key" >&2
    exit 1
  fi
done
