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

## Measured state of the test path (2026-10-30)

The human supplied `ipconfig /all` from the Windows machine, and the Linux side was probed
with `tailscale status` and TCP connects. Findings, identifiers removed on purpose:

- Both machines are on the **same Tailscale tailnet**, and the Windows peer shows as
  `active; direct <lan-ip>:41641`. A tailnet peer connection needs no LAN port forward
  and no VPN setup of our own; the host alias used below is `win-test`.
- From this Linux host, TCP **22 (ssh), 5985 (WinRM), 8006, 3389 (RDP)** on that peer are
  closed/filtered. So there is no remote shell yet: OpenSSH Server and WinRM are not
  listening. That is the one missing human provisioning step.
- On the Linux side (`ss -ltnp`): the CLIProxyAPI gateway on **8317 is already bound to
  the tailnet address**, not only to loopback, and **8080** is bound to `0.0.0.0`. Both
  are reachable from `win-test` with no tunnel at all.
- Still **loopback-only** here: **9222** (the BrowserOS/CDP endpoint), **3000**,
  **8190**. Those are exactly the services that need a `RemoteForward` from
  `win-test`, or a deliberate rebind.

### Human provisioning step on `win-test` (documented Windows commands)

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
# firewall rule OpenSSH-Server-In-TCP if it was not created by the install
```

Source: Microsoft Learn, "Get started with OpenSSH Server for Windows"
(https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse),
retrieved 2026-10-30. Then the Linux key goes into the Windows user's
`administrators_authorized_keys` or `authorized_keys`, and `ssh -G win-test` on the Linux
side must resolve to the intended configuration before any test run.


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

- D1 (answered): the test target is the tailnet peer aliased `win-test`. A route exists
  today; OpenSSH Server is not enabled yet, so test execution stays blocked until the
  provisioning block above runs on that machine.
- D2 (answered): a reverse tunnel is needed only for the loopback-only services
  (9222 CDP, 3000, 8190). The gateway on 8317 and 8080 are already reachable over the
  tailnet and need no forwarding.
- D3 (open, human): does the Windows box run the tests against its own installed tools,
  or must it also reach this Linux host's models/CLIProxyAPI? If yes, add the two
  `RemoteForward` lines for 9222 and 8190 only.

## Not yet specified

- Whether setup-ai should ship a `--windows-remote <alias>` launcher flag. Deferred
  until D1/D2 are answered: it would add a transport concern to an installer that is
  deliberately dependency-free and OS-agnostic.

## Out of scope

- Installing an SSH server or keys anywhere (human provisioning step).
- Any credential, key material, or private hostname in either repository.
- Replacing native macOS verification: forwarding does not create a macOS host.
