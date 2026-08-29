# Codex Window Anchor — Installation and Configuration

This document provides the complete Public V1 installation and day-to-day management flow for Codex Window Anchor. The goal is to give users one clear deployment path first, with advanced installation options, runtime updates, reinstall, and uninstall details available when needed.

If you only want a quick overview, start with the [README](../README.md).

> [!IMPORTANT]
> Codex Window Anchor does not download Codex, sign in to ChatGPT during installation, send an Anchor, create a default Schedule, or start a Timer.
>
> **Automatic scheduling starts only after you explicitly run:**
>
> ```bash
> sudo systemctl enable --now codex-window-anchor.timer
> ```

## Installation flow at a glance

```text
Prepare the Linux environment
→ Install the official OpenAI Codex CLI
→ Install Codex Window Anchor
→ Sign in to ChatGPT as codex-anchor
→ Choose your timezone / times
→ Review the Timer
→ (Optional but recommended) run one manual Anchor
→ Explicitly enable the Timer
→ Verify the Timer
```

---

## 1. Prepare the environment

The fully validated Public V1 baseline is **AlmaLinux 8.10 x86_64 / systemd 239**. The project has completed real automatic Timer validation on a **Vultr VPS**, and separate end-to-end integration validation in a clean **AlmaLinux 8.10 Minimal / systemd 239 / SELinux Enforcing** environment covering the Installer, Schedule, Timer, security boundaries, and Uninstall.

| Item | Public V1 baseline |
| --- | --- |
| Linux | AlmaLinux 8.10 x86_64 |
| systemd | 239 |
| SELinux | Enforcing (clean integration validation) |
| Codex | Official OpenAI standalone Linux executable |
| Authentication | ChatGPT account |
| Anchor user | `codex-anchor` |
| Default model | `gpt-5.6-luna` |

Vultr is **not a project dependency**. It is simply one VPS environment in which real operation has been validated. Other Linux distributions, systemd versions, and CPU architectures may work, but Public V1 does not claim the same support level until they receive equivalent integration validation.

### Install basic dependencies

AlmaLinux 8.10:

```bash
sudo dnf install -y git curl tar
```

Confirm systemd:

```bash
systemctl --version
```

You also need:

- `sudo` or root access;
- network access to OpenAI Codex;
- a ChatGPT account with Codex access.

If you use another Linux distribution, install equivalent dependencies with that distribution's package manager. This guide does not provide unvalidated distribution-specific commands.

---

## 2. Install the official OpenAI Codex CLI

Codex Window Anchor **does not download, bundle, or redistribute Codex**. Install the Codex CLI from an official OpenAI source first.

Official references:

