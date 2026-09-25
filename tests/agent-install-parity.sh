#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${ROOT}" node <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const root = process.env.ROOT;
const sh = fs.readFileSync(path.join(root, 'setup-ai.sh'), 'utf8');
const ps = fs.readFileSync(path.join(root, 'setup-ai.ps1'), 'utf8');
const mjs = fs.readFileSync(path.join(root, 'bin/setup-ai.mjs'), 'utf8');
const bashModules = sh.match(/MODULE_ORDER=\(([^)]+)\)/)[1].trim().split(/\s+/);
const powershellModules = ps.match(/\$ModuleOrder = @\(([^)]+)\)/)[1]
  .split(',').map((item) => item.replaceAll("'", '').trim());
const nodeModules = [...mjs.matchAll(/\{ name: "([^"]+)"/g)].map((match) => match[1]);
if (JSON.stringify(bashModules) !== JSON.stringify(powershellModules) ||
    JSON.stringify(bashModules) !== JSON.stringify(nodeModules)) {
  throw new Error(JSON.stringify({ bashModules, powershellModules, nodeModules }, null, 2));
}
for (const modules of [bashModules, powershellModules, nodeModules]) {
  if (modules.at(-1) !== 'extras') throw new Error('extras must be the final optional module');
}
const bashSkillAgents = sh.match(/SKILL_AGENT_NAMES=\(([^)]+)\)/)?.[1].trim().split(/\s+/) ?? [];
const powershellSkillAgents = ps.match(/\$SkillAgentNames = @\(([^)]+)\)/)?.[1]
  .split(',').map((item) => item.replaceAll("'", '').trim()) ?? [];
