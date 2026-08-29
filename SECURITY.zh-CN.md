# Codex Window Anchor — 安全政策

Codex Window Anchor 是一个在用户自己的 Linux 主机上运行 OpenAI 官方 Codex CLI 的轻量 systemd 调度层。项目涉及本地系统权限、ChatGPT authentication state、systemd service/timer 和真实 Codex 请求，因此安全问题应当通过**私密渠道**报告，而不是公开 Issue。

> [!IMPORTANT]
> **如果你认为发现了安全漏洞，请不要在公开 GitHub Issue、Discussion、Pull Request、截图或日志中披露可利用细节、认证文件、token、服务器凭据或完整 PoC。**
>
> 仓库切换为 Public 后，应在正式发布 `v1.0.0` 和对外推广之前启用 **GitHub Private Vulnerability Reporting**，并将它作为本项目的正式漏洞报告渠道。

---

## 支持版本

Codex Window Anchor 的安全修复以**当前最新稳定版本**为主。

| 版本 | 安全支持 |
| --- | --- |
| 最新稳定 `v1.x` release | 支持 |
| 更早的 `v1.x` release | 不保证单独维护；建议升级到最新稳定版本 |
| pre-release / development snapshot | 不作为稳定安全支持版本 |
| 未发布的本地修改版 | 不在正式支持范围内 |

在首个稳定版本 `v1.0.0` 发布之前，repository 中的 pre-release 内容不应被理解为已经建立稳定版本安全维护承诺。

如果某个安全问题影响旧版本，但已在最新稳定版本中修复，维护者可能直接要求升级，而不是为每个旧版本单独 backport。

---

## 如何报告安全漏洞

### 推荐渠道：GitHub Private Vulnerability Reporting

GitHub 仓库切换为 Public 后，应立即在 Repository Settings 中启用 **Private Vulnerability Reporting**，并在发布 `v1.0.0` 之前确认该私密报告入口可以正常使用。

启用后，请在仓库页面进入 GitHub 当前显示的 **Security / Security and quality** 区域，选择：

```text
Report a vulnerability
```

通过该入口私下提交报告。

GitHub 官方也建议项目通过 `SECURITY.md` 明确支持版本和私密报告方式，并提供 Private Vulnerability Reporting 作为仓库级安全报告渠道。

### 不要通过这些公开渠道报告漏洞

不要使用：

- Public Issue；
- Discussion；
- Pull Request；
- README 评论；
- 公开社交媒体；
- 含敏感信息的截图或日志链接。

如果 Private Vulnerability Reporting 尚未启用，请**不要公开漏洞细节**。仓库可以先完成 Private → Public 的必要切换，但在正式发布 `v1.0.0`、公开宣传或邀请普通用户使用之前，应先完成私密漏洞报告渠道配置。

### 报告中建议包含

为了尽快判断问题是否属于本项目，请尽量提供：

- 受影响的 Codex Window Anchor 版本；
- Linux distribution / version；
- CPU architecture；
- systemd version；
- Codex CLI version；
- 问题发生在 Installer / login / runtime / Schedule / Timer / Uninstall 的哪一层；
- 完整但已去除 secret 的错误信息；
- 最小复现步骤；
- 预期行为与实际行为；
- 你认为可能造成的安全影响；
- 如有 PoC，请只通过私密报告渠道提供。

不要为了证明漏洞而访问不属于你的账号、主机、token 或数据。

---

## 安全问题的范围

### 属于本项目安全范围的示例

下面这些问题如果能够在受支持版本中复现，通常属于 Codex Window Anchor 的安全范围：

- Installer 错误接管不属于项目的 user/group/path/service；
- Schedule helper 可以通过未受信任脚本或参数获得非预期 root 权限；
- systemd service 以 root 或错误 identity 运行 Codex；
- Anchor runtime 可以被普通用户非预期替换或篡改而仍被接受；
- ownership / metadata / SHA-256 验证被绕过，导致错误删除其它系统资源；
- default uninstall 在未显式 `--purge-user` 时删除 dedicated home 或 ChatGPT authentication state；
- `--purge-user` 可以删除与 installation metadata 不匹配的其它同名用户；
- 项目脚本把 ChatGPT credentials、token 或其它 secret 写入 repository-managed public files；
- Runner 非预期继承 API Key、access token、provider endpoint 或其它未允许的敏感 runtime input；
- path traversal、symlink、alias/drop-in 或 race condition 导致项目修改不属于自己的文件或 systemd namespace；
- 项目自身生成的日志或输出意外暴露 authentication secret；
- Installer / Uninstaller 的 fail-closed 边界可以被绕过并造成权限提升或破坏性删除。

这不是完整清单。核心判断标准是：

> **问题是否违反了 Codex Window Anchor 自己声明的权限、身份、凭据、ownership 或资源边界。**

### 通常不属于本项目漏洞的情况

以下问题通常应报告给对应上游或由主机管理员处理，而不是作为 Anchor 本身的安全漏洞：

