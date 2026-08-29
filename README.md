<p align="center">
  <img src="./assets/banner-reset.png" alt="Codex Window Anchor banner" width="100%">
</p>

<h1 align="center">Codex Window Anchor</h1>

<p align="center">
  <strong>English</strong> ·
  <a href="./README.zh-CN.md">简体中文</a> ·
  <a href="./README.ja.md">日本語</a>
</p>

**A self-hosted scheduled Anchor tool built around the official OpenAI Codex CLI. It runs a minimal real request at times you choose, based on observed Codex Usage Window behavior.**

Codex Window Anchor is intended for users who want this workflow to run reliably on a Linux server without introducing browser automation, API-key cron jobs, third-party keepalive services, a web dashboard, or a long-running daemon. It uses a dedicated non-root `codex-anchor` user, a systemd oneshot service, and a user-configured Timer. Installation does not automatically sign in to ChatGPT, create a schedule, or start sending requests.

> [!IMPORTANT]
> **Codex Window Anchor does not increase Codex quota, create additional allowance, bypass limits, force quota resets, or provide “unlimited Codex.”**
>
> References in this project to a Usage Window or usage-window anchoring describe observed behavior. They are not a permanent product guarantee from OpenAI about ChatGPT, Codex, models, quota, or Usage Window behavior.
>
> **Every Anchor is a real Codex request. The application-level input and output are intentionally tiny, and the overall task is designed to be as lightweight as possible, but actual token accounting can vary with the Codex CLI, model, and OpenAI-side context.**

