# Pi extensions and packages — Guida / Guide

> Guida di riferimento bilingue per le estensioni e i pacchetti pi installati da `setup-ai`.
> Bilingual reference for the pi extensions and packages installed by `setup-ai`.
>
> Ogni sezione è in coppia **Italiano / English**; i blocchi di codice condivisi sono
> identici nelle due lingue.
> Each section is paired **Italiano / English**; shared code blocks are identical in both.
>
> Comportamento implementato in / Behavior implemented in `setup-ai.sh` (module
> `pi`, `pi-packages`, `pi-workflows`) e nel manifest di esempio
> `pi-packages.example.txt`. Dove una voce è un consiglio e non comportamento
> implementato, è etichettata **(raccomandazione)** / **(recommendation)**.
>
> Guida correlata / Related guide:
> [pi-workflows-guide.md](pi-workflows-guide.md).

---

## 1. Dove Pi tiene i pacchetti / Where Pi keeps packages

**Italiano**

Pi legge i pacchetti da **due** root npm di scope utente, e devono contenere la
**stessa build**:

- `~/.pi/agent/npm` — **managed root**: è la root che `pi install` e
  `pi update --extensions` scrivono e caricano. È anche la root che pi usa per gli
  aggiornamenti.
- `~/.pi/agent/extensions` — **shared resolution root**: setup-ai vi installa la
  stessa versione così il codice delle estensioni può importare quei pacchetti
  senza dipendere da una singola copia.

