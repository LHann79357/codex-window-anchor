# Codex Window Anchor — 仕組み

このドキュメントでは、Codex Window Anchor Public V1 の中核アーキテクチャ、1 回の Anchor のライフサイクル、そして runtime、認証、Schedule、アンインストールを別々の境界として設計している理由を説明します。

デプロイだけが目的なら [INSTALLATION.md](INSTALLATION.md) を参照してください。問題が発生した場合は [TROUBLESHOOTING.md](TROUBLESHOOTING.md) を参照してください。

---

## 設計目標

Codex Window Anchor は新しい Codex client でも、常駐 Agent でもありません。小さく監査可能な **systemd scheduling wrapper** です。ユーザーは先に OpenAI 公式 standalone Codex CLI をインストールし、Anchor Installer はその executable から独立した runtime snapshot を作成します。その後 systemd がユーザー自身の選んだ時刻に one-shot service を起動し、専用の非 root identity で 1 回の最小実 Codex リクエストを送り、完了後に終了します。

Public V1 は 6 つの原則を中心に設計されています。

| 原則 | 意味 |
| --- | --- |
| Official Codex first | Anchor は Codex をダウンロード・再配布しない |
| Explicit opt-in | install、sign-in、Schedule generation、enable を分離 |
| Dedicated identity | 専用 `codex-anchor` user と Codex Home を使用 |
| Small runtime surface | Web dashboard、database、常駐 daemon を不要にする |
| Fail closed | ownership / identity / state を確認できなければ推測して変更しない |
| Easy to stop/remove | Timer は独立して停止でき、default uninstall は確認済み managed resources のみ削除 |

Public V1 は「あらゆる操作を自動化する」ことを目的にしていません。credential、実リクエスト、system-level scheduling に関わる操作には、ユーザーの明示的な authorization point を残します。

---

## アーキテクチャ概要

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

次回実行を待つ Anchor process は常駐しません。待機を担当するのは systemd Timer で、Codex process は trigger された間だけ存在します。

### 主なコンポーネント

| コンポーネント | 役割 |
| --- | --- |
| `install.sh` | managed identity、runtime、systemd 基盤を作成 |
| `/usr/local/bin/codex-window-anchor` | 独立した root-owned Codex runtime snapshot |
| `run-anchor.sh` | 各 Anchor の固定実行 entrypoint |
| `anchor.conf` | 非 secret runtime configuration |
| `/home/codex-anchor/.codex` | dedicated Codex Home / authentication state |
| `codex-window-anchor.service` | 1 request 用 systemd oneshot service |
| `codex-window-anchor-schedule` | user times を検証して Timer を生成 |
| `codex-window-anchor.timer` | ユーザー自身が選択し明示 enable する Schedule |
| `install.meta` | ownership / identity / runtime evidence |
| `uninstall.sh` | evidence に基づいて project resources を安全に削除 |

---

## Runtime isolation

### なぜユーザー Home の `codex` を直接実行しないのか

最も単純な設計なら、systemd からユーザー既存の Codex を直接実行できます。しかし Public V1 はそうしていません。

実際の AlmaLinux 環境で、interactive shell では実行できる executable が、同じ path から systemd + SELinux でも必ず実行できるとは限らないことが確認されました。また Anchor が常にユーザー PATH の `codex` を参照すると、ホスト側の通常 update によって、自動処理の runtime が Anchor 側で再検証されないまま変わる可能性があります。

そこで Installer は、ユーザーが明示的に選択した standalone Codex executable から:

```text
/usr/local/bin/codex-window-anchor
```

を作成します。

この snapshot は root-owned で、インストール後は元の Codex path と独立します。

Installer はその後:

- native Linux ELF であること;
- non-privileged identity で `--version` が実行できること;
- Anchor が依存する `codex exec` options をサポートすること;
- SHA-256 fingerprint を計算・記録できること;
- systemd から実際に実行できること;

を検証します。

`restorecon` が利用可能なら期待される SELinux context を復元し、transient `systemd-run` probe で最終実行 path を検証します。

結果:

```text
ユーザー側の通常 codex を更新
        ≠
Anchor runtime が自動変更
```

となります。

runtime snapshot 方式は automatic upgrade の利便性を下げる代わりに、より明確で繰り返し検証できる自動実行境界を提供します。

---

## Identity と Authentication boundary

Anchor request は root で実行されず、Installer を実行した Linux account を直接使用しません。

Installer は専用 identity:

```text
user:  codex-anchor
group: codex-anchor
home:  /home/codex-anchor
```

を使用します。

systemd service はこの user/group で動き、ChatGPT authentication state は:

```text
CODEX_HOME=/home/codex-anchor/.codex
```

を使用します。

そのため:

```text
host user の Codex environment
        │
        └──── 直接再利用しない ────┐

codex-anchor dedicated Home
        │                          │
        ├── ChatGPT auth           │
        └── Anchor Codex state
```

という分離になります。

Installer は他ユーザーの `auth.json` をコピーせず、自動 ChatGPT login も行いません。ユーザー自身が `codex-anchor` を明示的に認証します。