**Navigation:** [Validated environment](#validated-environment-and-known-limitations) · [How it works](#how-it-works) · [Quick start](#quick-start) · [Daily operations](#daily-operations) · [Uninstall](#uninstall) · [Documentation](#documentation)

---

## Validated environment and known limitations

Public V1 has been validated both through real scheduled VPS operation and through a separate clean-environment integration test. The real deployment runs on **Vultr VPS — AlmaLinux 8.10 x86_64 / systemd 239** and has successfully completed actual systemd-scheduled Anchor runs. The release candidate was also validated in a clean **AlmaLinux 8.10 Minimal x86_64 / systemd 239 / SELinux Enforcing** environment across installation, schedule generation, Timer behavior, SELinux boundaries, and uninstall. Vultr is not a project dependency; it is simply one VPS environment in which real operation has been validated.

| Validation level | Environment | Result |
| --- | --- | --- |
| Real server operation | Vultr VPS · AlmaLinux 8.10 x86_64 · systemd 239 | Actual scheduled Anchor runs validated |
| Clean integration | AlmaLinux 8.10 Minimal x86_64 · systemd 239 · SELinux Enforcing | Install, configuration, Timer, security boundaries, and uninstall validated |

The fully validated Public V1 baseline remains **AlmaLinux 8.10 x86_64**. Other Linux distributions, systemd versions, and CPU architectures may work, but this project does not claim the same support level until they receive equivalent integration testing. V1 requires Linux, systemd, `sudo`/root access, network access to Codex, and a user-installed **official OpenAI standalone Linux Codex executable**. The Installer verifies that the selected runtime is a native Linux ELF and checks the Codex CLI options Anchor depends on, so an npm/node wrapper is not the current V1 Anchor runtime path.

ChatGPT Device Code availability depends on OpenAI's current authentication policy and the user's Workspace settings. The current default model is `gpt-5.6-luna`; model names and availability may change in the future. Schedules use an independent IANA timezone and do not change the Linux host's global timezone. Every configured run time results in one real Codex request.

If your environment is outside the validated baseline above, read the [detailed installation guide](docs/INSTALLATION.md) and [troubleshooting guide](docs/TROUBLESHOOTING.md) first.

---

## How it works

Codex Window Anchor is a small systemd scheduling wrapper, not a continuously running background Agent. After the user enables the Timer, systemd wakes a `Type=oneshot` service at the configured time. The service starts `run-anchor.sh` as the dedicated non-root `codex-anchor` user, which then invokes the root-owned Codex runtime snapshot stored at `/usr/local/bin/codex-window-anchor`. The Runner uses a dedicated `CODEX_HOME`, an explicit minimal environment, `--ephemeral`, and `--sandbox read-only`, while ignoring ordinary user Codex config and rules. It then sends a fixed minimal request instructing Codex to reply only with `OK`. When the request completes, the process exits; no Anchor daemon remains running.

```text
user-selected systemd timer
          ↓
codex-window-anchor.service
          ↓
      run-anchor.sh
          ↓
root-owned Codex runtime snapshot
          ↓
  codex-anchor (non-root)
          ↓
 one minimal real request
          ↓
          OK
          ↓
        exits
```

The Timer uses `Persistent=false`: if the server is offline at a scheduled time, systemd does not run the missed Anchor later when the server returns. When configuring a schedule, `codex-window-anchor-schedule` validates the IANA timezone and strict `HH:MM` time format, removes duplicates, sorts the times, and performs bounded self-elevation through `/usr/bin/sudo` only when it needs to write the systemd Timer. After generation, it verifies that the Timer remains `disabled / inactive`. Automatic operation starts only after the user explicitly runs `sudo systemctl enable --now codex-window-anchor.timer`.

The Installer only prepares the isolated runtime environment: it creates the `codex-anchor` user, builds a root-owned snapshot from an already installed official standalone Codex executable, and installs the runner, service, schedule helper, and configuration. It does not download Codex, sign in to ChatGPT, read or copy the user's `auth.json`, send an Anchor, create a public default schedule, or modify the firewall, proxy, swap, `/etc/fstab`, global system timezone, or SELinux policy.

Anchor uses the **runtime snapshot captured at installation time**. Updating another `codex` executable in the host user's PATH does not silently replace the Anchor runtime. This avoids runtime drift after the Anchor environment has already been validated. See [HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md) for the full architecture and security design.

---

## Quick start

The example below uses **AlmaLinux 8.10 x86_64**. Follow the commands in order to install the prerequisites, install Codex Window Anchor, authenticate the dedicated user, configure your own schedule, review it, optionally run one manual validation, and explicitly enable automatic scheduling. Codex Window Anchor does not download Codex, so the first step uses OpenAI's current standalone Mac/Linux installer.

```bash
# Install basic dependencies
sudo dnf install -y git curl tar

# Install the official OpenAI standalone Codex CLI
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex --version

# Clone and install Codex Window Anchor
git clone https://github.com/LHann79357/codex-window-anchor.git
cd codex-window-anchor
sudo ./scripts/install.sh

# Sign in to ChatGPT for the dedicated codex-anchor user
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login --device-auth

# Confirm authentication state
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status

# Set your own timezone and run time
# This is a neutral example, not a recommended or quota-optimization time
codex-window-anchor-schedule \
  --timezone Etc/UTC \
  --time 09:30

# Review the generated Timer
systemctl cat codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

During Device Code login, the terminal displays the OpenAI sign-in URL and a one-time code. Complete authorization in a browser using a ChatGPT account with Codex access. Official OpenAI references: [Codex GitHub](https://github.com/openai/codex) and [Codex Authentication](https://developers.openai.com/codex/auth).

> [!NOTE]
> Installation creates no public default schedule and starts no Timer. After `codex-window-anchor-schedule` generates the schedule, the Timer remains `disabled / inactive`; automatic scheduling does not begin until you explicitly confirm and enable it.

### Optional but recommended: validate one Anchor before enabling the Timer

If you want to verify ChatGPT authentication, the Anchor runtime, and the systemd service before starting automatic scheduling, run one manual Anchor:

```bash
sudo systemctl start codex-window-anchor.service
sudo journalctl -u codex-window-anchor.service -n 50 --no-pager
```

This immediately sends **1 real Anchor request**.

Because the service is `Type=oneshot`, seeing:

```text
inactive (dead)
```

after a successful run is normal and does not indicate failure.

After the manual validation succeeds and you have reviewed the Schedule, enable automatic scheduling:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

Confirm the Timer state:

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

If the machine contains multiple Codex executables, explicitly select the official standalone executable during installation:

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/codex
```

To install Anchor with another currently available model:

```bash
sudo ./scripts/install.sh --model MODEL
```

For pre-install checks, network-specific notes, runtime updates, and reinstall instructions, see [INSTALLATION.md](docs/INSTALLATION.md).

---

## Daily operations

The most common management commands are:

| Operation | Command |
| --- | --- |
| View Timer | `systemctl list-timers codex-window-anchor.timer` |
| View recent Anchor logs | `sudo journalctl -u codex-window-anchor.service -n 50 --no-pager` |
| Pause | `sudo systemctl disable --now codex-window-anchor.timer` |
| Resume | `sudo systemctl enable --now codex-window-anchor.timer` |

Pausing only stops automatic scheduling. It does not remove Anchor, the `codex-anchor` user, ChatGPT authentication state, or the generated Timer.

To change the schedule, pause the Timer first and then run the schedule helper again. The helper refuses to overwrite a Timer that is still enabled or active, so it does not silently change a live schedule:

```bash
sudo systemctl disable --now codex-window-anchor.timer

codex-window-anchor-schedule \
  --timezone YOUR/ZONE \
  --time HH:MM \
  --time HH:MM

systemctl cat codex-window-anchor.timer

sudo systemctl enable --now codex-window-anchor.timer
```

The Schedule timezone belongs only to this Timer and does not change the host's global timezone.

---

## Uninstall

Run the default uninstall from the repository directory:

```bash
sudo ./scripts/uninstall.sh
```

The default path removes only managed resources that can be safely identified as belonging to Codex Window Anchor, including the Timer, service, runner, schedule helper, Anchor runtime snapshot, and project configuration. It **preserves the user's original official/global Codex CLI, the dedicated `codex-anchor` user, `/home/codex-anchor`, and the ChatGPT authentication state stored there**. It also leaves system journal history, firewall, proxy, SELinux, swap, `/etc/fstab`, and unrelated services untouched.

If you explicitly want to remove the dedicated user, home, and authentication state as well:

```bash
sudo ./scripts/uninstall.sh --purge-user
```

This destructive path requires interactive confirmation by default. Use the non-interactive form only when you intentionally want a full purge:

```bash
sudo ./scripts/uninstall.sh --purge-user --yes
```

`--purge-user` is destructive. See [INSTALLATION.md](docs/INSTALLATION.md) and [SECURITY.md](SECURITY.md) for the exact default-uninstall and purge boundaries.

---

## Security and credentials

Anchor requests run as the dedicated non-root `codex-anchor` user. Project-managed runtime and configuration files are root-owned. Runtime execution uses a read-only sandbox, an ephemeral session, and an explicit minimal environment. The Public V1 standard path does not depend on an API Key and does not use an infinite retry loop. The goal is not to take over the server, but to keep the project's scope limited to its own identity, files, service, and Timer.

> [!WARNING]
> Codex login credentials may be stored under `/home/codex-anchor/.codex/`. When Codex uses file-based credential storage, `auth.json` is password-level sensitive data.
>
> **Do not commit or share `auth.json`, ChatGPT tokens, API Keys, SSH private keys, server passwords, or private proxy credentials in GitHub Issues, logs, screenshots, or chat.**

See [SECURITY.md](SECURITY.md) for the complete security boundary and vulnerability reporting policy.

---

## Documentation

The README keeps the common user path concise. More detailed documentation is split into:

**[Installation and configuration](docs/INSTALLATION.md)** · **[Troubleshooting](docs/TROUBLESHOOTING.md)** · **[How it works](docs/HOW_IT_WORKS.md)** · **[Security](SECURITY.md)**

All language versions keep the same commands, paths, flags, and security meaning.

---

## License

Codex Window Anchor is licensed under the [Apache License 2.0](LICENSE).

---

Codex Window Anchor is an independent open-source project and is not an official OpenAI product. References to Usage Window behavior describe observed behavior and implementation experience only; they should not be interpreted as an OpenAI guarantee about future ChatGPT plans, Codex models, usage limits, quota, authentication, or usage-window behavior.
