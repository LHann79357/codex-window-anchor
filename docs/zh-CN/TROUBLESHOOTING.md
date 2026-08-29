# Codex Window Anchor — 故障排查

本文档用于排查 Codex Window Anchor Public V1 的安装、ChatGPT 登录、手动 Anchor、Schedule、systemd Timer 和卸载问题。

如果你还没有完成标准安装，请先按照 [INSTALLATION.md](INSTALLATION.md) 操作。这里不重复完整部署流程，只处理“某一步没有按预期工作”的情况。

> [!IMPORTANT]
> 排查故障时不要为了“先跑起来”而关闭 SELinux、使用 `chmod 777`、删除不明 systemd 文件、手工修改 `auth.json`，或者把 API Key 写入 Anchor 配置。
>
> Public V1 的 Installer / Schedule / Uninstall 都采用 fail-closed 设计：当脚本无法安全确认文件、用户、runtime 或 systemd 状态属于本项目时，**拒绝继续通常是安全保护，不是要求你强制绕过检查。**

## 先从这里开始

大多数问题可以先用下面几条命令定位到“Codex 本身、认证、Anchor service 还是 Timer”中的某一层：

```bash
# 系统
uname -a
systemctl --version

# 宿主机上的官方 Codex
command -v codex
codex --version

# Anchor 认证状态
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status

# Anchor service
sudo systemctl status codex-window-anchor.service --no-pager -l
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager

# Timer（仅在已经配置 Schedule 后）
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer --all --no-pager
systemctl cat codex-window-anchor.timer
```

