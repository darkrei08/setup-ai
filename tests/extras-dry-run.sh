#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf -- "${TMP_HOME}"' EXIT

output="$({
    HOME="${TMP_HOME}/home" \
    DOTENV_DIR="${TMP_HOME}/dotenv" \
    bash "${ROOT}/setup-ai.sh" --dry-run --only extras --yes
} 2>&1)"

for expected in \
    'npx --yes hyperframes skills update' \
    'impeccable install -y --providers=claude' \
    '--scope=global --no-hooks' \
    'npm install -g typescript-express-starter' \
    'npm install -g @alibaba-group/open-code-review' \
    '34f519533bc175d2fe287ab8316b0dd99bb9cc43'; do
    if ! grep -F -- "${expected}" <<<"${output}" >/dev/null; then
        printf 'missing planned action: %s\n' "${expected}" >&2
        exit 1
    fi
done

if [[ -e "${TMP_HOME}/home" || -e "${TMP_HOME}/dotenv" ]]; then
    printf 'extras dry-run wrote persistent state\n' >&2
    exit 1
fi

printf '%s\n' 'PASS: extras dry-run plans every issue #98 action without writing state'
