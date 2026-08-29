# Codex Window Anchor — インストールと設定

このドキュメントでは、Codex Window Anchor Public V1 の完全なインストール手順と日常管理フローを説明します。最初に 1 本の明確なデプロイ経路を示し、必要に応じて高度なインストールオプション、runtime 更新、再インストール、アンインストールを確認できる構成です。

プロジェクト概要だけを知りたい場合は、先に [日本語 README](../../README.ja.md) を参照してください。

> [!IMPORTANT]
> Codex Window Anchor は Codex をダウンロードしません。インストール中に ChatGPT へログインせず、Anchor を送信せず、デフォルト Schedule を作らず、Timer を起動しません。
>
> **自動実行が始まるのは、ユーザーが明示的に次を実行した後だけです。**
>
> ```bash
> sudo systemctl enable --now codex-window-anchor.timer
> ```

## インストールフロー

```text
Linux 環境を準備
→ OpenAI 公式 Codex CLI をインストール
→ Codex Window Anchor をインストール
→ codex-anchor で ChatGPT にログイン
→ 自分の timezone / times を設定
→ Timer を Review
→ （任意・推奨）Anchor を 1 回手動検証
→ 明示的に enable
→ Timer を確認
```

---

## 1. 環境を準備

Public V1 の完全検証基準は **AlmaLinux 8.10 x86_64 / systemd 239** です。実際の **Vultr VPS** 上で自動 Timer 実行を確認し、さらに独立した **AlmaLinux 8.10 Minimal / systemd 239 / SELinux Enforcing** の clean environment で Installer、Schedule、Timer、安全境界、Uninstall の一連の統合検証を完了しています。

| 項目 | Public V1 基準 |
| --- | --- |
| Linux | AlmaLinux 8.10 x86_64 |
| systemd | 239 |
| SELinux | Enforcing（clean integration validation） |
| Codex | OpenAI 公式 standalone Linux executable |
| Authentication | ChatGPT account |
| Anchor user | `codex-anchor` |
| デフォルトモデル | `gpt-5.6-luna` |

Vultr は**プロジェクト依存関係ではありません**。実運用検証を完了した VPS 環境の一例です。他の Linux ディストリビューション、systemd バージョン、CPU アーキテクチャでも動作する可能性はありますが、同等の統合検証が完了するまでは Public V1 と同じサポートレベルを表明しません。

### 基本依存関係

AlmaLinux 8.10:

```bash
sudo dnf install -y git curl tar
```

systemd を確認:

```bash
systemctl --version
```

さらに必要です:

- `sudo` または root 権限;
- OpenAI Codex に接続できるネットワーク;
- Codex 利用権限のある ChatGPT アカウント。

他の Linux ディストリビューションでは、対応する package manager で同等の依存関係を入れてください。このドキュメントでは未検証の distribution-specific コマンドは提供しません。

---

## 2. OpenAI 公式 Codex CLI をインストール

Codex Window Anchor は **Codex をダウンロード、同梱、再配布しません**。先に OpenAI 公式チャネルから Codex CLI をインストールしてください。

公式リンク:

