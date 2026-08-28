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

export HOME="$SERVICE_HOME"
export CODEX_HOME="$CODEX_HOME_DIR"

# V1 uses stored ChatGPT authentication rather than API-key or access-token
# authentication. Clear ambient credential variables so a server-wide
# environment cannot silently change the authentication route.
unset OPENAI_API_KEY
unset CODEX_API_KEY
unset CODEX_ACCESS_TOKEN
unset OPENAI_BASE_URL

cd "$WORK_DIR"

# One invocation equals at most one intended Anchor request.
exec "$CODEX_BIN" exec \
  --model "$CODEX_MODEL" \
  --ephemeral \
  --ignore-user-config \
  --ignore-rules \
  --skip-git-repo-check \
  --sandbox read-only \
  --color never \
  "$ANCHOR_PROMPT"
