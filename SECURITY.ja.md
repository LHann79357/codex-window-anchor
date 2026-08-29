# Codex Window Anchor — セキュリティポリシー

Codex Window Anchor は、ユーザー自身の Linux ホスト上で OpenAI 公式 Codex CLI を実行する軽量な systemd scheduling layer です。ローカルの system privilege、ChatGPT authentication state、systemd service/timer、実際の Codex request を扱うため、セキュリティ脆弱性は **private channel** で報告し、public Issue では公開しないでください。

> [!IMPORTANT]
> **セキュリティ脆弱性を発見したと思われる場合、悪用可能な詳細、authentication file、token、server credential、完全な PoC を public GitHub Issue、Discussion、Pull Request、スクリーンショット、ログで公開しないでください。**
>
> repository を Public に切り替えた後、正式な `v1.0.0` release と public promotion の前に **GitHub Private Vulnerability Reporting** を有効にし、本プロジェクトの正式な private vulnerability reporting channel として使用します。

---

## サポート対象バージョン

Codex Window Anchor の security fix は主に**最新 stable release**を対象にします。

| バージョン | セキュリティサポート |
| --- | --- |
| 最新 stable `v1.x` release | サポート |
| それ以前の `v1.x` release | 個別保守は保証しない。最新 stable への upgrade を推奨 |
| pre-release / development snapshot | stable security-supported release として扱わない |
| 未公開の local modification | 正式サポート範囲外 |

最初の stable `v1.0.0` release 前は、repository 上の pre-release content を stable-version security maintenance commitment と解釈しないでください。

古い version に影響する問題が最新 stable version で既に修正されている場合、maintainer は各旧 version への backport ではなく upgrade を求めることがあります。

---

## セキュリティ脆弱性の報告

### 推奨: GitHub Private Vulnerability Reporting

GitHub repository を Public に切り替えた後、Repository Settings で **Private Vulnerability Reporting** を有効にし、`v1.0.0` release 前に private report entry point が利用できることを確認してください。

有効化後は、repository の現在の **Security / Security and quality** 領域から:

```text
Report a vulnerability
```

を選び、private に報告してください。

GitHub は `SECURITY.md` で supported versions と private reporting method を明示することを推奨しており、Private Vulnerability Reporting は repository-level の private channel を提供します。

### public channel で報告しない

次を使用しないでください。

- Public Issue;
- Discussion;
- Pull Request;
- README comment;
- public social media;
- 機密情報を含む screenshot / log link.

Private Vulnerability Reporting がまだ有効でない場合、**脆弱性詳細を公開しないでください**。Private → Public への切り替えが先に必要な場合はありますが、正式な `v1.0.0` release、public promotion、一般ユーザーへの利用案内前に private vulnerability channel を設定してください。

### 報告に含める情報

問題が本プロジェクトの scope か判断しやすくするため、可能な範囲で以下を含めてください。

- 影響を受ける Codex Window Anchor version;
- Linux distribution / version;
- CPU architecture;
- systemd version;
- Codex CLI version;
- Installer / login / runtime / Schedule / Timer / Uninstall のどの層か;
- secret を除去した完全な error output;
- 最小再現手順;
- expected behavior と actual behavior;
- 想定する security impact;
- PoC がある場合は private reporting channel 内だけで共有.

脆弱性を証明するために、自分に属さない account、host、token、data へアクセスしないでください。

---

## セキュリティ範囲

### 通常 scope 内となる例

supported version で再現できる場合、次のような問題は通常 Codex Window Anchor の security scope に入ります。

- Installer が project に属さない user/group/path/service を誤って takeover する;
- Schedule helper が untrusted script や argument 経路を通じて意図しない root privilege を得る;
- systemd service が root または誤った identity で Codex を実行する;
- Anchor runtime が通常ユーザーによって予期せず置換・改変されても受け入れられる;
- ownership / metadata / SHA-256 check を bypass して unrelated system resource を削除できる;
- default uninstall が `--purge-user` なしで dedicated home や ChatGPT authentication state を削除する;
- `--purge-user` が installation metadata と一致しない同名 user を削除できる;
- project script が ChatGPT credential、token、その他 secret を repository-managed public file に書き込む;
- Runner が除外すべき API Key、access token、provider endpoint、その他 sensitive runtime input を意図せず継承する;
- path traversal、symlink、alias/drop-in、race condition により project 所有外 file や systemd namespace を変更できる;
- project-generated log/output が authentication secret を意図せず漏えいする;
- Installer / Uninstaller の fail-closed boundary を bypass して privilege escalation や destructive deletion が可能になる.

これは完全な一覧ではありません。中心的な判断基準は:

> **その問題が、Codex Window Anchor 自身が宣言する privilege、identity、credential、ownership、resource boundary を破るかどうか。**

です。

### 通常 project vulnerability ではないもの

以下は一般に Anchor 自身ではなく upstream provider や host administrator の問題です。

