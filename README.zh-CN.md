<p align="center">
  <img src="./assets/banner-reset.png" alt="Codex Window Anchor 横幅" width="100%">
</p>

<h1 align="center">Codex Window Anchor</h1>

<p align="center">
  <a href="./README.md">English</a> ·
  <strong>简体中文</strong> ·
  <a href="./README.ja.md">日本語</a>
</p>

**基于 OpenAI 官方 Codex CLI 的自托管定时 Anchor 工具，用于围绕观察到的 Codex Usage Window 行为，在用户自己选择的时间运行最小真实请求。**

Codex Window Anchor 面向希望把这件事放到 Linux 服务器上稳定运行、又不想引入浏览器自动化、API Key 定时任务、第三方 keepalive 服务、Web 面板或常驻 daemon 的用户。它使用独立的 `codex-anchor` 非 root 用户、systemd oneshot service 和用户自行配置的 Timer；安装完成后不会自动登录 ChatGPT、不会自动创建时间表，也不会自动开始发送请求。

> [!IMPORTANT]
> **Codex Window Anchor 不会增加 Codex 配额、创建额外额度、绕过限制、强制重置配额，也不会提供“无限 Codex”。**
>
> 本项目所说的 Usage Window / usage-window anchoring 来自实际运行中观察到的行为（observed behavior），不是 OpenAI 对 ChatGPT、Codex、模型、配额或 Usage Window 的永久产品承诺。
>
> **每次 Anchor 都是真实 Codex 请求；业务输入和输出极小，整体任务被设计为尽可能轻量，但实际 token 计量会随 Codex CLI、模型和 OpenAI 侧上下文变化。**