root 権限は root-owned files の install、systemd Timer generation、system Timer の enable/disable など、実際に system-level privilege が必要な操作だけに使います。実 Codex request は non-root `codex-anchor` identity で実行されます。

---

## 1 回の Anchor がどう動くか

manual trigger / Timer trigger のどちらでも、最終的に:

```text
/usr/local/libexec/codex-window-anchor/run-anchor.sh
```

へ入ります。

Runner は:

```text
/etc/codex-window-anchor/anchor.conf
```

を読みます。

ここに保存されるのは非 secret runtime information だけです。

```text
CODEX_BIN=/usr/local/bin/codex-window-anchor
CODEX_MODEL=gpt-5.6-luna
```

ChatGPT token や API Key は保存しません。

Runner は Codex 起動前に runtime、model、dedicated Home、Codex Home、自身の state directories を確認します。その後 systemd manager environment 全体を継承せず:

```text
/usr/bin/env -i
```

を使って明示的な environment を構築します。

基本 allowlist:

```text
HOME
USER
LOGNAME
SHELL
PATH
CODEX_HOME
CODEX_SQLITE_HOME
```

既存の proxy / CA 環境で必要になり得る network variables も限定的に許可します。

```text
HTTP_PROXY / HTTPS_PROXY / ALL_PROXY / NO_PROXY
CODEX_CA_CERTIFICATE
SSL_CERT_FILE / SSL_CERT_DIR
CURL_CA_BUNDLE / REQUESTS_CA_BUNDLE
```

これにより `OPENAI_API_KEY`、`CODEX_ACCESS_TOKEN`、`OPENAI_BASE_URL` などの provider/workload identity switch を意図せず Anchor runtime に持ち込むことを避けつつ、管理者が既に正しく設定した enterprise proxy / CA environment を壊さないようにします。

---

## Codex invocation

Runner の中核実行 semantics:

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

各 option は Public V1 の境界に対応します。

- `--ephemeral`: 各実行を短命で独立した task にする;
- `--ignore-user-config`: 通常ユーザーの Codex config で Anchor behavior を変えない;
- `--ignore-rules`: user/project rules で task が拡張されない;
- `--skip-git-repo-check`: runtime work directory を Git repository 必須にしない;
- `--sandbox read-only`: Anchor の目的を server file modification にしない;
- `--color never`: journald に terminal color output を不要とする.

Installer は install 時点で選択 runtime がこれら options をサポートするか確認します。contract を満たさない場合は install を停止し、将来の Timer trigger まで failure を持ち越しません。

固定 prompt:

```text
Reply exactly with OK. Do not inspect files, run commands, browse the web, use tools, or perform any additional work.
```

目的は Codex に code task を実行させることではなく、application-level work を明確な最小 request に縮小することです。

**各 Anchor は実際の Codex リクエストです。アプリケーションレベルの入力と出力は非常に小さく、タスク全体も可能な限り軽量になるよう設計されていますが、実際の token 計測は Codex CLI、モデル、OpenAI 側のコンテキストによって変動します。**

---

## systemd execution model

### Oneshot service

`codex-window-anchor.service`:

```text
Type=oneshot
User=codex-anchor
Group=codex-anchor
WorkingDirectory=/var/lib/codex-window-anchor/work
ExecStart=/usr/local/libexec/codex-window-anchor/run-anchor.sh
```

さらに:

```text
NoNewPrivileges=true
PrivateTmp=true
UMask=0077
TimeoutStartSec=180
```

を使用します。

1 回の trigger:

```text
systemd starts service
→ runner execs Codex
→ one request completes
→ process exits
→ service becomes inactive
```

成功後に:

```text
inactive (dead)
```

となるのは正常です。daemon crash ではありません。

### なぜ常駐 daemon を使わないのか

Anchor work は選択された時刻だけ存在します。専用 process が 24/7 resident で待ち続ける必要はありません。「待つ」役割を systemd Timer に任せることで、persistent process、state management、long-running complexity を減らします。

---

## Schedule と explicit opt-in

Public V1 には公開デフォルト実行時刻がありません。Schedule はユーザー自身が決め、多くの時刻を設定すればその分多くの実 Codex requests が発生します。

Installer 完了直後には:

```text
/etc/systemd/system/codex-window-anchor.timer
```

自体が存在しません。

ユーザーが:

```bash
codex-window-anchor-schedule \
  --timezone AREA/CITY \
  --time HH:MM
```

を実行して初めて、Schedule helper が IANA timezone、厳密な 24-hour time、完全な install state、dedicated identity、managed files、runtime fingerprint を検証し、Timer を生成します。

各時刻は:

```text
OnCalendar=*-*-* HH:MM:00 AREA/CITY
```

になります。

生成 Timer:

```text
AccuracySec=30s
RandomizedDelaySec=0
Persistent=false
Unit=codex-window-anchor.service
```

`Persistent=false` により、server recovery 後に missed Schedule を catch-up しません。次回正常時刻を待ちます。

