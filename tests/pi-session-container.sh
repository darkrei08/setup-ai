#!/usr/bin/env bash
# Pi-session test per distribution: does a real `pi` install and start inside a
# container of that family?
#
# It is not a copy of the bash gates in container-matrix.sh. Those check this
# repository's scripts; this one checks the thing the installer exists to deliver,
# which is a working `pi` on the target distribution. The steps are ordered so a
# failure says where it broke: node, the vendor installer, the binary, the CLI's
# own subsystems, then a real session attempt.
#
# A bare container has no provider credentials, so the session step is expected to
# reach the provider and be refused there. That is reported as what it is, never as
# a pass: the value of the step is proving the process starts and gets that far.
#
# Usage: tests/pi-session-container.sh <image> [node-version]
set -uo pipefail

IMAGE="${1:?usage: pi-session-container.sh <image> [node-version]}"
NODE_VERSION="${2:-v22.23.2}"

# The vendor installer writes to $HOME/.pi/agent/bin and says so on stdout; it does
# not use ~/.local/bin, which is the trap this recipe was written to avoid.
RECIPE=$(cat <<'RECIPE_EOF'
set -u
step() { printf '%-14s %s\n' "$1" "$2"; }
need() { command -v "$1" >/dev/null 2>&1; }

if need apt-get; then apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq curl ca-certificates xz-utils >/dev/null 2>&1
elif need dnf; then dnf install -y -q curl ca-certificates xz >/dev/null 2>&1
elif need pacman; then pacman -Sy --noconfirm --needed curl ca-certificates xz >/dev/null 2>&1
elif need zypper; then zypper --non-interactive install -y curl ca-certificates xz >/dev/null 2>&1
fi
need curl || { step curl MISSING; exit 1; }

# pi needs Node >= 22.19, which most distribution packages are too old for, so the
# official tarball is used instead of the distro package. That keeps the test about
# the distribution and not about its Node version.
NODE_VERSION="${NODE_VERSION:?}"
curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz" -o /tmp/node.tar.xz || { step node DOWNLOAD_FAILED; exit 1; }
mkdir -p /opt && tar -xJf /tmp/node.tar.xz -C /opt || { step node EXTRACT_FAILED; exit 1; }
ln -sf "/opt/node-${NODE_VERSION}-linux-x64/bin/node" /usr/local/bin/node
ln -sf "/opt/node-${NODE_VERSION}-linux-x64/bin/npm" /usr/local/bin/npm
step node "$(node -v 2>&1)"

curl -fsSL https://pi.dev/install.sh -o /tmp/pi-install.sh || { step installer DOWNLOAD_FAILED; exit 1; }
if sh /tmp/pi-install.sh >/tmp/pi-install.log 2>&1; then step installer exit_0; else step installer "FAILED rc=$?"; tail -5 /tmp/pi-install.log; exit 1; fi

export PATH="$HOME/.pi/agent/bin:$PATH"
if ! command -v pi >/dev/null 2>&1; then step pi "NOT_ON_PATH (looked in $HOME/.pi/agent/bin)"; exit 1; fi
step pi "$(pi --version 2>&1 | head -1)"

if pi --help >/dev/null 2>&1; then step cli help_ok; else step cli HELP_FAILED; fi
if pi --list-models >/dev/null 2>&1; then step catalog models_listed; else step catalog LIST_FAILED; fi

# A real session. In a bare container there is no provider credential, so a refusal
# from the provider is the expected outcome and proves the process reached it.
out=$(timeout 180 pi -p "Reply with exactly PI_OK" 2>&1); rc=$?
case "$rc" in
  0)  case "$out" in *PI_OK*) step session PI_OK ;; *) step session "rc_0_unexpected: $(printf '%s' "$out" | tail -1)" ;; esac ;;
  124) step session TIMEOUT ;;
  *)  step session "reached_provider_and_was_refused (rc=$rc): $(printf '%s' "$out" | grep -iE 'auth|credential|provider|api key|login' | head -1)" ;;
esac
RECIPE_EOF
)

echo "IMAGE ${IMAGE}"
out=$(timeout 900 docker run --rm -e NODE_VERSION="${NODE_VERSION}" "${IMAGE}" bash -lc "${RECIPE}" 2>&1); rc=$?
printf '%s\n' "$out" | sed 's/^/  /'
if (( rc != 0 )); then echo "  RESULT rc=${rc} (see the step that failed)"; else echo "  RESULT ok"; fi
exit "$rc"