- [OpenAI Codex GitHub](https://github.com/openai/codex)
- [OpenAI Codex Authentication](https://developers.openai.com/codex/auth)

OpenAI が現在 Mac/Linux 向けに提供している standalone installer:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

インストール後:

```bash
codex --version
command -v codex
```

両方が正常に動作してから Anchor のインストールへ進みます。

> [!NOTE]
> Codex Window Anchor Public V1 は **native standalone Linux Codex executable** を Anchor runtime として使用します。
>
> Installer は選択した executable から独立した root-owned snapshot を作成し、native Linux ELF であることと、Anchor が必要とする Codex CLI options を検証します。現在の V1 runtime path では npm/node wrapper を使用しません。

---

## 3. Codex Window Anchor をインストール

リポジトリを clone:

```bash
git clone https://github.com/LHann79357/codex-window-anchor.git
cd codex-window-anchor
```

標準 Installer:

```bash
sudo ./scripts/install.sh
```

成功すると Anchor runtime、service user、configured model が表示され、次の内容が明示されます。

```text
No ChatGPT login was performed.
No Anchor request was sent.
No Anchor schedule was created.
No systemd timer is enabled or active.
```

### Installer が配置するもの

| 用途 | パス |
| --- | --- |
| Anchor Codex runtime | `/usr/local/bin/codex-window-anchor` |
| Schedule helper | `/usr/local/bin/codex-window-anchor-schedule` |
| Runner | `/usr/local/libexec/codex-window-anchor/run-anchor.sh` |
| Runtime config | `/etc/codex-window-anchor/anchor.conf` |
| Install metadata | `/etc/codex-window-anchor/install.meta` |
| systemd service | `/etc/systemd/system/codex-window-anchor.service` |
| Dedicated home | `/home/codex-anchor` |
| Runtime state | `/var/lib/codex-window-anchor/` |

Installer は専用の非 root ユーザー:

```text
codex-anchor
```

を作成します。

さらに、既にインストール済みの standalone Codex executable から Anchor 専用の root-owned runtime snapshot を作成します。ホストユーザーの PATH にある別の `codex` を更新しても、この snapshot は自動更新されません。

<details>
<summary><strong>Installer が明示的に変更しないもの</strong></summary>

Installer は次を行いません。

- Codex のダウンロード;
- ChatGPT へのログイン;
- `auth.json` の読み取り・コピー;
- Anchor リクエスト送信;
- 公開デフォルト Schedule の作成;
- live Timer の作成;
- Timer の enable/start;
- system global timezone の変更;
- firewall の変更;
- proxy の変更;
- swap の変更;
- `/etc/fstab` の変更;
- SELinux の無効化;
- `chmod 777`;
- `/etc/sudoers` の変更.

</details>

<details>
<summary><strong>高度なオプション: Codex executable / model を指定</strong></summary>

複数の Codex executable が存在する場合、OpenAI 公式チャネル由来だと確認した standalone binary を絶対パスで指定できます。

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/codex
```

Installer は最初に:

```bash
command -v codex
```

を試します。

`sudo` 環境で PATH から見つからない場合は、呼び出し元ユーザーの:

```text
~/.local/bin/codex
```

も確認します。

Installer は executable の file form、runtime capability、Anchor が必要とする CLI capability を検証しますが、**publisher provenance を独自に証明しません**。OpenAI 公式チャネルから取得した Codex だけを使用してください。

デフォルトモデル:

```text
gpt-5.6-luna
```

別の現在利用可能な model を指定する場合:

```bash
sudo ./scripts/install.sh --model MODEL
```

全 Installer options:

```bash
sudo ./scripts/install.sh --help
```

</details>

---

## 4. `codex-anchor` で ChatGPT にログイン

Anchor は独立した Codex Home を使用します。

```text
/home/codex-anchor/.codex
```

通常の Linux ユーザーの Codex Home を直接再利用しません。

remote/headless Linux で実行:

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login --device-auth
```

ターミナルに表示される OpenAI Device Code フローに従い、Codex 利用権限のある ChatGPT アカウントでブラウザ認証を完了します。

認証状態を確認:

```bash
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status
```

> [!WARNING]
> `/home/codex-anchor/.codex/` には ChatGPT authentication state が保存される場合があります。file-based credential storage の場合、`auth.json` はパスワード相当の機密情報です。
>
> `auth.json`、ChatGPT token、API Key、その他認証情報を GitHub、Issue、チャット、公開ログに投稿しないでください。

認証に失敗した場合、`/etc/codex-window-anchor/anchor.conf` に API Key を一時的に書かないでください。OpenAI の現在の [Authentication documentation](https://developers.openai.com/codex/auth) を確認し、その後 [Troubleshooting](TROUBLESHOOTING.md) を参照してください。

---

## 5. 自分の Schedule を設定

Codex Window Anchor には**公開デフォルト実行時刻がありません**。ユーザー自身が次を決めます。

- timezone;
- 1 日に何回実行するか;
- 各実行時刻.

利用可能 timezone:

```bash
timedatectl list-timezones
```

一般的な IANA timezone:

```text
America/New_York
Europe/London
Asia/Shanghai
Etc/UTC
```

### Schedule を作成

1 時刻:

```bash
codex-window-anchor-schedule \
  --timezone Etc/UTC \
  --time 09:30
```

複数時刻:

```bash
codex-window-anchor-schedule \
  --timezone Europe/London \
  --time 07:15 \
  --time 16:45
```

これらは**形式例**であり、デフォルト、推奨値、quota 最適化 Schedule ではありません。

Schedule helper は次を受け付けます。

```text
exactly one --timezone AREA/CITY
one or more --time HH:MM
```

時刻は厳密な 24-hour format です。

```text
00:00
09:30
23:59
```

通常ユーザーとして `codex-window-anchor-schedule` を直接実行してください。手動で `sudo` を付ける必要はありません。helper は先に引数を解析・検証し、systemd Timer への書き込みが必要なときだけ、インストール済み root-owned helper が `/usr/bin/sudo` を使って再実行します。

`/etc/sudoers` を変更せず、サーバーの global timezone も変更しません。

### Schedule helper 完了後

成功時:

```text
Timer state:
  disabled / inactive

No Anchor request was sent.
```

と表示されます。

これは Schedule が**生成済みだが、自動実行はまだ始まっていない**ことを意味します。

> [!NOTE]
> 生成される Timer は `Persistent=false` です。予定時刻にサーバーがオフラインなら、復旧後に取り逃した Anchor を補完実行せず、次の通常 Schedule を待ちます。

---

## 6. Schedule を Review

Schedule helper 成功後:

```text
Timer state:
  disabled / inactive

No Anchor request was sent.
```

となっていることを前提に、生成された Timer を確認します。

```bash
systemctl cat codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

まだ開始されていないことを明示的に確認する場合:

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
```

正常状態:

```text
disabled / inactive
```

Schedule は存在しますが、自動 Anchor はまだ始まっていません。

---

## 7. 推奨: Timer を有効にする前に 1 回手動検証

自動実行開始前に ChatGPT authentication、Anchor runtime、systemd service を確認できます。

```bash
sudo systemctl start codex-window-anchor.service
```

ログ:

```bash
sudo journalctl -u codex-window-anchor.service -n 50 --no-pager
```

または:

```bash
sudo systemctl status codex-window-anchor.service --no-pager -l
```

> [!IMPORTANT]
> 手動実行すると直ちに **1 回の実 Anchor リクエスト**が送信されます。

`codex-window-anchor.service` は `Type=oneshot` です。成功して終了した後に:

```text
inactive (dead)
```

と表示されるのは正常で、失敗ではありません。

手動検証に失敗した場合は Timer を enable せず、[TROUBLESHOOTING.md](TROUBLESHOOTING.md) を確認してください。

---

## 8. 自動実行を明示的に有効化

以下を確認したら:

- Schedule の timezone と時刻が正しい;
- 手動検証を行った場合、その実行が正常;

Timer を明示的に有効化します。

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

確認:

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

正常なら Timer は enabled / active で、次の Schedule を待ちます。

この時点以降、Schedule に一致する各 trigger は 1 回の実 Anchor リクエストになります。

**各 Anchor は実際の Codex リクエストです。アプリケーションレベルの入力と出力は非常に小さく、タスク全体も可能な限り軽量になるよう設計されていますが、実際の token 計測は Codex CLI、モデル、OpenAI 側のコンテキストによって変動します。**

---

## 9. 日常操作

| 操作 | コマンド |
| --- | --- |
| 次回実行を見る | `systemctl list-timers codex-window-anchor.timer --all --no-pager` |
| Timer 状態 | `systemctl status codex-window-anchor.timer --no-pager -l` |
| 最近の Anchor ログ | `sudo journalctl -u codex-window-anchor.service -n 50 --no-pager` |
| 自動実行を一時停止 | `sudo systemctl disable --now codex-window-anchor.timer` |
| 自動実行を再開 | `sudo systemctl enable --now codex-window-anchor.timer` |

一時停止しても Anchor インストール、generated Timer、`codex-anchor` ユーザー、ChatGPT authentication state は削除されません。

### Schedule を変更

Schedule helper は enabled / active の Timer を上書きしません。先に停止:

```bash
sudo systemctl disable --now codex-window-anchor.timer
```

再設定:

```bash
codex-window-anchor-schedule \
  --timezone America/New_York \
  --time 08:30 \
  --time 17:00
```

Review:

```bash
systemctl cat codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

この時点では:

```text
disabled / inactive
```

のままです。

確認後に再開:

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

Schedule timezone はこの Timer のみに適用され、サーバーの global timezone を変更しません。

---

## 10. Codex runtime を更新

Anchor はインストール時に保存した runtime snapshot:

```text
/usr/local/bin/codex-window-anchor
```

を使います。

ホストユーザー PATH の:

```text
codex
```

を更新しても **Anchor runtime は自動更新されません**。検証済み runtime の silent drift を避けるための意図的な設計です。

Public V1 は Anchor runtime をバックグラウンドで自動置換しません。

新しい公式 standalone Codex executable を使う場合は、監査可能な再インストール手順を使用します。

```bash
# 1. 一時停止
sudo systemctl disable --now codex-window-anchor.timer

# 2. デフォルト uninstall（dedicated user / home / auth を保持）
sudo ./scripts/uninstall.sh

# 3. 新しい Codex runtime を Installer で検証して再インストール
sudo ./scripts/install.sh
```

デフォルト uninstall は generated Timer を削除するため、再インストール後に**Schedule を再作成**します。

```bash
codex-window-anchor-schedule \
  --timezone YOUR/ZONE \
  --time HH:MM
```

その後 Review して再び明示的に enable:

```bash
systemctl cat codex-window-anchor.timer
sudo systemctl enable --now codex-window-anchor.timer
```

デフォルト uninstall は安全に検証できる `codex-anchor` identity/home/authentication state を保持します。Installer が再利用するのは username、UID、group、GID、home path、ownership が完全一致する場合だけです。

---

## 11. アンインストール

### デフォルトアンインストール

リポジトリディレクトリで:

```bash
sudo ./scripts/uninstall.sh
```

デフォルト uninstall は Codex Window Anchor に属すると安全に確認できる managed resources のみを削除します。

- Anchor Timer;
- Anchor service;
- runner;
- schedule helper;
- Anchor runtime snapshot;
- Anchor configuration;
- 空の Anchor runtime directories.

デフォルト uninstall は次を**保持**します。

- ユーザーが元から持つ official/global Codex CLI;
- `codex-anchor` user;
- `/home/codex-anchor`;
- その中の ChatGPT authentication state;
- system journal history;
- firewall / proxy / SELinux;
- swap / `/etc/fstab`;
- unrelated services/files.

将来の reinstall で dedicated identity を安全に再利用できるよう、最小限の verified identity metadata も保持します。

### dedicated user と認証も削除

明示的に削除したい場合だけ:

```bash
sudo ./scripts/uninstall.sh --purge-user
```

この経路では対話確認が入り、dedicated user/home を削除します。その中には ChatGPT authentication state が含まれる場合があります。

明示的な非対話 purge:

```bash
sudo ./scripts/uninstall.sh --purge-user --yes
```

`--yes` は `--purge-user` と一緒にだけ使用できます。

Purge は user/group/UID/GID/home identity を検証します。対象が project 作成の exact dedicated identity だと安全に確認できない場合、同名 user や directory を盲目的に削除せず fail closed します。

---

## 12. インストールが途中で失敗した場合

Installer は system mutation 前に可能な限り preflight checks を行います。mutation 開始後にインストールが完了しなかった場合、partial installation が残る可能性を警告し、Timer を手動 enable しないよう案内します。

次が存在する場合:

```text
/etc/codex-window-anchor/install.meta
```

先に散在ファイルを手動削除して再試行しないでください。

優先して:

```bash
sudo ./scripts/uninstall.sh
```

を実行し、ownership metadata を使って project が安全に識別できる resources を削除してから Installer を再実行します。

Uninstaller が ownership、identity、systemd state の ambiguity で停止する場合、それは fail-closed behavior です。状態を保ち、[TROUBLESHOOTING.md](TROUBLESHOOTING.md) に進んでください。

---

## 13. Reference

### 重要パス

| 用途 | パス |
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

### 正常状態

| 段階 | Timer |
| --- | --- |
| Installer 直後 | 存在しない / 未 enable / 未実行 |
| Schedule helper 直後 | `disabled / inactive` |
| `enable --now` 後 | enabled / active、次回 trigger 待ち |
| `disable --now` 後 | disabled / inactive |

### セキュリティ注意

Issue、ログ、スクリーンショットを公開する前に以下が含まれないことを確認してください。

- `auth.json` 内容;
- ChatGPT token;
- API Key;
- SSH private key;
- root/SSH password;
- VPS login credentials;
- private proxy credentials.

Public V1 の標準経路では API Key を repository や Anchor configuration に書く必要はありません。

---

## 次へ

- [トラブルシューティング](TROUBLESHOOTING.md)
- [仕組み](HOW_IT_WORKS.md)
- [セキュリティ](../../SECURITY.ja.md)
- [README に戻る](../../README.ja.md)

Codex Window Anchor は独立したプロジェクトであり、OpenAI 公式製品ではありません。OpenAI は Codex CLI、model、authentication method、plan limits、Usage Window behavior を変更する可能性があります。本プロジェクトの Usage Window 記述は観測された挙動と実装経験のみを表します。
