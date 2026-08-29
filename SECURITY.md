# Codex Window Anchor — Security Policy

Codex Window Anchor is a lightweight systemd scheduling layer that runs the official OpenAI Codex CLI on a user's own Linux host. The project touches local system privileges, ChatGPT authentication state, systemd service/timer configuration, and real Codex requests, so security vulnerabilities should be reported through a **private channel**, not a public Issue.

> [!IMPORTANT]
> **If you believe you have found a security vulnerability, do not disclose exploitable details, authentication files, tokens, server credentials, or a complete PoC in a public GitHub Issue, Discussion, Pull Request, screenshot, or log.**
>
> After the repository is switched to Public, **GitHub Private Vulnerability Reporting** should be enabled before the formal `v1.0.0` release and before public promotion, and it should serve as this project's official private vulnerability reporting channel.

---

## Supported versions

Codex Window Anchor security fixes primarily target the **latest stable release**.

| Version | Security support |
| --- | --- |
| Latest stable `v1.x` release | Supported |
| Earlier `v1.x` releases | No guarantee of separate maintenance; upgrade to the latest stable release |
| Pre-release / development snapshot | Not treated as a stable security-supported release |
| Unreleased local modifications | Outside formal support scope |

Before the first stable `v1.0.0` release, repository pre-release content should not be interpreted as already having a stable-version security maintenance commitment.

If a vulnerability affects an older version but has already been fixed in the latest stable version, maintainers may require an upgrade rather than backporting the fix to every older release.

---

## Reporting a security vulnerability

### Recommended channel: GitHub Private Vulnerability Reporting

After the GitHub repository is switched to Public, enable **Private Vulnerability Reporting** in Repository Settings and confirm that the private reporting entry point works before releasing `v1.0.0`.

Once enabled, open the repository's current **Security / Security and quality** area and choose:

```text
Report a vulnerability
```

to submit the report privately.

GitHub recommends using `SECURITY.md` to document supported versions and private reporting methods, and Private Vulnerability Reporting provides a repository-level private channel.

### Do not report vulnerabilities through public channels

Do not use:

- Public Issues;
- Discussions;
- Pull Requests;
- README comments;
- public social media;
- screenshots or log links that contain sensitive data.

If Private Vulnerability Reporting is not yet enabled, **do not publish vulnerability details**. The repository may need to complete the Private → Public transition first, but the private vulnerability channel should be configured before the formal `v1.0.0` release, public promotion, or inviting ordinary users to rely on the project.

### What to include in a report

To help determine whether a problem belongs to this project, include as much of the following as possible:

- affected Codex Window Anchor version;
- Linux distribution / version;
- CPU architecture;
- systemd version;
- Codex CLI version;
- whether the problem is in Installer / login / runtime / Schedule / Timer / Uninstall;
- full error output with secrets removed;
- minimal reproduction steps;
- expected behavior and actual behavior;
- the security impact you believe is possible;
- PoC details, if any, only through the private reporting channel.

Do not access accounts, hosts, tokens, or data that do not belong to you in order to demonstrate a vulnerability.

---

## Security scope

### Examples that are generally in scope

If reproducible in a supported version, issues like these usually fall within Codex Window Anchor's security scope:

- the Installer takes over a user/group/path/service that does not belong to the project;
- the Schedule helper can obtain unintended root privileges through an untrusted script or argument path;
- the systemd service runs Codex as root or as the wrong identity;
- the Anchor runtime can be unexpectedly replaced or tampered with by an ordinary user and still be accepted;
- ownership / metadata / SHA-256 checks can be bypassed, causing unrelated system resources to be removed;
- default uninstall removes the dedicated home or ChatGPT authentication state without explicit `--purge-user`;
- `--purge-user` can delete a same-named user that does not match installation metadata;
- project scripts write ChatGPT credentials, tokens, or other secrets into repository-managed public files;
- the Runner unexpectedly inherits an API Key, access token, provider endpoint, or other sensitive runtime input that should have been excluded;
- path traversal, symlink, alias/drop-in, or race-condition behavior causes the project to modify files or systemd namespace it does not own;
- project-generated logs or output unintentionally expose authentication secrets;
- Installer / Uninstaller fail-closed boundaries can be bypassed to gain privileges or perform destructive deletion.

This list is not exhaustive. The core question is:

> **Does the issue violate a privilege, identity, credential, ownership, or resource boundary that Codex Window Anchor itself claims to enforce?**

### Cases that are generally not project vulnerabilities

These issues generally belong to an upstream provider or host administrator rather than to Anchor itself:

