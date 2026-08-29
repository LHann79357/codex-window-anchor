# Codex Window Anchor — How It Works

This document explains the core Public V1 architecture of Codex Window Anchor, the lifecycle of one Anchor, and why the project separates runtime, authentication, scheduling, and uninstall into distinct boundaries.

If you only want to deploy the project, read [INSTALLATION.md](INSTALLATION.md). If something fails, read [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Design goals

Codex Window Anchor is not a new Codex client and not a long-running Agent. It is a small, auditable **systemd scheduling wrapper**: the user first installs the official OpenAI standalone Codex CLI, the Anchor Installer creates an independent runtime snapshot from that executable, and systemd later starts a one-shot service at times chosen by the user. That service sends one minimal real Codex request as a dedicated non-root identity and exits when the request finishes.

Public V1 is built around six principles:

| Principle | Meaning |
| --- | --- |
| Official Codex first | Anchor does not download or redistribute Codex |
| Explicit opt-in | Install, sign-in, Schedule generation, and enable are separate steps |
| Dedicated identity | Anchor uses a separate `codex-anchor` user and Codex Home |
| Small runtime surface | No web dashboard, database, or Anchor daemon is required |
| Fail closed | If ownership / identity / state cannot be verified, the project refuses to guess |
| Easy to stop/remove | The Timer can be paused independently; default uninstall removes only verified managed resources |

Public V1 deliberately does not try to make every step automatic. Anything involving credentials, real requests, or system-level scheduling retains an explicit user authorization point.

---

## Architecture overview

```text
Official standalone Codex CLI
          │
          │ install-time source
          ▼
root-owned Anchor runtime snapshot
/usr/local/bin/codex-window-anchor
          │
          │
user-selected systemd timer
          │
          ▼
codex-window-anchor.service
          │
          ▼
      run-anchor.sh
          │
          ├── dedicated codex-anchor user
          ├── dedicated CODEX_HOME
          ├── explicit minimal environment
          └── ephemeral + read-only Codex invocation
          │
          ▼
    one real Codex request
          │
          ▼
          OK
          │
          ▼
       process exits
```

There is no Anchor process continuously waiting for the next run. systemd Timer handles the waiting; a Codex process exists only during an actual trigger.

### Main components

| Component | Responsibility |
| --- | --- |
| `install.sh` | Creates managed identity, runtime, and systemd foundation |
| `/usr/local/bin/codex-window-anchor` | Independent root-owned Codex runtime snapshot |
| `run-anchor.sh` | Fixed execution entrypoint for every Anchor |
| `anchor.conf` | Non-secret runtime configuration |
| `/home/codex-anchor/.codex` | Dedicated Codex Home / authentication state |
| `codex-window-anchor.service` | systemd oneshot service for one request |
| `codex-window-anchor-schedule` | Validates user times and generates the Timer |
| `codex-window-anchor.timer` | The Schedule explicitly chosen and enabled by the user |
| `install.meta` | Ownership / identity / runtime evidence |
| `uninstall.sh` | Safely removes project resources based on evidence |

---

## Runtime isolation

### Why Anchor does not directly run the user's `codex` from Home

The simplest design would let systemd execute the user's existing Codex directly. Public V1 intentionally does not do that.

A real AlmaLinux environment exposed an important distinction: an executable that works in an interactive shell is not automatically guaranteed to execute under systemd + SELinux from the same path. In addition, if Anchor always referenced the user's PATH `codex`, an ordinary host-side update could silently change the runtime used by an automated job without any Anchor revalidation.

The Installer therefore creates:

```text
/usr/local/bin/codex-window-anchor
```

from the standalone Codex executable explicitly selected by the user.

This snapshot is root-owned and independent from the original Codex path after installation.

The Installer then verifies that it:

- is a native Linux ELF;
- can execute `--version` as a non-privileged identity;
- supports the `codex exec` options required by Anchor;
- can be SHA-256 fingerprinted and recorded;
- can actually be executed by systemd.

When `restorecon` is available, the Installer restores the expected SELinux context and validates the final path through a transient `systemd-run` probe.

The result is:

```text
updating the user's normal codex
        ≠
automatically changing the Anchor runtime
```

The runtime snapshot design gives up automatic upgrade convenience in exchange for a clearer, repeatably verifiable automation boundary.

---

## Identity and authentication boundary

Anchor requests do not run as root and do not directly use the installing user's Linux account.

The Installer uses a dedicated identity:

```text
user:  codex-anchor
group: codex-anchor
home:  /home/codex-anchor
```

The systemd service runs as that user/group, and ChatGPT authentication state uses:

```text
CODEX_HOME=/home/codex-anchor/.codex
```

This separates the host user's normal Codex environment from Anchor:

```text
host user's Codex environment
        │
        └──── not directly reused ────┐

codex-anchor dedicated Home
        │                             │
        ├── ChatGPT auth              │
        └── Anchor Codex state
```

The Installer does **not** copy another user's `auth.json` and does not automatically sign in to ChatGPT. The user explicitly authenticates `codex-anchor`.

Root privileges are used only where system-level privileges are actually required, such as installing root-owned files, generating the systemd Timer, or enabling/disabling the system Timer. The real Codex request runs as the non-root `codex-anchor` identity.

---

## How one Anchor runs

Every manual trigger or Timer trigger eventually enters:

```text
/usr/local/libexec/codex-window-anchor/run-anchor.sh
```

The Runner reads:

```text
/etc/codex-window-anchor/anchor.conf
```

which contains only non-secret runtime information such as:

```text
CODEX_BIN=/usr/local/bin/codex-window-anchor
CODEX_MODEL=gpt-5.6-luna
```

It does not store ChatGPT tokens or an API Key there.

Before starting Codex, the Runner checks the runtime, model, dedicated Home, Codex Home, and its own state directories. It then uses:

```text
/usr/bin/env -i
```

instead of inheriting the full systemd manager environment.

The base allowlist includes:

```text
HOME
USER
LOGNAME
SHELL
PATH
CODEX_HOME
CODEX_SQLITE_HOME
```

It also permits common network variables that may be required by an existing proxy or CA setup, for example:

```text
HTTP_PROXY / HTTPS_PROXY / ALL_PROXY / NO_PROXY
CODEX_CA_CERTIFICATE
SSL_CERT_FILE / SSL_CERT_DIR
CURL_CA_BUNDLE / REQUESTS_CA_BUNDLE
```

This prevents ordinary environment variables such as `OPENAI_API_KEY`, `CODEX_ACCESS_TOKEN`, `OPENAI_BASE_URL`, or other provider/workload identity switches from accidentally entering the Anchor runtime while still allowing an administrator's already-correct enterprise proxy / CA environment to function.

---

## Codex invocation

The Runner's core execution semantics are:

```text
codex exec
  --model <configured model>
  --ephemeral
  --ignore-user-config
  --ignore-rules
  --skip-git-repo-check
  --sandbox read-only
  --color never
  <fixed minimal prompt>
```

Each option supports a Public V1 boundary:

- `--ephemeral`: every run is a short-lived independent task;
- `--ignore-user-config`: ordinary user Codex configuration does not change Anchor behavior;
- `--ignore-rules`: user/project rules do not expand the task;
- `--skip-git-repo-check`: the runtime work directory does not need to be a Git repository;
- `--sandbox read-only`: Anchor is not intended to modify server files;
- `--color never`: journald does not need terminal color output.

The Installer checks that the selected runtime supports these options at installation time. If it does not meet the contract, installation stops instead of leaving the failure for a future scheduled run.

The fixed prompt is:

```text
Reply exactly with OK. Do not inspect files, run commands, browse the web, use tools, or perform any additional work.
```

The goal is not to make Codex perform a code task, but to reduce the application-level work to one explicit minimal request.

**Every Anchor is a real Codex request. The application-level input and output are intentionally tiny, and the overall task is designed to be as lightweight as possible, but actual token accounting can vary with the Codex CLI, model, and OpenAI-side context.**

---

## systemd execution model

### Oneshot service

`codex-window-anchor.service` uses:

```text
Type=oneshot
User=codex-anchor
Group=codex-anchor
WorkingDirectory=/var/lib/codex-window-anchor/work
ExecStart=/usr/local/libexec/codex-window-anchor/run-anchor.sh
```

and:

```text
NoNewPrivileges=true
PrivateTmp=true
UMask=0077
TimeoutStartSec=180
```

One trigger therefore has this lifecycle:

```text
systemd starts service
→ runner execs Codex
→ one request completes
→ process exits
→ service becomes inactive
```

Seeing:

```text
inactive (dead)
```

after a successful run is normal. It does not mean a daemon crashed.

### Why there is no long-running daemon

Anchor work only exists at selected points in time. There is no need for a custom program to remain resident 24/7 waiting. Letting systemd Timer handle the waiting reduces persistent processes, state management, and long-running complexity.

---

## Schedule and explicit opt-in

Public V1 has no public default run time. The user chooses the Schedule, and more scheduled times mean more real Codex requests.

Immediately after installation, this file does not even exist:

```text
/etc/systemd/system/codex-window-anchor.timer
```

Only after the user runs:

```bash
codex-window-anchor-schedule \
  --timezone AREA/CITY \
  --time HH:MM
```

does the Schedule helper validate the IANA timezone, strict 24-hour times, complete installation state, dedicated identity, managed files, and runtime fingerprint, then generate the Timer.

Each configured time becomes:

```text
OnCalendar=*-*-* HH:MM:00 AREA/CITY
```

The generated Timer uses:

```text
AccuracySec=30s
RandomizedDelaySec=0
Persistent=false
Unit=codex-window-anchor.service
```

`Persistent=false` means a missed Schedule is not caught up after the server returns. Anchor waits for the next normal time instead.

The timezone is part of `OnCalendar=` and does not require changing the host's global timezone.

### Bounded self-elevation

Writing under `/etc/systemd/system/...` requires root, but the public CLI is intentionally:

```bash
codex-window-anchor-schedule ...
```

The helper elevates only when the system write is needed. Before doing so, it verifies that the current executable resolves to:

```text
/usr/local/bin/codex-window-anchor-schedule
```

and is a root-owned, mode `755`, regular managed file. Only then does it re-execute the original arguments through:

```text
/usr/bin/sudo
```

It does not modify:

```text
/etc/sudoers
sudoers.d
user PATH
```

### Why Schedule generation still does not start anything

The Schedule helper lifecycle is:

```text
validate
→ generate
→ verify
→ daemon-reload
→ prove disabled/inactive
```

It does not enable or start the Timer.

If a managed Timer already exists, the helper only replaces it after proving it is:

```text
disabled
inactive
```

The explicit authorization point that turns a configuration file into a running automatic task is:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

---

## Ownership evidence and fail-closed behavior

One of the most dangerous mistakes in system-level uninstall logic is treating “same name” as proof of ownership.

The Installer therefore maintains:

```text
/etc/codex-window-anchor/install.meta
```

with project ownership and identity/runtime evidence such as:

```text
format version
installation state
service user / group / home
UID / GID
runtime SHA-256
```

It does not contain ChatGPT credentials.

The Schedule helper and Uninstaller combine metadata, ownership markers, file owner/mode, identity, runtime fingerprint, and systemd namespace/state to determine whether an object is still project-managed.

Public V1's removal rule is therefore not:

```text
named codex-window-anchor
→ delete
```

but:

```text
positively proven to belong to this project
→ allow modification/removal
```

If there is an alias, drop-in, UID/GID mismatch, changed runtime hash, uncertain ownership, or other ambiguity, the scripts prefer to preserve state and fail closed.

That is why some abnormal uninstall cases may leave metadata or a residual resource instead of forcing a “clean-looking” result with `rm -rf`.

---

## Uninstall and authentication preservation

By default:

```bash
sudo ./scripts/uninstall.sh
```

removes verified Anchor Timer/service/runner/schedule helper/runtime snapshot/configuration and empty runtime directories, while preserving:

```text
codex-anchor user
/home/codex-anchor
ChatGPT authentication state
```

along with minimal verified identity metadata.

Authentication is valuable state established explicitly by the user. A normal uninstall should not destroy it as a side effect, and preserving it also allows a later verified reinstall to reuse authentication if the exact identity still matches.

Reuse is not based on username alone. The Installer rechecks:

```text
username
UID
group
GID
home path
home ownership
preserved metadata
```

and accepts preserved identity only on an exact match.

To explicitly remove the dedicated identity and authentication too:

```bash
sudo ./scripts/uninstall.sh --purge-user
```

Purge represents a separate destructive intent. It verifies identity again before deletion and requests interactive confirmation by default.

---

## System boundary

Codex Window Anchor deliberately keeps its scope small.

### The project manages

```text
dedicated codex-anchor identity
Anchor runtime snapshot
Anchor runner/config/state
Anchor service
user-generated Anchor Timer
installation metadata
```

### The project does not automatically manage

```text
OpenAI Codex installation/upgrades
ChatGPT plan / quota
firewall
VPN
host proxy
system global timezone
swap / /etc/fstab
global journald retention
other systemd services
web dashboard / database
```

The Runner can inherit a limited set of proxy / CA environment variables so an existing network setup can work. That does not mean Anchor creates or manages a proxy.

SELinux follows the same principle: Public V1 has been validated in Enforcing mode. The Installer uses normal system paths/context and a systemd probe instead of gaining compatibility through:

```text
setenforce 0
disable SELinux
chmod 777
```

---

## Complete lifecycle

Starting from “the official Codex CLI is already installed”:

```text
Official Codex
      │
      ▼
Installer
      │
      ├── dedicated identity
      ├── runtime snapshot + fingerprint
      ├── runner / config / service
      └── ownership metadata
      │
      ▼
NO TIMER / NO REQUEST
      │
      ▼
user authenticates codex-anchor
      │
      ▼
user creates Schedule
      │
      ├── Timer generated
      └── proved disabled / inactive
      │
      ▼
user reviews
      │
      ▼
explicit enable --now
      │
      ▼
Timer waits
      │
      ▼
scheduled trigger
      │
      ▼
oneshot service
      │
      ▼
one minimal Codex request
      │
      ▼
process exits
```

Pause:

```text
disable --now
→ Timer disabled/inactive
→ runtime/auth remain
```

Default uninstall:

```text
managed runtime/service/timer removed
→ dedicated identity/auth preserved
```

Explicit purge:

```text
managed resources removed
→ verified dedicated identity/home/auth removed
```

---

## Important paths

| Purpose | Path |
| --- | --- |
| Anchor runtime | `/usr/local/bin/codex-window-anchor` |
| Schedule helper | `/usr/local/bin/codex-window-anchor-schedule` |
| Runner | `/usr/local/libexec/codex-window-anchor/run-anchor.sh` |
| Runtime config | `/etc/codex-window-anchor/anchor.conf` |
| Installation metadata | `/etc/codex-window-anchor/install.meta` |
| systemd service | `/etc/systemd/system/codex-window-anchor.service` |
| Generated Timer | `/etc/systemd/system/codex-window-anchor.timer` |
| Dedicated Home | `/home/codex-anchor` |
| Dedicated Codex Home | `/home/codex-anchor/.codex` |
| Work directory | `/var/lib/codex-window-anchor/work` |
| SQLite state | `/var/lib/codex-window-anchor/sqlite` |

---

## Related documentation

- [Installation and configuration](INSTALLATION.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Security](../SECURITY.md)
- [Back to README](../README.md)

Codex Window Anchor is an independent project and is not an official OpenAI product. This document describes the current Public V1 implementation. Usage Window behavior is observed behavior; OpenAI may change the Codex CLI, authentication, models, plan limits, or related usage behavior in the future.
