#!/usr/bin/env bash
# Registry parity (Bash/PowerShell/Node) and fake-npx argv, dry-run and idempotency checks.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "${TMP}"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# 1. Parity: both scripts declare identical entries and the menu lists every extras id.
ROOT="${ROOT}" node --input-type=module - <<'JS'
import { readFileSync } from 'node:fs';
const read = (f) => readFileSync(`${process.env.ROOT}/${f}`, 'utf8');
const sh = read('setup-ai.sh'), ps = read('setup-ai.ps1'), mjs = read('bin/setup-ai.mjs');
const bash = [...sh.match(/SKILL_REGISTRY=\(([\s\S]*?)\n\)/)[1].matchAll(/"([^"]+)"/g)]
  .map((m) => m[1].split('|')).map(([id, mod, src, skills, agents]) => [id, mod, src, skills, agents].join('|'));
const pwsh = [...ps.match(/\$SkillRegistry = @\(([\s\S]*?)\n\)/)[1].matchAll(/@\{([^}]+)\}/g)].map((m) => {
  const f = Object.fromEntries([...m[1].matchAll(/(\w+)\s*=\s*('[^']*'|@\([^)]*\))/g)].map((x) => [x[1], x[2]]));
  const list = (v) => [...v.matchAll(/'([^']*)'/g)].map((x) => x[1]).join(',');
  return [list(f.Id), list(f.Module), list(f.Source), list(f.Skills), list(f.Agents)].join('|');
});
if (bash.length < 7 || JSON.stringify(bash) !== JSON.stringify(pwsh)) {
  throw new Error(`registry mismatch\nbash: ${bash.join('\n  ')}\npwsh: ${pwsh.join('\n  ')}`);
}
for (const e of bash.map((x) => x.split('|')).filter((x) => x[1] === 'extras')) {
  if (!mjs.includes(`{ extra: true, name: "${e[0]}",`)) {
    throw new Error(`menu is missing extras entry ${e[0]}`);
  }
}
JS

# 2. Fake npx: records argv and "installs" every requested skill under $HOME/.agents/skills.
mkdir -p "${TMP}/bin"
cat > "${TMP}/bin/npx" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_NPX_LOG}"
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[i]}" == "--skill" ]]; then
        for ((j = i + 1; j < ${#args[@]}; j++)); do
            [[ "${args[j]}" == --* ]] && break
            mkdir -p "${HOME}/.agents/skills/${args[j]}"
            printf 'fake\n' > "${HOME}/.agents/skills/${args[j]}/SKILL.md"
        done
    fi
done
FAKE
# Containers run as root without sudo; the installer's bootstrap only needs it to exist.
printf '#!/usr/bin/env bash\nexec "$@"\n' > "${TMP}/bin/sudo"
chmod +x "${TMP}/bin/npx" "${TMP}/bin/sudo"

run_setup() {
    HOME="${TMP}/home" DOTENV_DIR="${TMP}/dotenv" FAKE_NPX_LOG="${TMP}/npx.log" \
        PATH="${TMP}/bin:${PATH}" bash "${ROOT}/setup-ai.sh" "$@" >"${TMP}/out.txt" 2>&1 \
        || { cat "${TMP}/out.txt" >&2; fail "setup-ai.sh $* exited non-zero"; }
}

mkdir -p "${TMP}/home"
: > "${TMP}/npx.log"

# Dry run: plans every install but runs nothing and writes nothing.
run_setup --dry-run --extras taste,heroui --yes
[[ ! -s "${TMP}/npx.log" ]] || fail "dry-run executed npx"
[[ -z "$(ls -A "${TMP}/home")" ]] || fail "dry-run wrote into HOME"
grep -F -- 'skills@latest add Leonxlnx/taste-skill --skill design-taste-frontend --global --agent pi --copy --yes' "${TMP}/out.txt" >/dev/null \
    || fail "dry-run did not plan the taste argv"
grep -F -- 'heroui-react' "${TMP}/out.txt" >/dev/null || fail "dry-run did not plan heroui"
grep -F -- 'humanizer --global' "${TMP}/out.txt" >/dev/null && fail "dry-run planned an unselected entry"

# Item-by-item selection: exact argv, only the chosen entries.
run_setup --extras taste,humanizer --yes
expected=$'--yes skills@latest add Leonxlnx/taste-skill --skill design-taste-frontend --global --agent pi --copy --yes\n--yes skills@latest add blader/humanizer --skill humanizer --global --agent pi --copy --yes'
[[ "$(cat "${TMP}/npx.log")" == "${expected}" ]] || { cat "${TMP}/npx.log" >&2; fail "unexpected argv for --extras taste,humanizer"; }
for s in design-taste-frontend humanizer; do
    [[ -f "${TMP}/home/.agents/skills/${s}/SKILL.md" ]] || fail "${s} not installed at the canonical path"
done
[[ ! -e "${TMP}/home/.agents/skills/heroui-react" ]] || fail "unselected heroui-react was installed"

# Idempotent: a re-run repeats the same argv and succeeds.
: > "${TMP}/npx.log"
run_setup --extras taste,humanizer --yes
[[ "$(cat "${TMP}/npx.log")" == "${expected}" ]] || fail "re-run changed argv"

# Unknown entry is rejected.
if HOME="${TMP}/home" bash "${ROOT}/setup-ai.sh" --extras nope --dry-run --yes >/dev/null 2>&1; then
    fail "unknown extras entry accepted"
fi

# Argument edge cases: trimmed ids, empty value, uninstall conflict, launcher forms.
run_setup --dry-run --extras "taste, heroui" --yes
for bad in "--extras=" "--extras= , " "--uninstall --extras taste" "--only , --extras taste" "--extras TASTE"; do
    bad_args=()
    case "${bad}" in
        "--extras= , ") bad_args=("--extras= , ") ;;
        *) IFS=' ' read -r -a bad_args <<< "${bad}" ;;
    esac
    if HOME="${TMP}/home" bash "${ROOT}/setup-ai.sh" "${bad_args[@]}" --dry-run --yes >/dev/null 2>&1; then fail "setup-ai.sh accepted: ${bad}"; fi
    if HOME="${TMP}/home" node "${ROOT}/bin/setup-ai.mjs" "${bad_args[@]}" --dry-run >/dev/null 2>&1; then fail "launcher accepted: ${bad}"; fi
done
HOME="${TMP}/home" PATH="${TMP}/bin:${PATH}" node "${ROOT}/bin/setup-ai.mjs" --extras=taste --dry-run 2>&1 \
    | grep -F -- 'Leonxlnx/taste-skill --skill design-taste-frontend --global --agent pi --copy --yes' >/dev/null \
    || fail "launcher dropped --extras=taste"

# PowerShell parity: -Extras validation exits 2 (needs pwsh; skipped where absent).
if command -v pwsh >/dev/null 2>&1; then
    for bad in 'nope' ' , ' 'TASTE'; do
        if HOME="${TMP}/home" pwsh -NoProfile -File "${ROOT}/setup-ai.ps1" -Extras "${bad}" >/dev/null 2>&1; then fail "setup-ai.ps1 accepted -Extras '${bad}'"; fi
    done
    if HOME="${TMP}/home" pwsh -NoProfile -File "${ROOT}/setup-ai.ps1" -Only , -Extras taste >/dev/null 2>&1; then fail "setup-ai.ps1 accepted -Only , -Extras"; fi
    if HOME="${TMP}/home" pwsh -NoProfile -File "${ROOT}/setup-ai.ps1" -All -Extras taste >/dev/null 2>&1; then fail "setup-ai.ps1 accepted -All -Extras"; fi
    if HOME="${TMP}/home" pwsh -NoProfile -File "${ROOT}/setup-ai.ps1" -Uninstall -Extras taste >/dev/null 2>&1; then fail "setup-ai.ps1 accepted -Uninstall -Extras"; fi
fi

# skills module: one call per registry entry and detected agent (defaults to pi).
: > "${TMP}/npx.log"
rm -rf "${TMP}/home" && mkdir -p "${TMP}/home"
run_setup --only skills --yes
expected_skills=$'--yes skills@latest add herdrdev/herdr --skill herdr --global --agent pi --copy --yes\n--yes skills@latest add mattpocock/skills --skill triage grill-me grilling wayfinder domain-modeling prototype research --global --agent pi --copy --yes\n--yes skills@latest add https://github.com/pedronauck/skills --skill typescript-advanced --global --agent pi --copy --yes\n--yes skills@latest add humanlayer/skills --skill show-me --global --agent pi --copy --yes'
[[ "$(cat "${TMP}/npx.log")" == "${expected_skills}" ]] || { cat "${TMP}/npx.log" >&2; fail "unexpected skills argv"; }

printf '%s\n' 'PASS: skills registry parity, argv, dry-run and idempotency'