- [OpenAI Codex GitHub](https://github.com/openai/codex)
- [OpenAI Codex Authentication](https://developers.openai.com/codex/auth)

OpenAI currently provides this standalone installer for Mac/Linux:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

After installation:

```bash
codex --version
command -v codex
```

Continue with Anchor only after both commands work normally.

> [!NOTE]
> Codex Window Anchor Public V1 uses a **native standalone Linux Codex executable** as the Anchor runtime.
>
> The Installer creates an independent root-owned snapshot from the selected executable, verifies that it is a native Linux ELF, and checks the Codex CLI options Anchor depends on. The current V1 runtime path does not use an npm/node wrapper.

---

## 3. Install Codex Window Anchor

Clone the repository:

```bash
git clone https://github.com/LHann79357/codex-window-anchor.git
cd codex-window-anchor
```

Run the standard Installer:

```bash
sudo ./scripts/install.sh
```

On success, the Installer reports the Anchor runtime, service user, and configured model, and explicitly states:

```text
No ChatGPT login was performed.
No Anchor request was sent.
No Anchor schedule was created.
No systemd timer is enabled or active.
```

### What the Installer installs

| Purpose | Path |
| --- | --- |
| Anchor Codex runtime | `/usr/local/bin/codex-window-anchor` |
| Schedule helper | `/usr/local/bin/codex-window-anchor-schedule` |
| Runner | `/usr/local/libexec/codex-window-anchor/run-anchor.sh` |
| Runtime config | `/etc/codex-window-anchor/anchor.conf` |
| Install metadata | `/etc/codex-window-anchor/install.meta` |
| systemd service | `/etc/systemd/system/codex-window-anchor.service` |
| Dedicated home | `/home/codex-anchor` |
| Runtime state | `/var/lib/codex-window-anchor/` |

The Installer creates the dedicated non-root user:

```text
codex-anchor
```

It also builds Anchor's own root-owned runtime snapshot from the standalone Codex executable you already installed. Updating another `codex` executable in the host user's PATH does not automatically replace this snapshot.

<details>
<summary><strong>What the Installer explicitly does not modify</strong></summary>

The Installer does not:

- download Codex;
- sign in to ChatGPT;
- read or copy `auth.json`;
- send an Anchor request;
- create a public default Schedule;
- create a live Timer;
- enable/start the Timer;
- change the system global timezone;
- modify the firewall;
- modify proxy configuration;
- modify swap;
- modify `/etc/fstab`;
- disable SELinux;
- use `chmod 777`;
- modify `/etc/sudoers`.

</details>

<details>
<summary><strong>Advanced installation options: select a Codex executable or model</strong></summary>

If the machine has multiple Codex executables, explicitly select the standalone binary you have verified came from an official OpenAI source:

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/codex
```

By default, the Installer first tries:

```bash
command -v codex
```

In a `sudo` scenario, if Codex is not found in PATH, it also checks the invoking user's:

```text
~/.local/bin/codex
```

The Installer validates the executable's file form, runtime capability, and required Anchor CLI capabilities, but it **does not independently establish publisher provenance**. Only select a Codex executable obtained from an official OpenAI source.

Default model:

```text
gpt-5.6-luna
```

To explicitly select another currently available model:

```bash
sudo ./scripts/install.sh --model MODEL
```

View all Installer options:

```bash
sudo ./scripts/install.sh --help
```

</details>

---

## 4. Sign in to ChatGPT as `codex-anchor`

Anchor uses its own Codex Home:

```text
/home/codex-anchor/.codex
```

It therefore does not directly reuse your normal Linux user's Codex Home.

On a remote/headless Linux host, run:

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login --device-auth
```

Follow the OpenAI Device Code flow shown in the terminal and complete authorization in a browser using a ChatGPT account with Codex access.

Then check authentication state:

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status
```

> [!WARNING]
> `/home/codex-anchor/.codex/` may contain ChatGPT authentication state. When file-based credential storage is used, `auth.json` is password-level sensitive data.
>
> Do not commit or share `auth.json`, ChatGPT tokens, API Keys, or other credentials in GitHub, Issues, chats, or public logs.

If authentication fails, do not temporarily place an API Key in `/etc/codex-window-anchor/anchor.conf`. Check OpenAI's current [Authentication documentation](https://developers.openai.com/codex/auth), then see this project's [Troubleshooting guide](TROUBLESHOOTING.md).

---

## 5. Configure your own Schedule

Codex Window Anchor has **no public default run time**. You choose:

- the timezone;
- how many times per day to run;
- each run time.

List installed timezones:

```bash
timedatectl list-timezones
```

Common IANA timezone forms:

```text
America/New_York
Europe/London
Asia/Shanghai
Etc/UTC
```

### Create a Schedule

One time:

```bash
codex-window-anchor-schedule \
  --timezone Etc/UTC \
  --time 09:30
```

Multiple times:

```bash
codex-window-anchor-schedule \
  --timezone Europe/London \
  --time 07:15 \
  --time 16:45
```

These are **format examples only**. They are not defaults, recommendations, or quota-optimization schedules.

The Schedule helper accepts:

```text
exactly one --timezone AREA/CITY
one or more --time HH:MM
```

Times use strict 24-hour format, for example:

```text
00:00
09:30
23:59
```

Run `codex-window-anchor-schedule` directly as a normal user. Do not manually prefix it with `sudo`. The helper parses and validates the arguments first, and only when it needs to write the systemd Timer does the installed root-owned helper re-execute through `/usr/bin/sudo`.

It does not modify `/etc/sudoers` and does not change the server's global timezone.

### After the Schedule helper finishes

On success, it explicitly reports:

```text
Timer state:
  disabled / inactive

No Anchor request was sent.
```

This means the Schedule **has been generated, but automatic operation has not started**.

> [!NOTE]
> The generated Timer uses `Persistent=false`. If the server is offline at a scheduled time, it does not catch up the missed Anchor later; it waits for the next normal Schedule.

---

## 6. Review the Schedule

After the Schedule helper succeeds, it should have reported:

```text
Timer state:
  disabled / inactive

No Anchor request was sent.
```

Review the generated Timer:

```bash
systemctl cat codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

If you want to explicitly confirm that the Timer has not started:

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
```

The expected state is still:

```text
disabled / inactive
```

This means the Schedule exists, but automatic Anchor operation has not begun.

---

## 7. Recommended: validate one Anchor before enabling the Timer

Before starting automatic scheduling, you can verify ChatGPT authentication, the Anchor runtime, and the systemd service with one manual Anchor:

```bash
sudo systemctl start codex-window-anchor.service
```

View logs:

```bash
sudo journalctl -u codex-window-anchor.service -n 50 --no-pager
```

Or:

```bash
sudo systemctl status codex-window-anchor.service --no-pager -l
```

> [!IMPORTANT]
> A manual run immediately sends **1 real Anchor request**.

`codex-window-anchor.service` is `Type=oneshot`. After a successful run completes and exits, seeing:

```text
inactive (dead)
```

is normal and does not mean the task failed.

If manual validation fails, do not enable the Timer. Go directly to [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## 8. Explicitly enable automatic scheduling

After both of the following are correct:

- the Schedule timezone and run times;
- the manual Anchor test, if you chose to run it;

explicitly enable the Timer:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

Verify:

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

The normal state is enabled / active, waiting for the next Schedule.

From this point onward, every matching Schedule trigger corresponds to one real Anchor request.

**Every Anchor is a real Codex request. The application-level input and output are intentionally tiny, and the overall task is designed to be as lightweight as possible, but actual token accounting can vary with the Codex CLI, model, and OpenAI-side context.**

---

## 9. Daily operations

Common commands:

| Operation | Command |
| --- | --- |
| View next run | `systemctl list-timers codex-window-anchor.timer --all --no-pager` |
| View Timer status | `systemctl status codex-window-anchor.timer --no-pager -l` |
| View recent Anchor logs | `sudo journalctl -u codex-window-anchor.service -n 50 --no-pager` |
| Pause automatic scheduling | `sudo systemctl disable --now codex-window-anchor.timer` |
| Resume automatic scheduling | `sudo systemctl enable --now codex-window-anchor.timer` |

Pausing does not remove the Anchor installation, generated Timer, `codex-anchor` user, or ChatGPT authentication state.

### Change the Schedule

The Schedule helper will not overwrite a Timer that is still enabled or active. Pause first:

```bash
sudo systemctl disable --now codex-window-anchor.timer
```

Configure the new Schedule:

```bash
codex-window-anchor-schedule \
  --timezone America/New_York \
  --time 08:30 \
  --time 17:00
```

Review again:

```bash
systemctl cat codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

The Timer should still be:

```text
disabled / inactive
```

After review, resume:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

The Schedule timezone belongs only to this Timer and does not modify the server's global timezone.

---

## 10. Update the Codex runtime

Anchor uses the runtime snapshot captured at installation:

```text
/usr/local/bin/codex-window-anchor
```

Updating another:

```text
codex
```

in the host user's PATH **does not automatically update the Anchor runtime**. This is intentional and prevents silent drift in an already validated runtime.

Public V1 does not include a background mechanism that automatically replaces the Anchor runtime.

To move Anchor to a newer official standalone Codex executable, use the reviewable reinstall path:

```bash
# 1. Pause automatic scheduling
sudo systemctl disable --now codex-window-anchor.timer

# 2. Default uninstall (preserves dedicated user / home / auth)
sudo ./scripts/uninstall.sh

# 3. Reinstall and let the Installer validate the new Codex runtime
sudo ./scripts/install.sh
```

The default uninstall removes the generated Timer, so after reinstall you must **create the Schedule again**:

```bash
codex-window-anchor-schedule \
  --timezone YOUR/ZONE \
  --time HH:MM
```

Then review and explicitly enable it again:

```bash
systemctl cat codex-window-anchor.timer
sudo systemctl enable --now codex-window-anchor.timer
```

The default uninstall preserves the safely verified `codex-anchor` identity/home/authentication state. The Installer can reuse it only when the exact username, UID, group, GID, home path, and ownership still match.

---

## 11. Uninstall

### Default uninstall

From the repository directory:

```bash
sudo ./scripts/uninstall.sh
```

The default uninstall removes only managed resources that can be safely confirmed as belonging to Codex Window Anchor, such as:

- the Anchor Timer;
- the Anchor service;
- runner;
- schedule helper;
- Anchor runtime snapshot;
- Anchor configuration;
- empty Anchor runtime directories.

The default uninstall **preserves**:

- the user's original official/global Codex CLI;
- the `codex-anchor` user;
- `/home/codex-anchor`;
- ChatGPT authentication state stored there;
- system journal history;
- firewall / proxy / SELinux state;
- swap / `/etc/fstab`;
- unrelated services/files.

The project also retains minimal verified identity metadata so a future reinstall can safely reuse the dedicated identity only when it still matches exactly.

### Remove the dedicated user and authentication state too

Only when you explicitly want to remove them:

```bash
sudo ./scripts/uninstall.sh --purge-user
```

This path requests interactive confirmation and removes the dedicated user/home, which may contain ChatGPT authentication state.

For an explicitly intended non-interactive purge:

```bash
sudo ./scripts/uninstall.sh --purge-user --yes
```

`--yes` may only be used together with `--purge-user`.

Purge validates the user/group/UID/GID/home identity first. If it cannot safely prove that the target is still the exact dedicated identity created by this project, it fails closed rather than blindly removing a same-named user or directory.

---

## 12. If installation stops partway through

The Installer tries to complete preflight checks before modifying the system. If mutation has already started and installation does not complete, it warns that a partial installation may remain and explicitly tells you not to manually enable the Timer.

If this metadata exists:

```text
/etc/codex-window-anchor/install.meta
```

do not begin by manually deleting scattered files and retrying.

Prefer:

```bash
sudo ./scripts/uninstall.sh
```

This lets the project use ownership metadata to remove resources it can safely identify as its own. Then run the Installer again.

If the Uninstaller refuses to continue because of ownership, identity, or systemd-state ambiguity, that is fail-closed behavior. Preserve the state and continue with:

[TROUBLESHOOTING.md](TROUBLESHOOTING.md)

---

## 13. Reference

### Important paths

| Purpose | Path |
| --- | --- |
| Anchor runtime | `/usr/local/bin/codex-window-anchor` |
| Schedule helper | `/usr/local/bin/codex-window-anchor-schedule` |
| Runner | `/usr/local/libexec/codex-window-anchor/run-anchor.sh` |
| Runtime config | `/etc/codex-window-anchor/anchor.conf` |
| Install metadata | `/etc/codex-window-anchor/install.meta` |
| Service | `/etc/systemd/system/codex-window-anchor.service` |
| Generated Timer | `/etc/systemd/system/codex-window-anchor.timer` |
| Dedicated home | `/home/codex-anchor` |
| Codex Home | `/home/codex-anchor/.codex` |
| Runtime state | `/var/lib/codex-window-anchor` |

### Normal state reference

| Stage | Timer |
| --- | --- |
| Immediately after Installer | Absent / not enabled / not running |
| Immediately after Schedule helper | `disabled / inactive` |
| After `enable --now` | enabled / active, waiting for next trigger |
| After `disable --now` | disabled / inactive |

### Security reminder

Before posting an Issue, log, or screenshot, confirm that it does not contain:

- `auth.json` contents;
- ChatGPT tokens;
- API Keys;
- SSH private keys;
- root/SSH passwords;
- VPS login credentials;
- private proxy credentials.

The Public V1 standard path does not require placing an API Key in the repository or Anchor configuration.

---

## Next

- [Troubleshooting](TROUBLESHOOTING.md)
- [How it works](HOW_IT_WORKS.md)
- [Security](../SECURITY.md)
- [Back to README](../README.md)

Codex Window Anchor is an independent project and is not an official OpenAI product. OpenAI may change the Codex CLI, models, authentication methods, plan limits, or Usage Window behavior. This project describes Usage Window behavior only as observed behavior and implementation experience.
