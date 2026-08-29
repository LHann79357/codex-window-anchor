# Codex Window Anchor — Troubleshooting

This document is for troubleshooting Codex Window Anchor Public V1 installation, ChatGPT sign-in, manual Anchor runs, Schedule generation, systemd Timer behavior, and uninstall.

If you have not completed the standard installation yet, follow [INSTALLATION.md](INSTALLATION.md) first. This guide does not repeat the full deployment flow; it focuses on cases where a specific step does not behave as expected.

> [!IMPORTANT]
> Do not try to “make it work first” by disabling SELinux, using `chmod 777`, deleting unknown systemd files, manually editing `auth.json`, or putting an API Key into Anchor configuration.
>
> Public V1 Installer / Schedule / Uninstall flows are designed to fail closed. When a script cannot safely prove that a file, user, runtime, or systemd state belongs to this project, **refusing to continue is usually a safety boundary, not an invitation to bypass the check.**

## Start here

Most problems can first be narrowed down to one of four layers: the official Codex installation, authentication, the Anchor service, or the Timer.

```bash
# System
uname -a
systemctl --version

# Official Codex on the host
command -v codex
codex --version

# Anchor authentication state
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status

# Anchor service
sudo systemctl status codex-window-anchor.service --no-pager -l
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager

# Timer (only after a Schedule has been configured)
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer --all --no-pager
systemctl cat codex-window-anchor.timer
```

