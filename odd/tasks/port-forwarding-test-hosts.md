# Port forwarding so tests can run on the machine that launches or receives commands

Status: study complete, one decision open. No code changed in any repository.

## Destination

A reproducible way to run the Windows half of setup-ai's verification on a real
Windows host from this Linux machine, and to let browser/automation tooling on either
side reach services running on the other, without VPNs and without credentials or
private hostnames in any repository.

## Why this exists (proven constraints)

- Native Windows verification is a standing gap in this repository (`.ai/todo.md`,
  `docs/releasing.md`; every release PR says "Windows verification pending").
- A local Windows container is **not** available here: `dockur/windows` requires
  `/dev/kvm` and at least 32 GB free (64 GB default disk); this host exposes no KVM
  (Proxmox guest, nested virtualization off) and has 25 GB free.
- Neither repository has any SSH surface today: `setup-ai.sh`, `setup-ai.ps1`,
  `bin/setup-ai.mjs`, `docs/` mention no `ssh`, no `WinRM`, no forwarding. The dotenv
  checkout has no `ssh/config` fragment, no `LocalForward`, no `RemoteForward`.
  So this is greenfield, not a repair.

## Primitives (primary source: `man 5 ssh_config`, OpenSSH shipped on this host)

- `LocalForward [bind_address:]port host:hostport` - a local TCP port is forwarded over
  the secure channel to a destination **reachable from the remote machine**. Use it
  when the client side must reach something that only the remote side can see.
- `RemoteForward [bind_address:]port host:hostport` - a port on the **remote** machine
  is forwarded back over the secure channel to a destination reachable from the local
  machine. Use it when the remote side must reach something local (a service, a
  sandbox, a browser automation endpoint).
- `ExitOnForwardFailure yes` - the connection is terminated when any requested
  forwarding cannot be set up, so a silently missing tunnel cannot look like a pass.
- `ForkAfterAuthentication yes` plus `ExitOnForwardFailure yes` waits for the remote
  forwards to be established before backgrounding: the right shape for a
  `ssh -f -N` tunnel started by a script.

## Options considered

| Option | Verdict |
| --- | --- |
| A. Local Windows container (`dockur/windows`) | **Blocked** on this host (no KVM, 25 GB free vs 32 GB minimum). Would work on a bare-metal Linux box with VT-x and 64 GB free. |
| B. `ssh` into the Windows host, run `setup-ai.ps1` there | **Recommended primary.** Needs OpenSSH Server on Windows, which is a first-class Windows optional feature. `ssh winbox 'pwsh -NoProfile -File C:\...\setup-ai.ps1 -Only pi -DryRun'`-shaped calls keep the Linux orchestrator in control. |
| C. `RemoteForward` from Windows back to this Linux host | **Recommended companion.** Lets the Windows run reach Linux-only endpoints: CLIProxyAPI at `127.0.0.1:8317`, and the browser automation endpoints. |
| D. `LocalForward` from this host to services on Windows | Use only for the reverse dependency: a browser tool on this side reaching an app served on Windows. |
| E. WinRM remoting instead of SSH | Rejected for now: a second authentication surface, heavier to provision, no advantage over B for running a script and reading its exit code. |
| F. WSL on the Windows host for the Linux half | Complementary, not a substitute: WSL is not a native Linux host for the container matrix. |

## Recommended shape (smallest complete)

1. **dotenv owns the transport, not this repository.** A `Host` block per test machine
   with `ServerAliveInterval`, `ExitOnForwardFailure yes`, the needed `LocalForward` /
   `RemoteForward` lines, kept in the user's private dotenv checkout (its `setup_env.sh`
   already rsyncs `pi/agent` into `~/.pi/agent`; an SSH fragment belongs in the same
   private place, never in setup-ai).
2. **setup-ai owns the test, not the tunnel.** A documented invocation, for example
   `ssh winbox 'pwsh -NoProfile -ExecutionPolicy Bypass -File setup-ai.ps1 -Only pi -Yes'`
   plus the existing parse and lifecycle checks, recorded with exact host, command,
   exit code, and output in the release PR.
3. **A liveness assertion before any test run.** `ssh -G winbox` to read the resolved
   configuration (no secrets), then a `ssh -O check`-style probe or a short
   `ssh -N -f` with `ExitOnForwardFailure yes`; a tunnel that is not up fails the run
   instead of being ignored.
4. **Identifier hygiene.** Host aliases only, never hostnames, IPs, users, keys, or
   tokens in either repository. The repo-side artifact is the command shape and the
   evidence format.

## Decisions

- D1 (needs the human): which machine is the Windows test target, by alias only, and
  does it already run OpenSSH Server?
- D2 (needs the human): is the reverse tunnel required at all, or does the Windows box
  reach the Linux services through a routable address? The answer decides whether
  `RemoteForward` lines are part of the minimal shape.

## Not yet specified

- Whether setup-ai should ship a `--windows-remote <alias>` launcher flag. Deferred
  until D1/D2 are answered: it would add a transport concern to an installer that is
  deliberately dependency-free and OS-agnostic.

## Out of scope

- Installing an SSH server or keys anywhere (human provisioning step).
- Any credential, key material, or private hostname in either repository.
- Replacing native macOS verification: forwarding does not create a macOS host.