- OpenAI / ChatGPT / Codex 服务端漏洞；
- OpenAI account compromise；
- Codex CLI 本身的上游漏洞，与 Anchor glue code 无关；
- OpenAI 修改模型、Usage Window、quota、authentication 或 plan 行为；
- 用户主动把 `auth.json`、token、SSH key 或密码提交到公开仓库；
- 主机在安装 Anchor 之前已经被 root compromise；
- 用户主动关闭 SELinux、执行 `chmod 777` 或修改项目 root-owned files 后造成的边界失效；
- firewall、VPN、proxy、DNS、企业 TLS 或主机网络配置问题；
- 未支持 Linux distribution 上单纯的兼容性差异；
- 用户手工修改 systemd unit / Timer / metadata 后导致的非预期运行；
- “Anchor 没有增加 quota / 没有重置额度”之类的产品行为问题。

如果一个上游 Codex CLI 漏洞**只有通过 Anchor 的特殊调用方式才会产生新的可利用影响**，则可以先私密报告给本项目维护者，并说明为什么 Anchor 会扩大或改变其风险。

---

## 凭据与 Authentication State

Public V1 标准路径使用 ChatGPT account authentication，不要求用户把 API Key 写入 Anchor 配置。

Dedicated Codex Home：

```text
/home/codex-anchor/.codex
```

OpenAI 当前官方 Codex 文档说明，登录信息可能保存在 OS credential store，或以 plaintext file 形式保存在：

```text
~/.codex/auth.json
```

如果使用 file-based credential storage，OpenAI 明确要求把 `auth.json` **像密码一样保护**，因为其中包含 access tokens。

因此：

- 不要 commit `auth.json`；
- 不要粘贴到 GitHub Issue；
- 不要上传到 Discussion；
- 不要放进聊天记录；
- 不要把内容复制进 `anchor.conf`；
- 不要把它作为“诊断附件”公开发送。

项目的 `.gitignore` 应继续忽略 `.codex/`、`auth.json`、credentials、token、secret 和常见 SSH private key。

### Device Code Login

远程/headless Linux 的标准文档路径使用：

```bash
codex login --device-auth
```

OpenAI 当前官方文档将 Device Code Authentication 作为 remote/headless 环境的首选登录方式之一。是否可用取决于个人 ChatGPT security settings 或 Workspace permissions。

Device Code 本身也不应发布到 public Issue 或截图中。

---

## Runtime 安全边界

Anchor 不直接长期引用宿主用户 PATH 中可能变化的 `codex`。

Installer 会从用户已经安装的 standalone Codex executable 建立：

```text
/usr/local/bin/codex-window-anchor
```

并对这份 snapshot 进行验证。当前 Public V1 会检查：

- regular file；
- executable；
- native Linux ELF；
- 非特权 `--version` 可执行；
- Anchor 所需的 `codex exec` options；
- root ownership；
- SHA-256 fingerprint；
- systemd execution probe。

Installer 明确提示：它验证 runtime 的**形式和能力**，但不会自行证明 publisher provenance。

因此用户仍然必须从 OpenAI 官方渠道取得 Codex。`--codex-bin` 不应被理解为“任意可执行文件都安全”。

---

## Privilege boundary

### Anchor request 本身不以 root 运行

systemd service 使用：

```text
User=codex-anchor
Group=codex-anchor
```

并包含：

```text
NoNewPrivileges=true
PrivateTmp=true
UMask=0077
```

真实 Codex 请求由 dedicated non-root identity 执行。

root 只用于确实需要系统权限的操作，例如：

- 安装 root-owned runtime / runner / unit；
- 写入 `/etc/systemd/system`；
- enable/disable system Timer；
- verified uninstall / purge。

### Schedule helper 的 bounded self-elevation

公共命令：

```text
/usr/local/bin/codex-window-anchor-schedule
```

可以由普通用户直接运行。

当需要更新 systemd Timer 时，它只会在确认自身解析到的是预期的 root-owned、mode `755`、带项目 ownership marker 的正式 helper 后，通过：

```text
/usr/bin/sudo
```

重新执行原始参数。

它不会：

- 创建 sudoers rule；
- 修改 `/etc/sudoers`；
- 修改 PATH；
- 对任意仓库脚本提供通用提权入口。

如果 helper 无法确认自己的正式安装路径或 ownership，它会拒绝提权。

---

## Runtime environment boundary

`run-anchor.sh` 使用：

```text
/usr/bin/env -i
```

构造显式环境，而不是直接继承 systemd manager 的全部环境。

Public V1 不允许普通环境中的这些 authentication/provider inputs 自动进入 Anchor runtime：

```text
OPENAI_API_KEY
CODEX_API_KEY
CODEX_ACCESS_TOKEN
OPENAI_BASE_URL
OPENAI_FEDERATION_RULE_ID
OPENAI_IDENTITY_TOKEN_FILE
```

以及其它未列入 allowlist 的变量。

Runner 只重新建立基础 runtime identity/path/state 变量，并允许常规 network / CA variables，例如：

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

