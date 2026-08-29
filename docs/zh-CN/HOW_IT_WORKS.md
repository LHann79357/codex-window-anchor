# Codex Window Anchor — 工作原理

本文档解释 Codex Window Anchor Public V1 的核心架构、一次 Anchor 的生命周期，以及为什么项目把 runtime、认证、Schedule 和卸载设计成彼此分离的边界。

如果你只想完成部署，请阅读 [INSTALLATION.md](INSTALLATION.md)；如果遇到错误，请阅读 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。

---

## 设计目标

Codex Window Anchor 不是新的 Codex 客户端，也不是常驻 Agent。它是一层很小、可审查的 **systemd scheduling wrapper**：用户先安装 OpenAI 官方 standalone Codex CLI，Anchor Installer 从这份 executable 建立独立 runtime snapshot；之后由 systemd 在用户自己选择的时间启动一个一次性 service，以 dedicated non-root identity 发送最小真实 Codex 请求，请求结束后立即退出。

Public V1 围绕六个原则设计：

| 原则 | 含义 |
| --- | --- |
| Official Codex first | Anchor 不下载或重新分发 Codex |
| Explicit opt-in | 安装、登录、Schedule、enable 分开完成 |
| Dedicated identity | Anchor 使用独立 `codex-anchor` 用户和 Codex Home |
| Small runtime surface | 不需要 Web 面板、数据库或常驻 daemon |
| Fail closed | 无法确认 ownership / identity / state 时拒绝猜测修改 |
| Easy to stop/remove | Timer 可单独暂停；默认卸载只删除可验证 managed resources |

这些原则意味着 Public V1 不追求“安装后什么都自动完成”。凡是涉及凭据、真实请求或系统级调度的步骤，都保留明确的用户授权点。

---

## 架构总览

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

系统里没有一个 Anchor 进程持续等待下一次运行。等待 Schedule 的是 systemd Timer；Codex 进程只在某次触发期间存在。

### 主要组件

| 组件 | 职责 |
| --- | --- |
| `install.sh` | 建立受管理的 identity、runtime 和 systemd 基础 |
| `/usr/local/bin/codex-window-anchor` | 独立、root-owned Codex runtime snapshot |
| `run-anchor.sh` | 每次 Anchor 的固定执行入口 |
| `anchor.conf` | 非 secret runtime 配置 |
| `/home/codex-anchor/.codex` | dedicated Codex Home / authentication state |
| `codex-window-anchor.service` | 一次请求对应的 systemd oneshot service |
| `codex-window-anchor-schedule` | 校验用户时间并生成 Timer |
| `codex-window-anchor.timer` | 用户真正选择并显式启用的 Schedule |
| `install.meta` | ownership / identity / runtime evidence |
| `uninstall.sh` | 根据 evidence 安全删除项目资源 |

---

## Runtime isolation

### 为什么不直接运行用户 Home 里的 `codex`

最简单的实现可以直接让 systemd 执行用户原本安装的 Codex，但 Public V1 没有这样做。

真实 AlmaLinux 环境曾暴露一个重要问题：某个 executable 在交互 Shell 中可以运行，并不代表它在 systemd + SELinux execution context 下也一定可执行。同时，如果 Anchor 永远引用用户 PATH 中的 `codex`，宿主用户一次普通升级就可能在没有重新验证的情况下改变自动任务使用的 runtime。

因此 Installer 从用户明确选择的 standalone Codex executable 建立：

```text
/usr/local/bin/codex-window-anchor
```

这份 snapshot 是 root-owned，安装完成后与原始 Codex 路径分离。

Installer 随后验证它：

- 是 native Linux ELF；
- 可以由非特权身份执行 `--version`；
- 支持 Anchor 当前依赖的 `codex exec` options；
- 能计算并记录 SHA-256；
- 可以由 systemd 实际执行。

如果 `restorecon` 可用，还会恢复正常 SELinux context，并通过 transient `systemd-run` probe 验证最终执行路径。

结果是：

```text
普通用户更新自己的 codex
        ≠
Anchor runtime 自动改变
```

这种 runtime snapshot 设计牺牲了自动升级便利性，换来一个更明确、可重复验证的自动运行边界。

---

## Identity 与 Authentication boundary

Anchor 请求不会以 root 身份执行，也不会直接借用安装者的 Linux account。

Installer 使用独立 identity：

```text
user:  codex-anchor
group: codex-anchor
home:  /home/codex-anchor
```

systemd service 明确以该 user/group 运行，而 ChatGPT authentication state 使用：

```text
CODEX_HOME=/home/codex-anchor/.codex
```

这让两个边界保持分离：

```text
宿主用户的 Codex 环境
        │
        └──── 不直接复用 ────┐

codex-anchor dedicated Home
        │                    │
        ├── ChatGPT auth     │
        └── Anchor Codex state
```

Installer **不会**复制其它用户的 `auth.json`，也不会自动登录 ChatGPT。用户需要明确为 `codex-anchor` 完成认证。

