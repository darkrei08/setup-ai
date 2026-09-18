#!/usr/bin/env bash
# Docker row (from the repository root; the host pi binary is mounted at /opt/pi
# and the repository is mounted read-only at /w):
# docker run --rm -i -v "$(cd -- "$(dirname "$(command -v pi)")/.." && pwd):/opt/pi:ro" -v "$PWD:/w:ro" node:22-bookworm bash /w/tests/container-c1-repro.sh
set -Eeuo pipefail

SETUP_AI_SH="${SETUP_AI_SH:-/w/setup-ai.sh}"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/setup-ai-c1.XXXXXXXX")"
trap 'rm -rf -- "${SCRATCH}"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -r "${SETUP_AI_SH}" ]] || fail "setup-ai.sh is not readable: ${SETUP_AI_SH}"
[[ -x /opt/pi/bin/pi ]] || fail "host pi is not executable at /opt/pi/bin/pi"

AGENT_DIR="${SCRATCH}/.pi/agent"
mkdir -p "${AGENT_DIR}/npm" "${SCRATCH}/bin"
printf '%s\n' '{"private":true}' > "${AGENT_DIR}/npm/package.json"
ln -s /opt/pi/bin/pi "${SCRATCH}/bin/pi"
export HOME="${SCRATCH}"
export PATH="${SCRATCH}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PI_CODING_AGENT_DIR="${AGENT_DIR}"
command -v pi >/dev/null 2>&1 || fail "pi is not on PATH"

# This is the real package pair from the reproduced C1 environment. The package
# marker above prevents npm from walking up to an unrelated project root.
npm install --prefix "${AGENT_DIR}/npm" --legacy-peer-deps --ignore-scripts --no-audit --no-fund pi-tool-display@0.5.0 gentle-pi@3.2.1

write_broken_settings() {
    mkdir -p "${AGENT_DIR}"
    cat > "${AGENT_DIR}/settings.json" <<'JSON'
{
  "packages": [
    "npm:gentle-pi",
    "npm:pi-tool-display"
  ]
}
JSON
}

run_pi() {
    local stdout="$1" stderr="$2"
    timeout 45s env PI_OFFLINE=1 pi </dev/null >"${stdout}" 2>"${stderr}"
}

write_broken_settings
if run_pi "${SCRATCH}/broken.out" "${SCRATCH}/broken.err"; then
    fail "plain gentle-pi settings unexpectedly passed startup"
fi
grep -Eiq 'conflicts' "${SCRATCH}/broken.err" || fail "broken startup stderr did not contain a conflict"
printf 'PASS: broken settings abort with a tool conflict\n'

extract_function() {
    local name="$1"
    awk -v name="${name}" '
        $0 ~ "^" name "\\(\\) \\{" { capture = 1 }
        capture {
            line = $0
            opens = gsub(/\{/, "", line)
            closes = gsub(/\}/, "", line)
            depth += opens - closes
            print
            if (depth == 0) exit
        }
    ' "${SETUP_AI_SH}"
}

PRODUCT_FUNCTIONS="${SCRATCH}/product-functions.sh"
for function_name in remove_line_from_file remove_stale_quiet_tools_switch handle_quiet_tools_conflict; do
    extract_function "${function_name}" >> "${PRODUCT_FUNCTIONS}"
done
TMP_DIR="${SCRATCH}"
HUMAN_LOG="${SCRATCH}/human.log"
PI_AGENT_DIR="${AGENT_DIR}"
: > "${HUMAN_LOG}"
log_event() {
    printf '%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "${5:-0}" "${6:-}" >> "${HUMAN_LOG}"
}
source "${PRODUCT_FUNCTIONS}"
handle_quiet_tools_conflict || fail "quiet-tools repair failed"
node -e '
    const fs = require("node:fs");
    const s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const e = s.packages.find((entry) => entry && typeof entry === "object" && entry.source === "npm:gentle-pi");
    if (!e || !e.extensions.includes("-extensions/quiet-tools.ts") || !e.extensions.includes("-extensions/pi-pretty.ts")) process.exit(1);
' "${AGENT_DIR}/settings.json" || fail "repair did not create the guarded object entry"
printf 'PASS: extracted product repair writes the guarded object entry\n'

if run_pi "${SCRATCH}/repaired.out" "${SCRATCH}/repaired.err"; then
    printf 'PASS: repaired settings pass pi startup\n'
else
    cat "${SCRATCH}/repaired.err" >&2
    fail "repaired settings still fail pi startup"
fi

write_broken_settings
if GENTLE_PI_QUIET_TOOLS=0 run_pi "${SCRATCH}/historic.out" "${SCRATCH}/historic.err"; then
    fail "historic GENTLE_PI_QUIET_TOOLS=0 variant unexpectedly passed startup"
fi
grep -Eiq 'conflicts' "${SCRATCH}/historic.err" || fail "historic variant stderr did not contain a conflict"
printf 'PASS: historic GENTLE_PI_QUIET_TOOLS=0 variant aborts\n'
