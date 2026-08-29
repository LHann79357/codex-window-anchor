# Codex Window Anchor — トラブルシューティング

このドキュメントは Codex Window Anchor Public V1 のインストール、ChatGPT ログイン、手動 Anchor、Schedule、systemd Timer、アンインストールに関する問題の切り分けに使います。

標準インストールがまだ完了していない場合は、先に [INSTALLATION.md](INSTALLATION.md) に従ってください。ここでは完全なデプロイ手順を繰り返さず、「特定のステップが期待どおり動かない」場合だけを扱います。

> [!IMPORTANT]
> 「とりあえず動かす」ために SELinux を無効化したり、`chmod 777` を使ったり、不明な systemd ファイルを削除したり、`auth.json` を手動編集したり、API Key を Anchor configuration に書いたりしないでください。
>
> Public V1 の Installer / Schedule / Uninstall は fail-closed を基本にしています。ファイル、ユーザー、runtime、systemd state が本プロジェクトのものだと安全に確認できない場合、**処理を拒否すること自体が安全保護であり、チェックを強制的に回避すべきという意味ではありません。**

## まずここから確認

多くの問題は、次のコマンドで「Codex 本体」「認証」「Anchor service」「Timer」のどの層にあるか切り分けられます。

```bash
# システム
uname -a
systemctl --version

# ホスト上の公式 Codex
command -v codex
codex --version

# Anchor 認証状態
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status

# Anchor service
sudo systemctl status codex-window-anchor.service --no-pager -l
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager

# Timer（Schedule 設定後のみ）
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer --all --no-pager
systemctl cat codex-window-anchor.timer
```

