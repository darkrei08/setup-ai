#!/usr/bin/env bash
# Container matrix for the setup-ai scripts: the same gates on every distribution
# family the installer claims, plus the PowerShell parse check in a container.
#
# The repository is copied into a writable directory inside the container because
# sourcing setup-ai.sh writes its logs next to the script, so a read-only mount
# fails for the wrong reason. Images are pulled, used with --rm, and nothing is
# left behind. macOS and Windows are not containerizable here: a Linux Docker host
# cannot run a Windows container, and there is no macOS container at all.
set -uo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROW_FMT='%-48s %-34s %s\n'
FAILED_ROWS=0

printf "$ROW_FMT" "IMAGE" "GATE" "EXIT"
printf '%s\n' "--------------------------------------------------------------------------------------"

run() { # image, label, in-container command
  local img="$1" label="$2" cmd="$3" rc out
  out=$(timeout 1200 docker run --rm -v "${REPO}":/repo:ro "$img" bash -lc \
    "cp -r /repo /work && cd /work && ${cmd}" 2>&1); rc=$?
  printf "$ROW_FMT" "$img" "$label" "$rc"
  if (( rc != 0 )); then
    (( FAILED_ROWS += 1 ))
    printf '%s\n' "$out" | tail -4 | sed 's/^/    | /'
  fi
}

# shellcheck disable=SC2016 # deferred command run later via ${BASH_GATES}; vars/subshells must expand then, not here
AI_MEMORY_DRY_RUN='aimem_prefix="$(mktemp -d)" && trap '\''rm -rf -- "${aimem_prefix}"'\'' EXIT && AIMEM_PREFIX="${aimem_prefix}" bash setup-ai.sh --dry-run --only ai-memory >/dev/null'
BASH_GATES="bash -n setup-ai.sh && bash tests/gentle-ai-cli-resolution.sh >/dev/null && bash tests/configurator-retry-check.sh >/dev/null && ${AI_MEMORY_DRY_RUN}"
NODE_GATES="${BASH_GATES} && node bin/setup-ai.mjs --list >/dev/null && bash tests/jsonl-schema.sh >/dev/null && bash tests/pi-startup-check.sh >/dev/null && bash tests/rotator-npm-ownership.sh >/dev/null"

run node:22-bookworm      "bash gates + node launcher + jsonl" "$NODE_GATES"
run debian:13             "bash gates"                        "$BASH_GATES"
run ubuntu:24.04          "bash gates"                        "$BASH_GATES"
run archlinux:latest      "bash gates"                        "$BASH_GATES"
run fedora:latest         "bash gates (util-linux-script for script)" 'dnf install -y -q util-linux-script >/dev/null 2>&1 && '"$BASH_GATES"
run opensuse/leap:latest  "bash gates"                        "$BASH_GATES"
run mcr.microsoft.com/powershell:lts-ubuntu-22.04 "pwsh parse check" 'pwsh -NoProfile -Command "\$null=[ScriptBlock]::Create((Get-Content -Raw /work/setup-ai.ps1)); \"parse ok\"" && pwsh -NoProfile -File /work/tests/powershell-lifecycle.ps1'

echo
echo "Not containerizable here: Windows (no Windows container on a Linux host) and macOS (no container image)."
echo "The live winget path is therefore pending on a Windows host, as recorded in the pull requests."

if (( FAILED_ROWS != 0 )); then exit 1; fi
