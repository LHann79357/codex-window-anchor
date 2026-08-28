# Codex Window Anchor

**Self-hosted scheduling for observed Codex usage-window anchoring with the official Codex CLI.**

Codex Window Anchor is a lightweight Linux/systemd project that runs a minimal, real Codex CLI request at user-selected times. It is designed for users who want a predictable, auditable, self-hosted schedule around observed Codex usage-window behavior without browser automation, API-key-based scheduling, third-party keepalive plugins, a web panel, or a permanent daemon.

> [!IMPORTANT]
> **Codex Window Anchor does not increase Codex quota, create additional allowance, bypass limits, force quota resets, or provide unlimited Codex.**
>
> Every Anchor is a **real Codex request** and consumes real allowance.
>
> The approximately five-hour usage-window behavior referenced by this project is an **observed behavior from testing**, not a permanent OpenAI product or API contract. OpenAI may change plans, models, authentication, quotas, limits, and usage-window behavior at any time.

## How it works

```text
systemd timer
    ↓
systemd oneshot service
    ↓
run-anchor.sh
    ↓
official Codex CLI
    ↓
minimal real request
    ↓
OK
    ↓
process exits
```

The V1 runtime uses:

- a dedicated non-root `codex-anchor` user;
- the official standalone Codex CLI;
- ChatGPT account authentication;
- a root-owned Codex runtime snapshot;
- `--ephemeral`;
- `--ignore-user-config`;
- `--ignore-rules`;
- `--skip-git-repo-check`;
- `--sandbox read-only`;
- a fixed minimal prompt;
- a systemd oneshot service;
- a systemd timer with no persistent catch-up.

No permanent Anchor daemon is kept running.

**Codex Window Anchor does not choose your schedule for you.** Before enabling scheduling, you explicitly choose the timezone, number of Anchor runs, and Anchor times.

## Validated reference environment

The public V1 implementation was validated against the following reference environment:

| Component | Reference |
| --- | --- |
| Distribution | AlmaLinux 8.10 x86_64 |
| systemd | 239 |
| SELinux | Enforcing |
| Codex | Official standalone Codex CLI |
| Authentication | ChatGPT account login |
| Runtime identity | Dedicated non-root `codex-anchor` user |
| Reference model | `gpt-5.6-luna` |
| Tested integration candidate | `9b255360ca611991817265b30f57e3ebee7c5a0e` |

This is the primary V1 reference target. Do not assume identical behavior on every Linux distribution or future Codex CLI version.

## Prerequisites

You need:

- a Linux host with systemd;
- `sudo` or root access for installation;
- network access for Codex;
- a ChatGPT account with Codex access;
- the **official standalone Linux Codex CLI** installed before running the Anchor installer.

Codex Window Anchor does **not** download or redistribute Codex.

### Install the official Codex CLI

Follow OpenAI's official Codex installation instructions:

https://github.com/openai/codex

For Mac/Linux, OpenAI currently documents the standalone installer as:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

Then verify:

```bash
codex --version
```

> [!NOTE]
> Codex Window Anchor V1 expects a native standalone Linux Codex executable. The V1 installer does not use an npm/node wrapper as its Anchor runtime.

## Quick start

### 1. Clone Codex Window Anchor

```bash
git clone https://github.com/LHann79357/codex-window-anchor.git
cd codex-window-anchor
```

### 2. Run the installer

```bash
sudo ./scripts/install.sh
```

The installer performs preflight checks, creates the dedicated runtime identity, stages a root-owned Codex runtime snapshot, and installs the runner, oneshot service, and schedule command.

It does **not** log into ChatGPT, send an Anchor request, create a schedule, or install a live timer.

### 3. Authenticate the dedicated service user

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login --device-auth
```

Then verify login status:

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status
```

Do not copy, publish, or commit Codex authentication files.

### 4. Run one manual Anchor

```bash
sudo systemctl start codex-window-anchor.service
```

Check:

```bash
sudo systemctl status codex-window-anchor.service
sudo journalctl -u codex-window-anchor.service -n 50 --no-pager
```

Because this is a `Type=oneshot` service, a successful run normally returns to `inactive (dead)`.

### 5. Configure your own schedule

```bash
sudo codex-window-anchor-schedule \
  --timezone <Area/City> \
  --time <HH:MM> \
  [--time <HH:MM> ...]
```

**Syntax example only — choose your own timezone and times:**

```bash
sudo codex-window-anchor-schedule \
  --timezone America/New_York \
  --time 07:30 \
  --time 19:15
```

The command validates the installed timezone and strict 24-hour times, removes duplicates, generates the timer atomically, reloads systemd, and proves the timer remains disabled and inactive. It never enables or starts the timer.

More scheduled Anchors mean more real Codex requests and more real allowance consumption. More scheduled Anchors do **not** create additional quota.

### 6. Review the generated schedule