**元のエラーメッセージを全文保存**してください。OpenAI のログインやリクエスト段階で失敗する場合は、[OpenAI Status](https://status.openai.com/) も確認します。Codex の認証、アクセス、サービス障害が Anchor 側の問題とは限りません。

---

## よくある問題

| 症状 | まず確認 |
| --- | --- |
| Codex 公式 installer が `tar is required` と表示 | [`tar` 不足](#codex-公式-installer-が-tar-is-required-と表示) |
| Anchor Installer が Codex を見つけられない | [Codex CLI not found](#installer-が-codex-cli-was-not-found-と表示) |
| native ELF ではない / required option がないと言われる | [Codex runtime が V1 要件を満たさない](#installer-が選択した-codex-runtime-を拒否する) |
| Device Code ログインに失敗 | [ChatGPT / Device Code](#device-code-ログインに失敗する) |
| `systemctl start` が失敗 | [手動 Anchor](#手動-anchor-が失敗する) |
| service が `inactive (dead)` | [正常かどうか](#service-が-inactive-dead-と表示される) |
| systemd が Codex を実行できない | [SELinux / systemd execution](#systemd-が-anchor-runtime-を実行できない) |
| Schedule helper が Timer enabled/active と表示 | [先に Timer を停止](#schedule-helper-が実行中-timer-の変更を拒否する) |
| timezone / time が拒否される | [Schedule 引数](#timezone-または-time-引数が拒否される) |
| Timer はあるが自動実行されない | [Timer trigger](#timer-が期待どおり動かない) |
| サーバー復旧後に補完実行されない | [設計どおり](#取り逃した-anchor-が補完実行されない) |
| Uninstaller が削除を拒否 | [Safe uninstall](#uninstaller-が続行を拒否するまたは-resource-を保持する) |
| インストール中断後に再インストールできない | [Partial installation](#インストールが途中で失敗し再インストールできない) |
| 制限ネットワーク / proxy で失敗 | [Network / proxy](#network-または-proxy-環境で-codex-に接続できない) |

---

## Codex 公式 installer が `tar is required` と表示

### 症状

OpenAI 公式 standalone Codex CLI のインストール中に:

```text
tar is required to install Codex.
```

のように表示されます。

### 原因

AlmaLinux Minimal などの最小構成では `tar` が標準で入っていない場合があります。これは standalone Codex installer の前提依存関係であり、Anchor Installer の障害ではありません。

### 解決

AlmaLinux 8.10:

```bash
sudo dnf install -y git curl tar
```

その後、OpenAI 公式 Codex installer を再実行:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

確認:

```bash
codex --version
command -v codex
```

ホストユーザーで公式 standalone Codex が正常に動いてから:

```bash
sudo ./scripts/install.sh
```

を実行します。

---

## Installer が `Codex CLI was not found` と表示

### 症状

Anchor Installer:

```text
Codex CLI was not found. Install the official standalone Codex CLI first, or use --codex-bin PATH
```

### まず確認

```bash
command -v codex
codex --version
```

ここで失敗するなら、Anchor より先に公式 Codex のインストールを修正します。

Codex は存在するが Installer が安全に発見できる場所にない場合:

```bash
readlink -f "$(command -v codex)"
```

を確認し、**公式 standalone executable の絶対パス**を指定します。

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/codex
```

Installer は通常 `PATH` の `codex` を確認します。`sudo` 環境で見つからない場合は、呼び出し元ユーザーの:

```text
~/.local/bin/codex
```

も確認します。

> [!IMPORTANT]
> `--codex-bin` は「任意 binary を受け入れる」ための回避オプションではありません。
>
> Installer は file form と CLI capabilities を検証しますが publisher provenance を代わりに証明しません。OpenAI 公式チャネルから取得した standalone Codex executable だけを選択してください。

---

## Installer が選択した Codex runtime を拒否する

### 例

```text
staged Codex snapshot is not a native Linux ELF executable
```

または:

```text
staged Codex CLI does not support required option: ...
```

### 意味

Public V1 はあらゆる `codex` wrapper への適応を目的としていません。Installer は root-owned runtime snapshot を作成し、次を要求します。

- regular executable file;
- native Linux ELF;
- 非特権ユーザーで `--version` 実行可能;
- Anchor が使う `exec` options をサポート.

npm/node wrapper、アーキテクチャ違い、古い/非互換 CLI、別の同名プログラムは拒否される場合があります。

### 対処

```bash
command -v codex
codex --version
file "$(command -v codex)"
```

を確認し、OpenAI 公式チャネルから現在の standalone Codex CLI を再インストールします。ELF check や required-option check を回避するよう Installer を改変しないでください。

複数の Codex がある場合:

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/official/codex
```

で正しいものを明示します。

---

## Device Code ログインに失敗する

Public V1 の remote/headless Linux 標準経路:

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login --device-auth
```

OpenAI の現在の認証ドキュメントでは Device Code Authentication を remote/headless 環境で利用できます。利用可否は個人セキュリティ設定や Workspace permissions に依存する場合があります。また file-based `auth.json` はパスワードのように保護する必要があります。

### まず確認

1. ChatGPT アカウントに Codex 利用権限がある。
2. 個人設定または Workspace policy で Device Code Login が許可されている。
3. サーバーから OpenAI/Codex に接続できる。
4. OpenAI で Codex authentication incident が発生していない。

公式リンク:

- [Codex Authentication](https://developers.openai.com/codex/auth)
- [OpenAI Status](https://status.openai.com/)

その後:

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status
```

を再確認します。

> [!WARNING]
> login log の token、`auth.json` 内容、Device Code を Issue に投稿しないでください。
>
> OpenAI は headless 用に他の fallback も案内していますが、認証キャッシュのコピーや SSH callback forwarding が含まれる場合があります。それらは Codex Window Anchor の標準インストール経路ではありません。必要な場合は OpenAI の最新公式 Authentication documentation に直接従い、不明なサードパーティ手順で認証情報を扱わないでください。

---

## 手動 Anchor が失敗する

手動検証:

```bash
sudo systemctl start codex-window-anchor.service
```

失敗した場合、Timer を enable しないでください。

まず:

```bash
sudo systemctl status codex-window-anchor.service --no-pager -l
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

を確認します。

### 1. 認証は存在するか

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status
```

無効なら Device Code Login をやり直します。

### 2. Anchor configuration は存在するか

```bash
sudo cat /etc/codex-window-anchor/anchor.conf
```

通常は少なくとも:

```text
CODEX_BIN=/usr/local/bin/codex-window-anchor
CODEX_MODEL=...
```

のような内容があります。

これは**非 secret runtime config**です。API Key や ChatGPT token を追加しないでください。

### 3. runtime は存在するか

```bash
ls -l /usr/local/bin/codex-window-anchor
/usr/local/bin/codex-window-anchor --version
```

runtime が欠損または外部変更されている場合、binary を手動で上書きしないでください。[INSTALLATION.md](INSTALLATION.md) の runtime update / reinstall flow で検証可能状態を復元します。

### 4. OpenAI 側エラーか

journal に authentication、capacity、service unavailable などの remote error がある場合:

[OpenAI Status](https://status.openai.com/)

も確認します。

Codex の認証、アクセス、model capacity の remote incident は発生しうるため、自動的に Anchor の障害と判断しないでください。

---

## Service が `inactive (dead)` と表示される

多くの場合**正常です**。

`codex-window-anchor.service` は:

```text
Type=oneshot
```

です。

1 回の Anchor が完了すると process は終了し、service は:

```text
inactive (dead)
```

に戻ります。

これは正常な lifecycle です。

`active (running)` が維持されないことを失敗判定に使わないでください。

最近の実行:

```bash
sudo journalctl -u codex-window-anchor.service -n 50 --no-pager
```

または:

```bash
sudo systemctl status codex-window-anchor.service --no-pager -l
```

を確認し、最新 invocation が正常終了したか、journal に実エラーがあるかを見ます。

---

## systemd が Anchor runtime を実行できない

### 典型的な Installer error

```text
systemd could not execute the Codex runtime; inspect the system journal and SELinux audit log
```

### なぜ起こるか

実際の AlmaLinux/RHEL-family 環境では、ユーザー Home にある Codex executable が interactive shell では動いても、同じ場所から systemd/SELinux が実行できないケースがありました。

Public V1 はユーザー Home から Codex を直接実行せず:

```text
/usr/local/bin/codex-window-anchor
```

に root-owned runtime snapshot を作成します。`restorecon` があれば SELinux context を復元し、その後 transient systemd probe で systemd から本当に実行可能か検証します。

### 調査

```bash
getenforce
ls -l /usr/local/bin/codex-window-anchor
ls -Z /usr/local/bin/codex-window-anchor
sudo journalctl -b --no-pager | grep -i -E 'codex-window-anchor|avc|selinux'
```

`restorecon` が利用可能なら、この**project-managed runtime file**の default context を復元できます。

```bash
sudo restorecon -v /usr/local/bin/codex-window-anchor
```

その後 Installer を再実行し、transient probe に再検証させます。

> [!CAUTION]
> 次を使わないでください。
>
> ```bash
> setenforce 0
> chmod 777 /usr/local/bin/codex-window-anchor
> ```
>
> Public V1 は **SELinux Enforcing** で検証済みです。SELinux 無効化や `777` は本プロジェクトの認める修正方法ではありません。

---

## Schedule helper が実行中 Timer の変更を拒否する

### 典型エラー

```text
timer is enabled; pause it first with:
sudo systemctl disable --now codex-window-anchor.timer
```

または Timer が active と表示されます。

### 意図的な挙動

`codex-window-anchor-schedule` は実行中 Schedule を暗黙に停止・置換しません。

先に:

```bash
sudo systemctl disable --now codex-window-anchor.timer
```

確認:

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
```

再設定:

```bash
codex-window-anchor-schedule \
  --timezone YOUR/ZONE \
  --time HH:MM
```

helper 完了後は再び:

```text
disabled / inactive
```

です。

Review 後、ユーザー自身が明示的に再開:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

します。

最終 helper 実装は既存 Timer が disabled/inactive だと証明できる場合だけ置換します。

---

## Timezone または Time 引数が拒否される

### Timezone

利用可能 zoneinfo にある IANA `AREA/CITY` を使います。

```text
America/New_York
Europe/London
Asia/Shanghai
```

一覧:

```bash
timedatectl list-timezones
```

次の形式は使いません。

```text
UTC+8
GMT+8
CST
/path/to/zone
../zone
```

UTC なら:

```text
Etc/UTC
```

### Time

厳密な 24-hour format:

```text
00:00
09:30
23:59
```

次は拒否されます。

```text
9:30
24:00
9 PM
09:60
```

重複時刻は自動的に deduplicate され、sort されます。

Schedule timezone は server global timezone を変更せず、Timer の `OnCalendar=` にのみ書かれます。

---

## Timer が期待どおり動かない

Timer が本当に**明示的に enable されたか**確認します。

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer --all --no-pager
```

まだ:

```text
disabled
inactive
```

なら Schedule generation だけ済み、自動実行は開始していません。

enable:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

実際の Timer:

```bash
systemctl cat codex-window-anchor.timer
```

で `OnCalendar=` の timezone と時刻が自分の設定どおりか確認します。

Timer が active なのに service が失敗する場合:

```bash
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

Timer は service を**trigger するだけ**です。認証、network、model、Codex runtime error は service journal に出ます。

---

## 取り逃した Anchor が補完実行されない

これは Public V1 の設計どおりで、Timer 障害ではありません。

生成 Timer:

```text
Persistent=false
```

予定時刻にサーバーが:

- shutdown;
- reboot 中;
- その他 unavailable;

なら、復旧後に即座に missed Anchor を補完実行しません。

次の通常 Schedule を待ちます。

固定時刻を意図した Anchor が、数時間後の復旧時に予期せず実行されることを避けるためです。

---

## `codex-window-anchor-schedule` が見つからない、または昇格できない

確認:

```bash
command -v codex-window-anchor-schedule
```

Public V1 の配置先:

```text
/usr/local/bin/codex-window-anchor-schedule
```

さらに:

```bash
ls -l /usr/local/bin/codex-window-anchor-schedule
```

を確認します。

Schedule helper の self-elevation は**インストール済み正式 helper**だけを認めます。通常ユーザーが実行するのは:

```bash
codex-window-anchor-schedule ...
```

です。

repository 内の:

```text
scripts/configure-schedule.sh
```

を通常ユーザー用 public command として直接実行しないでください。

Public V1 は `/usr/local/bin` を使うことで、一部システムの `sudo secure_path` が `/usr/local/sbin` を含まないケースに依存しません。最終実装は `/etc/sudoers` や user PATH の変更を必要としません。

正式 helper が欠損、または ownership/mode を外部変更された場合、script の self-check を回避せず、デフォルト uninstall / reinstall で managed state を復元します。

---

## Network または proxy 環境で Codex に接続できない

Codex Window Anchor は **host firewall や proxy configuration を変更しません**。これは Installer の明示的な境界です。

まず次を区別します。

### ホスト上の公式 Codex 自体も接続できない

先に Codex / OpenAI network 問題を解決してください。Anchor は network proxy tool ではありません。

確認:

```bash
codex --version
```

OpenAI status:

[https://status.openai.com/](https://status.openai.com/)

ログイン失敗なら [OpenAI Codex Authentication](https://developers.openai.com/codex/auth) を参照してください。

OpenAI の認証ドキュメントでは enterprise TLS proxy / private CA 環境向けに `CODEX_CA_CERTIFICATE` や `SSL_CERT_FILE` も案内されています。これは Codex network/certificate configuration であり、Anchor が自動管理するものではありません。

### Interactive shell では接続できるが systemd Anchor は失敗

SSH shell で:

```bash
export HTTP_PROXY=...
export HTTPS_PROXY=...
```

しても、そのまま systemd service の persistent environment になるとは限りません。

Public V1 は user shell proxy settings を自動コピーせず、system proxy も変更しません。まず service journal で network error か確認します。

```bash
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

custom proxy、enterprise CA、その他 network injection が必須のサーバーは**高度な環境適応**です。private proxy address、subscription URL、credential を repository、Issue、公開例に書かないでください。

---

## Model が利用できない、または request が拒否される

デフォルト:

```text
gpt-5.6-luna
```

model availability は Codex やユーザー plan によって変わる可能性があります。

journal に model unavailable / capacity / access error が出る場合:

1. OpenAI Status;
2. account に現在その model/Codex 権限があるか;
3. OpenAI の現在の Codex model availability;

を確認します。

Timer 障害と自動判断しないでください。

別の**現在利用可能と確認した model**を使う場合、Public V1 は再インストール時に明示します。

```bash
sudo ./scripts/install.sh --model MODEL
```

デフォルト uninstall は generated Timer を削除するため、runtime/model 再インストール後は schedule helper の再実行、Review、明示 enable が必要です。[INSTALLATION.md](INSTALLATION.md) を参照してください。

---

## インストールが途中で失敗し再インストールできない

Installer は system-level path、service name、service user、home、metadata の collision を確認します。

system mutation 開始後にインストールが完了しない場合:

```text
Installation did not complete.
A partial installation may remain on this host.
```

と表示されます。

この状態で:

```text
rm -rf /etc/codex-window-anchor
userdel -r codex-anchor
systemd file を手動削除して繰り返し retry
```

しないでください。

metadata:

```text
/etc/codex-window-anchor/install.meta
```

があれば、repository directory で:

```bash
sudo ./scripts/uninstall.sh
```

を優先します。

Uninstaller は metadata と ownership evidence を使い、安全に project-managed と識別できる partial resources を削除します。

その後:

```bash
sudo ./scripts/install.sh
```

で再インストールします。

Uninstall も identity/path ambiguity で停止する場合、強制削除せずエラー全文を保存し、後述の Issue diagnostic を使ってください。

---

## Uninstaller が続行を拒否する、または resource を保持する

Uninstaller は「名前が同じ」だけでは削除しません。

確認項目:

- installation metadata;
- managed ownership marker;
- root ownership;
- runtime SHA-256;
- service user / group;
- UID / GID;
- home path / ownership;
- exact systemd state.

安全に確認できない項目があると:

```text
WARNING
```

を表示して resource / metadata を保持するか、fail closed します。デフォルト uninstall は `codex-anchor` user/home/authentication state を**意図的に保持**します。

「きれいな出力」にするため `rm -rf` を使わないでください。

次を保持:

```text
/etc/codex-window-anchor/install.meta
```

し、エラー全文とともに:

```bash
sudo ./scripts/uninstall.sh --help
```

を確認します。

dedicated user/home/auth も削除する目的なら:

```bash
sudo ./scripts/uninstall.sh --purge-user
```

を使います。

> [!NOTE]
> Public V1 は AlmaLinux 8.10 / systemd 239 で uninstall 検証済みで、service absent、stopped、abnormal state を区別できます。
>
> 現在版で uninstall failure が出る場合、エラー全文を保存してください。`systemctl` error を広く無視したり、resource を手動強制削除して check を回避しないでください。

---

## Journal が多いので自動削除できるか

Public V1 は system journal を自動 vacuum しません。

最近の Anchor log:

```bash
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

時間指定なら journald 自身の query options を使い、global history を削除しないでください。

Anchor のためだけに安易に global:

```text
journalctl --vacuum-*
```

を実行しないでください。journal は system services 全体で共有され、cleanup は無関係な service history にも影響します。

デフォルト uninstall も system journal history を保持します。

---

## Issue を開く前に集める情報

Issue 前に**最小・再現可能・機密情報なし**の問題説明を準備し、最低限:

```bash
uname -a
systemctl --version
codex --version
```

を取得します。

Installer 完了後なら:

```bash
/usr/local/bin/codex-window-anchor --version

sudo systemctl status codex-window-anchor.service --no-pager -l
sudo journalctl -u codex-window-anchor.service -n 100 --no-pager
```

Schedule 関連なら:

```bash
systemctl cat codex-window-anchor.timer
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer --all --no-pager
```

Issue には:

- Linux distribution / version;
- CPU architecture;
- systemd version;
- Codex version;
- 実行した**正確な command**;
- 完全な error message;
- install / login / manual run / schedule / timer / uninstall のどこか;
- 安定して再現するか;

を含めてください。

### ログ公開前に機密情報を削除

絶対に投稿しないもの:

- `/home/codex-anchor/.codex/auth.json`;
- ChatGPT access / refresh token;
- Device Code;
- API Key;
- SSH private key;
- root/SSH password;
- 公開したくない VPS IP;
- proxy subscription / proxy credential;
- その他無関係 service の secret.

OpenAI の公式ドキュメントでは file-based `auth.json` に access token が含まれるため、パスワード同様に扱うよう案内されています。

---

## まだ解決しない場合

次の順序が効率的です。

```text
公式 Codex 自体が動くか確認
        ↓
codex-anchor 認証を確認
        ↓
Anchor service を手動実行
        ↓
service journal を確認
        ↓
Schedule / Timer state を確認
        ↓
OpenAI 側 incident か確認
        ↓
機密情報なしの最小 diagnostic を整理
        ↓
GitHub Issue を作成
```

Codex ログイン、account permission、model access、OpenAI service status の問題は OpenAI 公式資料を優先してください。Anchor Installer、runtime isolation、Schedule helper、systemd Timer、safe uninstall の問題は Codex Window Anchor project に報告してください。

---

## 関連ドキュメント

- [インストールと設定](INSTALLATION.md)
- [仕組み](HOW_IT_WORKS.md)
- [セキュリティ](../../SECURITY.ja.md)
- [README に戻る](../../README.ja.md)

Codex Window Anchor は独立したプロジェクトであり、OpenAI 公式製品ではありません。
