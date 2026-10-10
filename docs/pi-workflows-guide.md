# pi-extensible-workflows — Guida / Guide

> Guida bilingue pratica per installare e usare i workflow di pi.
> Practical bilingual guide to install and use pi workflows.
>
> Ogni sezione è in coppia **Italiano / English**.
> Each section is paired **Italiano / English**.
>
> Documentazione canonica upstream / Canonical upstream docs:
> - <https://vekexasia.github.io/pi-extensible-workflows/>
> - <https://github.com/vekexasia/pi-extensible-workflows>

---

## 1. Prerequisiti / Prerequisites

**Italiano**

- **Node.js >= 22.19** (engine richiesto: `>=22.19.0` da `pi-extensible-workflows` e da `@earendil-works/pi-coding-agent`). Verifica con `node --version`.
- **pi** installato e funzionante (vedi il README principale di `setup-ai`).
- **Avviso pacchetto attendibile / trusted package:** la prima volta che installi
  un'estensione pi ti verrà chiesto di considerare il pacchetto come attendibile
  ("trusted package"). È un passo previsto: conferma solo per pacchetti che riconosci
  (in questo caso `pi-extensible-workflows` e i pacchetti `@piewf/*` ufficiali).

**English**

- **Node.js >= 22.19** (engine required by both `pi-extensible-workflows` and `@earendil-works/pi-coding-agent`: `>=22.19.0`). Check with `node --version`.
- **pi** installed and working (see the main `setup-ai` README).
- **Trusted package warning:** the first time you install a pi extension, pi asks you
  to mark the package as a *trusted package*. This is expected: only confirm for
  packages you recognize (here `pi-extensible-workflows` and the official `@piewf/*`
  packages).

---

## 2. Installazione core / Core install

**Italiano**

Installa l'estensione principale dentro pi:

```bash
pi install npm:pi-extensible-workflows
```

Dopo l'installazione, **riavvia pi** per caricare l'estensione. Da quel momento
avrai a disposizione il picker `/workflow` e il tool `workflow`.

Per provare una checkout locale senza modificare le impostazioni persistenti di pi:

```bash
git clone https://github.com/vekexasia/pi-extensible-workflows.git
cd pi-extensible-workflows
npm ci
npm run check
pi --no-extensions --extension "$PWD/packages/core/src/index.ts"
```

Per installare invece il checkout come pacchetto locale usa `pi install "$PWD/packages/core"`.
In PowerShell sostituisci `$PWD/packages/core` con `(Join-Path $PWD 'packages/core')`.

**English**

Install the core extension inside pi:

```bash
pi install npm:pi-extensible-workflows
```

After installing, **restart pi** to load the extension. From then on you get the
`/workflow` picker and the `workflow` tool.

To try a source checkout for one session without changing persistent pi settings:

```bash
git clone https://github.com/vekexasia/pi-extensible-workflows.git
cd pi-extensible-workflows
npm ci
npm run check
pi --no-extensions --extension "$PWD/packages/core/src/index.ts"
```

To install the checkout as a local package instead, use `pi install "$PWD/packages/core"`.
In PowerShell, replace `$PWD/packages/core` with `(Join-Path $PWD 'packages/core')`.

---

## 3. Pacchetti opzionali / Optional packages

**Italiano**

Due pacchetti opzionali estendono i workflow: `@piewf/cli` è una CLI standalone e
`@piewf/herdr` è un'estensione pi.

```bash
npm install -g @piewf/cli       # CLI di supporto: piewf doctor / piewf inspect
pi install npm:@piewf/herdr    # estensione pi per l'integrazione con Herdr
```

- **`@piewf/cli`** fornisce i comandi diagnostici `piewf doctor` (controllo dello stato /
  ambiente) e `piewf inspect` (ispezione dei workflow/run). Utile per il troubleshooting.
- **`@piewf/herdr`** è l'**estensione pi** (Pi extension) che collega i workflow a Herdr.
  Attenzione: è **diversa** dal binario Herdr del terminale (vedi §4).

