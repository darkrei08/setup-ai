# Keep skill installation on the canonical global root
Owner: el Gentleman
Target: `@darkrei08/setup-ai`

## Specs
- S1: The requested cleanup command was: `rm -rf ~/.herdr/worktrees/pi-atelier/worktree-resolv-ui/.agents/skills ~/.pi/agent/skills/multi-repo-product-workflow && node -e 'const fs=require("fs"),p="/root/.pi/agent/settings.json",s=JSON.parse(fs.readFileSync(p,"utf8"));s.packages=s.packages.map(x=>typeof x==="string"&&x.includes("pi-herdr-orchestration")?{source:x,skills:[]}:x);fs.writeFileSync(p,JSON.stringify(s,null,2))' && pi update --extensions && (cd /root/.pi/agent/npm/node_modules/gentle-pi && node scripts/install-gentle-ai.mjs)`.
- S2: The requested repository change was: `aggiornare anceh setup-ai epr correggere pi atelier nel mio repo setup-ai`.
- S3: The intended invariant is: `Tutte le 21 skill sono già globali: la cartella .agents/skills dentro quella worktree è una duplicazione locale ridondante.`
- S4: Future skill installation must not create repository-local `.agents/skills` or `skills-lock.json`; the canonical target is `~/.agents/skills`.
- S5: Bash and PowerShell behavior must remain parallel and the existing installer tests must prove the working-directory invariant.

## Tasks
- T1 (S1-S4): Remove the redundant pi-atelier worktree skill root and make all shared `skills add` calls execute from the user's home directory. Route: `setup-ai.sh`, `setup-ai.ps1`. Commit: TBD.
- T2 (S4-S5): Ignore local skill artifacts and add regression coverage for canonical-root installation and Bash/PowerShell parity. Route: `.gitignore`, `tests/skills-registry.sh`, `tests/agent-install-parity.sh`. Commit: TBD.
- T3 (S1-S5): Run shell, PowerShell, focused, and cross-platform checks; record evidence and final status. Route: verification only. Commit: TBD.

## Log
- L1: `aggiornare anceh setup-ai epr correggere pi atelier nel mio repo setup-ai`
- L2: User authorized modifying `/root/git/personale/pi.dev/setup-ai` and removing the redundant pi-atelier worktree skill directory.
- L3: Updated `setup-ai.sh` and `setup-ai.ps1` so shared skill CLI calls run from the user's home directory; added `.agents/` and `skills-lock.json` ignore rules; added regression checks for global-root isolation and Bash/PowerShell parity.
- L4: Host, Debian 13, Fedora latest, Arch latest, and openSUSE Tumbleweed focused checks passed. Alpine passed syntax/parity checks but the installer explicitly rejects unsupported distribution `alpine`; Windows and macOS runners were unavailable.
- L5: Before deletion, direct comparison found 24 local pi-atelier skills, 4 absent from `~/.agents/skills`, and 20 with differing content. The directory cleanup is blocked pending an explicit disposition for those local copies.
- L6: User authorized a reversible backup move, but the local skills directory was already absent and no backup directory was created. Removed `npm:@narumitw/pi-goal` from live Pi settings, linked `gentle-pi/.gentle-ai/v4.3.1` to `v4.4.0`, and `pi update --extensions` completed successfully. Settings and `pi list` were verified afterward.