root 权限只用于真正需要系统级权限的操作，例如安装 root-owned 文件、生成 systemd Timer 和 enable/disable Timer；真实 Codex request 本身运行在 `codex-anchor` 非 root identity 下。

---

## 一次 Anchor 如何运行

每次手动触发或 Timer 触发最终都会进入：

```text
/usr/local/libexec/codex-window-anchor/run-anchor.sh
```

Runner 读取：

```text
/etc/codex-window-anchor/anchor.conf
```

其中只保存非 secret runtime information，例如：

```text
CODEX_BIN=/usr/local/bin/codex-window-anchor
CODEX_MODEL=gpt-5.6-luna
```

它不会把 ChatGPT token 或 API Key 写在这个配置文件里。

Runner 在启动 Codex 前会确认 runtime、model、dedicated Home、Codex Home 和自己的 state directories 都处于预期状态。随后，它不是继承整个 systemd manager environment，而是通过：

```text
/usr/bin/env -i
```

建立一份显式 runtime environment。

基础 allowlist 包括：

```text
HOME
USER
LOGNAME
SHELL
PATH
CODEX_HOME
CODEX_SQLITE_HOME
```

同时允许常规网络环境可能需要的 proxy / CA certificate variables，例如：

```text
HTTP_PROXY / HTTPS_PROXY / ALL_PROXY / NO_PROXY
CODEX_CA_CERTIFICATE
SSL_CERT_FILE / SSL_CERT_DIR
CURL_CA_BUNDLE / REQUESTS_CA_BUNDLE
```

这样可以避免 Anchor 无意继承 `OPENAI_API_KEY`、`CODEX_ACCESS_TOKEN`、`OPENAI_BASE_URL` 或其它 provider/workload identity switches，同时又不强行破坏管理员已经正确配置的企业 proxy / CA 环境。

---

## Codex invocation

Runner 最终使用的核心执行语义是：

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

这些 flags 共同限定了 Anchor 的任务范围：

- `--ephemeral`：每次运行都是短生命周期任务；
- `--ignore-user-config`：不让普通用户 Codex 配置改变 Anchor 行为；
- `--ignore-rules`：不读取用户/项目 rules 扩展工作内容；
- `--skip-git-repo-check`：runtime work directory 不需要是 Git repository；
- `--sandbox read-only`：Anchor 不以修改服务器文件为目标；
- `--color never`：journald 不需要终端彩色输出。

Installer 在安装阶段已经检查 runtime 是否支持这些参数。如果所选 Codex CLI 不满足当前 contract，安装会停止，而不是把错误留到未来 Timer 触发时才发现。

固定 prompt 是：

```text
Reply exactly with OK. Do not inspect files, run commands, browse the web, use tools, or perform any additional work.
```

它的目的不是让 Codex完成代码任务，而是把业务工作量收缩到一个明确的最小请求。

**每次 Anchor 都是真实 Codex 请求；业务输入和输出极小，整体任务被设计为尽可能轻量，但实际 token 计量会随 Codex CLI、模型和 OpenAI 侧上下文变化。**

---

## systemd execution model

### Oneshot service

`codex-window-anchor.service` 使用：

```text
Type=oneshot
User=codex-anchor
Group=codex-anchor
WorkingDirectory=/var/lib/codex-window-anchor/work
ExecStart=/usr/local/libexec/codex-window-anchor/run-anchor.sh
```

同时配置：

```text
NoNewPrivileges=true
PrivateTmp=true
UMask=0077
TimeoutStartSec=180
```

这意味着一次触发的生命周期就是：

```text
systemd starts service
→ runner execs Codex
→ one request completes
→ process exits
→ service becomes inactive
```

所以成功完成后看到：

```text
inactive (dead)
```

是正常状态，而不是 daemon 崩溃。

### 为什么没有常驻 daemon

Anchor 的任务只在某些时间点存在，没有必要让自己的程序 24/7 常驻等待。把“等待”交给 systemd Timer，可以减少独立进程、状态管理和长期运行复杂度。

---

## Schedule 与 explicit opt-in

Public V1 没有公共默认运行时间，因为 Schedule 应由用户自己决定，而更多运行时间也意味着更多真实 Codex requests。

Installer 完成时甚至不会创建：

```text
/etc/systemd/system/codex-window-anchor.timer
```

只有用户主动运行：

```bash
codex-window-anchor-schedule \
  --timezone AREA/CITY \
  --time HH:MM
```

后，Schedule helper 才会验证 IANA timezone、严格的 24 小时时间、完整安装状态、dedicated identity、managed files 和 runtime fingerprint，再生成 Timer。

每个用户时间会形成：

```text
OnCalendar=*-*-* HH:MM:00 AREA/CITY
```

生成的 Timer 使用：

```text
AccuracySec=30s
RandomizedDelaySec=0
Persistent=false
Unit=codex-window-anchor.service
```

`Persistent=false` 表示服务器如果错过某个 Schedule，不会在恢复后补跑旧 Anchor，而是等待下一次正常时间。

