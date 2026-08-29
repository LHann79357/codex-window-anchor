**语言：** [English](../INSTALLATION.md) · **简体中文** · [日本語](../ja/INSTALLATION.md)

# Codex Window Anchor — 安装与配置

本文档提供 Codex Window Anchor Public V1 的完整安装和日常管理流程。目标是让用户先沿着一条明确的主路径完成部署，再在需要时查看高级安装选项、重装和卸载说明。

如果你只想快速了解项目，请先阅读 [README 中文版](../../README.zh-CN.md)。

> [!IMPORTANT]
> Codex Window Anchor 不负责下载 Codex，不会在安装过程中登录 ChatGPT、发送 Anchor、创建默认 Schedule 或启动 Timer。
>
> **真正开始自动调度，只发生在你显式执行：**
>
> ```bash
> sudo systemctl enable --now codex-window-anchor.timer
> ```

## 安装流程一览

```text
准备 Linux 环境
→ 安装 OpenAI 官方 Codex CLI
→ 安装 Codex Window Anchor
→ 为 codex-anchor 登录 ChatGPT
→ 设置自己的 timezone / times
→ Review Timer
→ （可选但推荐）手动验证一次 Anchor
→ 显式 enable
→ 验证 Timer
```

---

## 1. 准备环境

Public V1 的完整验证基线是 **AlmaLinux 8.10 x86_64 / systemd 239**。项目已经在真实 **Vultr VPS** 上完成自动 Timer 运行验证，并在独立的 **AlmaLinux 8.10 Minimal / systemd 239 / SELinux Enforcing** clean environment 中完成 Installer、Schedule、Timer、安全边界和 Uninstall 全链路验证。

| 项目 | Public V1 基线 |
| --- | --- |
| Linux | AlmaLinux 8.10 x86_64 |
| systemd | 239 |
| SELinux | Enforcing（clean integration validation） |
| Codex | OpenAI 官方 standalone Linux executable |
| Authentication | ChatGPT account |
| Anchor user | `codex-anchor` |
| 默认模型 | `gpt-5.6-luna` |

Vultr **不是项目依赖**，只是已完成真实运行验证的 VPS 环境之一。其它 Linux 发行版、systemd 版本和 CPU 架构可能可以运行，但在完成同等级集成验证前，Public V1 不对它们声明相同支持级别。

### 安装基础依赖

AlmaLinux 8.10：

```bash
sudo dnf install -y git curl tar
```

确认 systemd：

```bash
systemctl --version
```

你还需要：

- `sudo` 或 root 权限；
- 能访问 OpenAI Codex 的网络；
- 拥有 Codex 使用权限的 ChatGPT 账号。

如果你使用其它 Linux 发行版，请用对应的包管理器安装等价依赖。本文档不提供未经验证的发行版专用命令。

---

## 2. 安装 OpenAI 官方 Codex CLI

Codex Window Anchor **不会下载、打包或重新分发 Codex**。请先从 OpenAI 官方渠道安装 Codex CLI。

官方入口：