> **`setup-ai` non li installa.** Il modulo `pi-workflows` installa solo
> `pi-extensible-workflows` (release pubblicata + eventuale build locale patchata):
> `@piewf/cli` e `@piewf/herdr` non sono prerequisiti. La CLI è solo diagnostica;
> l'estensione `@piewf/herdr` resta inattiva fuori dai pane gestiti da Herdr. Entrambi
> sono opt-in. Lo stato atteso è `pi-extensible-workflows` registrato in
> `~/.pi/agent/settings.json`; l'assenza di `@piewf/herdr` non è un errore di
> installazione.
>
> Per installare la CLI, esegui `npm install -g @piewf/cli`. Per installare l'estensione
> Herdr, aggiungi solo `npm:@piewf/herdr` al manifest `pi-packages.txt` (vedi
> `pi-packages.example.txt`), oppure esegui `pi install npm:@piewf/herdr`. Il modulo
> `pi-packages` installa e verifica l'estensione rileggendo `~/.pi/agent/settings.json`.
> Nessuno dei due pacchetti è necessario per `/workflow`.

**English**

Two optional packages extend workflows: `@piewf/cli` is a standalone CLI and
`@piewf/herdr` is a pi extension.

```bash
npm install -g @piewf/cli       # helper CLI: piewf doctor / piewf inspect
pi install npm:@piewf/herdr    # pi extension for Herdr integration
```

- **`@piewf/cli`** provides the diagnostic commands `piewf doctor` (state / environment
  check) and `piewf inspect` (inspect workflows/runs). Handy for troubleshooting.
- **`@piewf/herdr`** is the **pi extension** that wires workflows to Herdr. Note: it is
  **not** the same thing as the Herdr terminal binary (see §4).

> **`setup-ai` does not install them.** The `pi-workflows` module installs only
> `pi-extensible-workflows` (published release + optional patched local build):
> `@piewf/cli` and `@piewf/herdr` are not prerequisites. The CLI is for diagnostics only;
> the `@piewf/herdr` extension stays inactive outside Herdr-managed panes. Both are
> opt-in. The expected state is `pi-extensible-workflows` registered in
> `~/.pi/agent/settings.json`; the absence of `@piewf/herdr` is not an install error.
>
> Install the CLI with `npm install -g @piewf/cli`. To install the Herdr extension, add
> only `npm:@piewf/herdr` to your `pi-packages.txt` manifest (see
> `pi-packages.example.txt`), or run `pi install npm:@piewf/herdr`. The `pi-packages`
> module installs and verifies the extension by reading `~/.pi/agent/settings.json` back.
> Neither package is needed for `/workflow`.

---

## 4. Herdr: estensione pi vs binario terminale / pi extension vs terminal binary

**Italiano**

Ci sono **due cose distinte** con nomi simili — non confonderle:

1. **Herdr** (binario del terminale): il terminale/multiplexer `herdr`, installato dal
   modulo `herdr` di `setup-ai` (`brew install herdr`, `curl -fsSL https://herdr.dev/install.sh | sh`,
   o `irm https://herdr.dev/install.ps1 | iex`).
2. **`@piewf/herdr`** (estensione pi): il ponte software installato dentro pi con
   `pi install npm:@piewf/herdr`.

Requisiti e attivazione:

- Serve avere Herdr (il binario) installato e in esecuzione.
- Registra l'integrazione con il comando esatto:

  ```bash
  herdr integration install pi
  ```

- **Il pacchetto `@piewf/herdr` si attiva solo nei pane gestiti da Herdr**
  (Herdr-managed panes). Fuori da un pane gestito da Herdr resta inattivo: è il
  comportamento previsto, non un bug.

**English**

There are **two distinct things** with similar names — do not conflate them:

1. **Herdr** (terminal binary): the `herdr` terminal/multiplexer, installed by the
   `herdr` module in `setup-ai` (`brew install herdr`,
   `curl -fsSL https://herdr.dev/install.sh | sh`, or
   `irm https://herdr.dev/install.ps1 | iex`).
2. **`@piewf/herdr`** (pi extension): the software bridge installed inside pi with
   `pi install npm:@piewf/herdr`.

Requirements and activation:

- You need Herdr (the binary) installed and running.
- Register the integration with the exact command:

  ```bash
  herdr integration install pi
  ```

- **The `@piewf/herdr` package activates only in Herdr-managed panes.** Outside a
  Herdr-managed pane it stays inactive — that is expected behavior, not a bug.