```bash
systemctl cat codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

### 7. Enable scheduling explicitly

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

Verify:

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

## Pause and resume

Pause:

```bash
sudo systemctl disable --now codex-window-anchor.timer
```

Resume:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

Pausing the timer does not remove the installation or ChatGPT authentication state.

To change the schedule later:

1. Disable and stop the timer with `sudo systemctl disable --now codex-window-anchor.timer`.
2. Run `sudo codex-window-anchor-schedule` again with exactly one timezone and your chosen times.
3. Review the generated timer.
4. Explicitly enable the timer again only when ready.

The schedule command refuses to replace a timer that is enabled or active; it does not silently pause or resume scheduling.

## What the installer intentionally does not do

| Action | Automatic? | Reason |
| --- | ---: | --- |
| Download or install Codex | No | Codex remains managed through OpenAI's official installation path |
| Log into ChatGPT | No | Authentication must be explicitly performed by the user |
| Read or copy `auth.json` | No | Authentication state is managed by Codex |
| Send the first Anchor | No | A real allowance-consuming request requires explicit user action |
| Choose or create a schedule during install | No | The user explicitly chooses timezone, run count, and times afterward |
| Enable the timer | No | Scheduling starts only after explicit review and approval |
| Automatically update Codex | No | Prevents silent runtime drift |
| Configure Swap | No | Host resource management is outside the project boundary |
| Modify `/etc/fstab` | No | Avoids unrelated persistent host changes |
| Modify firewall rules | No | Not required by the project |
| Modify proxy configuration | No | Not a project dependency |
| Change the global timezone | No | The timer uses an explicit IANA timezone |
| Disable SELinux | No | Compatibility is not achieved by weakening SELinux |
| Use `chmod 777` | No | Unsafe permissions are intentionally avoided |
| Vacuum global journald history | No | The project does not delete unrelated service logs |
| Manage X-ui/Xray | No | They are not project dependencies |

**Manual does not mean optional.** Authentication, the first real Anchor, schedule review, and timer enablement are intentionally manual because they involve credentials, real allowance consumption, or host-level administrative decisions.

## Security model

- Codex requests run as the dedicated non-root `codex-anchor` user.
- Project-managed runtime/configuration files are root-owned.
- The service uses `NoNewPrivileges=true`, `PrivateTmp=true`, and a restrictive umask.
- The Codex sandbox is `read-only`.
- Sessions are `--ephemeral`.
- User Codex configuration and exec-policy rules are ignored for Anchor execution.
- The runner uses an explicit minimal environment.
- No API key is required for the documented V1 path.
- There is no infinite retry loop.
- The timer uses `Persistent=false`.
- Destructive user removal is opt-in.

Never publish Codex authentication state, ChatGPT tokens, API keys, SSH private keys, VPS credentials, proxy subscriptions, X-ui/Xray credentials, or private deployment notes containing sensitive information.

## AlmaLinux / RHEL-family / SELinux note

A real AlmaLinux 8.10 reference deployment exposed an important SELinux compatibility issue: a Codex executable under a user's home directory can work interactively while systemd is still denied permission to execute it.

V1 therefore uses a root-owned runtime snapshot at:

```text
/usr/local/bin/codex-window-anchor
```

and restores the normal SELinux context when `restorecon` is available.

The project does **not** solve SELinux compatibility by disabling enforcement, running `setenforce 0`, or using `chmod 777`.

## Configuration

Runtime configuration:

```text
/etc/codex-window-anchor/anchor.conf
```

The reference validation used:

```text
gpt-5.6-luna
```

Model availability can change. Review and update configuration if the reference model is no longer available.

The schedule is generated at `/etc/systemd/system/codex-window-anchor.timer` only after the user runs `codex-window-anchor-schedule`. It is not stored in `anchor.conf`, and no public default schedule is installed.

## Uninstall

Default uninstall:

```bash
sudo ./scripts/uninstall.sh
```

This preserves the dedicated identity/home/authentication state and the minimum evidence required for a verified preserved-auth reinstall.

Explicit purge:

```bash
sudo ./scripts/uninstall.sh --purge-user
```

Non-interactive explicit purge:

```bash
sudo ./scripts/uninstall.sh --purge-user --yes
```

The purge path performs identity checks before destructive user removal.

## Usage-window disclaimer

Treat the behavior documented by this project as:

- observed behavior;
- implementation experience;
- a scheduling pattern.

Do **not** treat it as:

- an OpenAI API guarantee;
- a permanent ChatGPT plan guarantee;
- a quota-reset mechanism;
- a quota multiplier;
- a limit bypass;
- a promise that future Codex versions will behave identically.

## Project structure

```text
codex-window-anchor/
├─ README.md
├─ LICENSE
├─ SECURITY.md
├─ .gitignore
├─ .gitattributes
├─ scripts/
│  ├─ install.sh
│  ├─ configure-schedule.sh
│  ├─ run-anchor.sh
│  └─ uninstall.sh
├─ systemd/
│  ├─ codex-window-anchor.service
│  └─ codex-window-anchor.timer.template
├─ tests/
│  └─ static-contract.sh
├─ docs/
│  ├─ INSTALL.md
│  ├─ OPERATIONS.md
│  ├─ TROUBLESHOOTING.md
│  └─ UNINSTALL.md
└─ examples/
   └─ schedule.example
```

## Project philosophy

V1 does not need a web dashboard, database, permanent daemon, browser automation, third-party keepalive service, or unrelated VPS software.

The goal is a small, inspectable systemd-based scheduling layer around the official Codex CLI.

## License

This project is intended to be released under the Apache License 2.0.

See `LICENSE` for the full license text.

---

Codex Window Anchor is an independent open-source project and is not an official OpenAI product.