timezone は `OnCalendar=` 内にあり、host global timezone を変更しません。

### Bounded self-elevation

`/etc/systemd/system/...` への書き込みには root が必要ですが、public CLI は:

```bash
codex-window-anchor-schedule ...
```

のままです。

helper は system write が必要な場合だけ elevate します。その前に current executable が:

```text
/usr/local/bin/codex-window-anchor-schedule
```

へ resolve し、root-owned、mode `755`、regular managed file であることを確認します。

その後だけ:

```text
/usr/bin/sudo
```

で同じ original arguments を再実行します。

次を変更しません。

```text
/etc/sudoers
sudoers.d
user PATH
```

### Schedule generation 後も自動実行しない理由

Schedule helper lifecycle:

```text
validate
→ generate
→ verify
→ daemon-reload
→ prove disabled/inactive
```

Timer を enable/start しません。

既存 managed Timer がある場合も:

```text
disabled
inactive
```

だと証明できるときだけ置換します。

configuration file を running automatic task に変える明示的 authorization point は:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

だけです。

---

## Ownership evidence と fail-closed

system-level uninstall で危険なのは、「名前が同じ」を ownership の証拠と誤認することです。

Installer は:

```text
/etc/codex-window-anchor/install.meta
```

を維持します。

ここには project ownership と identity/runtime evidence が入り、例として:

```text
format version
installation state
service user / group / home
UID / GID
runtime SHA-256
```

があります。

ChatGPT credential は保存しません。

Schedule helper と Uninstaller は metadata、ownership marker、file owner/mode、identity、runtime fingerprint、systemd namespace/state を組み合わせて、対象がまだ project-managed resource か判断します。

Public V1 の削除ルールは:

```text
名前が codex-window-anchor
→ 削除
```

ではなく:

```text
本プロジェクト所属だと積極的に証明できる
→ 変更/削除を許可
```

です。

alias、drop-in、UID/GID mismatch、runtime hash change、ownership ambiguity などがあれば、state を保持して fail closed する方を優先します。

そのため abnormal uninstall 時に `rm -rf` で「見た目だけきれい」にせず、metadata や residual resource が残る場合があります。

---

## アンインストールと認証保持

デフォルト:

```bash
sudo ./scripts/uninstall.sh
```

では verified Anchor Timer/service/runner/schedule helper/runtime snapshot/configuration/empty runtime directories を削除しますが:

```text
codex-anchor user
/home/codex-anchor
ChatGPT authentication state
```

と minimal verified identity metadata は保持します。

認証はユーザー自身が明示的に作成した価値ある state です。通常 uninstall が副作用で破壊すべきではなく、exact identity が一致する場合は将来の verified reinstall で認証を再利用できます。

再利用は username だけでは判断しません。Installer は:

```text
username
UID
group
GID
home path
home ownership
preserved metadata
```

を再検証し、exact match のみ受け入れます。

dedicated identity と認証も明示的に削除する場合:

```bash
sudo ./scripts/uninstall.sh --purge-user
```

を使います。

Purge は別の破壊的意図です。削除前に identity を再検証し、デフォルトでは対話確認します。

---

## System boundary

Codex Window Anchor は作用範囲を意図的に小さく保ちます。

### project が管理するもの

```text
dedicated codex-anchor identity
Anchor runtime snapshot
Anchor runner/config/state
Anchor service
user-generated Anchor Timer
installation metadata
```

### project が自動管理しないもの

```text
OpenAI Codex installation/upgrades
ChatGPT plan / quota
firewall
VPN
host proxy
system global timezone
swap / /etc/fstab
global journald retention
other systemd services
web dashboard / database
```

Runner が限定的な proxy / CA environment variables を引き継げるのは、既存 network setup と互換にするためです。Anchor が proxy を作成・管理するという意味ではありません。

SELinux も同じです。Public V1 は Enforcing で検証され、Installer は正常な system path/context と systemd probe を使います。互換性のために:

```text
setenforce 0
disable SELinux
chmod 777
```

を使いません。

---

## 完全なライフサイクル

「公式 Codex CLI が既にインストール済み」から:

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

一時停止:

```text
disable --now
→ Timer disabled/inactive
→ runtime/auth remain
```

デフォルト uninstall:

```text
managed runtime/service/timer removed
→ dedicated identity/auth preserved
```

明示 purge:

```text
managed resources removed
→ verified dedicated identity/home/auth removed
```

---

## 重要パス

| 用途 | パス |
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

## 関連ドキュメント

- [インストールと設定](INSTALLATION.md)
- [トラブルシューティング](TROUBLESHOOTING.md)
- [セキュリティ](../../SECURITY.ja.md)
- [README に戻る](../../README.ja.md)

Codex Window Anchor は独立したプロジェクトであり、OpenAI 公式製品ではありません。このドキュメントは Public V1 の現在の実装を説明します。Usage Window は観測された挙動であり、OpenAI は将来 Codex CLI、認証、model、plan limits、関連 usage behavior を変更する可能性があります。