- OpenAI / ChatGPT / Codex server-side vulnerabilities;
- OpenAI account compromise;
- an upstream Codex CLI vulnerability unrelated to Anchor glue code;
- OpenAI changes to models, Usage Window behavior, quota, authentication, or plan behavior;
- a user intentionally publishing `auth.json`, tokens, SSH keys, or passwords;
- a host that was already root-compromised before Anchor was installed;
- a user intentionally disabling SELinux, running `chmod 777`, or modifying project root-owned files and thereby invalidating the expected boundary;
- firewall, VPN, proxy, DNS, enterprise TLS, or general host network configuration issues;
- compatibility differences on unsupported Linux distributions;
- unexpected behavior after a user manually edits a systemd unit / Timer / metadata;
- product-behavior complaints such as “Anchor did not increase quota” or “Anchor did not reset allowance.”

If an upstream Codex CLI vulnerability creates a **new exploitable impact specifically because of Anchor's invocation pattern**, it is reasonable to report it privately to this project first and explain how Anchor changes or amplifies the risk.

---

## Credentials and authentication state

The Public V1 standard path uses ChatGPT account authentication and does not require placing an API Key in Anchor configuration.

Dedicated Codex Home:

```text
/home/codex-anchor/.codex
```

OpenAI's current Codex documentation states that sign-in state may be stored in an OS credential store or, when file-based credential storage is used, as:

```text
~/.codex/auth.json
```

When file-based storage is used, `auth.json` contains access tokens and should be protected **like a password**.

Therefore:

- do not commit `auth.json`;
- do not paste it into a GitHub Issue;
- do not upload it to a Discussion;
- do not put it in chat history;
- do not copy its contents into `anchor.conf`;
- do not attach it publicly as “diagnostic data.”

The project's `.gitignore` should continue to ignore `.codex/`, `auth.json`, credentials, tokens, secrets, and common SSH private-key patterns.

### Device Code Login

The standard remote/headless Linux documentation path uses:

```bash
codex login --device-auth
```

OpenAI's current documentation describes Device Code Authentication as a remote/headless authentication path. Availability can depend on personal ChatGPT security settings or Workspace permissions.

The Device Code itself should not be posted in a public Issue or screenshot.

---

## Runtime security boundary

Anchor does not continuously reference a potentially changing `codex` executable in the host user's PATH.

The Installer creates:

```text
/usr/local/bin/codex-window-anchor
```

from the standalone Codex executable already installed by the user, and validates the snapshot. Public V1 currently checks:

- regular file;
- executable;
- native Linux ELF;
- non-privileged `--version` execution;
- the `codex exec` options Anchor requires;
- root ownership;
- SHA-256 fingerprint;
- systemd execution probe.

The Installer explicitly states that it validates the runtime's **form and capability** but does not independently establish publisher provenance.

Users must therefore still obtain Codex from an official OpenAI source. `--codex-bin` should not be interpreted as “any executable is safe.”

---

## Privilege boundary

### The Anchor request itself does not run as root

The systemd service uses:

```text
User=codex-anchor
Group=codex-anchor
```

and includes:

```text
NoNewPrivileges=true
PrivateTmp=true
UMask=0077
```

The real Codex request runs as the dedicated non-root identity.

Root is used only where system-level privileges are actually required, for example:

- installing root-owned runtime / runner / unit files;
- writing under `/etc/systemd/system`;
- enabling/disabling the system Timer;
- verified uninstall / purge.

### Bounded self-elevation in the Schedule helper

The public command:

```text
/usr/local/bin/codex-window-anchor-schedule
```

can be run directly by a normal user.

When a systemd Timer update requires root, the helper first verifies that it resolved to the expected formal helper, that the file is root-owned, mode `755`, and carries the project ownership marker. Only then does it re-execute the original arguments through:

```text
/usr/bin/sudo
```

It does not:

- create sudoers rules;
- modify `/etc/sudoers`;
- modify PATH;
- expose a general privilege-escalation entry point to arbitrary repository scripts.

If the helper cannot verify its formal installation path or ownership, it refuses to elevate.

---

## Runtime environment boundary

`run-anchor.sh` uses:

```text
/usr/bin/env -i
```

to build an explicit environment instead of inheriting the full systemd manager environment.

Public V1 does not allow ordinary environment values such as these to automatically enter the Anchor runtime:

```text
OPENAI_API_KEY
CODEX_API_KEY
CODEX_ACCESS_TOKEN
OPENAI_BASE_URL
OPENAI_FEDERATION_RULE_ID
OPENAI_IDENTITY_TOKEN_FILE
```

along with other variables not present in the allowlist.

The Runner rebuilds basic runtime identity/path/state variables and permits common network / CA variables such as:

```text
HTTP_PROXY
HTTPS_PROXY
ALL_PROXY
NO_PROXY
CODEX_CA_CERTIFICATE
SSL_CERT_FILE
SSL_CERT_DIR
CURL_CA_BUNDLE
REQUESTS_CA_BUNDLE
```