**导航：** [已验证环境](#已验证环境与已知限制) · [工作原理](#工作原理) · [快速开始](#快速开始) · [日常操作](#日常操作) · [卸载](#卸载) · [文档](#文档)

---

## 已验证环境与已知限制

Public V1 同时经过真实 VPS 自动运行验证和独立 clean VM 集成验证。真实部署运行在 **Vultr VPS — AlmaLinux 8.10 x86_64 / systemd 239**，已经完成实际 systemd 定时 Anchor 运行；发布候选又在 **AlmaLinux 8.10 Minimal x86_64 / systemd 239 / SELinux Enforcing** 的干净环境中完成 Installer、Schedule、Timer、SELinux 边界与 Uninstall 全链路验证。Vultr 不是项目依赖，只是已经完成真实运行验证的 VPS 环境之一。

| 验证层级 | 环境 | 结论 |
| --- | --- | --- |
| 真实服务器运行 | Vultr VPS · AlmaLinux 8.10 x86_64 · systemd 239 | 实际自动定时 Anchor 验证通过 |
| Clean integration | AlmaLinux 8.10 Minimal x86_64 · systemd 239 · SELinux Enforcing | 安装、配置、Timer、安全边界、卸载验证通过 |

当前 Public V1 的完整验证基线仍然是 **AlmaLinux 8.10 x86_64**。其它 Linux 发行版、systemd 版本和 CPU 架构可能可以运行，但在完成同等级集成测试前，本项目不对它们声明相同支持级别。V1 需要 Linux、systemd、`sudo`/root 权限、能够访问 Codex 的网络环境，以及用户预先安装的 **OpenAI 官方 standalone Linux Codex executable**；Installer 会验证所选 runtime 是原生 Linux ELF，并检查 Anchor 所依赖的 Codex CLI 参数，因此 npm/node wrapper 不是当前 V1 的 Anchor runtime 路径。

ChatGPT Device Code 登录是否可用取决于 OpenAI 当前认证策略和用户所在 Workspace 的设置；默认模型当前是 `gpt-5.6-luna`，未来模型名称和可用性也可能变化。Schedule 使用独立 IANA timezone，不会修改 Linux 的全局 timezone；每一个配置的运行时间都会产生一次真实 Codex 请求。

如果你的环境不属于上述完整验证基线，请先阅读 [详细安装说明](docs/zh-CN/INSTALLATION.md) 和 [故障排查](docs/zh-CN/TROUBLESHOOTING.md)。

---

## 工作原理

Codex Window Anchor 本质上是一层很小的 systemd 调度封装，而不是一个持续运行的后台 Agent。用户启用 Timer 后，systemd 会在指定时间唤醒一个 `Type=oneshot` service；service 以独立的 `codex-anchor` 非 root 用户启动 `run-anchor.sh`，再调用安装时保存到 `/usr/local/bin/codex-window-anchor` 的 root-owned Codex runtime snapshot。Runner 使用独立 `CODEX_HOME`、显式最小环境、`--ephemeral`、`--sandbox read-only`，并忽略普通用户环境中的 Codex config 和 rules，然后发送一个固定的最小请求，要求 Codex 只回复 `OK`。请求结束后进程立即退出，不会留下常驻 Anchor daemon。

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

Timer 使用 `Persistent=false`：如果服务器在某个计划时间处于离线状态，systemd 不会在服务器稍后恢复时“补跑”错过的 Anchor。配置时间表时，`codex-window-anchor-schedule` 会验证 IANA timezone 和严格的 `HH:MM` 时间格式、去除重复值并排序，在需要写入 systemd Timer 时自行通过 `/usr/bin/sudo` 完成受限提权；生成后它还会确认 Timer 仍然保持 `disabled / inactive`。真正开始自动运行，只发生在用户显式执行 `sudo systemctl enable --now codex-window-anchor.timer` 之后。

Installer 本身只负责准备隔离的运行环境：创建 `codex-anchor` 用户、从已经存在的官方 standalone Codex executable 建立 root-owned snapshot、安装 runner/service/schedule helper 和配置文件。它不会下载 Codex、不会登录 ChatGPT、不会读取或复制用户的 `auth.json`、不会发送 Anchor、不会生成公共默认 Schedule，也不会修改 firewall、proxy、swap、`/etc/fstab`、系统全局 timezone 或 SELinux 策略。

需要注意，Anchor 使用的是**安装时保存的 runtime snapshot**。以后更新宿主用户 PATH 中的另一份 `codex`，不会静默替换 Anchor runtime；这样可以避免已经验证过的 Anchor 在没有重新安装和检查的情况下发生 runtime drift。完整架构和安全设计见 [HOW_IT_WORKS.md](docs/zh-CN/HOW_IT_WORKS.md)。

---

## 快速开始

下面以 **AlmaLinux 8.10 x86_64** 为例。普通用户可以按顺序执行这一组命令完成安装、ChatGPT 登录、Schedule 配置和显式启用。Codex Window Anchor 不负责下载 Codex，因此第一步使用 OpenAI 当前提供的 standalone Mac/Linux 安装入口。

```bash
# 安装基础依赖
sudo dnf install -y git curl tar

# 安装 OpenAI 官方 standalone Codex CLI
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex --version

# 下载并安装 Codex Window Anchor
git clone https://github.com/LHann79357/codex-window-anchor.git
cd codex-window-anchor
sudo ./scripts/install.sh

# 为独立的 codex-anchor 用户登录 ChatGPT
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login --device-auth

# 确认认证状态
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status

# 设置你自己的 timezone 和运行时间
# 这里只是中性示例，不是推荐时间，也不是 quota 优化时间
codex-window-anchor-schedule \
  --timezone Etc/UTC \
  --time 09:30

# 检查生成的 Timer
systemctl cat codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

执行 Device Code 登录时，终端会显示 OpenAI 提供的登录地址和一次性代码；在浏览器中使用拥有 Codex 访问权限的 ChatGPT 账号完成授权即可。OpenAI 官方资料可直接查看 [Codex GitHub](https://github.com/openai/codex) 和 [Codex Authentication](https://developers.openai.com/codex/auth)。

> [!NOTE]
> 安装完成时没有公共默认 Schedule，也没有正在运行的 Timer。`codex-window-anchor-schedule` 生成时间表后仍保持 `disabled / inactive`；在你后续明确确认并启用之前，自动调度不会开始。

### 可选但推荐：启用 Timer 前先手动验证一次

如果你希望在正式开启自动调度前，先确认 ChatGPT 登录、Anchor runtime 和 systemd service 都正常，可以手动运行一次：

```bash
sudo systemctl start codex-window-anchor.service
sudo journalctl -u codex-window-anchor.service -n 50 --no-pager
```

这会立即发送 **1 次真实 Anchor 请求**。

因为 service 是 `Type=oneshot`，成功结束后显示：

```text
inactive (dead)
```

属于正常状态，并不表示任务失败。

确认手动验证正常、Schedule 也检查无误后，再正式开启自动调度：

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

确认 Timer：

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

如果机器上存在多份 Codex executable，可以在安装时明确选择：

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/codex
```

如果需要在安装时指定其它可用模型：

```bash
sudo ./scripts/install.sh --model MODEL
```

更多安装前检查、不同网络环境和重装说明放在 [INSTALLATION.md](docs/zh-CN/INSTALLATION.md)，README 不再重复展开。

---

## 日常操作

安装完成后，最常用的管理动作只有下面几项：

| 操作 | 命令 |
| --- | --- |
| 查看 Timer | `systemctl list-timers codex-window-anchor.timer` |
| 查看最近 Anchor 日志 | `sudo journalctl -u codex-window-anchor.service -n 50 --no-pager` |
| 暂停 | `sudo systemctl disable --now codex-window-anchor.timer` |
| 恢复 | `sudo systemctl enable --now codex-window-anchor.timer` |

暂停只会停止自动调度，不会删除 Anchor、`codex-anchor` 用户、ChatGPT authentication state 或已经生成的 Timer。

修改时间表时，先暂停 Timer，再重新运行 schedule helper。helper 会拒绝直接覆盖仍然 enabled 或 active 的 Timer，因此不会在后台悄悄修改一个正在运行的调度：

```bash
sudo systemctl disable --now codex-window-anchor.timer

codex-window-anchor-schedule \
  --timezone YOUR/ZONE \
  --time HH:MM \
  --time HH:MM

systemctl cat codex-window-anchor.timer

sudo systemctl enable --now codex-window-anchor.timer
```

Schedule 的 timezone 只属于该 Timer，不会改变服务器全局 timezone。

---

## 卸载

默认卸载在仓库目录中执行：

```bash
sudo ./scripts/uninstall.sh
```

默认路径只删除能够安全确认属于 Codex Window Anchor 的 managed resources，包括 Timer、service、runner、schedule helper、Anchor runtime snapshot 和项目配置；它**保留用户原本安装的官方 Codex CLI，也保留 `codex-anchor` dedicated user、`/home/codex-anchor` 以及其中的 ChatGPT authentication state**。system journal history、firewall、proxy、SELinux、swap、`/etc/fstab` 和无关服务同样不会被普通卸载修改。

如果你明确希望连 dedicated user、home 和其中的认证状态一起删除：

```bash
sudo ./scripts/uninstall.sh --purge-user
```

该路径默认要求交互确认。只有明确需要非交互式彻底清理时才使用：

```bash
sudo ./scripts/uninstall.sh --purge-user --yes
```

`--purge-user` 是破坏性操作。默认卸载与 purge 的具体边界以 [INSTALLATION.md](docs/zh-CN/INSTALLATION.md) 和 [SECURITY.zh-CN.md](SECURITY.zh-CN.md) 为准。

---

## 安全与凭据

Anchor 请求以 dedicated non-root `codex-anchor` 用户执行，项目管理的 runtime 和配置由 root 持有；运行时使用 read-only sandbox、ephemeral session 和显式最小环境，不依赖 API Key，也没有无限重试循环。Public V1 的设计目标不是“自动接管服务器”，而是尽量把作用范围限制在它自己的用户、文件、service 和 Timer 上。

> [!WARNING]
> Codex 登录凭据可能保存在 `/home/codex-anchor/.codex/` 中。如果当前 Codex 使用 file-based credential storage，其中的 `auth.json` 属于密码级敏感信息。
>
> **不要把 `auth.json`、ChatGPT token、API Key、SSH private key、服务器密码或私有代理凭据提交到 GitHub、Issue、日志分享或聊天记录。**

完整安全边界与漏洞报告方式见 [SECURITY.zh-CN.md](SECURITY.zh-CN.md)。

---

## 文档

README 只保留普通用户最需要的主路径。更完整的说明分别放在：

**[详细安装与配置](docs/zh-CN/INSTALLATION.md)** · **[故障排查](docs/zh-CN/TROUBLESHOOTING.md)** · **[工作原理](docs/zh-CN/HOW_IT_WORKS.md)** · **[安全说明](SECURITY.zh-CN.md)**

三个语言版本保持相同的命令、路径、参数和安全含义。

---

## License

> [!NOTE]
> Public V1 License 尚未最终决定。在 `v1.0.0` 正式公开前将单独完成 License 选择与审查；当前文档不预设 MIT、Apache-2.0 或其它 License。

---

Codex Window Anchor 是独立项目，不是 OpenAI 官方产品。本项目对 Usage Window 的描述仅代表观察到的行为和实现经验，不应被理解为 OpenAI 对未来 ChatGPT plans、Codex models、usage limits、quota、authentication 或 usage-window behavior 的保证。
