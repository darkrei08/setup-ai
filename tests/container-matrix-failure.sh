#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if output=$(env -u DOCKER_CONTEXT DOCKER_CONFIG=/dev/null DOCKER_HOST=unix:///dev/null \
  bash "${SCRIPT_DIR}/container-matrix.sh" 2>&1); then
  status=0
else
  status=$?
fi
printf '%s\n' "$output"

if (( status == 0 )); then
  printf '%s\n' "FAIL: container matrix succeeded although every Docker row should fail" >&2
  exit 1
fi
if [[ "$output" != *"unix:///dev/null"* ]]; then
  printf '%s\n' "FAIL: matrix output did not show the unavailable Docker socket" >&2
  exit 1
fi

for image in \
  node:22-bookworm \
  debian:13 \
  ubuntu:24.04 \
  archlinux:latest \
  fedora:latest \
  opensuse/leap:latest \
  mcr.microsoft.com/powershell:lts-ubuntu-22.04; do
  if ! grep -F -- "$image" <<<"$output" | grep -Eq '[[:space:]][1-9][0-9]*$'; then
    printf 'FAIL: missing failed matrix row for %s\n' "$image" >&2
    exit 1
  fi
done

printf 'PASS: matrix reported all failed rows and exited %s\n' "$status"