---

## 5. Il picker `/workflow` e il tool `workflow` / The `/workflow` picker and the `workflow` tool

**Italiano**

- **`/workflow`** è il **picker**: un comando slash dentro pi che elenca e controlla i
  run della sessione corrente in modo interattivo.
- **`workflow`** è il **tool** che esegue effettivamente un workflow. Parametri:
  - `name` — il nome del workflow.
  - **esattamente uno** tra `script` (contenuto inline) **oppure** `scriptPath`
    (percorso a un file di script). Non entrambi.
  - `args` — argomenti passati al workflow.
  - `foreground` — booleano: esecuzione in foreground o background (vedi §6).

**English**

- **`/workflow`** is the **picker**: a slash command inside pi that lists and controls
  runs in the current session.
- **`workflow`** is the **tool** that actually runs a workflow. Parameters:
  - `name` — the workflow name.
  - **exactly one** of `script` (inline content) **or** `scriptPath` (path to a script
    file). Not both.
  - `args` — arguments passed to the workflow.
  - `foreground` — boolean: run in foreground or background (see §6).

### Contratto completo di avvio / Complete launch contract

**Italiano**

Oltre ai campi minimi sopra, `workflow` accetta `description` (metadati leggibili),
`concurrency` (limite per-run da 1 a 16), `budget` (limiti aggregati opzionali per
`tokens`, `costUsd`, `durationMs` e `agentLaunches`) e `parentRunId` (solo un run
terminale della stessa sessione/progetto; riusa gli scope `withWorktree` compatibili,
non fa retry né resume). `scriptPath` è risolto dalla directory del progetto di lancio,
letto una volta e salvato come sorgente immutabile del run.

**English**

In addition to the required fields, `workflow` accepts `description` (human-readable
metadata), `concurrency` (per-run limit from 1 to 16), `budget` (optional aggregate
limits for `tokens`, `costUsd`, `durationMs`, and `agentLaunches`), and `parentRunId`
(a terminal run in the same session/project; it reuses compatible `withWorktree`
scopes, but does not retry or resume). `scriptPath` is resolved from the launch project,
read once, and saved as the run's immutable source.

### Funzioni di workflow del repository / Repository workflow functions

**Italiano**

I repository di configurazione (come `dotenv`) possono definire funzioni di workflow aggiuntive (`developIssues`, `developUntilApproved`, `devIssuesInBatches`, `fetchIssueDetails`, `tddDev`).
Il modulo `pi-workflows` di `setup-ai` possiede e garantisce il collegamento dei moduli da `${DOTENV_DIR}/pi/agent/extensions/pi-ext-workflows` verso `~/.pi/agent/extensions/pi-ext-workflows`, rendendo `developIssues` e le altre funzioni disponibili in `workflow_catalog`.

**English**

Configuration repositories (such as `dotenv`) can provide custom workflow functions (`developIssues`, `developUntilApproved`, `devIssuesInBatches`, `fetchIssueDetails`, `tddDev`).
The `setup-ai` `pi-workflows` module owns and maintains the link from `${DOTENV_DIR}/pi/agent/extensions/pi-ext-workflows` to `~/.pi/agent/extensions/pi-ext-workflows`, exposing `developIssues` and related functions in `workflow_catalog`.

---

## 6. Foreground vs background / Foreground vs background

**Italiano**

- **Foreground** (`foreground: true`): il tool **attende** il completamento del workflow
  e restituisce il risultato in linea.
- **Background** (`foreground: false`): il tool restituisce subito un **run ID** e le
  informazioni per il follow-up; il workflow prosegue in background e lo monitori con le
  operazioni della §7.
- **`backgroundWidget`**: impostazione globale che abilita/disabilita l'albero live delle
  esecuzioni in background e le ricevute persistenti del transcript. È **solo globale**
  (global-only): si configura nel file settings globale (vedi §8), non per singolo
  workflow/progetto. La resa dei workflow in foreground non cambia.

**English**

- **Foreground** (`foreground: true`): the tool **waits** for the workflow to finish and
  returns the result inline.
- **Background** (`foreground: false`): the tool returns immediately with a **run ID** and
  follow-up info; the workflow keeps running in the background and you monitor it with the
  operations in §7.
