#!/usr/bin/env bash
# Managed-By: codex-window-anchor
#
# Execute exactly one minimal Codex Window Anchor request.
#
# This script intentionally:
# - uses stored ChatGPT authentication;
# - runs one real Codex request;
# - uses an ephemeral session;
# - ignores ambient Codex config and exec-policy rules;
# - uses a read-only sandbox;
# - does not retry indefinitely;
# - does not modify the system or schedule.

set -Eeuo pipefail
umask 077

readonly CONFIG_FILE="/etc/codex-window-anchor/anchor.conf"
readonly SERVICE_HOME="/home/codex-anchor"
readonly CODEX_HOME_DIR="${SERVICE_HOME}/.codex"
readonly WORK_DIR="/var/lib/codex-window-anchor/work"
readonly SQLITE_DIR="/var/lib/codex-window-anchor/sqlite"
readonly SERVICE_USER="codex-anchor"

readonly ANCHOR_PROMPT='Reply exactly with OK. Do not inspect files, run commands, browse the web, use tools, or perform any additional work.'

fail() {
  printf 'codex-window-anchor: %s\n' "$*" >&2
  exit 1
}

[[ -r "$CONFIG_FILE" ]] || \
  fail "configuration is not readable: $CONFIG_FILE"

# shellcheck source=/dev/null
source "$CONFIG_FILE"

[[ -n "${CODEX_BIN:-}" ]] || \
  fail "CODEX_BIN is not set in $CONFIG_FILE"

[[ "$CODEX_BIN" = /* ]] || \
  fail "CODEX_BIN must be an absolute path"

[[ -x "$CODEX_BIN" ]] || \
  fail "Codex executable is not executable: $CODEX_BIN"

[[ -n "${CODEX_MODEL:-}" ]] || \
  fail "CODEX_MODEL is not set in $CONFIG_FILE"

[[ "$CODEX_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || \
  fail "CODEX_MODEL contains unsupported characters"

[[ -d "$SERVICE_HOME" ]] || \
  fail "service home does not exist: $SERVICE_HOME"

[[ -d "$CODEX_HOME_DIR" ]] || \
  fail "Codex home does not exist: $CODEX_HOME_DIR; authenticate the codex-anchor user first"

[[ -d "$WORK_DIR" ]] || \
  fail "working directory does not exist: $WORK_DIR"

[[ -d "$SQLITE_DIR" ]] || \
  fail "Codex SQLite state directory does not exist: $SQLITE_DIR"

# Build an explicit environment rather than inheriting the systemd manager's
# authentication, provider, base-URL, or workload-identity inputs. This clears
# OPENAI_API_KEY, CODEX_API_KEY, CODEX_ACCESS_TOKEN, OPENAI_BASE_URL,
# OPENAI_FEDERATION_RULE_ID, OPENAI_IDENTITY_TOKEN_FILE, and every other
# non-allowlisted switch. V1 retains only conventional proxy and CA variables.
runtime_env=(
  "HOME=$SERVICE_HOME"
  "USER=$SERVICE_USER"
  "LOGNAME=$SERVICE_USER"
  "SHELL=/bin/bash"
  "PATH=/usr/local/bin:/usr/bin:/bin"
  "CODEX_HOME=$CODEX_HOME_DIR"
  "CODEX_SQLITE_HOME=$SQLITE_DIR"
)

for name in \
  HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY \
  http_proxy https_proxy all_proxy no_proxy \
  CODEX_CA_CERTIFICATE SSL_CERT_FILE SSL_CERT_DIR \
  CURL_CA_BUNDLE REQUESTS_CA_BUNDLE
do
  if [[ -v "$name" ]]; then
    runtime_env+=("$name=${!name}")
  fi
done

cd "$WORK_DIR"

# One invocation equals at most one intended Anchor request.
exec /usr/bin/env -i "${runtime_env[@]}" "$CODEX_BIN" exec \
  --model "$CODEX_MODEL" \
  --ephemeral \
  --ignore-user-config \
  --ignore-rules \
  --skip-git-repo-check \
  --sandbox read-only \
  --color never \
  "$ANCHOR_PROMPT"
