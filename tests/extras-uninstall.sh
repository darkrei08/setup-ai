#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf -- "${WORK}"' EXIT
REF="34f519533bc175d2fe287ab8316b0dd99bb9cc43"

# Run a copy so the uninstall logs land in the scratch directory, never in the repository.
cp "${ROOT}/setup-ai.sh" "${WORK}/setup-ai.sh"
mkdir -p "${WORK}/bin"
cat > "${WORK}/bin/npm" <<'NPM'
#!/usr/bin/env bash
case "$1 $2" in
    "root -g") printf '%s\n' "${FAKE_NPM_ROOT}" ;;
    "uninstall -g") printf '%s\n' "$3" >> "${FAKE_NPM_LOG}"; rm -rf -- "${FAKE_NPM_ROOT:?}/$3" ;;
    *) exit 1 ;;
esac
NPM
chmod +x "${WORK}/bin/npm"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

setup_state() {
    local home="${WORK}/home" root="${WORK}/npm-root"
    rm -rf -- "${home}" "${root}" "${WORK}/npm.log"
    mkdir -p "${root}/typescript-express-starter" "${root}/@alibaba-group/open-code-review" \
        "${home}/.pi/agent/extensions/cli-anything"
    printf '{"name":"typescript-express-starter"}\n' > "${root}/typescript-express-starter/package.json"
    printf 'setup-ai extras npm-global typescript-express-starter\n' > "${root}/typescript-express-starter/.setup-ai-owned"
    # Present with the right identity but no marker: the user installed it, so it stays.
    printf '{"name":"@alibaba-group/open-code-review"}\n' > "${root}/@alibaba-group/open-code-review/package.json"
    printf 'export default {}\n' > "${home}/.pi/agent/extensions/cli-anything/index.ts"
    printf 'setup-ai extras CLI-Anything %s\n' "$1" > "${home}/.pi/agent/extensions/cli-anything/.setup-ai-owned"
    : > "${WORK}/npm.log"
}

run_uninstall() {
    HOME="${WORK}/home" PATH="${WORK}/bin:${PATH}" FAKE_NPM_ROOT="${WORK}/npm-root" \
        FAKE_NPM_LOG="${WORK}/npm.log" bash "${WORK}/setup-ai.sh" --uninstall --only extras --yes "$@" 2>&1
}

cli_dir="${WORK}/home/.pi/agent/extensions/cli-anything"

setup_state "${REF}"
out="$(run_uninstall)" || fail "uninstall without --purge exited non-zero: ${out}"
[[ "$(cat "${WORK}/npm.log")" == "typescript-express-starter" ]] || fail "only the marked npm package may be removed: $(cat "${WORK}/npm.log") ${out}"
[[ -d "${WORK}/npm-root/@alibaba-group/open-code-review" ]] || fail "unmarked npm package was removed"
[[ -d "${cli_dir}" ]] || fail "CLI-Anything was removed without --purge"
grep -F 'needs --purge' <<<"${out}" >/dev/null || fail "CLI-Anything skip did not name --purge"

setup_state "${REF}"
out="$(run_uninstall --purge)" || fail "uninstall --purge exited non-zero: ${out}"
[[ ! -e "${cli_dir}" ]] || fail "owned CLI-Anything was not removed with --purge"

setup_state "0000000000000000000000000000000000000000"
out="$(run_uninstall --purge)" || fail "uninstall with a foreign marker exited non-zero: ${out}"
[[ -d "${cli_dir}" ]] || fail "CLI-Anything with a mismatched marker was removed"

printf '%s\n' 'PASS: extras uninstall removes only exactly marked items, and destructive ones only with --purge'