- **`backgroundWidget`**: a global setting that enables/disables the live background-run
  tree and durable background transcript receipts. It is **global-only** — configured in
  the global settings file (see §8), not per workflow/project. Foreground rendering is
  unchanged.

---

## 7. Run ID e operazioni / Run IDs and operations

**Italiano**

Un'esecuzione in background produce un **run ID**. Usa questi tool (nomi esatti) per
gestirla; `workflow_resume` serve soprattutto per run `budget_exhausted`, mentre
`workflow_retry` accetta solo un run `failed` persistito nella sessione e nel progetto
correnti e crea un nuovo run collegato:

| Tool | Cosa fa |
|---|---|
| `workflow_status` | Stato di un run. |
| `workflow_stop` | Ferma un run. |
| `workflow_retry` | Riprova un run. |
| `workflow_resume` | Riprende un run sospeso. |
| `workflow_respond` | Invia una risposta a un run che attende input. |

**English**

A background run yields a **run ID**. Use these tools (exact names) to manage it;
`workflow_resume` is primarily for `budget_exhausted` runs, while `workflow_retry` accepts
only a persisted `failed` run in the current project and session, then creates a linked
new run:

| Tool | What it does |
|---|---|
| `workflow_status` | Status of a run. |
| `workflow_stop` | Stop a run. |
| `workflow_retry` | Retry a run. |
| `workflow_resume` | Resume a suspended run. |
| `workflow_respond` | Send a response to a run awaiting input. |

---

## 8. Impostazioni / Settings

**Italiano**

Le impostazioni globali vivono nel file:

```
<agentDir>/pi-extensible-workflows/settings.json
```

`<agentDir>` è la directory dell'agent pi (di solito `~/.pi/agent`). Esiste anche un
file di progetto in `<cwd>/.pi/pi-extensible-workflows/settings.json`; tuttavia
`backgroundWidget` (vedi §6) è una chiave **solo globale**. Gli alias dei modelli si
configurano nella chiave `modelAliases`.

**English**

Global settings live in:

```
<agentDir>/pi-extensible-workflows/settings.json
```

`<agentDir>` is the pi agent directory (normally `~/.pi/agent`). A project file may also
exist at `<cwd>/.pi/pi-extensible-workflows/settings.json`; however, `backgroundWidget`
(see §6) is a **global-only** key. Configure model aliases under `modelAliases`.

### Schema e precedenza / Schema and precedence

**Italiano**

Le chiavi top-level riconosciute sono `concurrency`, `backgroundWidget`, `modelAliases`,
`skills`, `extensions`, `extensionSettings` e `tools`. Il runtime rifiuta JSON malformato,
chiavi sconosciute, alias con target mancanti o cicli, e valori non validi: correggi sempre
il percorso indicato nell'errore prima di fare resume. La precedenza effettiva è:
`defaults < global < progetto trusted < opzioni per-run`. Un campo dichiarato dal progetto
sostituisce quel campo globale; oggetti e array non vengono fusi in profondità.

Per limitare le risorse di un agent usa selettori Minimatch in ordine: ogni candidato parte
abilitato, una corrispondenza positiva abilita e `!pattern` disabilita; vince l'ultima
corrispondenza. Usa `!*` prima di pattern positivi per creare una allow-list, oppure `!*`
da solo per non selezionare nulla. I selettori non possono creare tool, skill o estensioni
non disponibili.

**English**

Recognized top-level keys are `concurrency`, `backgroundWidget`, `modelAliases`, `skills`,
`extensions`, `extensionSettings`, and `tools`. The runtime rejects malformed JSON, unknown
keys, aliases with missing targets or cycles, and invalid values: fix the path named in the
error before resuming. Effective precedence is `defaults < global < trusted project <
per-run options`. A project-declared field replaces that global field; objects and arrays
are not deep-merged.

To restrict agent resources, use ordered Minimatch selectors: every candidate starts
enabled, a positive match enables it, and `!pattern` disables it; the last match wins.
Put `!*` before positive patterns to make an allow-list, or use `!*` alone to select none.
Selectors cannot create unavailable tools, skills, or extensions.

---

## 9. Selezione del modello / Model selection

**Italiano**

I modelli concreti hanno la forma `provider/model:thinking`, dove `:thinking` indica il
livello di ragionamento (es. `:high`).