Keep the **complete original error message**. If the failure occurs during OpenAI sign-in or request execution, also check [OpenAI Status](https://status.openai.com/). Codex authentication, access, or service incidents do not necessarily originate in Anchor.

---

## Common problems

| Symptom | Check first |
| --- | --- |
| Official Codex installer says `tar is required` | [Missing `tar`](#official-codex-installer-says-tar-is-required) |
| Anchor Installer cannot find Codex | [Codex CLI not found](#installer-says-codex-cli-was-not-found) |
| Installer says Codex is not native ELF / is missing a required option | [Codex runtime does not meet V1 requirements](#installer-rejects-the-selected-codex-runtime) |
| Device Code sign-in fails | [ChatGPT / Device Code sign-in](#device-code-sign-in-fails) |
| `systemctl start` fails | [Manual Anchor failure](#manual-anchor-run-fails) |
| service shows `inactive (dead)` | [Is this normal?](#service-shows-inactive-dead) |
| Installer says systemd cannot execute Codex | [SELinux / systemd execution](#systemd-cannot-execute-the-anchor-runtime) |
| Schedule helper says Timer is enabled/active | [Pause the Timer first](#schedule-helper-refuses-to-modify-a-running-timer) |
| timezone / time argument is rejected | [Schedule arguments](#timezone-or-time-argument-is-rejected) |
| Timer exists but does not run automatically | [Timer does not trigger](#timer-does-not-run-as-expected) |
| No catch-up run after the server was offline | [Designed behavior](#a-missed-anchor-is-not-caught-up) |
| Uninstaller refuses to remove something | [Safe uninstall](#uninstaller-refuses-to-continue-or-preserves-resources) |
| Installation stopped and reinstall now fails | [Partial installation](#installation-stopped-partway-through-and-reinstall-fails) |
| Restricted network / proxy environment fails | [Network / proxy](#network-or-proxy-environment-prevents-codex-access) |

---

## Official Codex installer says `tar is required`

### Symptom

While installing the official standalone Codex CLI, you see something like:

```text
tar is required to install Codex.
```

### Cause

Minimal systems such as AlmaLinux Minimal may not include `tar` by default. This is a prerequisite problem for the standalone Codex installer, not an Anchor Installer failure.

### Fix

AlmaLinux 8.10:

```bash
sudo dnf install -y git curl tar
```

Then run the official OpenAI Codex installer again:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

Finally confirm:

```bash
codex --version
command -v codex
```

Only after the host user can run the official standalone Codex normally should you run:

```bash
sudo ./scripts/install.sh
```

---

## Installer says `Codex CLI was not found`

### Symptom

The Anchor Installer reports:

```text
Codex CLI was not found. Install the official standalone Codex CLI first, or use --codex-bin PATH
```

### Check first

```bash
command -v codex
codex --version
```

If those already fail, fix the official Codex installation before troubleshooting Anchor.

If Codex does exist but is not in a location the Installer can safely discover:

```bash
readlink -f "$(command -v codex)"
```

Then explicitly point the Installer to the **official standalone executable using an absolute path**:

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/codex
```

By default, the Installer checks `codex` in the current `PATH`. In a `sudo` scenario, if it is not found there, it also checks the invoking user's:

```text
~/.local/bin/codex
```

> [!IMPORTANT]
> `--codex-bin` is not a general “accept any binary” escape hatch.
>
> The Installer validates file form and CLI capabilities but does not establish publisher provenance for you. Select only a standalone Codex executable obtained from an official OpenAI source.

---

## Installer rejects the selected Codex runtime

### Possible errors

For example:

```text
staged Codex snapshot is not a native Linux ELF executable
```

or:

```text
staged Codex CLI does not support required option: ...
```

### What it means

Public V1 does not attempt to adapt every possible `codex` wrapper. The Installer creates a root-owned runtime snapshot and requires it to be:

- a regular executable file;
- a native Linux ELF;
- executable as a non-privileged user with `--version`;
- compatible with the `exec` options Anchor uses.

An npm/node wrapper, wrong-architecture executable, old/incompatible CLI, or unrelated same-named program may therefore be rejected.

### Fix

Check:

```bash
command -v codex
codex --version
file "$(command -v codex)"
```

Then reinstall the current standalone Codex CLI from an official OpenAI source. Do not patch the Installer to skip ELF or required-option checks.

If the system has multiple Codex installations, select the correct one explicitly:

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/official/codex
```

---

## Device Code sign-in fails

Public V1 uses this flow on remote/headless Linux:

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login --device-auth
```

OpenAI's current authentication documentation describes Device Code Authentication for remote/headless environments. Whether it is available can depend on personal security settings or Workspace permissions. OpenAI also documents dedicated login diagnostics and states that file-based `auth.json` should be protected like a password.

### Check first

1. The ChatGPT account has Codex access.
2. Device Code Login is allowed by the personal account or Workspace policy.
3. The server can reach OpenAI/Codex.
4. OpenAI is not currently experiencing a Codex authentication incident.

Official references:

- [Codex Authentication](https://developers.openai.com/codex/auth)
- [OpenAI Status](https://status.openai.com/)

Then re-check:

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status
```

> [!WARNING]
> Do not post tokens, `auth.json` contents, or the Device Code in an Issue.
>
> OpenAI documents other headless fallbacks that can involve copying authentication state or SSH callback forwarding. Those are not part of Codex Window Anchor's standard installation path. If you need them, follow OpenAI's current official Authentication documentation directly and do not rely on unknown third-party credential-handling instructions.

---

## Manual Anchor run fails

Manual validation:

```bash
sudo systemctl start codex-window-anchor.service
```

If it fails, do not enable the Timer yet.

Check:

```bash
sudo systemctl status codex-window-anchor.service --no-pager -l
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

Then work through the following in order.

### 1. Does authentication exist?

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status
```

If authentication is invalid, complete Device Code Login again.

### 2. Does Anchor configuration exist?

```bash
sudo cat /etc/codex-window-anchor/anchor.conf
```

A normal file should contain at least something similar to:

```text
CODEX_BIN=/usr/local/bin/codex-window-anchor
CODEX_MODEL=...
```

This is **non-secret runtime configuration**. Do not add an API Key or ChatGPT token to it.

### 3. Does the runtime exist?

```bash
ls -l /usr/local/bin/codex-window-anchor
/usr/local/bin/codex-window-anchor --version
```

If the runtime is missing or was externally modified, do not manually copy a binary over it. Restore a verifiable state using the runtime update/reinstall flow in [INSTALLATION.md](INSTALLATION.md).

### 4. Is this an OpenAI-side error?

If the journal reports authentication, capacity, service unavailable, or another remote error, also check:

[OpenAI Status](https://status.openai.com/)

Remote Codex authentication, access, and model-capacity incidents can occur, so a remote error should not automatically be attributed to Anchor.

---

## Service shows `inactive (dead)`

This is usually **not a failure**.

`codex-window-anchor.service` is:

```text
Type=oneshot
```

After one Anchor finishes, the process exits and the service returns to:

```text
inactive (dead)
```

That is its normal lifecycle.

Do not judge success by expecting it to remain `active (running)`.

Inspect the latest run:

```bash
sudo journalctl -u codex-window-anchor.service -n 50 --no-pager
```

or:

```bash
sudo systemctl status codex-window-anchor.service --no-pager -l
```

Focus on whether the latest invocation exited successfully and whether the journal contains a real error.

---

## systemd cannot execute the Anchor runtime

### Typical Installer error

```text
systemd could not execute the Codex runtime; inspect the system journal and SELinux audit log
```

### Why this can happen

A real AlmaLinux/RHEL-family environment exposed an important distinction: a Codex executable that runs interactively from a user Home is not necessarily executable under systemd/SELinux in the same location.

Public V1 therefore does not run Codex directly from a user's Home. It creates:

```text
/usr/local/bin/codex-window-anchor
```

as a root-owned runtime snapshot. When `restorecon` is available, the Installer restores the expected SELinux context and then uses a transient systemd probe to verify that systemd can actually execute the runtime.

### Troubleshoot

Check:

```bash
getenforce
ls -l /usr/local/bin/codex-window-anchor
ls -Z /usr/local/bin/codex-window-anchor
sudo journalctl -b --no-pager | grep -i -E 'codex-window-anchor|avc|selinux'
```

If the system provides `restorecon`, you can restore the default context for this **project-managed runtime file**:

```bash
sudo restorecon -v /usr/local/bin/codex-window-anchor
```

Then rerun the project Installer so the transient probe can validate the runtime again.

> [!CAUTION]
> Do not use:
>
> ```bash
> setenforce 0
> chmod 777 /usr/local/bin/codex-window-anchor
> ```
>
> Public V1 has been validated with **SELinux Enforcing**. Disabling SELinux or loosening permissions to `777` is not an accepted project fix.

---

## Schedule helper refuses to modify a running Timer

### Typical error

```text
timer is enabled; pause it first with:
sudo systemctl disable --now codex-window-anchor.timer
```

or a message that the Timer is still active.

### This is intentional

`codex-window-anchor-schedule` does not silently pause or replace a live Schedule.

First run:

```bash
sudo systemctl disable --now codex-window-anchor.timer
```

Confirm:

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
```

Then configure again:

```bash
codex-window-anchor-schedule \
  --timezone YOUR/ZONE \
  --time HH:MM
```

After the helper completes, it should again remain:

```text
disabled / inactive
```

Review it, then explicitly resume:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

The final helper implementation only replaces an existing Timer after it can prove the Timer is disabled and inactive.

---

## Timezone or Time argument is rejected

### Timezone

The timezone must be an installed IANA `AREA/CITY` entry, for example:

```text
America/New_York
Europe/London
Asia/Shanghai
```

List available timezones:

```bash
timedatectl list-timezones
```

Do not pass forms such as:

```text
UTC+8
GMT+8
CST
/path/to/zone
../zone
```

For UTC, use:

```text
Etc/UTC
```

### Time

Time must use strict 24-hour format:

```text
00:00
09:30
23:59
```

These are rejected:

```text
9:30
24:00
9 PM
09:60
```

Duplicate times are automatically deduplicated and sorted.

The Schedule timezone does not modify the server's global timezone. The helper places the timezone in the Timer's `OnCalendar=` entry.

---

## Timer does not run as expected

First confirm that the Timer was actually **explicitly enabled**:

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer --all --no-pager
```

If it is still:

```text
disabled
inactive
```

you generated the Schedule but did not start automatic operation.

Enable it:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

Then inspect the actual Timer:

```bash
systemctl cat codex-window-anchor.timer
```

Confirm that `OnCalendar=` contains the timezone and time you configured.

If the Timer is active but the service fails:

```bash
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

The Timer only **triggers** the service. Authentication, networking, model, or Codex runtime failures appear in the service journal.

---

## A missed Anchor is not caught up

This is Public V1's intended behavior, not a Timer failure.

The generated Timer uses:

```text
Persistent=false
```

If the server is:

- powered off;
- rebooting;
- otherwise unavailable

at the scheduled time, systemd does not immediately “catch up” the missed Anchor later.

It waits for the next normal Schedule.

This prevents an Anchor intended for a fixed time from unexpectedly running hours later after the server recovers.

---

## `codex-window-anchor-schedule` is missing or cannot elevate

First check:

```bash
command -v codex-window-anchor-schedule
```

The Public V1 installation path should be:

```text
/usr/local/bin/codex-window-anchor-schedule
```

Then:

```bash
ls -l /usr/local/bin/codex-window-anchor-schedule
```

The helper's self-elevation logic only accepts the **installed formal helper**. A normal user should run:

```bash
codex-window-anchor-schedule ...
```

Do not treat the repository copy:

```text
scripts/configure-schedule.sh
```

as the public normal-user command.

Public V1 uses `/usr/local/bin` to avoid relying on environments where `sudo secure_path` may exclude `/usr/local/sbin`. The final implementation does not require changes to `/etc/sudoers` or the user's PATH.

If the formal helper is missing or its ownership/mode has been externally modified, do not patch the script to bypass its self-check. Restore managed state with the default uninstall/reinstall path.

---

## Network or proxy environment prevents Codex access

Codex Window Anchor **does not modify host firewall or proxy configuration**. That is an explicit Installer boundary.

First distinguish these cases.

### The official Codex on the host also cannot connect

Solve the Codex/OpenAI network problem first. Anchor is not a network proxy tool.

You can check:

```bash
codex --version
```

and OpenAI status:

[https://status.openai.com/](https://status.openai.com/)

If sign-in is failing, see [OpenAI Codex Authentication](https://developers.openai.com/codex/auth).

OpenAI's authentication documentation also describes `CODEX_CA_CERTIFICATE` or `SSL_CERT_FILE` for environments that use an enterprise TLS proxy / private CA. That is Codex network/certificate configuration, not something Anchor automatically manages.

### Interactive shell works, but the systemd Anchor fails

Do not assume that:

```bash
export HTTP_PROXY=...
export HTTPS_PROXY=...
```

in an SSH shell automatically becomes persistent systemd service environment.

Public V1 does not automatically copy user-shell proxy settings and does not modify system proxy configuration. First confirm through the service journal that the failure is actually network-related:

```bash
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

If your server requires a custom proxy, enterprise CA, or other injected network configuration to reach Codex, that is **advanced environment adaptation**. Do not place private proxy addresses, subscription URLs, or credentials in the repository, Issues, or public examples.

---

## Model is unavailable or the request is rejected

The default configuration uses:

```text
gpt-5.6-luna
```

Model availability can change with Codex and the user's plan.

If the journal clearly reports model unavailable / capacity / access errors, check:

1. OpenAI Status;
2. whether the account currently has access to that model/Codex;
3. current OpenAI Codex model availability.

Do not automatically treat this as a Timer failure.

To move Anchor to another **currently available model you have verified**, Public V1 uses the reviewable reinstall path:

```bash
sudo ./scripts/install.sh --model MODEL
```

Because the default uninstall removes the generated Timer, a runtime/model reinstall requires running the schedule helper again, reviewing the Timer, and explicitly enabling it. See [INSTALLATION.md](INSTALLATION.md).

---

## Installation stopped partway through and reinstall fails

The Installer checks system-level paths, service names, service users, homes, and metadata for collisions.

If an installation begins modifying the system but does not complete, the Installer reports:

```text
Installation did not complete.
A partial installation may remain on this host.
```

Do not immediately do things such as:

```text
rm -rf /etc/codex-window-anchor
userdel -r codex-anchor
manually delete systemd files and retry repeatedly
```

If project metadata exists:

```text
/etc/codex-window-anchor/install.meta
```

prefer running from the repository directory:

```bash
sudo ./scripts/uninstall.sh
```

The Uninstaller uses metadata and ownership evidence to remove partial resources it can safely identify as project-managed.

Then reinstall:

```bash
sudo ./scripts/install.sh
```

If uninstall also refuses to continue because of identity/path ambiguity, preserve the full error and use the Issue-diagnostics section below instead of forcing deletion.

---

## Uninstaller refuses to continue or preserves resources

The Uninstaller does not use “same name” as sufficient proof of ownership.

It checks:

- installation metadata;
- managed ownership marker;
- root ownership;
- runtime SHA-256;
- service user / group;
- UID / GID;
- home path / ownership;
- exact systemd state.

If one of those cannot be safely confirmed, it may report:

```text
WARNING
```

and preserve resources/metadata, or fail closed. The default uninstall also **intentionally preserves** the `codex-anchor` user/home/authentication state.

Do not use `rm -rf` just to produce a cleaner-looking result.

Preserve:

```text
/etc/codex-window-anchor/install.meta
```

and the complete error, then check:

```bash
sudo ./scripts/uninstall.sh --help
```

If your actual goal is to remove the dedicated user/home/auth as well, use:

```bash
sudo ./scripts/uninstall.sh --purge-user
```

instead of the default uninstall.

> [!NOTE]
> Public V1 has been validated on AlmaLinux 8.10 / systemd 239 and correctly distinguishes service-absent, stopped, and abnormal states.
>
> If the current version still reports an uninstall failure, preserve the complete error. Do not bypass the check by broadly ignoring `systemctl` failures or force-deleting resources manually.

---

## Journal history is large — can the project clean it automatically?

Public V1 does not automatically vacuum the system journal.

View recent Anchor logs:

```bash
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

For time-based filtering, use journald's own query options rather than deleting global history.

Do not casually run global:

```text
journalctl --vacuum-*
```

just for Anchor, because journal history is shared across system services and cleanup can affect unrelated service history.

The default uninstall also preserves system journal history.

---

## Collect this information before opening an Issue

Before opening an Issue, prepare a **minimal, reproducible, non-sensitive** problem description and collect at least:

```bash
uname -a
systemctl --version
codex --version
```

If the Installer has completed, also provide:

```bash
/usr/local/bin/codex-window-anchor --version

sudo systemctl status codex-window-anchor.service --no-pager -l
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

For Schedule-related problems:

```bash
systemctl cat codex-window-anchor.timer
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer --all --no-pager
```

The Issue description should include:

- Linux distribution / version;
- CPU architecture;
- systemd version;
- Codex version;
- the **exact command** you ran;
- the full error message;
- whether the problem occurred during install / login / manual run / schedule / timer / uninstall;
- whether it reproduces consistently.

### Remove sensitive data before posting logs

Never post:

- `/home/codex-anchor/.codex/auth.json`;
- ChatGPT access / refresh tokens;
- Device Code;
- API Keys;
- SSH private keys;
- root/SSH passwords;
- VPS IP address, if you do not want it public;
- proxy subscriptions / proxy credentials;
- unrelated service secrets.

OpenAI's documentation states that file-based `auth.json` contains access tokens and should be protected like a password.

---

## Still not resolved?

This order is usually the most effective:

```text
Confirm the official Codex itself works
        ↓
Confirm codex-anchor authentication
        ↓
Run the Anchor service manually
        ↓
Inspect the service journal
        ↓
Confirm Schedule / Timer state
        ↓
Check whether OpenAI currently has an incident
        ↓
Prepare minimal non-sensitive diagnostics
        ↓
Open a GitHub Issue
```

If the problem concerns Codex sign-in, account permissions, model access, or OpenAI service status, check OpenAI's official resources first. If it concerns the Anchor Installer, runtime isolation, Schedule helper, systemd Timer, or safe uninstall, report it to the Codex Window Anchor project.

---

## Related documentation

- [Installation and configuration](INSTALLATION.md)
- [How it works](HOW_IT_WORKS.md)
- [Security](../SECURITY.md)
- [Back to README](../README.md)

Codex Window Anchor is an independent project and is not an official OpenAI product.