- OpenAI / ChatGPT / Codex server-side vulnerability;
- OpenAI account compromise;
- Anchor glue code と無関係な upstream Codex CLI vulnerability;
- OpenAI による model、Usage Window、quota、authentication、plan behavior の変更;
- user 自身が `auth.json`、token、SSH key、password を public repository に公開した;
- Anchor install 前から host が root compromise されていた;
- user 自身が SELinux を無効化、`chmod 777`、project root-owned file の改変を行い期待 boundary を壊した;
- firewall、VPN、proxy、DNS、enterprise TLS、一般的な host network configuration;
- unsupported Linux distribution 上の compatibility difference;
- user が systemd unit / Timer / metadata を手動変更した後の予期しない behavior;
- 「Anchor が quota を増やさない」「allowance を reset しない」といった product behavior complaint.

ただし upstream Codex CLI vulnerability が **Anchor 特有の invocation pattern によって新たな悪用可能影響を生む**場合は、本プロジェクトへ private に先に報告し、Anchor がどう risk を増幅・変更するか説明して構いません。

---

## Credential と Authentication State

Public V1 の標準経路は ChatGPT account authentication を使い、API Key を Anchor configuration に書く必要はありません。

Dedicated Codex Home:

```text
/home/codex-anchor/.codex
```

OpenAI の現在の Codex documentation では、sign-in state は OS credential store、または file-based credential storage の場合:

```text
~/.codex/auth.json
```

に保存されることがあります。

file-based storage を使う場合、`auth.json` には access token が含まれるため、**password のように保護**してください。

そのため:

- `auth.json` を commit しない;
- GitHub Issue に貼らない;
- Discussion に upload しない;
- chat history に入れない;
- `anchor.conf` に内容を copy しない;
- “diagnostic data” として public attachment にしない.

project `.gitignore` は `.codex/`、`auth.json`、credentials、tokens、secrets、一般的な SSH private-key pattern を引き続き除外対象にするべきです。

### Device Code Login

remote/headless Linux の標準ドキュメント経路:

```bash
codex login --device-auth
```

OpenAI の現在の documentation では Device Code Authentication を remote/headless authentication path として利用できます。利用可否は ChatGPT personal security setting または Workspace permissions に依存する場合があります。

Device Code 自体も public Issue / screenshot に出さないでください。

---

## Runtime セキュリティ境界

Anchor は host user PATH の変化し得る `codex` を継続参照しません。

Installer は user が既にインストールした standalone Codex executable から:

```text
/usr/local/bin/codex-window-anchor
```

を作成し、その snapshot を検証します。Public V1 の現在の check:

- regular file;
- executable;
- native Linux ELF;
- non-privileged `--version` execution;
- Anchor が必要とする `codex exec` options;
- root ownership;
- SHA-256 fingerprint;
- systemd execution probe.

Installer は runtime の**form と capability**を検証しますが、publisher provenance を独自に証明しないことを明示します。

そのため user は OpenAI 公式チャネルから Codex を取得する必要があります。`--codex-bin` を「任意 executable が安全」という意味に解釈しないでください。

---

## Privilege boundary

### Anchor request 自体は root で実行しない

systemd service:

```text
User=codex-anchor
Group=codex-anchor
```

さらに:

```text
NoNewPrivileges=true
PrivateTmp=true
UMask=0077
```

を使用します。

実 Codex request は dedicated non-root identity で実行されます。

root が必要なのは system-level privilege を要する操作だけです。

- root-owned runtime / runner / unit file の install;
- `/etc/systemd/system` への書き込み;
- system Timer の enable/disable;
- verified uninstall / purge.

### Schedule helper の bounded self-elevation

public command:

```text
/usr/local/bin/codex-window-anchor-schedule
```

は通常ユーザーが直接実行できます。

systemd Timer update に root が必要な場合、helper はまず expected formal helper に resolve すること、root-owned、mode `755`、project ownership marker があることを確認します。その後だけ:

```text
/usr/bin/sudo
```

で original arguments を再実行します。

次を行いません。

- sudoers rule を作成;
- `/etc/sudoers` を変更;
- PATH を変更;
- arbitrary repository script に general privilege escalation entry point を提供.

formal installation path / ownership を確認できない場合、elevation を拒否します。

---

## Runtime environment boundary

`run-anchor.sh` は:

```text
/usr/bin/env -i
```

を使用して明示的 environment を構築し、systemd manager environment 全体を継承しません。

Public V1 は通常 environment の次のような値を Anchor runtime に自動で入れません。

```text
OPENAI_API_KEY
CODEX_API_KEY
CODEX_ACCESS_TOKEN
OPENAI_BASE_URL
OPENAI_FEDERATION_RULE_ID
OPENAI_IDENTITY_TOKEN_FILE
```

および allowlist にないその他 variables。

Runner は basic runtime identity/path/state variables を再構築し、一般的な network / CA variables を限定的に許可します。

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