Per **verificare quali modelli sono disponibili** usa:

```bash
pi --list-models "termine"
```

dove `"termine"` è un filtro di ricerca. **Controlla sempre la disponibilità reale prima
di usare un modello.**

> `gpt-5.6-luna:high` è solo un esempio di nome/livello da cercare e verificare con
> `pi --list-models`; non è una conferma che quel modello esista. Per usarlo servirebbe
> comunque l'ID completo `provider/model:thinking` restituito da Pi.

Un modello concreto passato a un agent deve includere il suffisso `:thinking`. Un alias
può puntare a un modello concreto o a un altro alias; per esempio `cheap-model:low`
riutilizza il target dell'alias ma ne sovrascrive il livello di ragionamento. Cambiare gli
alias vale per i nuovi launch e per i resume: ogni segmento di esecuzione salva la propria
mappa effettiva.

**English**

Concrete models have the form `provider/model:thinking`, where `:thinking` indicates the
reasoning level (e.g. `:high`).

To **check which models are available** use:

```bash
pi --list-models "term"
```

where `"term"` is a search filter. **Always verify actual availability before using a
model.**

> `gpt-5.6-luna:high` is only an example name/level to search for and verify with
> `pi --list-models`; it is not a claim that the model exists. To use it, you would still
> need the full `provider/model:thinking` ID returned by Pi.

A concrete model passed to an agent must include the `:thinking` suffix. An alias may target
a concrete model or another alias; for example, `cheap-model:low` reuses the alias target
while overriding its thinking level. Alias changes affect new launches and resumes: each
execution segment stores its effective mapping.

---

## 10. Ruoli e alias / Roles and aliases

**Italiano**

- **Alias**: nomi brevi per modelli/configurazioni. Gli alias sono **case-sensitive**
  (le maiuscole/minuscole contano): `Dev` e `dev` non sono lo stesso alias.
- **Ruoli / Roles**: profili predefiniti per il tipo di lavoro. Includono:
  `developer`, `reviewer`, `scout`, `oracle`, `researcher`. Puoi aggiungere ruoli trusted in
  `<agentDir>/pi-extensible-workflows/roles/<name>.md` o nel progetto trusted.

**English**

- **Aliases**: short names for models/configurations. Aliases are **case-sensitive**:
  `Dev` and `dev` are not the same alias.
- **Roles**: predefined profiles for the kind of work. They include
  `developer`, `reviewer`, `scout`, `oracle`, and `researcher`. Trusted custom roles can
  live at `<agentDir>/pi-extensible-workflows/roles/<name>.md` or in the trusted project.

I ruoli forniscono default per modello, tool, skill, estensioni e contesto; le opzioni
per-agent possono sovrascrivere questi default. Per il formato Markdown, frontmatter,
selettori e contratti completi consulta la guida canonica dei ruoli:
<https://vekexasia.github.io/pi-extensible-workflows/roles.html>.

Roles provide defaults for model, tools, skills, extensions, and context; per-agent options
can override those defaults. For Markdown format, frontmatter, selectors, and the complete
contract, use the canonical roles guide:
<https://vekexasia.github.io/pi-extensible-workflows/roles.html>.

---

## 11. Esempio minimo di workflow / Minimal workflow example

**Italiano**

Esecuzione in **foreground** (attende il risultato) con script JavaScript inline:

```jsonc
// tool: workflow
{
  "name": "hello",
  "script": "return await agent(\"Di qualcosa di breve su pi.\");",
  "args": null,
  "foreground": true
}
```

Esecuzione in **background** (restituisce un run ID) con file JavaScript:

```jsonc
// tool: workflow
{
  "name": "review",
  "scriptPath": "./workflows/review.js",
  "args": {"scope": "current changes"},
  "foreground": false
}
```

Poi controlla lo stato con `workflow_status` usando il run ID restituito. Lo script del
workflow è JavaScript sandboxed: per comandi host usa il primitivo `shell(...)`, non un
comando shell nudo.

Ricorda: fornisci **esattamente uno** tra `script` e `scriptPath`, mai entrambi.

**English**

**Foreground** run (waits for the result) with an inline JavaScript script:

```jsonc
// tool: workflow
{
  "name": "hello",
  "script": "return await agent(\"Say something brief about pi.\");",
  "args": null,
  "foreground": true
}
```

**Background** run (returns a run ID) with a JavaScript file:

```jsonc
// tool: workflow
{
  "name": "review",
  "scriptPath": "./workflows/review.js",
  "args": {"scope": "current changes"},
  "foreground": false
}
```

Then check status with `workflow_status` using the returned run ID. Workflow scripts are
sandboxed JavaScript: use the `shell(...)` primitive for host commands, not a bare shell
command.

Remember: provide **exactly one** of `script` or `scriptPath`, never both.

---

## 12. DSL sandboxed / Sandboxed DSL

**Italiano**

Lo script del workflow è JavaScript sandboxed: non ha `import`, filesystem, rete,
timer, `eval`/codice dinamico o accesso diretto al processo host. Le primitive disponibili
sono `agent(prompt, options)`, `agent.create({ name })` + `handle.send(...)`,
`parallel(name, tasks)`, `pipeline(name, items, stages)`, `prompt(template, values)`,
`shell(command, options)`, `phase(name)`, `log(message)`, `checkpoint(input)` e
`withWorktree(name, callback)`.

`shell()` è l'unica eccezione mediata dall'host: eredita la directory del workflow o
dello scope `withWorktree`. Un exit code diverso da zero è un **risultato** da gestire;
launch failure e timeout usano `SHELL_FAILED`. I risultati devono restare entro 10 MB
per il confine RPC. Usa `withWorktree` per isolare collaborazioni e `checkpoint` quando
serve una decisione umana.

**English**

Workflow scripts are sandboxed JavaScript: they have no `import`, filesystem, network,
timer, `eval`/dynamic code, or direct access to the host process. Available primitives
are `agent(prompt, options)`, `agent.create({ name })` + `handle.send(...)`,
`parallel(name, tasks)`, `pipeline(name, items, stages)`, `prompt(template, values)`,
`shell(command, options)`, `phase(name)`, `log(message)`, `checkpoint(input)`, and
`withWorktree(name, callback)`.

`shell()` is the only host-mediated exception: it inherits the workflow or active
`withWorktree` directory. A non-zero exit code is a **result** to handle; launch failures
and timeouts use `SHELL_FAILED`. Results must stay within the 10 MB RPC boundary. Use
`withWorktree` for isolated collaboration and `checkpoint` when a human decision is
required.

```javascript
const result = await withWorktree("verify", async ({ path, branch }) => {
  const tests = await shell("npm test", { timeoutMs: 120000 });
  return { path, branch, tests };
});
return result;
```

---

## 13. Neovim: integrazione dell'editor / Neovim: editor integration

**Italiano**

Neovim può essere usato come **percorso di integrazione dell'editor** con pi: apre file,
mostra diff, guida l'editing dall'interno dell'editor. Per esempio, puoi modificare uno
script con `nvim workflows/review.js` e poi avviarlo tramite il tool `workflow` di Pi.

**Confine importante:** Neovim è un **percorso di integrazione dell'editor**, **non** un
transport di workflow integrato. I workflow non "girano dentro Neovim": vengono eseguiti
dall'estensione pi (foreground/background, run ID, ecc. come sopra). Neovim è il lato
editor, non il motore dei workflow.

**English**

Neovim can be used as an **editor integration path** with pi: opening files, showing
diffs, and driving edits from within the editor. For example, edit a script with
`nvim workflows/review.js`, then launch it through Pi's `workflow` tool.

**Important boundary:** Neovim is an **editor integration path**, **not** a built-in
workflow transport. Workflows do not "run inside Neovim": they are executed by the pi
extension (foreground/background, run IDs, etc. as above). Neovim is the editor side, not
the workflow engine.

---

## 14. Lifecycle, budget e CLI / Lifecycle, budgets, and CLI

**Italiano**

Gli stati principali sono `queued`, `running`, `pausing`, `paused`, `awaiting_input`,
`budget_exhausted`, `completed`, `failed`, `stopped` e `interrupted`. `workflow_stop` è
immediato e irreversibile. Prima di un recovery leggi `workflow_status` e passa lo stato
restituito come `expectedState`: `workflow_retry` accetta solo un run persistito `failed`,
crea un nuovo child collegato e riproduce le operazioni journaled completate; non ripete
quelle side effect già registrate, ma gli effetti esterni non sono garantiti exactly-once.
`workflow_resume` è il percorso per `budget_exhausted` e per i run pausati/interrotti.