Il rischio di shadowing: se aggiorni una sola root, la copia vecchia resta
raggiungibile e può essere quella risolta. Un'estensione caricata da pi legge dal
managed root, mentre un `import` (o npm stesso, risalendo l'albero) può trovare la
copia stale in `<agentDir>/extensions` o in un `node_modules` antenato. Per questo
setup-ai scrive in entrambe le root e **verifica leggendo il path esatto**
(`<dir>/node_modules/<pkg>/package.json`) invece di usare `require.resolve`, che
risale l'albero e può risolvere una copia shadow (falso `version_mismatch`).

Il percorso è costruito da `$HOME`; pi supporta `PI_CODING_AGENT_DIR` per spostare
la agent dir, ma `setup-ai.sh` **non** legge quella variabile.

**English**

Pi reads packages from **two** user-scope npm roots, and they must hold the **same
build**:

- `~/.pi/agent/npm` — **managed root**: what `pi install` and
  `pi update --extensions` write and load, and the root pi updates through.
- `~/.pi/agent/extensions` — **shared resolution root**: setup-ai installs the same
  version there so extension code can import those packages without depending on a
  single copy.

The shadowing risk: update only one root and the stale copy stays reachable and may
be the one that resolves. An extension loaded by pi reads from the managed root,
while an `import` (or npm itself, walking up the tree) can find the stale copy in
`<agentDir>/extensions` or in an ancestor `node_modules`. That is why setup-ai
writes both roots and **verifies by reading the exact path**
(`<dir>/node_modules/<pkg>/package.json`) instead of using `require.resolve`, which
ascends the tree and can resolve a shadowing copy (a false `version_mismatch`).

The path is built from `$HOME`; pi supports `PI_CODING_AGENT_DIR` to relocate the
agent dir, but `setup-ai.sh` does **not** read that variable.

```bash
# both roots should hold the same artifact
ls -l ~/.pi/agent/npm/node_modules/pi-extensible-workflows/package.json \
      ~/.pi/agent/extensions/node_modules/pi-extensible-workflows/package.json
```

---

## 2. npm 12 e sorgenti remote (`EALLOWREMOTE`) / npm 12 and remote sources

**Italiano**

npm 12 imposta `allow-remote=none` come default: qualsiasi dipendenza che risolva
un URL/tarball ("remote source") fa abortire l'installazione con `EALLOWREMOTE`.
pi esegue le installazioni gestite come
`npm install <spec> --prefix <agentDir>/npm --legacy-peer-deps`, e npm risolve il
proprio `.npmrc` locale dal prefix che riceve: l'opt-in deve quindi stare **nella
root di installazione**, mai globale e mai nella cwd del chiamante.

Perché una sola dipendenza rompe tutto: `pi update --extensions` reinstalla *tutti*
i pacchetti configurati attraverso il managed root, quindi un singolo sorgente con
dipendenza URL/tarball interrompe l'intero comando, non solo quel pacchetto.

Cosa fa setup-ai (`ensure_npm_remote_sources`):

- crea la root e la marca come project root npm con
  `{"name":"pi-extensions","private":true}`, così npm non può risalire in un
  progetto antenato;
- legge `npm --version` e scrive `allow-remote=all` in `<root>/.npmrc` **solo** se
  la major è `>= 12`; con npm < 12 logga `remote_sources_default` e non scrive
  nulla (la chiave non esiste in quelle versioni);
- scrive in modalità **append-only** (un `.npmrc` esistente appartiene all'utente e
  può contenere altre chiavi);
- **verifica leggendo il file che npm leggerà davvero**; se la verifica fallisce
  logga `remote_sources_unverified` (ERROR) e il modulo fallisce invece di
  proseguire.

setup-ai scrive anche `ignore-scripts=false` (append-only) nelle root delle
estensioni, così gli script di installazione delle dipendenze sono ammessi lì.

Inoltre npm 12 **blocca gli script di installazione** di ogni dipendenza finché il
pacchetto non è approvato (`allowScripts` in `<root>/package.json`). `pi install`
esegue un semplice `npm install`, quindi su una macchina nuova lo script bloccato non
viene mai eseguito: per `gentle-pi` è lo script che installa il binario locale di
review `gentle-ai`. L'helper `approve_npm_install_scripts` gira **dopo** i moduli che
installano i pacchetti pi (l'approvazione accetta solo pacchetti già installati),
approva i tre pacchetti con script - `gentle-pi`, `node-pty`, `pi-tool-display` - e
poi esegue `npm rebuild`, perché l'approvazione da sola non riesegue lo script già
installato. L'approvazione è **per nome** (`npm install-scripts approve
--no-allow-scripts-pin`), non il pin `<pkg>@<versione>` che npm scrive per default: pi
aggiorna i pacchetti da sé (`pi update --extensions`) e un pin smette di coprire la
versione nuova, ri-blocca lo script e rimuove in silenzio ciò che installa (per
`gentle-pi`, il binario di review) finché l'installer non rigira; il nome copre ogni
versione e npm converte in nome un pin già presente. Verifica rileggendo lo stato di
npm: evento `install_scripts_approved`; un npm senza `install-scripts` (npm < 12)
logga `install_scripts_unsupported` e viene saltato, un pacchetto assente è un salto.

**English**

npm 12 defaults to `allow-remote=none`: any dependency that resolves a URL/tarball
("remote source") aborts the install with `EALLOWREMOTE`. pi runs managed installs
as `npm install <spec> --prefix <agentDir>/npm --legacy-peer-deps`, and npm resolves
its local `.npmrc` from the prefix it is given: the opt-in therefore belongs **in
the install root**, never globally and never in the caller's cwd.

Why one dependency breaks everything: `pi update --extensions` reinstalls *every*
configured package through the managed root, so a single source with a URL/tarball
dependency aborts the whole command, not just that package.

What setup-ai does (`ensure_npm_remote_sources`):

- creates the root and marks it as an npm project root with
  `{"name":"pi-extensions","private":true}`, so npm cannot walk up into an ancestor
  project;
- reads `npm --version` and writes `allow-remote=all` into `<root>/.npmrc` **only**
  when the major is `>= 12`; with npm < 12 it logs `remote_sources_default` and
  writes nothing (the key does not exist in those versions);
- is **append-only** (an existing `.npmrc` belongs to the user and may hold other
  keys);
- **verifies by reading the file npm will actually read**; when verification fails
  it logs `remote_sources_unverified` (ERROR) and the module fails instead of
  continuing.

setup-ai also writes `ignore-scripts=false` (append-only) into the extensions
roots, so dependency install scripts are allowed there.

npm 12 also **blocks dependency install scripts** until the package is approved
(`allowScripts` in `<root>/package.json`). `pi install` runs a plain `npm install`,
so on a fresh machine a blocked script never runs; for `gentle-pi` that script
installs the package-local `gentle-ai` review binary. The
`approve_npm_install_scripts` helper runs **after** the modules that install pi
packages (approval only accepts installed packages), approves the three packages with
install scripts - `gentle-pi`, `node-pty`, `pi-tool-display` - and then runs
`npm rebuild`, because approval alone does not re-run an already-installed script.
Approval is **by name** (`npm install-scripts approve --no-allow-scripts-pin`), not the
`<pkg>@<version>` pin npm writes by default: pi updates packages on its own (`pi
update --extensions`), and a pin stops covering the new version, re-blocks the
script and silently removes what it installs (for `gentle-pi`, the review binary)
until the installer runs again. The name covers every version, and npm converts an
existing pin into it. It is verified by re-reading npm's own state: event
`install_scripts_approved`; an npm without `install-scripts` (npm < 12) logs
`install_scripts_unsupported` and is skipped, and an absent package is a skip.

```bash
# what setup-ai enables, per install root
grep -Hx 'allow-remote=all'   ~/.pi/agent/npm/.npmrc ~/.pi/agent/extensions/.npmrc
grep -Hx 'ignore-scripts=false' ~/.pi/agent/extensions/.npmrc

# manual fallback (identical effect; append-only)
printf '%s\n' 'allow-remote=all' >> ~/.pi/agent/npm/.npmrc
printf '%s\n' 'allow-remote=all' >> ~/.pi/agent/extensions/.npmrc
printf '%s\n' 'ignore-scripts=false' >> ~/.pi/agent/extensions/.npmrc

# manual fallback for the blocked install scripts (managed root)
npm install-scripts approve --no-allow-scripts-pin gentle-pi node-pty pi-tool-display --prefix ~/.pi/agent/npm
npm rebuild --foreground-scripts --prefix ~/.pi/agent/npm gentle-pi node-pty pi-tool-display
```

```powershell
# Windows manual fallback
Add-Content "$HOME\.pi\agent\npm\.npmrc" "allow-remote=all"
Add-Content "$HOME\.pi\agent\extensions\.npmrc" "allow-remote=all"
Add-Content "$HOME\.pi\agent\extensions\.npmrc" "ignore-scripts=false"

# manual fallback for the blocked install scripts (managed root)
Push-Location "$HOME\.pi\agent\npm"; npm install-scripts approve --no-allow-scripts-pin gentle-pi node-pty pi-tool-display; npm rebuild --foreground-scripts gentle-pi node-pty pi-tool-display; Pop-Location
```

Nota di piattaforma: entrambi gli script configurano le root npm
(`ensure_npm_remote_sources` in `setup-ai.sh`, `Enable-NpmRemoteSources` in
`setup-ai.ps1`) e approvano gli script di installazione (`approve_npm_install_scripts`
/ `Approve-NpmInstallScripts`).
Platform note: both scripts configure the npm roots (`ensure_npm_remote_sources` in
`setup-ai.sh`, `Enable-NpmRemoteSources` in `setup-ai.ps1`) and approve install
scripts (`approve_npm_install_scripts` / `Approve-NpmInstallScripts`).

> **(raccomandazione / recommendation)** Non impostare `allow-remote` con
> `npm config set ... -g`: setup-ai scrive solo il `.npmrc` della root di
> installazione.
> Do not set `allow-remote` with `npm config set ... -g`: setup-ai writes only the
> install root's own `.npmrc`.

---

## 3. Il manifest `pi-packages` / The `pi-packages` manifest

**Italiano**

Il modulo `pi-packages` rende dichiarativa la lista dei pacchetti extra, così una
macchina nuova converge senza modificare a mano `~/.pi/agent/settings.json`.

**Ordine di risoluzione** (primo file esistente vince):

1. `PI_PACKAGES_FILE`, quando è impostato esplicitamente;
2. `<pi agent dir>/pi-packages.txt` → `~/.pi/agent/pi-packages.txt`, cioè il repo
   di configurazione/dotenv (vedi §4);
3. `<setup-ai dir>/pi-packages.txt` → un profilo tenuto accanto all'installer.

Nessun file trovato **non è un errore**: logga `manifest_absent` (INFO) e non
installa nulla. Se `PI_PACKAGES_FILE` punta a un file inesistente la risoluzione
**non** fallisce: prosegue con i candidati 2 e 3, mentre il `meta` di
`manifest_absent` continua a mostrare il valore dell'override.

**Formato**: un sorgente per riga; righe vuote ignorate; `#` apre un commento (sia
a inizio riga sia in coda); viene trimato solo lo spazio ai bordi, quindi uno
spazio interno rende la riga input non valido (non viene collassato). I sorgenti
supportati sono esattamente quelli che `pi install` accetta: `npm:<pkg>[@<version>]`,
`git:<host>/<owner>/<repo>[@<ref>]`, oppure un path locale.

**Idempotenza e verifica**: ogni riga è installata con `pi install` e poi
**verificata rileggendo `~/.pi/agent/settings.json`** e confrontando l'id del
pacchetto; se pi ha ignorato il sorgente il modulo fallisce con
`package_not_registered` invece di passare inosservato. Re-eseguire l'installer è
sicuro.

**Skip deliberato**: `pi-extensible-workflows` non va listato qui. Se compare, il
modulo logga `workflow_owned_elsewhere` (WARN), lo conta come `skipped` e continua:
quel pacchetto è di proprietà del modulo `pi-workflows` (release pubblicata + build
locale patchata).

**English**

The `pi-packages` module makes the extra-package list declarative, so a new machine
converges without hand-editing `~/.pi/agent/settings.json`.

**Resolution order** (first existing file wins):

1. `PI_PACKAGES_FILE`, when set explicitly;
2. `<pi agent dir>/pi-packages.txt` → `~/.pi/agent/pi-packages.txt`, i.e. the
   config/dotenv repo (see §4);
3. `<setup-ai dir>/pi-packages.txt` → a profile kept next to the installer.

No file found is **not an error**: it logs `manifest_absent` (INFO) and installs
nothing. If `PI_PACKAGES_FILE` points at a missing file, resolution does **not**
fail: it continues with candidates 2 and 3, while the `manifest_absent` `meta`
still shows the override value you set.

**Format**: one source per line; blank lines ignored; `#` starts a comment (both at
line start and trailing); only surrounding whitespace is trimmed, so internal
whitespace makes the line invalid input (it is not collapsed). Supported sources
are exactly what `pi install` accepts: `npm:<pkg>[@<version>]`,
`git:<host>/<owner>/<repo>[@<ref>]`, or a local path.

**Idempotency and verification**: each line is installed with `pi install` and then
**verified by reading `~/.pi/agent/settings.json` back** and matching the package
id; if pi ignored the source the module fails with `package_not_registered` instead
of passing unnoticed. Re-running the installer is safe.

**Deliberate skip**: `pi-extensible-workflows` must not be listed here. If it
appears, the module logs `workflow_owned_elsewhere` (WARN), counts it as `skipped`,
and continues: that package is owned by the `pi-workflows` module (published
release + patched local build).

**Esempi di manifest / Example manifests**

```ini
# --- personal machine -------------------------------------------------------
npm:pi-web-access
npm:pi-anthropic-oauth
npm:pi-vim
npm:pi-markdown-preview
npm:pi-btw@0.4.1          # pinned: must not drift

# --- CI box (minimal, pinned, no local paths) -------------------------------
npm:pi-anthropic-oauth@0.2.4
npm:pi-mcp-adapter@2.32.1

# --- work laptop (branch under test + local checkout) -----------------------
git:github.com/vekexasia/pi-notify@feat/customizable-notifications
~/git/personale/pi-cockpit-tools-sync
```

**Eseguire solo questo modulo / Run only this module**

```bash
# Linux / macOS (Bash installer)
bash setup-ai.sh --only pi-packages

# Linux / macOS with a list somewhere else (no file copying)
PI_PACKAGES_FILE=/path/to/list.txt bash setup-ai.sh --only pi-packages
```

```powershell
# Windows: the same module, same manifest resolution order
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-ai.ps1 -Only pi-packages
```
  ForEach-Object { pi install $_ }
```

`--only pi-packages` funziona anche da solo perché il modulo configura da sé il
managed root (§2) prima del primo `pi install`. / `--only pi-packages` works
standalone because the module configures the managed root itself (§2) before the
first `pi install`.

---

## 4. Dove vive la configurazione: dotenv vs l'estensione / Where configuration lives: dotenv vs the extension

**Italiano**

La separazione è quella usata da darkrei08: **configurazione** in un repo di
dotfiles, **pacchetti** come artefatti separati.

- `~/.pi/agent` è una **directory reale** popolata da un checkout di dotfiles (per
  esempio un fork di `darkrei08/dotenv`): il suo `setup_env.sh` vi copia con `rsync`
  un allowlist di file di configurazione, senza symlink. Quel checkout contiene
  `settings.json`, `package.json`, `prompts/`, `keybindings.json`, `models.json`,
  `skills/`, `themes/` e — per i workflow — `pi-extensible-workflows/settings.json`
  e `pi-extensible-workflows/roles/<nome>.md`.
- Di conseguenza la personalizzazione **appartiene a dotenv**, non a setup-ai. Il
  posto consigliato per la lista dei pacchetti extra è
  **`<dotenv>/pi/agent/pi-packages.txt`** (candidato 2 dell'ordine di risoluzione):
  ogni macchina che clona dotenv converge automaticamente.
  **(raccomandazione)**
- Le **estensioni/pacchetti** sono invece artefatti installati da pi/ setup-ai nelle
  root npm (§1): non vengono mai vendored dentro dotenv. Fa eccezione ciò che
  **costruisci tu**: un pacchetto locale resta un path registrato in
  `settings.json` (pi lo legge dal tuo checkout, non lo copia).
- L'unica cosa che setup-ai installa **dentro** l'albero dotenv è l'artefatto npm
  del pacchetto workflow in `<dotenv>/pi/agent/extensions/pi-ext-workflows/`,
  quando quella directory esiste: è un `node_modules`, non sorgente, e setup-ai non
  tocca `settings.json` né la lista dei pacchetti.
- `@darkrei08/setup-ai` non possiede il repo dotenv: legge il manifest e scrive
  nelle root di installazione di pi.

**Quando serve `PI_PACKAGES_FILE`** invece del candidato 2: setup-ai installato via
npm/npx (la directory del pacchetto non è un buon posto per la tua lista), una
macchina CI senza dotenv, o una lista che vive fuori da dotenv.

**(raccomandazione)** Tieni solo path locali per i pacchetti che costruisci tu;
pinna le versioni che non devono derivare (`npm:pkg@1.2.3`); usa il manifest invece
di modificare a mano `settings.json`, così una macchina nuova converge senza passi
manuali.

**English**

The split is the same one darkrei08 uses: **configuration** in a dotfiles repo,
**packages** as separate artifacts.

- `~/.pi/agent` is a **real directory** populated from a dotfiles checkout (for
  example a fork of `darkrei08/dotenv`): its `setup_env.sh` `rsync`s an allowlist of
  configuration files into it, with no symlink. That checkout holds `settings.json`,
  `package.json`, `prompts/`, `keybindings.json`, `models.json`, `skills/`,
  `themes/` and — for workflows — `pi-extensible-workflows/settings.json` and
  `pi-extensible-workflows/roles/<name>.md`.
- Customization therefore **belongs in dotenv**, not in setup-ai. The recommended
  place for the extra-package list is **`<dotenv>/pi/agent/pi-packages.txt`**
  (candidate 2 of the resolution order): every machine that clones dotenv converges
  automatically. **(recommendation)**
- **Extensions/packages** are separate artifacts installed by pi/setup-ai into the
  npm roots (§1): they are never vendored into dotenv. The exception is what you
  **build yourself**: a local package stays a path recorded in `settings.json` (pi
  reads it from your checkout, it does not copy it).
- The only thing setup-ai installs **inside** the dotenv tree is the workflow
  package's npm artifact at `<dotenv>/pi/agent/extensions/pi-ext-workflows/`, when
  that directory exists: it is a `node_modules`, not source, and setup-ai never
  touches `settings.json` or the package list.
- `@darkrei08/setup-ai` does not own the dotenv repo: it reads the manifest and
  writes into pi's install roots.

**When `PI_PACKAGES_FILE` is needed** instead of candidate 2: setup-ai installed
through npm/npx (the package dir is not a good home for your list), a CI machine
without dotenv, or a list that lives outside dotenv.

**(recommendation)** Keep local paths only for packages you build yourself; pin
versions that must not drift (`npm:pkg@1.2.3`); use the manifest instead of
hand-editing `settings.json`, so a fresh machine converges with no manual steps.

---

## 5. Cosa installa setup-ai per i workflow / What setup-ai installs for workflows

**Italiano**

Il modulo `pi-workflows` fa tre cose, in quest'ordine:

1. **Configura npm** nelle due root (§2) prima della prima installazione.
2. **Installa la release pubblicata** di `pi-extensible-workflows` alla versione
   risolta con `npm view pi-extensible-workflows version` (o da
   `PI_WORKFLOW_VERSION` se impostata): prima con
   `pi install npm:pi-extensible-workflows@<ver>`, poi con
   `npm install --save-exact` nella root `extensions`, e — se
   `<dotenv>/pi/agent/extensions/pi-ext-workflows` esiste — anche lì. Ogni copia è
   verificata leggendo il `package.json` **di quella directory** e confrontando la
   versione.
3. **Installa per ultima la build locale patchata**, così vince su entrambe le root.
   Provenienza: il checkout in `PI_WORKFLOWS_SOURCE_DIR` (default
   `~/git/personale/pi-extensible-workflows`) al ref `PI_WORKFLOWS_FIX_REF` (default
   `fix/windows-atomic-persistence`).

**Cosa fa e cosa non fa con git**: se la directory non esiste la clona da
`PI_WORKFLOWS_REMOTE` e può spostare **quel** checkout (creato da setup-ai) sul fix
ref. Su un checkout che possiedi non cambia mai branch: preferisce il ref già
risolto in locale, altrimenti fa **un** `git fetch` del solo ref in
`refs/remotes`, e verifica il **contenuto** (il file sorgente), non il nome del
branch. Non fa mai push e non pubblica nulla.

**La catena di prova** (il fix è dimostrato, non assunto):

| Passo / Step | File | Evento / Event |
| --- | --- | --- |
| sorgente / source | `<src>/packages/core/src/io.ts` | `retry_found_in_source` |
| artefatto buildato / built artifact | `<src>/packages/core/dist/src/io.js` | `retry_verified` (`context=built`) |
| artefatto installato / installed artifact | `<root>/node_modules/pi-extensible-workflows/dist/src/io.js` | `retry_verified` (`context=root=<root>`) |
| root gestito / managed root | `<pi agent>/npm/node_modules/pi-extensible-workflows/dist/src/io.js` | `retry_verified` (`context=managed-root`) |

Il marcatore cercato è il simbolo **`renameWithRetry`** (`PI_WORKFLOWS_RETRY_MARKER`).
**Ordine delle operazioni** (niente mezzo-swap): prima i **root di risoluzione**
(scrivono solo `node_modules`, quindi possono fallire senza toccare la configurazione),
poi lo **swap**: `pi uninstall npm:pi-extensible-workflows` → verifica `package_absent`
→ `pi install <checkout>/packages/core` → verifica `package_registered`. Perché lo swap:
`pi install` di un path locale **aggiunge** una entry, quindi lasciare registrata la
sorgente npm terrebbe due copie della stessa estensione (e la copia non patchata nel
root gestito). Da quel punto ogni fallimento esegue un **rollback**
(`patch_rollback_start` → `patch_rolled_back`); se il ripristino non riesce lo dice con
`patch_rollback_failed` (ERROR), che include il comando da lanciare a mano.

**Guardia anti walk-up**: `npm install` gira **solo** in directory con un `package.json`
locale. Un root senza manifest viene saltato con `root_not_npm_project`, altrimenti npm
risale l'albero e riscrive il manifest di un progetto antenato.

Se un passo non è dimostrabile il modulo **tiene la release pubblicata** e lo dice:
`workspace_install_failed`, `patch_build_failed`, `retry_missing`, `retry_probe_missing`,
`fix_ref_unavailable`, `source_missing`, `source_not_git`, `retry_missing_in_source`,
`root_not_npm_project`, `managed_copy_stale`, e in chiusura `patched_build_unavailable`
(WARN). Il successo finale è `patched_workflow_installed` (+ `patched_version_active`).

**Riavvia pi dopo lo swap**: una sessione già in esecuzione ha risolto le risorse dal
vecchio root npm (estensioni, `dist/starter/roles`), quindi può fallire finché non
riparte; dopo il riavvio pi carica la build patchata dal nuovo path.

**Limite Windows**: lo script di build di `packages/core` è **POSIX-only**
(`rm -rf dist`, `cp -R ...`): da PowerShell/cmd fallisce con `'rm' is not recognized`.
`setup-ai.ps1` cerca uno shell POSIX — `bash` nel `PATH`, poi
`%ProgramFiles%\Git\bin\bash.exe` e la variante `(x86)` — e passa da lì la build; se non
lo trova logga `posix_shell_missing` e resta la release pubblicata. Su una macchina
pulita serve prima un `npm install` nella root del checkout, perché `typescript` ed
`esbuild` arrivano dalle devDependencies di `packages/core`.

**English**

The `pi-workflows` module does three things, in this order:

1. **Configures npm** in both roots (§2) before the first install.
2. **Installs the published release** of `pi-extensible-workflows` at the version
   resolved with `npm view pi-extensible-workflows version` (or from
   `PI_WORKFLOW_VERSION` when set): first with
   `pi install npm:pi-extensible-workflows@<ver>`, then with `npm install
   --save-exact` in the `extensions` root, and — if
   `<dotenv>/pi/agent/extensions/pi-ext-workflows` exists — there too. Every copy
   is verified by reading **that directory's** `package.json` and comparing the
   version.
3. **Installs the patched local build last**, so it wins in both roots. Source: the
   checkout at `PI_WORKFLOWS_SOURCE_DIR` (default
   `~/git/personale/pi-extensible-workflows`) at `PI_WORKFLOWS_FIX_REF` (default
   `fix/windows-atomic-persistence`).

**What it does and does not do with git**: if the directory does not exist it clones
it from `PI_WORKFLOWS_REMOTE` and may move **that** checkout (created by setup-ai)
to the fix ref. On a checkout you own it never switches branch: it prefers a ref
that already resolves locally, otherwise makes **one** `git fetch` of just that ref
into `refs/remotes`, and trusts the **content** (the source file), not the branch
name. It never pushes and never publishes.

**The proof chain** (the fix is proven, not assumed): see the table above — source
→ built artifact → installed artifact, each step logged.

The marker it greps for is the symbol **`renameWithRetry`**
(`PI_WORKFLOWS_RETRY_MARKER`).

**Order of operations** (no half-swap): the **resolution roots** come first (they only
write `node_modules`, so they can fail without touching configuration), then the
**swap**: `pi uninstall npm:pi-extensible-workflows` → verify `package_absent` →
`pi install <checkout>/packages/core` → verify `package_registered`. Why the swap:
`pi install` of a local path only **adds** an entry, so leaving the npm source
registered would keep two copies of the same extension (including the unpatched one in
the managed root). From that point every failure runs a **rollback**
(`patch_rollback_start` → `patch_rolled_back`); when the restore itself fails it says so
with `patch_rollback_failed` (ERROR), including the command to run by hand.

**Walk-up guard**: `npm install` only ever runs in a directory that has a local
`package.json`. A root without a manifest is skipped with `root_not_npm_project`,
otherwise npm walks up the tree and rewrites an ancestor project's manifest.

If a step cannot be proven the module **keeps the published release** and says so:
`workspace_install_failed`, `patch_build_failed`, `retry_missing`,
`retry_probe_missing`, `fix_ref_unavailable`, `source_missing`, `source_not_git`,
`retry_missing_in_source`, `root_not_npm_project`, `managed_copy_stale`, and finally
`patched_build_unavailable` (WARN). Success is `patched_workflow_installed`
(plus `patched_version_active`).

**Restart pi after the swap**: a session that is already running resolved resources
(extensions, `dist/starter/roles`) from the old npm root, so it can fail until it
restarts; after the restart pi loads the patched build from the new path.

**Windows limitation**: `packages/core`'s build script is **POSIX-only**
(`rm -rf dist`, `cp -R ...`): from PowerShell/cmd it fails with
`'rm' is not recognized`. `setup-ai.ps1` looks for a POSIX shell — `bash` on `PATH`,
then `%ProgramFiles%\Git\bin\bash.exe` and the `(x86)` variant — and runs the build
through it; without one it logs `posix_shell_missing` and keeps the published release.
On a clean machine a root `npm install` in the checkout is required first, because
`typescript` and `esbuild` come from `packages/core`'s devDependencies.

```bash
# Linux / macOS / WSL: override source, ref and remote
PI_WORKFLOWS_SOURCE_DIR=/path/to/pi-extensible-workflows \
PI_WORKFLOWS_FIX_REF=fix/windows-atomic-persistence \
bash setup-ai.sh --only pi-workflows
```

```powershell
# Windows: build the checkout through Git Bash (validated: exit 0, ~23s on node v26 / npm 12.0.2)
cd C:\path\to\pi-extensible-workflows
npm install
& "C:\Program Files\Git\bin\bash.exe" -lc "cd '$(Get-Location)' && npm run build --workspace=packages/core"
```

> **(raccomandazione / recommendation)** Sul checkount dei workflow npm 12 può
> bloccare gli script di installazione delle dipendenze (es. il postinstall di
> `esbuild`): è una causa nota di `workspace_install_failed`. Abilita gli script
> per quel workspace prima della build.
> In the workflow checkout, npm 12 may block dependency install scripts (e.g.
> `esbuild`'s postinstall): a known cause of `workspace_install_failed`. Allow
> scripts for that workspace before building.

---

## 6. Modelli e ruoli (subagent) / Models and roles (subagents)

**Italiano**

Il modello di `pi-extensible-workflows`: un **file di ruolo** è un Markdown con
frontmatter YAML; il corpo è il prompt. I campi di frontmatter forniscono i
**default**: `description`, `model`, `tools`, `skills`, `extensions`,
`extensionSettings`, `overrideSystemPrompt`, `contextFiles`.

- I ruoli globali vivono in `<agentDir>/pi-extensible-workflows/roles/<nome>.md`
  (per un utente dotenv: `<dotenv>/pi/agent/pi-extensible-workflows/roles/`); i
  ruoli di progetto trusted in `<cwd>/.pi/pi-extensible-workflows/roles/<nome>.md`.
  Precedenza: starter < ruoli di estensione < globali < progetto trusted.
- **Le opzioni per-chiamata (`AgentOptions`) sovrascrivono i default del ruolo**
  per `model`, `tools`, `skills`, `extensions`, `contextFiles` — senza avviso: il
  ruolo resta il default, ma per quella chiamata vince l'opzione.
- **Selettori** (`tools`, `skills`, `extensions`): pattern Minimatch ordinati,
  concatenati nell'ordine *global settings → trusted project settings → frontmatter
  del ruolo → opzioni di chiamata*. Ogni candidato scoperto parte **abilitato**; un
  pattern positivo abilita, `!pattern` disabilita, vince l'ultima regola che
  matcha. `["!*"]` azzera la selezione corrente prima delle aggiunte successive;
  `["*"]` riabilita tutto; `["!*", "read", "grep"]` parte da niente e abilita solo
  ciò che è elencato. I selettori non creano risorse non disponibili.

**Scelta dei modelli**: un modello concreto ha la forma
`provider/model:thinking`. Gli alias sono **case-sensitive** e un alias può
puntare a un modello o a un altro alias; un suffisso sull'alias sovrascrive quello
del target, e un'opzione di thinking a livello di chiamata ha la precedenza più
alta. **Verifica sempre l'identificatore reale** con `pi --list-models "<termine>"`
prima di usarlo: non indovinarlo. Le reference statiche (model concreto o alias
letterale) sono risolte e controllate in preflight.

**(raccomandazione)** Usa un modello economico/veloce per i ruoli meccanici
(scout, ricerche, esecuzione ripetitiva) e un modello forte per i ruoli da
architetto/reviewer. Per aggiungere un altro provider/modello, usa `/provider add`
in pi oppure `pi.registerProvider(...)`, poi riferiscine l'id concreto
`provider/model:thinking` o un alias.

**English**

The `pi-extensible-workflows` model: a **role file** is a Markdown file with YAML
frontmatter; the body is the prompt. Frontmatter fields supply the **defaults**:
`description`, `model`, `tools`, `skills`, `extensions`, `extensionSettings`,
`overrideSystemPrompt`, `contextFiles`.

- Global roles live at `<agentDir>/pi-extensible-workflows/roles/<name>.md` (for a
  dotenv user: `<dotenv>/pi/agent/pi-extensible-workflows/roles/`); trusted project
  roles at `<cwd>/.pi/pi-extensible-workflows/roles/<name>.md`. Precedence: starter
  < extension roles < global < trusted project.
- **Per-call `AgentOptions` override role defaults** for `model`, `tools`,
  `skills`, `extensions`, `contextFiles` — silently: the role stays the default,
  but for that call the option wins.
- **Selectors** (`tools`, `skills`, `extensions`): ordered Minimatch patterns,
  concatenated in the order *global settings → trusted project settings → role
  frontmatter → call options*. Every discovered candidate starts **enabled**; a
  positive pattern enables, `!pattern` disables, and the last matching rule wins.
  `["!*"]` clears the current selection before later additions; `["*"]` re-enables
  everything; `["!*", "read", "grep"]` starts from nothing and enables only what is
  listed. Selectors never create unavailable resources.

**Choosing models**: a concrete model has the form `provider/model:thinking`.
Aliases are **case-sensitive** and an alias may target a model or another alias; an
alias suffix overrides the target's suffix, and a call-level thinking option has
the highest precedence. **Always verify the real identifier** with
`pi --list-models "<term>"` before using it: never guess it. Static references (a
concrete model or a literal alias) are resolved and checked during launch
preflight.

**(recommendation)** Use a cheap/fast model for mechanical roles (scout, research,
repetitive execution) and a strong model for architect/reviewer roles. To add
another provider/model, use `/provider add` in pi or `pi.registerProvider(...)`,
then reference its concrete `provider/model:thinking` id or an alias.

```bash
pi --list-models "claude"                 # verify what actually exists
piewf doctor --role reviewer              # inspect the effective role (read-only)
piewf doctor --role reviewer --json       # machine-readable effective policy
```

---

## 7. Iniettare o escludere estensioni, tool e skill per ruolo / Injecting or excluding extensions, tools and skills per role

**Italiano**

**Quale livello vince**: le **opzioni di chiamata** battono il frontmatter del
ruolo, che batte le trusted project settings, che battono le global settings;
dentro ogni livello di selettori vince l'ultima regola che matcha.

| Obiettivo / Goal | Ricetta / Recipe | Effetto / Effect |
| --- | --- | --- |
| ruolo senza estensioni / role with no extensions | `extensions: ["!*"]` | seleziona nessuna estensione / selects none |
| solo una estensione / only one extension | `extensions: ["!*", "my-ext"]` | parte da niente e abilita `my-ext` / clears, then enables `my-ext` |
| aggiungere una estensione senza i default del ruolo / add one extension without the role's defaults | `extensions: ["!*", "extra"]` | azzera anche la lista del ruolo, abilita solo `extra` / clears the role's list too, enables only `extra` |
| escludere un singolo tool / exclude a single tool | `tools: ["*", "!write"]` | tutto tranne `write` / everything except `write` |
| ruolo deterministico / deterministic role | dichiara sempre `tools`, `skills`, `extensions` nel frontmatter / always declare `tools`, `skills`, `extensions` in frontmatter | nessun default implicito / no implicit defaults |

**Attenzione**: un selettore è un overlay, non un'eredità della selezione viva del
parent. Se il ruolo o la chiamata partono da `!*`, tutto ciò che il parent aveva
abilitato viene spento e torna solo ciò che è elencato dopo; viceversa un ruolo
**senza** campo `extensions` lascia abilitate le estensioni scoperte (i candidati
senza regola che matcha restano abilitati). I tool del child restano comunque
dentro il confine del parent. `piewf doctor` segnala
`AGENT_RESOURCE_TOOL_SELECTOR_ALLOWLIST` quando una lista di `tools` solo positiva
sembra un allow-list inefficace: anteponi `!*`.

**English**

**Which layer wins**: **call options** beat the role frontmatter, which beats
trusted project settings, which beat global settings; within each selector layer
the last matching rule wins.

**Note**: a selector is an overlay, not an inheritance of the parent session's live
selection. If the role or the call starts from `!*`, everything the parent had
enabled is turned off and only what is listed afterwards comes back; conversely a
role **without** an `extensions` field leaves discovered extensions enabled
(candidates with no matching rule stay enabled). Child tools still remain within
the parent boundary. `piewf doctor` reports
`AGENT_RESOURCE_TOOL_SELECTOR_ALLOWLIST` when a positive-only `tools` list looks
like an ineffective allow-list: prepend `!*`.

```md
---
description: Reviews code for correctness
model: reviewer-model:high
tools: ["!*", read, grep]
skills: ["!*"]
extensions: ["!*"]
---

Focus on correctness and regressions.
```

```js
// call-level option: wins over the role file for this call
await agent("Review this change", {
  role: "reviewer",
  model: "cheap-model:low",
  tools: ["!*", "read", "grep"],
  extensions: ["!*"],          // no extensions for this run
});
```

---

## 8. Checklist per una macchina nuova / New machine checklist

**Italiano**

1. **verifica npm**: `npm --version`. Con major `>= 12` aspettati l'opt-in scritto
   da setup-ai nelle due root (§2).
2. **clona/wire dotenv**: clona il tuo fork di dotenv ed esegui `setup_env.sh`,
   che popola `~/.pi/agent` con un `rsync` selettivo da `<dotenv>/pi/agent` (non
   uno symlink; su Windows, dove `setup_env.sh` non gira, copia gli stessi file).
3. **crea/verifica il manifest**: copia `pi-packages.example.txt` in
   `<dotenv>/pi/agent/pi-packages.txt` (candidato 2) e commenta ciò che ti serve.
   Non listare `pi-extensible-workflows`: è saltato di proposito, lo possiede il
   modulo `pi-workflows`.
4. **esegui setup-ai**: `bash setup-ai.sh --all` (o `--only pi,pi-packages,pi-workflows`;
   su Windows `powershell -File .\setup-ai.ps1 -Only pi,pi-packages,pi-workflows`).
5. **verifica dagli eventi** (non a occhio): `remote_sources_enabled` per entrambe
   le root, `install_scripts_approved` (script di installazione), `manifest_loaded` +
   `manifest_applied` (`installed=`, `skipped=`), `retry_found_in_source` + due
   `retry_verified` + `patched_workflow_installed` **oppure**
   `patched_build_unavailable` con la release pubblicata.
6. **verifica l'artefatto** con il marcatore `renameWithRetry` (§9): `2` = patchato,
   `0` = release pubblicata.
7. **pinna ciò che non deve derivare** (`npm:pkg@1.2.3`) e tieni come path locale
   solo i pacchetti che costruisci tu. **(raccomandazione)**

**English**

1. **check npm**: `npm --version`. With major `>= 12`, expect setup-ai's opt-in
   written into both roots (§2).
2. **clone/wire dotenv**: clone your dotenv fork and run `setup_env.sh`, which
   populates `~/.pi/agent` with a selective `rsync` from `<dotenv>/pi/agent` (not a
   symlink; on Windows, where `setup_env.sh` does not run, copy the same files).
3. **create/verify the manifest**: copy `pi-packages.example.txt` to
   `<dotenv>/pi/agent/pi-packages.txt` (candidate 2) and uncomment what you need.
   Do not list `pi-extensible-workflows`: it is deliberately skipped and owned by
   the `pi-workflows` module.
4. **run setup-ai**: `bash setup-ai.sh --all` (or `--only pi,pi-packages,pi-workflows`;
   on Windows `powershell -File .\setup-ai.ps1 -Only pi,pi-packages,pi-workflows`).
5. **verify from the events** (not by eye): `remote_sources_enabled` for both roots,
   `install_scripts_approved` (install scripts), `manifest_loaded` +
   `manifest_applied` (`installed=`, `skipped=`), `retry_found_in_source` + two
   `retry_verified` + `patched_workflow_installed` **or** `patched_build_unavailable`
   with the published release.
6. **verify the artifact** with the `renameWithRetry` marker (§9): `2` = patched,
   `0` = published release.
7. **pin what must not drift** (`npm:pkg@1.2.3`) and keep local paths only for
   packages you build yourself. **(recommendation)**

---

## 9. Troubleshooting

**Italiano**

- **`EALLOWREMOTE` durante `pi install` / `pi update --extensions`** — causa: npm 12
  con `allow-remote=none` e una dipendenza URL/tarball. Fix: riesegui setup-ai (che
  scrive `allow-remote=all` nelle root), oppure il fallback manuale di §2. Verifica:
  `grep -Hx 'allow-remote=all' ~/.pi/agent/npm/.npmrc ~/.pi/agent/extensions/.npmrc`.
  Evento atteso: `remote_sources_enabled`.
- **Script di installazione bloccati / binario `gentle-ai` mancante** — causa: npm 12
  blocca gli script di installazione finché il pacchetto non è approvato. Fix: riesegui
  setup-ai (che approva i pacchetti ed esegue `npm rebuild`), oppure il fallback
  manuale di §2. Verifica: `npm install-scripts ls` non deve elencare `gentle-pi`,
  `node-pty`, `pi-tool-display`; evento atteso: `install_scripts_approved`.
- **RDD "unknown" e review nativa che non parte dopo un aggiornamento di pi** —
  sintomo: ogni sessione pi stampa `receipt-driven-development status is unavailable`
  e il prompt rende `Receipt-driven development: unknown`; `gentle_review start` non
  negozia. Causa: con il pin `<pkg>@<versione>` un `pi update --extensions` porta
  `gentle-pi` a una versione non approvata, il suo `postinstall` viene bloccato e il
  binario locale `.gentle-ai/<versione>/gentle-ai` non esiste più. Diagnosi (npm 12):
  `npm install-scripts ls --prefix ~/.pi/agent/npm` elenca `gentle-pi` come bloccato e
  `~/.pi/agent/npm/node_modules/gentle-pi/.gentle-ai/` manca. Fix: riesegui setup-ai
  (che ora approva per nome) o il fallback di §2. Un'approvazione per nome non può
  più essere scavalcata da un aggiornamento.
- **`EPERM: operation not permitted, rename '...state.json.tmp'`** — causa: la
  release pubblicata scrive lo stato con write(`.tmp`) + `rename()` senza retry, e
  un lock transitorio (Defender, indicizzazione, client di sync o un pi concorrente)
  fa fallire la scrittura. Il fix è il retry di `renameWithRetry` (EACCES/EBUSY/EPERM
  con backoff limitato). Controllo del marcatore:

  ```bash
  # Linux / macOS / WSL
  grep -c renameWithRetry ~/.pi/agent/npm/node_modules/pi-extensible-workflows/dist/src/io.js
  grep -c renameWithRetry ~/.pi/agent/extensions/node_modules/pi-extensible-workflows/dist/src/io.js
  wc -c ~/.pi/agent/npm/node_modules/pi-extensible-workflows/dist/src/io.js
  ```

  ```powershell
  # Windows
  Select-String -Path "$HOME\.pi\agent\npm\node_modules\pi-extensible-workflows\dist\src\io.js" -Pattern renameWithRetry
  Select-String -Path "$HOME\.pi\agent\extensions\node_modules\pi-extensible-workflows\dist\src\io.js" -Pattern renameWithRetry
  ```

  Un artefatto **non patchato** è di ~2277 byte con `0` match; uno **patchato** di
  ~3077 byte con `2` match. Devono risultare patchate **entrambe** le root.
- **Trappola principale: la versione non cambia.** Il pacchetto resta `5.13.2`
  anche dopo la patch locale, quindi un controllo di versione (`node -e
  "console.log(require('<path>/package.json').version)"`) **non** distingue
  patchato da non patchato: l'unica prova è il contenuto dell'artefatto
  (`renameWithRetry`).
- **Pacchetto mancante dopo l'install** — `package_not_registered` (ERROR): pi non
  ha registrato il sorgente in `~/.pi/agent/settings.json`. Controlla il `meta`
  (`spec=`, `settings=`), che il sorgente sia valido per `pi install`, e che
  `settings.json` esista.
- **Copie stale/duplicate nelle due root** — sintomo tipico: una root patchata e
  l'altra no, o versioni divergenti. Le due `package.json` non sono equivalenti:
  `~/.pi/agent/npm/package.json` usa un range caret (`"^5.13.2"`) mentre
  `~/.pi/agent/extensions/package.json` pinna esatto (`"5.13.2"`): un aggiornamento
  del managed root può quindi lasciare la seconda indietro. Rimedio: riesegui il
  modulo `pi-workflows` (riscrive e riverifica entrambe) e ricontrolla i due
  marcatori.
- **`pi update --extensions` fallisce su un sorgente cattivo** — causa: reinstalla
  tutto attraverso il managed root, quindi un solo sorgente con dipendenza remote
  (o un ref git non raggiungibile) rompe il comando intero. Rimedio: sistema o
  rimuovi quella riga dal manifest / da `settings.json`, poi ripeti.
- **Root dotenv su Windows** — il flusso `dotenv` è Linux-only, quindi su Windows
  `<checkout dotenv>\pi\agent\extensions\pi-ext-workflows` non è un progetto npm (non
  ha `package.json`). Il modulo `pi-workflows` lo salta con `root_not_npm_project`
  invece di installare in un antenato: è il comportamento corretto, non un errore.
  Su Linux/WSL quel root esiste come progetto npm e viene patchato come gli altri.
- **Leggere le prove strutturate** — ogni run scrive `logs/setup_<runid>.log`
  (umano), `logs/setup_<runid>.jsonl` (strutturato) e
  `engineering-report_<runid>.md`. Ogni riga JSONL ha `phase`, `event`, `meta`:

  ```bash
  jq -r 'select(.event|test("remote_sources_enabled|install_scripts_approved|install_scripts_unverified|retry_verified|retry_found_in_source|patched_workflow_installed|patched_build_unavailable|manifest_applied|workflow_owned_elsewhere")) | "\(.phase)\t\(.event)\t\(.meta // "")"' \
    logs/setup_<runid>.jsonl
  ```

  `remote_sources_enabled` → `meta` con `npmrc=<root>/.npmrc`; `retry_verified` →
  `path=...;context=built|installed`; `patched_workflow_installed` →
  `source=...;ref=...`; `patched_build_unavailable` → `source=...;ref=...`;
  `manifest_applied` → `installed=<n>;skipped=<n>;manifest=<path>`;
  `workflow_owned_elsewhere` → `spec=<riga>`.

**English**

- **`EALLOWREMOTE` during `pi install` / `pi update --extensions`** — cause: npm 12
  with `allow-remote=none` and a URL/tarball dependency. Fix: re-run setup-ai
  (it writes `allow-remote=all` into the roots), or use the manual fallback in §2.
  Verify: `grep -Hx 'allow-remote=all' ~/.pi/agent/npm/.npmrc ~/.pi/agent/extensions/.npmrc`.
  Expected event: `remote_sources_enabled`.
- **Blocked install scripts / missing `gentle-ai` binary** — cause: npm 12 blocks
  install scripts until the package is approved. Fix: re-run setup-ai (it approves the
  packages and runs `npm rebuild`), or the manual fallback in §2. Verify:
  `npm install-scripts ls` must not list `gentle-pi`, `node-pty`, `pi-tool-display`;
  expected event: `install_scripts_approved`.
- **RDD "unknown" and native review that will not start after a pi update** — symptom:
  every pi session prints `receipt-driven-development status is unavailable` and the
  prompt renders `Receipt-driven development: unknown`; `gentle_review start` does not
  negotiate. Cause: with the `<pkg>@<version>` pin, `pi update --extensions` moves
  `gentle-pi` to a version that is not approved, its `postinstall` is blocked, and the
  package-local `.gentle-ai/<version>/gentle-ai` binary is gone. Diagnose (npm 12):
  `npm install-scripts ls --prefix ~/.pi/agent/npm` lists `gentle-pi` as blocked and
  `~/.pi/agent/npm/node_modules/gentle-pi/.gentle-ai/` is missing. Fix: re-run setup-ai
  (it now approves by name) or the §2 fallback. A name-only approval cannot be
  invalidated by an update.
- **`EPERM: operation not permitted, rename '...state.json.tmp'`** — cause: the
  published release writes state with write(`.tmp`) + `rename()` without retry, and
  a transient lock (Defender, indexing, a sync client, or a concurrent pi process)
  makes the write fail. The fix is the `renameWithRetry` retry (EACCES/EBUSY/EPERM
  with bounded backoff). Marker check: see the commands and sizes above; an
  **unpatched** artifact is ~2277 bytes with `0` matches, a **patched** one ~3077
  bytes with `2` matches, and **both** roots must be patched.
- **Main trap: the version does not change.** The package stays `5.13.2` even after
  the local patch, so a version check (`node -e
  "console.log(require('<path>/package.json').version)"`) **cannot** distinguish
  patched from unpatched: the only proof is the artifact content
  (`renameWithRetry`).
- **Package missing after install** — `package_not_registered` (ERROR): pi did not
  record the source in `~/.pi/agent/settings.json`. Check the `meta` (`spec=`,
  `settings=`), that the source is valid for `pi install`, and that
  `settings.json` exists.
- **Stale/duplicated copies in the two roots** — typical symptom: one root patched
  and the other not, or diverging versions. The two `package.json` files are not
  equivalent: `~/.pi/agent/npm/package.json` uses a caret range (`"^5.13.2"`) while
  `~/.pi/agent/extensions/package.json` pins exactly (`"5.13.2"`): updating the
  managed root can leave the second one behind. Remedy: re-run the `pi-workflows`
  module (it rewrites and re-verifies both) and re-check both markers.
- **`pi update --extensions` fails on one bad source** — cause: it reinstalls
  everything through the managed root, so a single source with a remote dependency
  (or an unreachable git ref) breaks the whole command. Remedy: fix or remove that
  line from the manifest / `settings.json`, then retry.
- **dotenv root on Windows** — the `dotenv` flow is Linux-only, so on Windows
  `<dotenv checkout>\pi\agent\extensions\pi-ext-workflows` is not an npm project (it
  has no `package.json`). The `pi-workflows` module skips it with
  `root_not_npm_project` instead of installing into an ancestor: that is correct
  behaviour, not an error. On Linux/WSL that root exists as an npm project and is
  patched like the others.
- **Reading the structured evidence** — every run writes `logs/setup_<runid>.log`
  (human), `logs/setup_<runid>.jsonl` (structured) and
  `engineering-report_<runid>.md`. Every JSONL line has `phase`, `event`, `meta`;
  the `jq` command above prints them for the event names used in this page.

---

## 10. Riferimento: variabili d'ambiente / Reference: environment variables

Tabella di riferimento (nomi, default e valori sono letterali) / Reference table
(names, defaults and values are literal):

| Variable | Default | Purpose | Platform notes |
| --- | --- | --- | --- |
| `PI_PACKAGES_FILE` | unset (`""`) | Explicit path of the extra-packages manifest; **first** candidate of the resolution order | Declared and consumed by both scripts (`pi-packages` / `Mod-PiPackages`). A set-but-missing path does not error: resolution falls through to `<agentDir>/pi-packages.txt` then `<script dir>/pi-packages.txt`. |
| `PI_WORKFLOWS_SOURCE_DIR` | `$HOME/git/personale/pi-extensible-workflows` | Local checkout that can carry the unpushed fix; source of the patched build | Declared and consumed by both scripts. Read/build only: never pushed, never published, and an existing checkout is never switched to another branch. |
| `PI_WORKFLOWS_FIX_REF` | `fix/windows-atomic-persistence` | Ref whose **content** must contain `renameWithRetry` | Declared and consumed by both scripts. Prefers a locally resolvable ref, else one `git fetch` of that ref; a checkout created by setup-ai may be moved to it. |
| `PI_WORKFLOWS_REMOTE` | `https://github.com/darkrei08/pi-extensible-workflows.git` | Clone source used when `PI_WORKFLOWS_SOURCE_DIR` does not exist | Declared and consumed by both scripts. Used only for the initial clone. |

Variabili correlate / Related variables:

| Variable | Default | Purpose | Platform notes |
| --- | --- | --- | --- |
| `PI_WORKFLOW_VERSION` | unset → resolved with `npm view pi-extensible-workflows version` | Pins the published workflow version installed into the roots | `setup-ai.sh` only; read by the `pi-workflows` module. |
| `DEBUG` | `0` | `DEBUG=1` prints `DEBUG`-level lines from the logger | Both scripts. |
| `PI_CODING_AGENT_DIR` | unset (`~/.pi/agent`) | Relocates **pi**'s agent directory | Read by pi, **not** by `setup-ai.sh` (which builds the path from `$HOME`). |
| `OPENCODE_PI_BIN` | unset → the `opencode` on `PATH` | Native launcher the `opencode-pi` Pi extension spawns for the local OpenCode CLI | Written (user scope) by `setup-ai.ps1` when the npm shim is not directly spawnable, because the extension spawns without a shell and a `.cmd`/`.ps1` shim fails there; read by the extension, never by the scripts. `setup-ai.sh` only verifies the spawn. |

---

## 11. Vedi anche / See also

- [pi-workflows-guide.md](pi-workflows-guide.md) — guida bilingue a installazione,
  `/workflow`, tool `workflow`, modelli, ruoli e Neovim / bilingual guide to the
  install, the `/workflow` picker, the `workflow` tool, models, roles and Neovim.
- `pi-packages.example.txt` — il manifest di esempio commentato / the annotated
  example manifest.
- Pi packages (upstream): <https://pi.dev/docs/latest/packages>
- Pi extensions (upstream): <https://pi.dev/docs/latest/extensions>
- Pi custom providers (upstream): <https://pi.dev/docs/latest/custom-provider>
- pi-extensible-workflows docs: <https://vekexasia.github.io/pi-extensible-workflows/>
  (roles: <https://vekexasia.github.io/pi-extensible-workflows/roles.html>,
  subagents: <https://vekexasia.github.io/pi-extensible-workflows/subagents.html>)
- Repository: <https://github.com/vekexasia/pi-extensible-workflows>