if (JSON.stringify(bashSkillAgents) !== JSON.stringify(powershellSkillAgents) ||
    bashSkillAgents.includes('antigravity') || !bashSkillAgents.includes('antigravity-cli') ||
    powershellSkillAgents.includes('antigravity') || !powershellSkillAgents.includes('antigravity-cli')) {
  throw new Error(JSON.stringify({ bashSkillAgents, powershellSkillAgents }));
}
const bashAgentConfig = sh.match(/agent_config_dir\(\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
const bashAgentRoot = sh.match(/agent_skill_root\(\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
const powershellAgentConfig = ps.match(/\$SkillAgentConfigDirs = @\{([\s\S]*?)\n\}/)?.[1] ?? '';
const powershellAgentRoot = ps.match(/\$SkillAgentRoots = @\{([\s\S]*?)\n\}/)?.[1] ?? '';
if (!bashAgentConfig.includes('antigravity-cli)') || !bashAgentConfig.includes('${HOME}/.gemini/antigravity-cli') ||
    bashAgentConfig.includes('antigravity)') || !bashAgentRoot.includes('antigravity-cli)') ||
    !powershellAgentConfig.includes("'antigravity-cli' = Join-Path $HOME \".gemini\\antigravity-cli\"") ||
    powershellAgentConfig.includes('antigravity =') ||
    !powershellAgentRoot.includes("'antigravity-cli' = Join-Path $HOME \".gemini\\antigravity-cli\\skills\"")) {
  throw new Error('Antigravity skills detection and roots must use the antigravity-cli harness');
}
const bashGentle = sh.match(/mod_gentle_ai\(\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
const powershellGentle = ps.match(/function Mod-GentleAi \{([\s\S]*?)\n\}/)?.[1] ?? '';
if (!bashGentle.includes('GENTLE_AI_AGENT_NAMES') || !bashGentle.includes('gentle_ai_agent_config_dir') ||
    !powershellGentle.includes('Get-GentleAiTargetAgents') ||
    !ps.includes("$GentleAiAgentNames = @('pi','claude-code','gemini-cli','cursor','antigravity','codex','opencode')")) {
  throw new Error('gentle-ai must retain its antigravity harness name separately from skills CLI');
}
const bashEe = sh.match(/mod_ee\(\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
const bashSkills = sh.match(/mod_skills\(\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
if (!bashEe.includes('SKILL_AGENT_NAMES') || !bashSkills.includes('SKILL_AGENT_NAMES') ||
    !ps.includes('Get-TargetSkillAgents')) {
  throw new Error('skills CLI loops must use the corrected harness list');
}
const shellOptional = sh.match(/module_is_optional\(\)\s*\{\s*\[\[([^\]]+)\]\]/)?.[1] ?? '';
const powershellOptional = ps.match(/\$ModuleOptional\s*=\s*@\{([^}]+)\}/)?.[1] ?? '';
if (!shellOptional.includes('"extras"') || !/'extras'\s*=\s*\$true/.test(powershellOptional)) {
  throw new Error('extras must be optional in Bash and PowerShell');
}
const nodeExtras = mjs.match(/\{ name: "extras",\s*core: (true|false)/);
if (!nodeExtras || nodeExtras[1] !== 'false') throw new Error('Node extras must be unchecked by default');
const bashStage = sh.match(/install_extras_skill\(\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
const psStage = ps.match(/function Install-ExtrasSkill \{([\s\S]*?)\n\}/)?.[1] ?? '';
if (!bashStage.includes('cd "${stage_home}"') || /skills@latest add[^\n]*--global/.test(bashStage) ||
    !bashStage.includes('"${stage_home}/.agents/skills/${skill}"') ||
    !psStage.includes('Push-Location -LiteralPath $stageHome') || /skills@latest add[^\n]*--global/.test(psStage) ||
    !psStage.includes('Join-Path $stageHome ".agents\\\\skills\\\\$Skill"')) {
  throw new Error('extras skills must be staged locally before canonical installation');
}
const bashLink = sh.match(/link_extras_skill\(\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
const psLink = ps.match(/function Link-ExtrasSkill \{([\s\S]*?)\n\}/)?.[1] ?? '';
const bashAgentRoots = sh.match(/agent_skill_root\(\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
if (!bashLink.includes('for agent in claude-code codex opencode gemini-cli antigravity-cli') ||
    !bashLink.includes('root="$(agent_skill_root "${agent}")"') ||
    !bashLink.includes('"${canonical}/SKILL.md"') || !bashLink.includes('skill_link_conflict') ||
    /for agent in pi\\b/.test(bashLink) ||
    !bashAgentRoots.includes('"${HOME}/.gemini/antigravity-cli/skills"') ||
    bashAgentRoots.includes('"${HOME}/.antigravity/skills"') ||
    bashLink.includes('link-skills.mjs') || !bashLink.includes('if ! link_target=') ||
    !bashLink.includes('if ! canonical_target=') || bashLink.includes('readlink "${target}"') ||
    !psLink.includes('$canonical = Join-Path $HOME ".agents\\\\skills\\\\$Skill"') || psLink.includes('$PiAgentDir') ||
    psLink.includes('$DotenvDir') || psLink.includes('link-skills.mjs') ||
    !psLink.includes('Resolve-Path -LiteralPath $target') || !psLink.includes('Resolve-Path -LiteralPath $canonical') ||
    !['.claude\\\\skills', '.codex\\\\skills', '.config\\\\opencode\\\\skills', '.gemini\\\\skills', '.gemini\\\\antigravity-cli\\\\skills'].every((root) => psLink.includes(root)) ||
    psLink.includes('.antigravity\\\\skills')) {
  throw new Error('extras must preserve copies and resolve existing link targets before comparing');
}
const bashExtras = sh.match(/mod_extras\(\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
const psExtras = ps.match(/function Mod-Extras \{([\s\S]*?)\n\}/)?.[1] ?? '';
for (const skill of [
  'Leonxlnx/taste-skill', 'design-taste-frontend',
  'blader/humanizer', 'humanizer',
  'heroui-inc/heroui', 'heroui-react',
]) {
  if (!bashExtras.includes(skill) || !psExtras.includes(skill)) throw new Error(`Missing extras skill ${skill}`);
}
const impeccableInstallArgs = 'impeccable install -y --providers=claude,codex,opencode,gemini,antigravity,pi --scope=global --no-hooks';
if (!bashExtras.includes(impeccableInstallArgs) || !psExtras.includes(impeccableInstallArgs)) {
  throw new Error('extras must install Impeccable globally without hooks');
}
const cliAnythingRef = '34f519533bc175d2fe287ab8316b0dd99bb9cc43';
if (!bashExtras.includes('npx --yes hyperframes skills update </dev/null') ||
    !psExtras.includes("'' | npx --yes hyperframes skills update") ||
    !sh.includes(`CLI_ANYTHING_REF="${cliAnythingRef}"`) || !ps.includes(`$CliAnythingRef = '${cliAnythingRef}'`)) {
  throw new Error('extras must update HyperFrames skills non-interactively and pin CLI-Anything in both scripts');
}
for (const pkg of ['typescript-express-starter', '@alibaba-group/open-code-review']) {
  if (!bashExtras.includes(`install_extras_global_package ${pkg}`) ||
      !psExtras.includes(`Install-ExtrasGlobalPackage -Package '${pkg}'`) ||
      !sh.includes(`npm-global|extras|${pkg}|-|setup-ai extras npm-global ${pkg}`)) {
    throw new Error(`extras must install, mark, and catalog ${pkg} in both scripts`);
  }
}
for (const marker of ['setup-ai extras npm-global ', 'setup-ai extras CLI-Anything ']) {
  if (!sh.includes(marker) || !ps.includes(marker)) throw new Error(`Ownership marker drift: ${marker}`);
const bashAiMemory = sh.match(/mod_ai_memory\(\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
const psAiMemory = ps.match(/function Mod-AiMemory \{([\s\S]*?)\n\}/)?.[1] ?? '';
const bashMemoryInstallAt = bashAiMemory.indexOf('run_cmd "ai-memory" env AIMEM_REF=');
const bashExistingTemplateCheckAt = bashAiMemory.indexOf('-d "${aimem_templates}"');
const bashFreshTemplateCheckAt = bashAiMemory.indexOf('-d "${aimem_templates}"', bashMemoryInstallAt);
const bashReuseAt = bashAiMemory.indexOf('return 0', bashExistingTemplateCheckAt);
const psMemoryInstallAt = psAiMemory.indexOf('& $pwshPath -NoProfile -ExecutionPolicy Bypass -File $installer');
const psExistingTemplateCheckAt = psAiMemory.indexOf('Test-Path -LiteralPath $aimemTemplates -PathType Container');
const psFreshTemplateCheckAt = psAiMemory.indexOf('Test-Path -LiteralPath $aimemTemplates -PathType Container', psMemoryInstallAt);
const psReuseAt = psAiMemory.indexOf('return');
if (!bashAiMemory.includes('local aimem_templates="${AIMEM_PREFIX}/share/ai-memory-kit/templates"') ||
    bashMemoryInstallAt < 0 || bashReuseAt < 0 ||
    bashExistingTemplateCheckAt < 0 || bashExistingTemplateCheckAt > bashReuseAt ||
    bashFreshTemplateCheckAt < bashMemoryInstallAt ||
    !psAiMemory.includes('Join-Path $aimemPrefix "share\\ai-memory-kit\\templates"') ||
    psMemoryInstallAt < 0 || psReuseAt < 0 ||
    psExistingTemplateCheckAt < 0 || psExistingTemplateCheckAt > psReuseAt ||
    psFreshTemplateCheckAt < psMemoryInstallAt) {
  throw new Error('Bash and PowerShell must verify ai-memory-kit templates at AIMEM_PREFIX/share/ai-memory-kit/templates before reuse and after install');
}
for (const needle of [
  'https://claude.ai/install.sh',
  'run_vendor_installer "claude-code"',
  'nvim --headless "+Lazy! sync" +qa',
  'XDG_CONFIG_HOME="${TMP_DIR}" NVIM_APPNAME=nvim',
  'LAZYVIM_CLONED',
  '/opt/nvim-linux-x86_64/bin',
]) {
  if (!sh.includes(needle)) throw new Error(`Bash missing ${needle}`);
}
const powershellClaude = ps.match(/function Mod-ClaudeCode \{([\s\S]*?)\n\}/)?.[1] ?? '';
if (!powershellClaude.includes('npm install -g @anthropic-ai/claude-code') ||
    powershellClaude.includes('https://claude.ai/install.ps1') ||
    powershellClaude.includes('Invoke-RemoteScriptNoPrompt')) {
  throw new Error('Claude Code PowerShell install must use npm directly');
}
for (const needle of [
  'npm install -g @anthropic-ai/claude-code',
  'function Mod-ClaudeCode',
  'nvim --headless "+Lazy! sync" +qa',
  '$script:LazyVimCloned',
]) {
  if (!ps.includes(needle)) throw new Error(`PowerShell missing ${needle}`);
}
console.log(`PASS: ${bashModules.length} module entries match across Bash, PowerShell, and Node`);
NODE
