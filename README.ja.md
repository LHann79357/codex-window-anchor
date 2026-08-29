# Codex Window Anchor

**言語:** [English](README.md) · [简体中文](README.zh-CN.md) · **日本語**

**OpenAI 公式 Codex CLI をベースにしたセルフホスト型の定時 Anchor ツールです。観測された Codex Usage Window の挙動を前提に、ユーザーが自分で選んだ時刻に最小限の実リクエストを実行します。**

Codex Window Anchor は、この仕組みを Linux サーバー上で安定して動かしたい一方で、ブラウザ自動化、API Key を使った cron、サードパーティの keepalive サービス、Web パネル、常駐 daemon を導入したくないユーザー向けです。専用の非 root ユーザー `codex-anchor`、systemd の oneshot service、ユーザー自身が設定する Timer を使用します。インストール完了時点では ChatGPT へのログイン、Schedule の作成、リクエスト送信は自動では始まりません。

> [!IMPORTANT]
> **Codex Window Anchor は Codex の quota を増やしません。追加枠を作成せず、制限を回避せず、quota のリセットを強制せず、「無制限 Codex」を提供しません。**
>
> 本プロジェクトでいう Usage Window / usage-window anchoring は、実運用で観測された挙動（observed behavior）を指します。ChatGPT、Codex、モデル、quota、Usage Window に関する OpenAI の恒久的な製品保証ではありません。
>
> **各 Anchor は実際の Codex リクエストです。アプリケーションレベルの入力と出力は非常に小さく、タスク全体も可能な限り軽量になるよう設計されていますが、実際の token 計測は Codex CLI、モデル、OpenAI 側のコンテキストによって変動します。**