先保留**完整错误原文**。如果错误发生在 OpenAI 登录或请求阶段，同时检查 [OpenAI Status](https://status.openai.com/)；Codex 本身的认证、访问或服务异常并不一定来自 Anchor。OpenAI 的状态页会单独显示 Codex 组件状态。

---

## 常见问题

| 症状 | 优先检查 |
| --- | --- |
| Codex 官方安装器提示 `tar is required` | [缺少 `tar`](#官方-codex-安装器提示-tar-is-required) |
| Anchor Installer 找不到 Codex | [Codex CLI not found](#installer-提示-codex-cli-was-not-found) |
| Installer 说 Codex 不是 native ELF / 缺少 required option | [Codex runtime 不符合 V1 要求](#installer-拒绝所选-codex-runtime) |
| Device Code 登录失败 | [ChatGPT / Device Code 登录](#device-code-登录失败) |
| `systemctl start` 失败 | [手动 Anchor 失败](#手动-anchor-运行失败) |
| service 显示 `inactive (dead)` | [这是正常的吗？](#service-显示-inactive-dead) |
| Installer 提示 systemd 无法执行 Codex | [SELinux / systemd execution](#systemd-无法执行-anchor-runtime) |
| Schedule helper 提示 Timer enabled/active | [先暂停 Timer](#schedule-helper-拒绝修改正在运行的-timer) |
| timezone / time 参数被拒绝 | [Schedule 参数](#timezone-或-time-参数被拒绝) |
| Timer 已生成但没有自动运行 | [Timer 没有触发](#timer-没有按预期运行) |
| 服务器离线后没有补跑 | [这是设计行为](#错过的-anchor-没有补跑) |
| 卸载器拒绝删除某些内容 | [Safe uninstall](#uninstaller-拒绝继续或保留了资源) |
| 安装中断后无法重装 | [Partial installation](#安装中途失败后无法直接重装) |
| 受限网络 / 代理环境下失败 | [Network / proxy](#网络或代理环境导致-codex-不可访问) |

---

## 官方 Codex 安装器提示 `tar is required`

### 症状

安装 OpenAI 官方 standalone Codex CLI 时出现类似：

```text
tar is required to install Codex.
```

### 原因

AlmaLinux Minimal 等精简系统可能默认没有安装 `tar`。这是 Codex standalone installer 的前置依赖问题，不是 Anchor Installer 故障。

### 解决

AlmaLinux 8.10：

```bash
sudo dnf install -y git curl tar
```

然后重新执行 OpenAI 官方 Codex installer：

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

最后确认：

```bash
codex --version
command -v codex
```

只有宿主用户能够正常执行官方 standalone Codex 后，再运行：

```bash
sudo ./scripts/install.sh
```

---

## Installer 提示 `Codex CLI was not found`

### 症状

Anchor Installer 报错：

```text
Codex CLI was not found. Install the official standalone Codex CLI first, or use --codex-bin PATH
```

### 先检查

```bash
command -v codex
codex --version
```

如果这里已经失败，先修复官方 Codex 安装，不要继续排查 Anchor。

如果 Codex 确实存在，但不在 Installer 能安全发现的位置：

```bash
readlink -f "$(command -v codex)"
```

然后显式指定**官方 standalone executable 的绝对路径**：

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/codex
```

Installer 默认会检查当前 `PATH` 中的 `codex`；在 `sudo` 场景下，如果没有发现，还会尝试调用者 Home 下的：

```text
~/.local/bin/codex
```

> [!IMPORTANT]
> `--codex-bin` 不是让你绕过 Codex 来源检查的“任意 binary”入口。
>
> Installer 会验证文件形式和 CLI capabilities，但不会替用户证明 publisher provenance。请只选择你从 OpenAI 官方渠道安装的 standalone Codex executable。

---

## Installer 拒绝所选 Codex runtime

### 可能的错误

例如：

```text
staged Codex snapshot is not a native Linux ELF executable
```

或：

```text
staged Codex CLI does not support required option: ...
```

### 含义

Public V1 不是对所有形式的 `codex` wrapper 做兼容适配。Installer 会建立 root-owned runtime snapshot，并要求它：

- 是 regular executable file；
- 是 native Linux ELF；
- 能以非特权用户执行 `--version`；
- 支持 Anchor 当前使用的 `exec` options。

因此 npm/node wrapper、错误架构的 executable、过旧/不兼容 CLI 或其它同名程序都可能被拒绝。

### 处理

重新确认：

```bash
command -v codex
codex --version
file "$(command -v codex)"
```

然后从 OpenAI 官方渠道重新安装当前 standalone Codex CLI。不要修改 Installer 去跳过 ELF 或 required-option checks。

如果系统上有多份 Codex，明确选择正确版本：

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/official/codex
```

---

## Device Code 登录失败

Public V1 在远程/headless Linux 上使用：

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login --device-auth
```

OpenAI 当前官方认证文档明确把 Device Code Authentication 用于远程/headless 环境，同时要求个人账号或 Workspace 管理员允许 device-code login。OpenAI 也说明直接 `codex login` 会生成专门的登录诊断日志，并且 file-based `auth.json` 应按密码保护。

### 先确认

1. ChatGPT 账号本身具有 Codex 访问权限。
2. Device Code Login 在个人安全设置或 Workspace permissions 中允许使用。
3. 服务器能够访问 OpenAI/Codex。
4. OpenAI 当前没有 Codex authentication incident。

OpenAI 官方入口：

- [Codex Authentication](https://developers.openai.com/codex/auth)
- [OpenAI Status](https://status.openai.com/)

完成后重新检查：

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status
```

> [!WARNING]
> 不要把登录日志中的 token、`auth.json` 内容或 Device Code 发布到 Issue。
>
> OpenAI 官方文档提供其它 headless fallback 方法，但这些方法涉及复制认证缓存或 SSH callback forwarding。它们不属于 Codex Window Anchor 的标准安装主路径；如确实需要，请直接按照 OpenAI 当前官方 Authentication 文档操作，不要使用第三方教程中的未知凭据处理方式。

---

## 手动 Anchor 运行失败

手动验证：

```bash
sudo systemctl start codex-window-anchor.service
```

如果命令返回失败，不要立即启用 Timer。

先查看：

```bash
sudo systemctl status codex-window-anchor.service --no-pager -l
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

然后按下面顺序判断。

### 1. 认证是否存在

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status
```

如果认证无效，先重新完成 Device Code Login。

### 2. Anchor 配置是否存在

```bash
sudo cat /etc/codex-window-anchor/anchor.conf
```

正常情况下应至少包含类似：

```text
CODEX_BIN=/usr/local/bin/codex-window-anchor
CODEX_MODEL=...
```

这个文件是**非 secret runtime config**。不要往里面加入 API Key 或 ChatGPT token。

### 3. runtime 是否存在

```bash
ls -l /usr/local/bin/codex-window-anchor
/usr/local/bin/codex-window-anchor --version
```

如果 runtime 不存在或已经被外部修改，不建议手工重新复制 binary。按照 [INSTALLATION.md](INSTALLATION.md) 的 runtime 更新/重装流程恢复可验证状态。

### 4. 是否为 OpenAI 侧错误

如果 journal 显示 authentication、capacity、service unavailable 或其它远端错误，同时检查：

[OpenAI Status](https://status.openai.com/)

OpenAI 历史上确实发生过 Codex authentication、访问和模型容量类 incident，因此远端错误不能自动归因于 Anchor。

---

## Service 显示 `inactive (dead)`

这通常**不是故障**。

`codex-window-anchor.service` 是：

```text
Type=oneshot
```

一次 Anchor 完成后，进程退出，service 回到：

```text
inactive (dead)
```

属于正常生命周期。

不要以“它没有长期显示 active (running)”作为失败依据。

检查最近一次运行：

```bash
sudo journalctl -u codex-window-anchor.service -n 50 --no-pager
```

或：

```bash
sudo systemctl status codex-window-anchor.service --no-pager -l
```

应关注本次 invocation 是否成功退出，以及 journal 是否记录了真实错误。

---

## systemd 无法执行 Anchor runtime

### 典型 Installer 错误

```text
systemd could not execute the Codex runtime; inspect the system journal and SELinux audit log
```

### 为什么会出现

项目在真实 AlmaLinux/RHEL-family 环境中曾遇到过一种情况：Codex executable 在用户 Home 下可以交互执行，但 systemd/SELinux 不允许同样的执行路径。

Public V1 因此不直接从用户 Home 运行 Codex，而是建立：

```text
/usr/local/bin/codex-window-anchor
```

这个 root-owned runtime snapshot，并在 `restorecon` 可用时恢复正常 SELinux context。Installer 随后还会通过 transient systemd probe 验证 systemd 确实能够执行它。

### 排查

查看：

```bash
getenforce
ls -l /usr/local/bin/codex-window-anchor
ls -Z /usr/local/bin/codex-window-anchor
sudo journalctl -b --no-pager | grep -i -E 'codex-window-anchor|avc|selinux'
```

如果系统提供 `restorecon`，可以检查并重新恢复这个**项目 runtime 文件**的默认 context：

```bash
sudo restorecon -v /usr/local/bin/codex-window-anchor
```

然后重新运行项目 Installer，让 transient probe 再次完成验证。

> [!CAUTION]
> 不要使用：
>
> ```bash
> setenforce 0
> chmod 777 /usr/local/bin/codex-window-anchor
> ```
>
> Public V1 已经在 **SELinux Enforcing** 环境中完成验证。关闭 SELinux 或放宽到 `777` 不是本项目认可的修复方式。

---

## Schedule helper 拒绝修改正在运行的 Timer

### 典型错误

```text
timer is enabled; pause it first with:
sudo systemctl disable --now codex-window-anchor.timer
```

或者提示 Timer 仍然 active。

### 这是有意行为

`codex-window-anchor-schedule` 不会悄悄暂停或替换一个正在运行的 Schedule。

先执行：

```bash
sudo systemctl disable --now codex-window-anchor.timer
```

确认：

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
```

然后重新配置：

```bash
codex-window-anchor-schedule \
  --timezone YOUR/ZONE \
  --time HH:MM
```

Schedule helper 完成后应再次保持：

```text
disabled / inactive
```

Review 无误后，用户自己显式恢复：

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

这个约束来自 schedule helper 的最终实现：它只有在能证明现有 Timer 已 disabled/inactive 时才允许替换。

---

## Timezone 或 Time 参数被拒绝

### Timezone

合法形式需要是已安装 zoneinfo 中的 IANA `AREA/CITY`：

```text
America/New_York
Europe/London
Asia/Shanghai
```

查看当前主机可用 timezone：

```bash
timedatectl list-timezones
```

不要传：

```text
UTC+8
GMT+8
CST
/path/to/zone
../zone
```

如果你希望 UTC，可以使用：

```text
Etc/UTC
```

### Time

必须是严格 24 小时：

```text
00:00
09:30
23:59
```

下面会被拒绝：

```text
9:30
24:00
9 PM
09:60
```

多个重复时间会自动去重并排序。

Schedule timezone 不会修改服务器 global timezone；helper 只是把 timezone 写入 Timer 的 `OnCalendar=`。

---

## Timer 没有按预期运行

先确认 Timer 是否真的**已显式启用**：

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer --all --no-pager
```

如果状态仍是：

```text
disabled
inactive
```

说明你只完成了 Schedule generation，还没有启动自动运行。

启用：

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

然后查看实际 Timer：

```bash
systemctl cat codex-window-anchor.timer
```

确认 `OnCalendar=` 中的 timezone 和时间就是你自己配置的内容。

如果 Timer active 但 service 运行失败：

```bash
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

Timer 只负责**触发** service；认证、网络、模型或 Codex runtime 错误会体现在 service journal 中。

---

## 错过的 Anchor 没有补跑

这是 Public V1 的设计行为，不是 Timer 故障。

生成的 Timer 使用：

```text
Persistent=false
```

如果服务器在计划时间：

- 关机；
- 重启中；
- 网络/系统不可用；

systemd 不会在恢复后立即“补跑”错过的 Anchor。

它会等待下一次正常 Schedule。

这样可以避免一个本来应该在固定时间发生的 Anchor，因为服务器晚几个小时恢复而在意外时间执行。

---

## `codex-window-anchor-schedule` 找不到或无法提权

首先确认：

```bash
command -v codex-window-anchor-schedule
```

Public V1 安装位置应该是：

```text
/usr/local/bin/codex-window-anchor-schedule
```

再检查：

```bash
ls -l /usr/local/bin/codex-window-anchor-schedule
```

Schedule helper 的 self-elevation 只认可**安装后的正式 helper**。普通用户应该执行：

```bash
codex-window-anchor-schedule ...
```

而不是把仓库里的：

```text
scripts/configure-schedule.sh
```

当成普通用户公共命令直接运行。

Public V1 之所以使用 `/usr/local/bin`，就是为了避免某些系统 `sudo secure_path` 对 `/usr/local/sbin` 的可见性问题。最终实现不需要修改 `/etc/sudoers` 或用户 PATH。

如果正式 helper 丢失或 ownership/mode 已被外部修改，不要修改脚本跳过 self-check；按默认卸载/重装路径恢复受管理文件。

---

## 网络或代理环境导致 Codex 不可访问

Codex Window Anchor **不会修改 host firewall 或 proxy configuration**。这也是 Installer 的明确安全边界。

先区分：

### 宿主机上的官方 Codex 本身也无法访问

先解决 Codex / OpenAI 网络问题，Anchor 不是网络代理工具。

可以检查：

```bash
codex --version
```

以及 OpenAI 当前状态：

[https://status.openai.com/](https://status.openai.com/)

如果登录阶段失败，参考 [OpenAI Codex Authentication](https://developers.openai.com/codex/auth)。

OpenAI 官方认证文档还说明：企业 TLS proxy / private CA 环境可能需要 `CODEX_CA_CERTIFICATE` 或 `SSL_CERT_FILE`。这属于 Codex 网络/证书配置，不是 Anchor 自动管理的内容。

### 交互 Shell 可以访问，但 systemd Anchor 失败

不要假设你在 SSH shell 中执行的：

```bash
export HTTP_PROXY=...
export HTTPS_PROXY=...
```

会自动成为 systemd service 的持久运行环境。

Public V1 不自动复制用户 shell proxy settings，也不修改系统 proxy。先通过 service journal 确认错误确实是网络问题：

```bash
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

如果你的服务器必须依赖自定义 proxy、企业 CA 或其它网络注入才能访问 Codex，这属于**高级环境适配**。不要把私人代理地址、订阅链接或凭据写入仓库、Issue 或公共示例。


---

## Model 不可用或请求被拒绝

默认配置使用：

```text
gpt-5.6-luna
```

模型可用性可能随 Codex 和用户计划变化。

如果 journal 明确显示 model unavailable / capacity / access error，先检查：

1. OpenAI Status；
2. 当前账号是否具有该模型/Codex 权限；
3. OpenAI 当前 Codex 模型可用性。

不要把这种错误自动判断为 Timer 故障。

如果需要让 Anchor 使用其它**已经确认当前可用**的 model，Public V1 的可审查路径是重新安装时显式选择：

```bash
sudo ./scripts/install.sh --model MODEL
```

由于默认 uninstall 会删除 generated Timer，runtime/model 重装之后需要重新运行 schedule helper，再 Review 和显式 enable。详细流程见 [INSTALLATION.md](INSTALLATION.md)。

---

## 安装中途失败后无法直接重装

Installer 对 system-level path、service name、service user、home 和 metadata 都会做 collision 检查。

如果一次安装已经开始修改系统但没有完成，Installer 会明确提示：

```text
Installation did not complete.
A partial installation may remain on this host.
```

此时不要：

```text
rm -rf /etc/codex-window-anchor
userdel -r codex-anchor
手工删除 systemd 文件后反复重跑
```

如果项目 metadata 存在：

```text
/etc/codex-window-anchor/install.meta
```

优先在仓库目录执行：

```bash
sudo ./scripts/uninstall.sh
```

Uninstaller 会根据 metadata 和 ownership evidence 清理由项目能够安全识别的 partial resources。

然后再重新安装：

```bash
sudo ./scripts/install.sh
```

如果 uninstall 也因为 identity/path ambiguity 拒绝继续，保留错误原文并进入下一节的 Issue 诊断流程，不要强制删除。

---

## Uninstaller 拒绝继续或保留了资源

Uninstaller 不以“同名”作为删除依据。

它会检查：

- installation metadata；
- managed ownership marker；
- root ownership；
- runtime SHA-256；
- service user / group；
- UID / GID；
- home path / ownership；
- systemd exact state。

如果其中某项无法安全确认，脚本可能显示：

```text
WARNING
```

并保留资源和 metadata，或直接 fail closed。默认卸载还会**有意保留** `codex-anchor` user/home/authentication state。

这时不要为了得到“干净输出”而 `rm -rf`。

先保留：

```text
/etc/codex-window-anchor/install.meta
```

和完整错误信息，然后检查：

```bash
sudo ./scripts/uninstall.sh --help
```

如果你的目标本来就是连 dedicated user/home/auth 一起删除，应使用：

```bash
sudo ./scripts/uninstall.sh --purge-user
```

而不是默认 uninstall。

> [!NOTE]
> Public V1 已在 AlmaLinux 8.10 / systemd 239 上完成卸载验证，并能够区分 service 已不存在、已停止和异常状态。
>
> 如果当前版本仍然出现 uninstall failure，请保留完整错误信息，不要通过忽略 `systemctl` 错误或手工强制删除资源来绕过检查。

---

## Journal 太多，可以让项目自动清理吗？

Public V1 不会自动 vacuum system journal。

查看 Anchor 自己最近的日志：

```bash
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

需要按时间查看时，可以使用 journald 自己的查询参数，而不是直接删除全局 history。

不要为了 Anchor 随意执行全局：

```text
journalctl --vacuum-*
```

因为 journal 是系统级共享日志，清理操作可能影响其它 service 的历史记录。

默认 uninstall 也会保留 system journal history。

---

## 提交 Issue 前收集这些信息

提交 Issue 前，建议先准备一个**最小、可复现、无敏感信息**的问题描述，并至少收集：

```bash
uname -a
systemctl --version
codex --version
```

如果 Installer 已经完成，再提供：

```bash
/usr/local/bin/codex-window-anchor --version

sudo systemctl status codex-window-anchor.service --no-pager -l
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

如果问题与 Schedule 有关：

```bash
systemctl cat codex-window-anchor.timer
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer --all --no-pager
```

Issue 描述建议包含：

- Linux distribution / version；
- CPU architecture；
- systemd version；
- Codex version；
- 你执行的**确切命令**；
- 完整 error message；
- 问题发生在 install / login / manual run / schedule / timer / uninstall 哪一步；
- 是否可以稳定复现。


### 发布日志前必须删除敏感信息

绝对不要提交：

- `/home/codex-anchor/.codex/auth.json`；
- ChatGPT access / refresh token；
- Device Code；
- API Key；
- SSH private key；
- root/SSH password；
- VPS IP（如果你不希望公开）；
- proxy subscription / proxy credential；
- 其它无关服务的 secret。

OpenAI 官方文档明确要求把 file-based `auth.json` 当作密码，因为其中包含 access tokens。

---

## 仍然无法解决？

按下面的顺序处理通常最有效：

```text
确认官方 Codex 本身工作
        ↓
确认 codex-anchor 登录状态
        ↓
手动运行 Anchor service
        ↓
检查 service journal
        ↓
确认 Schedule / Timer 状态
        ↓
确认是否属于 OpenAI 当前服务异常
        ↓
整理无敏感信息的最小诊断信息
        ↓
提交 GitHub Issue
```

如果问题涉及 Codex 登录、账号权限、模型访问或 OpenAI 服务状态，应优先参考 OpenAI 官方资料；如果问题涉及 Anchor Installer、runtime isolation、Schedule helper、systemd Timer 或 safe uninstall，再向 Codex Window Anchor 项目报告。

---

## 相关文档

- [安装与配置](INSTALLATION.md)
- [工作原理](HOW_IT_WORKS.md)
- [安全说明](../../SECURITY.zh-CN.md)
- [返回 README](../../README.zh-CN.md)

Codex Window Anchor 是独立项目，不是 OpenAI 官方产品。