- [OpenAI Codex GitHub](https://github.com/openai/codex)
- [OpenAI Codex Authentication](https://developers.openai.com/codex/auth)

OpenAI 当前为 Mac/Linux 提供的 standalone installer：

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

安装完成后：

```bash
codex --version
command -v codex
```

两条命令都正常后，再继续安装 Anchor。

> [!NOTE]
> Codex Window Anchor Public V1 使用**原生 standalone Linux Codex executable** 作为 Anchor runtime。
>
> Installer 会对选中的 executable 建立独立的 root-owned snapshot，并验证它是原生 Linux ELF，同时检查 Anchor 需要使用的 Codex CLI options。当前 V1 不把 npm/node wrapper 作为 Anchor runtime。

---

## 3. 安装 Codex Window Anchor

克隆仓库：

```bash
git clone https://github.com/LHann79357/codex-window-anchor.git
cd codex-window-anchor
```

运行标准 Installer：

```bash
sudo ./scripts/install.sh
```

成功后，Installer 会显示 Anchor runtime、service user 和 configured model，并明确提示：

```text
No ChatGPT login was performed.
No Anchor request was sent.
No Anchor schedule was created.
No systemd timer is enabled or active.
```

### Installer 会安装什么

| 用途 | 路径 |
| --- | --- |
| Anchor Codex runtime | `/usr/local/bin/codex-window-anchor` |
| Schedule helper | `/usr/local/bin/codex-window-anchor-schedule` |
| Runner | `/usr/local/libexec/codex-window-anchor/run-anchor.sh` |
| Runtime config | `/etc/codex-window-anchor/anchor.conf` |
| Install metadata | `/etc/codex-window-anchor/install.meta` |
| systemd service | `/etc/systemd/system/codex-window-anchor.service` |
| Dedicated home | `/home/codex-anchor` |
| Runtime state | `/var/lib/codex-window-anchor/` |

Installer 会创建独立的非 root 用户：

```text
codex-anchor
```

并从你已经安装的 standalone Codex executable 建立 Anchor 自己的 root-owned runtime snapshot。更新宿主用户 PATH 中的另一份 `codex`，不会自动替换这份 snapshot。

<details>
<summary><strong>Installer 明确不会修改什么</strong></summary>

Installer 不会：

- 下载 Codex；
- 登录 ChatGPT；
- 读取或复制 `auth.json`；
- 发送 Anchor 请求；
- 创建公共默认 Schedule；
- 创建 live Timer；
- enable/start Timer；
- 修改系统全局 timezone；
- 修改 firewall；
- 修改 proxy；
- 修改 swap；
- 修改 `/etc/fstab`；
- disable SELinux；
- 使用 `chmod 777`；
- 修改 `/etc/sudoers`。

</details>

<details>
<summary><strong>高级安装选项：指定 Codex executable 或模型</strong></summary>

如果机器上有多份 Codex executable，可以明确指定已经确认来自 OpenAI 官方渠道的 standalone binary：

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/codex
```

Installer 默认首先尝试：

```bash
command -v codex
```

在 `sudo` 场景下，如果 PATH 没有发现 Codex，还会尝试调用者 Home 下的：

```text
~/.local/bin/codex
```

Installer 会验证 executable 的文件形式、运行能力和 Anchor 所需 CLI capabilities，但**不会自行建立 publisher provenance**。请只从 OpenAI 官方渠道取得 Codex。

默认模型：

```text
gpt-5.6-luna
```

如需显式指定其它当前可用模型：

```bash
sudo ./scripts/install.sh --model MODEL
```

查看完整 Installer 参数：

```bash
sudo ./scripts/install.sh --help
```

</details>

---

## 4. 为 `codex-anchor` 登录 ChatGPT

Anchor 使用独立的 Codex Home：

```text
/home/codex-anchor/.codex
```

因此它不会直接复用你日常 Linux 用户的 Codex Home。

远程/headless Linux 上执行：

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login --device-auth
```

根据终端显示的 OpenAI Device Code 登录流程，在浏览器中使用拥有 Codex 访问权限的 ChatGPT 账号完成授权。

然后检查登录状态：

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status
```

> [!WARNING]
> `/home/codex-anchor/.codex/` 可能包含 ChatGPT authentication state。使用 file-based credential storage 时，`auth.json` 属于密码级敏感凭据。
>
> 不要把 `auth.json`、ChatGPT token、API Key 或其它认证信息提交到 GitHub、Issue、聊天记录或公开日志中。

如果认证失败，请不要把 API Key 临时写入 `/etc/codex-window-anchor/anchor.conf`。先参考 OpenAI 当前 [Authentication 文档](https://developers.openai.com/codex/auth)，再查看本项目的 [Troubleshooting](TROUBLESHOOTING.md)。

---

## 5. 配置自己的 Schedule

Codex Window Anchor **没有公共默认运行时间**。用户自己决定：

- timezone；
- 每天运行几次；
- 每次运行时间。

查看系统已安装的 timezone：

```bash
timedatectl list-timezones
```

常见 IANA timezone 形式：

```text
America/New_York
Europe/London
Asia/Shanghai
Etc/UTC
```

### 创建 Schedule

单个时间：

```bash
codex-window-anchor-schedule \
  --timezone Etc/UTC \
  --time 09:30
```

多个时间：

```bash
codex-window-anchor-schedule \
  --timezone Europe/London \
  --time 07:15 \
  --time 16:45
```

这些只是**格式示例**，不是默认值、推荐值或 quota 优化策略。

Schedule helper 接受：

```text
exactly one --timezone AREA/CITY
one or more --time HH:MM
```

时间使用严格的 24 小时格式，例如：

```text
00:00
09:30
23:59
```

普通用户直接运行 `codex-window-anchor-schedule` 即可，不需要手动在命令前添加 `sudo`。helper 会先解析和验证参数，只在确实需要写入 systemd Timer 时，通过已安装的 root-owned helper 使用 `/usr/bin/sudo` 重新执行。

它不会修改 `/etc/sudoers`，也不会改变服务器的全局 timezone。

### Schedule helper 完成后

成功时会明确显示：

```text
Timer state:
  disabled / inactive

No Anchor request was sent.
```

这意味着 Schedule **已经生成，但还没有开始自动运行**。

> [!NOTE]
> 生成的 Timer 使用 `Persistent=false`。如果服务器在某个计划时间离线，之后恢复时不会补跑错过的 Anchor，而是等待下一个正常 Schedule。

---

## 6. Review Schedule

Schedule helper 成功结束后应该明确显示：

```text
Timer state:
  disabled / inactive

No Anchor request was sent.
```

先检查生成的 Timer：

```bash
systemctl cat codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

如果希望再次确认 Timer 还没有开始运行：

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
```

此时正常状态仍然应该是：

```text
disabled / inactive
```

这表示 Schedule 已经生成，但自动 Anchor 尚未开始。

---

## 7. 推荐：启用前手动验证一次

如果你希望在正式开启自动调度前，先确认 ChatGPT authentication、Anchor runtime 和 systemd service 都正常，可以执行一次手动 Anchor：

```bash
sudo systemctl start codex-window-anchor.service
```

查看日志：

```bash
sudo journalctl -u codex-window-anchor.service -n 50 --no-pager
```

或者：

```bash
sudo systemctl status codex-window-anchor.service --no-pager -l
```

> [!IMPORTANT]
> 手动运行会立即发送 **1 次真实 Anchor 请求**。

`codex-window-anchor.service` 是 `Type=oneshot`。成功执行并退出后显示：

```text
inactive (dead)
```

属于正常状态，不代表运行失败。

如果手动验证失败，先不要启用 Timer，直接查看 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。

---

## 8. 显式启用自动调度

当下面两项都已经确认无误：

- Schedule 中的 timezone 和运行时间正确；
- 如果进行了手动 Anchor 验证，测试运行正常；

再显式启用 Timer：

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

验证：

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

正常情况下，Timer 应处于 enabled / active 状态，并等待下一次 Schedule。

从这一刻开始，每个符合 Schedule 的触发都会对应一次真实 Anchor 请求。

**每次 Anchor 都是真实 Codex 请求；业务输入和输出极小，整体任务被设计为尽可能轻量，但实际 token 计量会随 Codex CLI、模型和 OpenAI 侧上下文变化。**

---

## 9. 日常操作

常用命令集中如下：

| 操作 | 命令 |
| --- | --- |
| 查看下一次运行 | `systemctl list-timers codex-window-anchor.timer --all --no-pager` |
| 查看 Timer 状态 | `systemctl status codex-window-anchor.timer --no-pager -l` |
| 查看最近 Anchor 日志 | `sudo journalctl -u codex-window-anchor.service -n 50 --no-pager` |
| 暂停自动运行 | `sudo systemctl disable --now codex-window-anchor.timer` |
| 恢复自动运行 | `sudo systemctl enable --now codex-window-anchor.timer` |

暂停不会删除 Anchor 安装、generated Timer、`codex-anchor` 用户或 ChatGPT authentication state。

### 修改 Schedule

Schedule helper 不会覆盖一个仍然 enabled 或 active 的 Timer。先暂停：

```bash
sudo systemctl disable --now codex-window-anchor.timer
```

重新配置：

```bash
codex-window-anchor-schedule \
  --timezone America/New_York \
  --time 08:30 \
  --time 17:00
```

再次 Review：

```bash
systemctl cat codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

此时 Timer 仍应是：

```text
disabled / inactive
```

确认后恢复：

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

Schedule timezone 只属于这个 Timer，不会修改服务器 global timezone。

---

## 10. 更新 Codex runtime

Anchor 使用安装时保存的 runtime snapshot：

```text
/usr/local/bin/codex-window-anchor
```

以后更新普通用户 PATH 中的：

```text
codex
```

**不会自动更新 Anchor runtime**。这是有意设计的行为，用于避免已经验证过的 runtime silent drift。

Public V1 不提供后台自动替换 Anchor runtime 的机制。

如果需要让 Anchor 使用新的官方 standalone Codex executable，推荐使用可审查的重装路径：

```bash
# 1. 暂停
sudo systemctl disable --now codex-window-anchor.timer

# 2. 默认卸载（保留 dedicated user / home / auth）
sudo ./scripts/uninstall.sh

# 3. 重新安装，并让 Installer 验证新的 Codex runtime
sudo ./scripts/install.sh
```

默认卸载会删除旧的 generated Timer，因此重装后需要**重新创建 Schedule**：

```bash
codex-window-anchor-schedule \
  --timezone YOUR/ZONE \
  --time HH:MM
```

然后 Review，并再次显式启用：

```bash
systemctl cat codex-window-anchor.timer
sudo systemctl enable --now codex-window-anchor.timer
```

默认卸载会保留能够安全验证的 `codex-anchor` identity/home/authentication state，因此在 exact username、UID、group、GID、home path 和 ownership 仍然匹配时，Installer 可以安全复用它。

---

## 11. 卸载

### 默认卸载

在仓库目录执行：

```bash
sudo ./scripts/uninstall.sh
```

默认卸载只删除能够安全确认属于 Codex Window Anchor 的 managed resources，例如：

- Anchor Timer；
- Anchor service；
- runner；
- schedule helper；
- Anchor runtime snapshot；
- Anchor configuration；
- 空的 Anchor runtime directories。

默认卸载**保留**：

- 用户原本的官方/global Codex CLI；
- `codex-anchor` user；
- `/home/codex-anchor`；
- 其中的 ChatGPT authentication state；
- system journal history；
- firewall / proxy / SELinux；
- swap / `/etc/fstab`；
- unrelated services/files。

项目还会保留最小 verified identity metadata，以便未来 reinstall 只在 dedicated identity 仍然精确匹配时进行安全复用。

### 连 dedicated user 和认证一起删除

只有明确需要时：

```bash
sudo ./scripts/uninstall.sh --purge-user
```

该路径会要求交互确认，并删除 dedicated user/home，其中可能包含 ChatGPT authentication state。

明确需要非交互 purge 时：

```bash
sudo ./scripts/uninstall.sh --purge-user --yes
```

`--yes` 只能与 `--purge-user` 一起使用。

Purge 会先验证 user/group/UID/GID/home identity；如果无法安全确认目标仍是本项目创建的 dedicated identity，会 fail closed，而不是盲目删除同名用户或目录。

---

## 12. 如果安装中途失败

Installer 会尽量在修改系统前完成 preflight checks。如果 mutation 已经开始但安装没有完成，它会提示 partial installation 可能仍然存在，并明确要求不要手动 enable Timer。

如果下面的 metadata 存在：

```text
/etc/codex-window-anchor/install.meta
```

不要先手工删除零散文件再重装。

优先执行：

```bash
sudo ./scripts/uninstall.sh
```

让项目根据 ownership metadata 清理由它能够安全确认的资源，再重新运行 Installer。

如果 uninstaller 因 ownership、identity 或 systemd state ambiguity 拒绝继续，这是 fail-closed 安全行为。请保留现场，并根据：

[TROUBLESHOOTING.md](TROUBLESHOOTING.md)

继续排查。

---

## 13. Reference

### 重要路径

| 用途 | 路径 |
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

### 正常状态速查

| 阶段 | Timer |
| --- | --- |
| Installer 刚完成 | 不存在 / 未启用 / 未运行 |
| Schedule helper 刚完成 | `disabled / inactive` |
| `enable --now` 后 | enabled / active，等待下一次触发 |
| `disable --now` 后 | disabled / inactive |

### 安全提醒

公开 Issue、日志或截图前，确认没有包含：

- `auth.json` 内容；
- ChatGPT token；
- API Key；
- SSH private key；
- root/SSH 密码；
- VPS 登录凭据；
- 私有 proxy credentials。

Public V1 的标准路径不要求把 API Key 写入仓库或 Anchor 配置。

---

## 下一步

- [故障排查](TROUBLESHOOTING.md)
- [工作原理](HOW_IT_WORKS.md)
- [安全说明](../../SECURITY.zh-CN.md)
- [返回 README](../../README.zh-CN.md)

Codex Window Anchor 是独立项目，不是 OpenAI 官方产品。OpenAI 可能调整 Codex CLI、模型、认证方式、计划限制和 Usage Window 行为；项目对 Usage Window 的描述仅代表观察到的行为和实现经验。
