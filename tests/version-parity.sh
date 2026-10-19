#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
package_version="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)",\{0,1\}[[:space:]]*$/\1/p' "${ROOT}/package.json" | head -1)"
bash_version="$(sed -n 's/^SCRIPT_VERSION="\([^"]*\)"$/\1/p' "${ROOT}/setup-ai.sh")"
powershell_version="$(sed -n 's/^\$ScriptVersion = "\([^"]*\)"$/\1/p' "${ROOT}/setup-ai.ps1")"

if [[ -z "${package_version}" || "${bash_version}" != "${package_version}" || "${powershell_version}" != "${package_version}" ]]; then
    printf 'version parity failed: package=%s bash=%s powershell=%s\n' \
        "${package_version}" "${bash_version}" "${powershell_version}" >&2
    exit 1
fi
printf 'version parity passed: %s\n' "${package_version}"