Allowing existing proxy / CA environment into the runtime does not mean Anchor configures or trusts an arbitrary proxy. Network endpoints and host proxy policy remain the administrator's responsibility.

---

## Codex execution boundary

Every Public V1 Anchor uses:

```text
--ephemeral
--ignore-user-config
--ignore-rules
--skip-git-repo-check
--sandbox read-only
```

and a fixed minimal prompt that instructs Codex to reply only with `OK` and not inspect files, run commands, browse the web, or use tools.

This reduces Anchor's own task surface, but it should not be described as an absolute sandbox guarantee. The Codex CLI, operating system, systemd, and OpenAI service remain separate trust boundaries.

**Every Anchor is a real Codex request. The application-level input and output are intentionally tiny, and the overall task is designed to be as lightweight as possible, but actual token accounting can vary with the Codex CLI, model, and OpenAI-side context.**

---

## systemd and Schedule boundary

Immediately after Installer completion:

```text
no ChatGPT login
no Anchor request
no generated Timer
no enabled / active Timer
```

Immediately after Schedule helper completion:

```text
generated Timer
disabled / inactive
no Anchor request
```

Automatic scheduling begins only after the user explicitly runs:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

The Schedule timezone is written into the Timer's `OnCalendar=` and does not modify the system global timezone.

The Timer uses:

```text
Persistent=false
```

so Anchors missed while the server is offline are not automatically caught up later.

---

## Installer host boundary

Public V1 Installer explicitly does not automatically modify:

- firewall;
- proxy;
- VPN;
- swap;
- `/etc/fstab`;
- host global timezone;
- SELinux enforcement;
- unrelated services;
- `/etc/sudoers`.

It does not use:

```text
chmod 777
setenforce 0
```

as compatibility fixes.

The full clean-integration validation uses **SELinux Enforcing**.

---

## Safe uninstall

Default:

```bash
sudo ./scripts/uninstall.sh
```

does not mean “delete every same-named file.”

The Uninstaller relies on:

- installation metadata;
- ownership marker;
- file ownership/mode;
- runtime SHA-256;
- user/group;
- UID/GID;
- home path / ownership;
- exact systemd state.

Only managed resources that can be positively identified as belonging to this project are removed.

Default uninstall preserves:

```text
codex-anchor user
/home/codex-anchor
ChatGPT authentication state
the user's original official/global Codex CLI
system journal history
firewall / proxy / SELinux
swap / /etc/fstab
unrelated files/services
```

If ownership, identity, runtime fingerprint, or systemd state is ambiguous, the script may preserve resources and fail closed.

### `--purge-user`

Only:

```bash
sudo ./scripts/uninstall.sh --purge-user
```

enters the destructive cleanup path for the dedicated user/home/authentication state.

Purge re-validates identity evidence and requests interactive confirmation by default. If it cannot prove that the target is still the exact identity created by the project, it should refuse deletion rather than running `userdel -r` merely because the username matches.

---

## Secrets must not appear in these places

Do not write or commit secrets into:

```text
README / docs
anchor.conf
schedule.example
systemd unit
Git commit
GitHub Issue
GitHub Discussion
Pull Request
public journal paste
screenshots
```

In particular, check for:

- `auth.json`;
- ChatGPT access / refresh tokens;
- API Keys;
- SSH private keys;
- VPS root password;
- private proxy subscriptions;
- proxy credentials;
- unrelated X-ray/VPN/service credentials;
- local `.env`;
- secrets accidentally exposed in shell history.

Review logs manually before publishing them.

---

## Usage Window / quota is not a security guarantee

Codex Window Anchor does not create, increase, reset, or bypass OpenAI usage limits.

This project may describe Usage Window behavior only as:

```text
observed behavior
observed usage-window anchoring
```

not as:

```text
OpenAI guaranteed reset
quota multiplier
extra allowance
limit bypass
unlimited Codex
```

OpenAI can change models, plans, authentication, limits, and Usage Window behavior. Those product changes are not Codex Window Anchor security vulnerabilities.

---

## Responsible disclosure

If you privately report a reproducible vulnerability, give maintainers reasonable time to:

```text
triage
→ reproduce
→ assess scope
→ prepare fix
→ release
→ disclosure
```

before publishing full exploitation details.

Public V1 **does not promise a fixed 24/48/72-hour response SLA and has no declared bug bounty program**. Until such an SLA or bounty is actually established, this documentation should not imply one.

Security fixes and necessary public disclosure can be handled through GitHub Security Advisory / Release Notes as appropriate to the vulnerability.

---

## Related documentation

- [Installation and configuration](docs/INSTALLATION.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [How it works](docs/HOW_IT_WORKS.md)
- [Back to README](README.md)

Codex Window Anchor is an independent project and is not an official OpenAI product.