Un budget aggregato limita `tokens`, `costUsd`, `durationMs` e `agentLaunches`:

```json
{
  "budget": {
    "tokens": { "soft": 100000, "hard": 120000 },
    "costUsd": { "soft": 5, "hard": 6 },
    "durationMs": { "soft": 900000, "hard": 1200000 },
    "agentLaunches": { "soft": 8, "hard": 10 }
  }
}
```

Il superamento di un hard limit porta a `budget_exhausted`; un aumento o la rimozione di
un limite richiede l'approvazione della proposta esatta con `workflow_respond`. Non usare
`workflow_retry` per un budget esaurito.

Per operare dal terminale, con `@piewf/cli` installato:

```bash
npx piewf doctor [--role <role>] [--json]
npx piewf inspect [session-id] [--json|--summary]
npx piewf transcript <session-file>
npx piewf run --script <workflow.js> [--name <name>] [--input <json>]
npx piewf export <workflow-name> [--output <path>] [--force]
npx piewf bundle <workflow-name> [--output <directory>] [--force]
```

`doctor` è read-only; `inspect` legge i run persistiti. `piewf doctor cleanup` è separato,
prima mostra un dry-run e cancella solo con `--yes`: usalo con attenzione.

**English**

The main states are `queued`, `running`, `pausing`, `paused`, `awaiting_input`,
`budget_exhausted`, `completed`, `failed`, `stopped`, and `interrupted`. `workflow_stop` is
immediate and irreversible. Before recovery, read `workflow_status` and pass its returned
state as `expectedState`: `workflow_retry` accepts only a persisted `failed` run, creates a
linked child, and replays completed journal operations; it does not repeat journaled side
effects, but external effects are not guaranteed exactly once. `workflow_resume` is the
path for `budget_exhausted` and paused/interrupted runs.

An aggregate budget limits `tokens`, `costUsd`, `durationMs`, and `agentLaunches`:

```json
{
  "budget": {
    "tokens": { "soft": 100000, "hard": 120000 },
    "costUsd": { "soft": 5, "hard": 6 },
    "durationMs": { "soft": 900000, "hard": 1200000 },
    "agentLaunches": { "soft": 8, "hard": 10 }
  }
}
```

Crossing a hard limit enters `budget_exhausted`; raising or removing a limit requires
approval of the exact proposal with `workflow_respond`. Do not use `workflow_retry` for an
exhausted budget.

For terminal operations, with `@piewf/cli` installed:

```bash
npx piewf doctor [--role <role>] [--json]
npx piewf inspect [session-id] [--json|--summary]
npx piewf transcript <session-file>
npx piewf run --script <workflow.js> [--name <name>] [--input <json>]
npx piewf export <workflow-name> [--output <path>] [--force]
npx piewf bundle <workflow-name> [--output <directory>] [--force]
```

`doctor` is read-only; `inspect` reads persisted runs. `piewf doctor cleanup` is separate,
previews first, and deletes only with `--yes`: use it carefully.

### Storage e privacy / Storage and privacy

I run sono salvati sotto `<agentDir>/../workflows/projects/.../sessions/<session-id>/runs/`;
la directory effettiva dipende dal valore di `PI_CODING_AGENT_DIR`. Il run conserva la
sorgente `workflow.js`, lo snapshot per l'esecuzione/resume, risultati e, per gli agent,
i prompt di sistema effettivi. Questi artefatti possono contenere istruzioni di progetto,
ruoli, configurazione e dati sensibili: trattali come privati e usa `inspect`/cleanup invece
di cancellare directory a mano. Le directory sono protette dal runtime, ma il controllo
accessi del sistema operativo resta decisivo.

Runs are stored under `<agentDir>/../workflows/projects/.../sessions/<session-id>/runs/`;
the effective root follows `PI_CODING_AGENT_DIR`. A run keeps `workflow.js`, its execution/
resume snapshot, results, and (for agents) effective system prompts. These artifacts may
contain project instructions, roles, configuration, and sensitive data: treat them as
private and use `inspect`/cleanup instead of deleting directories manually. Runtime
permissions help, but operating-system access control remains decisive.