**ナビゲーション:** [検証済み環境](#検証済み環境と既知の制限) · [仕組み](#仕組み) · [クイックスタート](#クイックスタート) · [日常操作](#日常操作) · [アンインストール](#アンインストール) · [ドキュメント](#ドキュメント)

---

## 検証済み環境と既知の制限

Public V1 は、実際の VPS 上での自動実行検証と、独立した clean environment での統合検証の両方を完了しています。実運用環境は **Vultr VPS — AlmaLinux 8.10 x86_64 / systemd 239** で、systemd による実際の定時 Anchor 実行を確認済みです。さらにリリース候補は、**AlmaLinux 8.10 Minimal x86_64 / systemd 239 / SELinux Enforcing** のクリーン環境で、Installer、Schedule、Timer、SELinux 境界、Uninstall の一連の検証を完了しています。Vultr は依存関係ではなく、実運用検証を完了した VPS 環境の一例です。

| 検証レベル | 環境 | 結果 |
| --- | --- | --- |
| 実サーバー運用 | Vultr VPS · AlmaLinux 8.10 x86_64 · systemd 239 | 実際の定時 Anchor 実行を検証済み |
| Clean integration | AlmaLinux 8.10 Minimal x86_64 · systemd 239 · SELinux Enforcing | インストール、設定、Timer、安全境界、アンインストールを検証済み |

Public V1 の完全な検証基準は現在も **AlmaLinux 8.10 x86_64** です。他の Linux ディストリビューション、systemd バージョン、CPU アーキテクチャでも動作する可能性はありますが、同等の統合検証を完了するまでは同じサポートレベルを表明しません。V1 には Linux、systemd、`sudo`/root 権限、Codex に接続できるネットワーク、そしてユーザー自身が事前にインストールした **OpenAI 公式 standalone Linux Codex executable** が必要です。Installer は選択した runtime が native Linux ELF であることと、Anchor が依存する Codex CLI option を検証します。そのため npm/node wrapper は現在の V1 Anchor runtime パスではありません。

ChatGPT Device Code ログインが利用できるかどうかは、OpenAI の現在の認証ポリシーと Workspace 設定に依存します。現在のデフォルトモデルは `gpt-5.6-luna` ですが、モデル名や利用可能性は将来変わる可能性があります。Schedule は独立した IANA timezone を使用し、Linux ホストの global timezone を変更しません。設定した各実行時刻ごとに 1 回の実 Codex リクエストが発生します。

上記の完全検証基準外の環境では、先に [詳細インストールガイド](docs/ja/INSTALLATION.md) と [トラブルシューティング](docs/ja/TROUBLESHOOTING.md) を確認してください。

---

## 仕組み

Codex Window Anchor は、常駐するバックグラウンド Agent ではなく、小さな systemd scheduling wrapper です。Timer を有効にすると、systemd が指定時刻に `Type=oneshot` service を起動します。service は専用の非 root ユーザー `codex-anchor` として `run-anchor.sh` を起動し、インストール時に `/usr/local/bin/codex-window-anchor` に保存した root-owned Codex runtime snapshot を呼び出します。Runner は専用 `CODEX_HOME`、明示的な最小環境、`--ephemeral`、`--sandbox read-only` を使用し、通常ユーザー側の Codex config と rules を無視します。そのうえで Codex に `OK` だけを返すよう求める固定の最小リクエストを送信します。処理が終わるとプロセスは終了し、Anchor daemon は常駐しません。

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

Timer は `Persistent=false` を使用します。サーバーが予定時刻にオフラインだった場合、復旧後に取り逃した Anchor を補完実行しません。Schedule 設定時、`codex-window-anchor-schedule` は IANA timezone と厳密な `HH:MM` 形式を検証し、重複時刻を除去して並べ替えます。systemd Timer への書き込みが必要な場合のみ `/usr/bin/sudo` を使って限定的に昇格し、生成後は Timer が `disabled / inactive` のままであることを確認します。自動実行が始まるのは、ユーザーが `sudo systemctl enable --now codex-window-anchor.timer` を明示的に実行した後だけです。

Installer が行うのは隔離された実行環境の準備だけです。`codex-anchor` ユーザーを作成し、既に存在する公式 standalone Codex executable から root-owned snapshot を作成し、runner/service/schedule helper と設定ファイルを配置します。Codex のダウンロード、ChatGPT へのログイン、ユーザーの `auth.json` の読み取り・コピー、Anchor 送信、公開デフォルト Schedule の生成、firewall、proxy、swap、`/etc/fstab`、global timezone、SELinux policy の変更は行いません。

Anchor が使うのは**インストール時に保存した runtime snapshot**です。ホストユーザーの PATH にある別の `codex` を後から更新しても、Anchor runtime は自動で置き換わりません。これにより、検証済み Anchor が再インストールや再検証なしに runtime drift することを防ぎます。詳細は [HOW_IT_WORKS.md](docs/ja/HOW_IT_WORKS.md) を参照してください。

---

## クイックスタート

以下は **AlmaLinux 8.10 x86_64** の例です。依存関係のインストール、Codex Window Anchor のインストール、専用ユーザーの認証、Schedule の設定と確認、任意の手動検証、明示的な自動実行開始までを順番に実行します。Codex Window Anchor 自体は Codex をダウンロードしないため、最初に OpenAI が現在提供している standalone Mac/Linux installer を使用します。

```bash
# 基本依存関係
sudo dnf install -y git curl tar

# OpenAI 公式 standalone Codex CLI
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex --version

# Codex Window Anchor を取得してインストール
git clone https://github.com/LHann79357/codex-window-anchor.git
cd codex-window-anchor
sudo ./scripts/install.sh

# 専用 codex-anchor ユーザーで ChatGPT にログイン
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login --device-auth

# 認証状態を確認
sudo -u codex-anchor -H env \
  CODEX_HOME=/home/codex-anchor/.codex \
  /usr/local/bin/codex-window-anchor login status

# 自分の timezone と実行時刻を設定
# これは中立的な形式例であり、推奨時刻や quota 最適化時刻ではありません
codex-window-anchor-schedule \
  --timezone Etc/UTC \
  --time 09:30

# 生成された Timer を確認
systemctl cat codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

Device Code ログイン時には、OpenAI のログイン URL とワンタイムコードがターミナルに表示されます。Codex 利用権限のある ChatGPT アカウントでブラウザ認証を完了してください。公式資料は [Codex GitHub](https://github.com/openai/codex) と [Codex Authentication](https://developers.openai.com/codex/auth) を参照してください。

> [!NOTE]
> インストール完了時点では公開デフォルト Schedule も実行中 Timer もありません。`codex-window-anchor-schedule` で Schedule を生成した後も Timer は `disabled / inactive` のままです。ユーザーが後で明示的に確認して有効化するまで、自動実行は始まりません。

### 任意ですが推奨：Timer を有効にする前に 1 回手動検証

自動実行を開始する前に ChatGPT 認証、Anchor runtime、systemd service を確認したい場合は、1 回手動 Anchor を実行できます。

```bash
sudo systemctl start codex-window-anchor.service
sudo journalctl -u codex-window-anchor.service -n 50 --no-pager
```

これは直ちに **1 回の実 Anchor リクエスト**を送信します。

service は `Type=oneshot` なので、成功終了後に：

```text
inactive (dead)
```

と表示されるのは正常で、失敗を意味しません。

手動検証と Schedule の確認が終わったら、自動実行を明示的に有効化します。

```bash
sudo systemctl enable --now codex-window-anchor.timer
```

Timer 状態を確認します。

```bash
systemctl is-enabled codex-window-anchor.timer
systemctl is-active codex-window-anchor.timer
systemctl list-timers codex-window-anchor.timer
```

複数の Codex executable がある場合は、インストール時に公式 standalone executable を明示できます。

```bash
sudo ./scripts/install.sh --codex-bin /absolute/path/to/codex
```

別の現在利用可能な model を使う場合：

```bash
sudo ./scripts/install.sh --model MODEL
```

事前チェック、ネットワーク環境、runtime 更新、再インストールの詳細は [INSTALLATION.md](docs/ja/INSTALLATION.md) を参照してください。

---

## 日常操作

よく使う管理コマンドは次のとおりです。

| 操作 | コマンド |
| --- | --- |
| Timer を確認 | `systemctl list-timers codex-window-anchor.timer` |
| 最近の Anchor ログ | `sudo journalctl -u codex-window-anchor.service -n 50 --no-pager` |
| 一時停止 | `sudo systemctl disable --now codex-window-anchor.timer` |
| 再開 | `sudo systemctl enable --now codex-window-anchor.timer` |

一時停止しても Anchor、`codex-anchor` ユーザー、ChatGPT authentication state、生成済み Timer は削除されません。

Schedule を変更する場合は、先に Timer を停止してから schedule helper を再実行します。helper は enabled / active の Timer を上書きしません。

```bash
sudo systemctl disable --now codex-window-anchor.timer

codex-window-anchor-schedule \
  --timezone YOUR/ZONE \
  --time HH:MM \
  --time HH:MM

systemctl cat codex-window-anchor.timer

sudo systemctl enable --now codex-window-anchor.timer
```

Schedule の timezone はこの Timer にだけ属し、サーバーの global timezone は変更しません。

---

## アンインストール

リポジトリディレクトリで：

```bash
sudo ./scripts/uninstall.sh
```

を実行します。

デフォルトアンインストールは、Codex Window Anchor に属すると安全に確認できる managed resources のみを削除します。Timer、service、runner、schedule helper、Anchor runtime snapshot、project configuration が対象です。**ユーザーが元からインストールしていた公式/global Codex CLI、専用 `codex-anchor` ユーザー、`/home/codex-anchor`、その中の ChatGPT authentication state は保持されます。** system journal history、firewall、proxy、SELinux、swap、`/etc/fstab`、無関係な service も変更しません。

dedicated user、home、認証状態まで明示的に削除したい場合：

```bash
sudo ./scripts/uninstall.sh --purge-user
```

を使用します。破壊的な操作なので、デフォルトでは対話確認を要求します。明示的に非対話で完全 purge したい場合のみ：

```bash
sudo ./scripts/uninstall.sh --purge-user --yes
```

を使用してください。

`--purge-user` は破壊的な操作です。デフォルト uninstall と purge の正確な境界は [INSTALLATION.md](docs/ja/INSTALLATION.md) と [SECURITY.ja.md](SECURITY.ja.md) を参照してください。

---

## セキュリティと認証情報

Anchor リクエストは専用の非 root `codex-anchor` ユーザーで実行されます。project-managed runtime と設定は root-owned です。runtime は read-only sandbox、ephemeral session、明示的な最小環境を使い、Public V1 の標準パスは API Key に依存せず、無限 retry loop もありません。目的はサーバーを自動的に支配することではなく、作用範囲を project 自身の identity、files、service、Timer に限定することです。

> [!WARNING]
> Codex のログイン情報は `/home/codex-anchor/.codex/` に保存される場合があります。file-based credential storage を使用している場合、`auth.json` はパスワード相当の機密情報です。
>
> **`auth.json`、ChatGPT token、API Key、SSH private key、サーバーパスワード、private proxy credential を GitHub Issue、ログ、スクリーンショット、チャットに公開しないでください。**

完全な安全境界と脆弱性報告方法は [SECURITY.ja.md](SECURITY.ja.md) を参照してください。

---

## ドキュメント

README は一般ユーザーが必要とする主経路だけを簡潔に残しています。詳細は以下に分けています。

**[インストールと設定](docs/ja/INSTALLATION.md)** · **[トラブルシューティング](docs/ja/TROUBLESHOOTING.md)** · **[仕組み](docs/ja/HOW_IT_WORKS.md)** · **[セキュリティ](SECURITY.ja.md)**

すべての言語版で、コマンド、パス、flag、安全上の意味は同一です。

---

## License

> [!NOTE]
> Public V1 の License はまだ最終決定していません。`v1.0.0` を正式公開する前に、別途 License の選択とレビューを完了します。現時点では MIT、Apache-2.0、その他の License を前提としていません。

---

Codex Window Anchor は独立したプロジェクトであり、OpenAI 公式製品ではありません。本プロジェクトの Usage Window に関する記述は観測された挙動と実装経験のみを表し、将来の ChatGPT plans、Codex models、usage limits、quota、authentication、usage-window behavior に関する OpenAI の保証を意味しません。