既存 proxy / CA environment を runtime に許可することは、Anchor が任意 proxy を設定・信頼するという意味ではありません。network endpoint と host proxy policy は administrator の責任です。

---

## Codex execution boundary

Public V1 の各 Anchor:

```text
--ephemeral
--ignore-user-config
--ignore-rules
--skip-git-repo-check
--sandbox read-only
```

を使用し、Codex に `OK` だけを返し、file inspection、command execution、web browsing、tool use をしないよう求める固定最小 prompt を送ります。

これは Anchor 自身の task surface を減らしますが、absolute sandbox guarantee と表現すべきではありません。Codex CLI、operating system、systemd、OpenAI service はそれぞれ独立した trust boundary です。

**各 Anchor は実際の Codex リクエストです。アプリケーションレベルの入力と出力は非常に小さく、タスク全体も可能な限り軽量になるよう設計されていますが、実際の token 計測は Codex CLI、モデル、OpenAI 側のコンテキストによって変動します。**

---

## systemd と Schedule boundary

Installer 完了直後:

```text
no ChatGPT login
no Anchor request
no generated Timer
no enabled / active Timer
```

Schedule helper 完了直後:

```text
generated Timer
disabled / inactive
no Anchor request
```

自動 scheduling が始まるのは user が明示的に:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

を実行した後だけです。

Schedule timezone は Timer の `OnCalendar=` に書かれ、system global timezone を変更しません。

Timer:

```text
Persistent=false
```

なので server offline 中に missed Anchor が後から自動 catch-up されません。

---

## Installer の host boundary

Public V1 Installer は次を自動変更しません。

- firewall;
- proxy;
- VPN;
- swap;
- `/etc/fstab`;
- host global timezone;
- SELinux enforcement;
- unrelated services;
- `/etc/sudoers`.

互換性修正として:

```text
chmod 777
setenforce 0
```

を使いません。

full clean integration validation は **SELinux Enforcing** で行っています。

---

## Safe uninstall

デフォルト:

```bash
sudo ./scripts/uninstall.sh
```

は「同名 file を全部削除」ではありません。

Uninstaller は:

- installation metadata;
- ownership marker;
- file ownership/mode;
- runtime SHA-256;
- user/group;
- UID/GID;
- home path / ownership;
- exact systemd state;

に依存します。

project-owned だと積極的に識別できる managed resource だけを削除します。

default uninstall が保持するもの:

```text
codex-anchor user
/home/codex-anchor
ChatGPT authentication state
user's original official/global Codex CLI
system journal history
firewall / proxy / SELinux
swap / /etc/fstab
unrelated files/services
```

ownership、identity、runtime fingerprint、systemd state に ambiguity があれば resource を保持して fail closed する場合があります。

### `--purge-user`

次を明示的に実行した場合だけ:

```bash
sudo ./scripts/uninstall.sh --purge-user
```

dedicated user/home/authentication state の destructive cleanup に入ります。

Purge は identity evidence を再検証し、デフォルトでは対話確認します。対象が project 作成の exact identity と証明できない場合、username が同じというだけで `userdel -r` を実行せず削除を拒否します。

---

## Secret を置いてはいけない場所

次へ secret を書いたり commit したりしないでください。

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

特に確認:

- `auth.json`;
- ChatGPT access / refresh token;
- API Key;
- SSH private key;
- VPS root password;
- private proxy subscription;
- proxy credential;
- unrelated X-ray/VPN/service credential;
- local `.env`;
- shell history に誤って残った secret.

公開前にログを手動確認してください。

---

## Usage Window / quota は security guarantee ではない

Codex Window Anchor は OpenAI usage limit を作成、増加、reset、bypass しません。

本プロジェクトでは Usage Window behavior を:

```text
observed behavior
observed usage-window anchoring
```

とだけ表現し、次のようには表現しません。

```text
OpenAI guaranteed reset
quota multiplier
extra allowance
limit bypass
unlimited Codex
```

OpenAI は model、plan、authentication、limit、Usage Window behavior を変更できます。これら product change は Codex Window Anchor の security vulnerability ではありません。

---

## Responsible disclosure

private channel で reproducible vulnerability を報告した場合、maintainer が:

```text
triage
→ reproduce
→ assess scope
→ prepare fix
→ release
→ disclosure
```

を行う合理的な時間を確保してから、完全な exploit details を公開してください。

Public V1 は **固定の 24/48/72-hour response SLA を約束せず、declared bug bounty program もありません**。実際に SLA / bounty を設ける前に documentation で存在を示唆しません。

security fix と必要な public disclosure は vulnerability の性質に応じて GitHub Security Advisory / Release Notes で扱えます。

---

## 関連ドキュメント

- [インストールと設定](docs/ja/INSTALLATION.md)
- [トラブルシューティング](docs/ja/TROUBLESHOOTING.md)
- [仕組み](docs/ja/HOW_IT_WORKS.md)
- [README に戻る](README.ja.md)

Codex Window Anchor は独立したプロジェクトであり、OpenAI 公式製品ではありません。