Timezone 直接写在 `OnCalendar=` 中，不需要修改服务器 global timezone。

### Bounded self-elevation

生成 `/etc/systemd/system/...` 需要 root，但 Public CLI 仍希望保持：

```bash
codex-window-anchor-schedule ...
```

因此 helper 只在需要系统写入时自提权，并且提权前验证当前执行的确实是：

```text
/usr/local/bin/codex-window-anchor-schedule
```

同时确认它是 root-owned、mode `755`、regular managed file，然后才通过 `/usr/bin/sudo` 使用原始参数重新执行。

它不会修改：

```text
/etc/sudoers
sudoers.d
用户 PATH
```

### 为什么 Schedule 生成后仍然不会启动

Schedule helper 的生命周期是：

```text
validate
→ generate
→ verify
→ daemon-reload
→ prove disabled/inactive
```

它不会 enable 或 start Timer。

如果已有 Timer，只有在能够证明它已经：

```text
disabled
inactive
```

时才允许替换。

真正把“配置文件”变成“正在运行的自动任务”的授权点只有：

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

---

## Ownership evidence 与 fail-closed

系统级卸载最危险的错误之一，是把“名字相同”误认为“资源属于我”。

因此 Installer 会维护：

```text
/etc/codex-window-anchor/install.meta
```

其中记录项目管理和 identity/runtime evidence，例如：

```text
format version
installation state
service user / group / home
UID / GID
runtime SHA-256
```

它不保存 ChatGPT credentials。

Schedule helper 和 Uninstaller 会结合 metadata、ownership marker、文件 owner/mode、identity、runtime fingerprint 和 systemd namespace/state 判断一个对象是否仍然是项目管理的资源。

因此 Public V1 的基本删除规则不是：

```text
名字叫 codex-window-anchor
→ 删除
```

而是：

```text
能够积极证明属于本项目
→ 才允许修改/删除
```

如果出现 alias、drop-in、UID/GID 不匹配、runtime hash 改变、ownership 不确定或其它 ambiguity，脚本倾向于保留现场并 fail closed。

这也是为什么某些异常情况下，Uninstaller 会留下 metadata 和 residual resource，而不是通过 `rm -rf` 强制给出一个“看起来干净”的结果。

---

## 卸载与认证保留

默认：

```bash
sudo ./scripts/uninstall.sh
```

会删除能够安全确认的 Anchor Timer、service、runner、schedule helper、runtime snapshot、configuration 和空 runtime directories，但默认保留：

```text
codex-anchor user
/home/codex-anchor
ChatGPT authentication state
```

同时保留最小 verified identity metadata。

原因是认证属于用户主动建立的高价值状态。普通卸载不应该顺便销毁它；而且这允许用户以后重新安装新的 verified runtime，在 exact identity 仍匹配时复用 authentication。

复用不是仅凭用户名判断。Installer 会重新核对：

```text
username
UID
group
GID
home path
home ownership
preserved metadata
```

只有 exact match 才接受 preserved identity。

如果用户明确希望连 dedicated identity 和认证一起删除，则使用：

```bash
sudo ./scripts/uninstall.sh --purge-user
```

Purge 是另一种明确的破坏性意图，并会在删除前再次验证 identity；默认还要求交互确认。

---

## 系统边界

Codex Window Anchor 刻意保持自己的作用域很小。

### 项目会管理

```text
dedicated codex-anchor identity
Anchor runtime snapshot
Anchor runner/config/state
Anchor service
user-generated Anchor Timer
installation metadata
```

### 项目不会自动管理

```text
OpenAI Codex 安装/升级
ChatGPT plan / quota
firewall
VPN
host proxy
system global timezone
swap / /etc/fstab
global journald retention
其它 systemd services
Web dashboard / database
```

Runner 可以继承受限的 proxy / CA environment variables，这只是为了兼容已经存在的网络配置，不代表 Anchor 负责创建或管理 proxy。

SELinux 也是同样的原则：Public V1 在 Enforcing 环境中验证，Installer 会使用正常 system path/context 和 systemd probe，而不会通过：

```text
setenforce 0
disable SELinux
chmod 777
```

来获得兼容性。

---

## 完整生命周期

从“官方 Codex 已经安装”开始：

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

暂停：

```text
disable --now
→ Timer disabled/inactive
→ runtime/auth remain
```

默认卸载：

```text
managed runtime/service/timer removed
→ dedicated identity/auth preserved
```

显式 purge：

```text
managed resources removed
→ verified dedicated identity/home/auth removed
```

---

## 关键路径

| 用途 | 路径 |
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

## 相关文档

- [安装与配置](INSTALLATION.md)
- [故障排查](TROUBLESHOOTING.md)
- [安全说明](../../SECURITY.zh-CN.md)
- [返回 README](../../README.zh-CN.md)

Codex Window Anchor 是独立项目，不是 OpenAI 官方产品。本文档描述的是 Public V1 当前实现；Usage Window 属于观察到的行为，OpenAI 未来可能调整 Codex CLI、认证、模型、计划限制或相关使用行为。