---

## 15. Note per OS / OS notes

**Italiano**

- **Windows**: usa PowerShell 7.3+; un comando per riga (niente `\` di continuazione bash).
  Per il binario Herdr usa `irm https://herdr.dev/install.ps1 | iex`. Se hai appena
  installato node o pi, apri un **nuovo terminale** perché il PATH si aggiorni. I comandi
  `pi install npm:...` sono identici tra gli OS.
- **macOS**: Herdr via `brew install herdr`; il resto è come sopra.
- **Linux**: Herdr via `curl -fsSL https://herdr.dev/install.sh | sh`; il resto è come sopra.

I comandi pi (`pi install`, `pi --list-models`, `/workflow`, il tool `workflow`) sono gli
stessi su tutti gli OS.

**English**

- **Windows**: use PowerShell 7.3+; one command per line (no bash `\` line continuations).
  For the Herdr binary, use `irm https://herdr.dev/install.ps1 | iex`. If you just
  installed node or pi, open a **new terminal** so PATH refreshes. The `pi install npm:...`
  commands are identical across OSes.
- **macOS**: Herdr via `brew install herdr`; the rest is as above.
- **Linux**: Herdr via `curl -fsSL https://herdr.dev/install.sh | sh`; the rest is as above.

The pi commands (`pi install`, `pi --list-models`, `/workflow`, the `workflow` tool) are
the same across all OSes.

---

## 16. Troubleshooting

**Italiano**

- **Il tool `workflow` o `/workflow` non compare:** verifica di aver eseguito
  `pi install npm:pi-extensible-workflows` e di aver **riavviato pi**.
- **Node troppo vecchio:** `node --version` deve essere `>= 22.19`.
- **Diagnostica generale:** con `@piewf/cli` installato, esegui `piewf doctor`; per
  ispezionare workflow/run, `piewf inspect`.
- **Herdr non si attiva:** ricorda che `@piewf/herdr` si attiva **solo nei pane gestiti da
  Herdr**; assicurati che Herdr sia in esecuzione e che tu abbia eseguito
  `herdr integration install pi`.
- **Modello non trovato:** verifica il nome reale con `pi --list-models "termine"`; la
  forma è `provider/model:thinking`.
- **Alias non riconosciuto:** gli alias sono **case-sensitive** — controlla le maiuscole.
- **Windows `EPERM` durante il rename di `state.json`:** aggiorna a una versione del
  pacchetto che include il retry dei lock transitori, riavvia Pi e chiudi eventuali
  processi Pi concorrenti. Defender, indicizzazione o sincronizzazione possono tenere
  il file aperto per un momento; non cancellare manualmente il run mentre è attivo.

**English**

- **The `workflow` tool or `/workflow` does not appear:** confirm you ran
  `pi install npm:pi-extensible-workflows` and **restarted pi**.
- **Node too old:** `node --version` must be `>= 22.19`.
- **General diagnostics:** with `@piewf/cli` installed, run `piewf doctor`; to inspect
  workflows/runs, `piewf inspect`.
- **Herdr does not activate:** remember `@piewf/herdr` activates **only in Herdr-managed
  panes**; make sure Herdr is running and that you ran `herdr integration install pi`.
- **Model not found:** check the real name with `pi --list-models "term"`; the form is
  `provider/model:thinking`.
- **Alias not recognized:** aliases are **case-sensitive** — check the casing.
- **Windows `EPERM` while renaming `state.json`:** update to a package version that
  includes transient-lock retries, restart Pi, and close competing Pi processes.
  Defender, indexing, or sync tools may hold the file briefly; do not manually delete
  an active run.

---

## 17. Link canonici / Canonical links

- Documentazione / Docs: <https://vekexasia.github.io/pi-extensible-workflows/>
- Developer guide: <https://vekexasia.github.io/pi-extensible-workflows/developers.html>
- Roles: <https://vekexasia.github.io/pi-extensible-workflows/roles.html>
- Herdr: <https://vekexasia.github.io/pi-extensible-workflows/herdr.html>
- Repository GitHub: <https://github.com/vekexasia/pi-extensible-workflows>