允许已有 proxy / CA environment 进入 runtime，不代表 Anchor 自动配置或信任任意 proxy。网络终点和主机代理策略仍由系统管理员负责。

---

## Codex execution boundary

Public V1 的每次 Anchor 使用：

```text
--ephemeral
--ignore-user-config
--ignore-rules
--skip-git-repo-check
--sandbox read-only
```

并发送固定最小 prompt，要求只回复 `OK`，不要读取文件、执行命令、浏览 Web 或调用工具。

这降低了 Anchor 自己的工作范围，但不应被描述成绝对安全沙箱保证。Codex CLI、操作系统、systemd 和 OpenAI 服务仍然是独立信任边界。

**每次 Anchor 都是真实 Codex 请求；业务输入和输出极小，整体任务被设计为尽可能轻量，但实际 token 计量会随 Codex CLI、模型和 OpenAI 侧上下文变化。**

---

## systemd 与 Schedule 边界

Installer 完成时：

```text
没有 ChatGPT login
没有 Anchor request
没有 generated Timer
没有 enabled / active Timer
```

Schedule helper 完成时：

```text
generated Timer
disabled / inactive
no Anchor request
```

只有用户显式执行：

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

后才开始自动调度。

Schedule timezone 写在 Timer 的 `OnCalendar=` 中，不修改系统 global timezone。

Timer 使用：

```text
Persistent=false
```

因此服务器离线时错过的 Anchor 不会在恢复后自动补跑。

---

## Installer 的主机边界

Public V1 Installer 明确不自动修改：

- firewall；
- proxy；
- VPN；
- swap；
- `/etc/fstab`；
- host global timezone；
- SELinux enforcement；
- unrelated services；
- `/etc/sudoers`。

它不会使用：

```text
chmod 777
setenforce 0
```

作为兼容性修复手段。

完整 clean integration validation 使用 **SELinux Enforcing**。

---

## Safe uninstall

默认：

```bash
sudo ./scripts/uninstall.sh
```

不是“删除所有同名文件”。

Uninstaller 会依赖：

- installation metadata；
- ownership marker；
- file ownership/mode；
- runtime SHA-256；
- user/group；
- UID/GID；
- home path / ownership；
- exact systemd state。

只有能够积极确认属于本项目的 managed resource 才会被删除。

默认 uninstall 会保留：

```text
codex-anchor user
/home/codex-anchor
ChatGPT authentication state
用户自己的官方/global Codex CLI
system journal history
firewall / proxy / SELinux
swap / /etc/fstab
unrelated files/services
```

如果 ownership、identity、runtime fingerprint 或 systemd state 出现 ambiguity，脚本可能保留资源并 fail closed。

### `--purge-user`

只有用户明确执行：

```bash
sudo ./scripts/uninstall.sh --purge-user
```

才进入 dedicated user/home/authentication state 的破坏性清理路径。

Purge 会再次验证 identity evidence，并默认要求交互确认。无法证明目标仍然是项目原本创建的 exact identity 时，应拒绝删除，而不是因为用户名相同就执行 `userdel -r`。

---

## Secrets 不应出现在这些位置

不要把 secret 写入或提交到：

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

特别检查：

- `auth.json`；
- ChatGPT access / refresh tokens；
- API keys；
- SSH private keys；
- VPS root password；
- private proxy subscriptions；
- proxy credentials；
- unrelated X-ray/VPN/service credentials；
- local `.env`；
- shell history 中意外暴露的 secret。

在公开日志前，先手工检查并删除敏感内容。

---

## Usage Window / quota 不属于安全保证

Codex Window Anchor 不创建、增加、重置或绕过 OpenAI usage limits。

Usage Window 在本项目中只能描述为：

```text
observed behavior
observed usage-window anchoring
```

不应表述成：

```text
OpenAI guaranteed reset
quota multiplier
extra allowance
limit bypass
unlimited Codex
```

OpenAI 可以调整模型、plans、authentication、limits 和 Usage Window behavior。此类产品行为变化本身不是 Codex Window Anchor 的安全漏洞。

---

## Responsible disclosure

如果你通过私密渠道报告了可复现的安全漏洞，请给维护者合理时间完成：

```text
triage
→ reproduce
→ assess scope
→ prepare fix
→ release
→ disclosure
```

再公开完整利用细节。

Public V1 **不承诺固定的 24/48/72 小时响应 SLA，也没有已声明的 bug bounty program**。在尚未建立正式 SLA 或 bounty 之前，不应在文档中制造这类承诺。

安全修复和必要的公开披露可以通过 GitHub Security Advisory / Release Notes 完成，具体方式取决于漏洞性质。


---

## 相关文档

- [安装与配置](docs/zh-CN/INSTALLATION.md)
- [故障排查](docs/zh-CN/TROUBLESHOOTING.md)
- [工作原理](docs/zh-CN/HOW_IT_WORKS.md)
- [返回 README](README.zh-CN.md)

Codex Window Anchor 是独立项目，不是 OpenAI 官方产品。
