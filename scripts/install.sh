#!/usr/bin/env bash
# Managed-By: codex-window-anchor
#
# Prepare a Codex Window Anchor installation.
#
# Important safety properties:
# - does not download Codex;
# - does not authenticate ChatGPT;
# - does not send an Anchor request;
# - does not enable the timer;
# - does not modify firewall, proxy, swap, or system timezone;
# - does not disable SELinux;
# - does not use chmod 777;
# - installs a root-owned runtime snapshot of an existing standalone Codex CLI;
# - runs scheduled Codex requests later as the dedicated non-root user.

set -Eeuo pipefail
umask 077

readonly FORMAT_VERSION="1"

readonly SERVICE_USER="codex-anchor"
readonly SERVICE_GROUP="codex-anchor"
readonly SERVICE_HOME="/home/codex-anchor"

readonly PROGRAM_DIR="/usr/local/libexec/codex-window-anchor"
readonly RUNNER_DST="${PROGRAM_DIR}/run-anchor.sh"
readonly RUNTIME_CODEX_BIN="/usr/local/bin/codex-window-anchor"

readonly CONFIG_DIR="/etc/codex-window-anchor"
readonly CONFIG_FILE="${CONFIG_DIR}/anchor.conf"
readonly META_FILE="${CONFIG_DIR}/install.meta"

readonly STATE_DIR="/var/lib/codex-window-anchor"
readonly WORK_DIR="${STATE_DIR}/work"

readonly UNIT_DIR="/etc/systemd/system"
readonly SERVICE_NAME="codex-window-anchor.service"
readonly TIMER_NAME="codex-window-anchor.timer"
readonly SERVICE_DST="${UNIT_DIR}/${SERVICE_NAME}"
readonly TIMER_DST="${UNIT_DIR}/${TIMER_NAME}"

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"

readonly RUNNER_SRC="${REPO_ROOT}/scripts/run-anchor.sh"
readonly SERVICE_SRC="${REPO_ROOT}/systemd/codex-window-anchor.service"
readonly TIMER_SRC="${REPO_ROOT}/systemd/codex-window-anchor.timer"

CODEX_SOURCE_ARG=""
CODEX_MODEL="gpt-5.6-luna"

SERVICE_USER_UID=""
INSTALL_STATE="preparing"

MUTATION_STARTED=0
INSTALL_COMPLETE=0

usage() {
  cat <<'EOF'
Usage:
  sudo ./scripts/install.sh [options]

Options:
  --codex-bin PATH   Path to an existing official standalone Codex executable.
                     If omitted, the installer attempts safe auto-discovery.

  --model MODEL      Codex model identifier for Anchor requests.
                     Default: gpt-5.6-luna

  -h, --help         Show this help.

This installer prepares the system only.

It does NOT:
  - install or download Codex;
  - log into ChatGPT;
  - send a Codex Anchor request;
  - enable the systemd timer.
EOF
}

info() {
  printf '[codex-window-anchor] %s\n' "$*"
}

fail() {
  printf '[codex-window-anchor] ERROR: %s\n' "$*" >&2
  exit 1
}

on_exit() {
  local status=$?

  if (( status != 0 )) && (( MUTATION_STARTED == 1 )) && (( INSTALL_COMPLETE == 0 )); then
    cat >&2 <<EOF

[codex-window-anchor] Installation did not complete.

No scheduled Anchor timer was intentionally enabled.
Do not manually enable ${TIMER_NAME}.

A partial installation may remain on this host.

When available, its ownership metadata is stored at:

  ${META_FILE}

Use the project's uninstall procedure to remove a partial installation
before attempting a fresh install.
EOF
  fi
}

trap on_exit EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || \
    fail "required command was not found: $1"
}

write_meta() {
  cat >"$META_FILE" <<EOF
MANAGED_BY=codex-window-anchor
FORMAT_VERSION=${FORMAT_VERSION}
INSTALL_STATE=${INSTALL_STATE}
SERVICE_USER=${SERVICE_USER}
SERVICE_GROUP=${SERVICE_GROUP}
SERVICE_HOME=${SERVICE_HOME}
SERVICE_USER_UID=${SERVICE_USER_UID}
EOF

  chmod 0644 "$META_FILE"
  chown root:root "$META_FILE"
}

while (( $# > 0 )); do
  case "$1" in
    --codex-bin)
      (( $# >= 2 )) || fail "--codex-bin requires a path"
      CODEX_SOURCE_ARG="$2"
      shift 2
      ;;
    --model)
      (( $# >= 2 )) || fail "--model requires a value"
      CODEX_MODEL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

(( EUID == 0 )) || \
  fail "run this installer with sudo or as root"

[[ "$(uname -s)" == "Linux" ]] || \
  fail "V1 installer supports Linux only"

for cmd in \
  systemctl \
  systemd-run \
  install \
  useradd \
  getent \
  id \
  readlink \
  runuser \
  head \
  od \
  tr \
  grep \
  cut
do
  require_cmd "$cmd"
done

[[ -f "$RUNNER_SRC" ]] || \
  fail "repository file is missing: $RUNNER_SRC"

[[ -f "$SERVICE_SRC" ]] || \
  fail "repository file is missing: $SERVICE_SRC"

[[ -f "$TIMER_SRC" ]] || \
  fail "repository file is missing: $TIMER_SRC"

[[ "$CODEX_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || \
  fail "model identifier contains unsupported characters"

find_codex_source() {
  local candidate=""
  local invoking_home=""

  if [[ -n "$CODEX_SOURCE_ARG" ]]; then
    candidate="$CODEX_SOURCE_ARG"
  elif command -v codex >/dev/null 2>&1; then
    candidate="$(command -v codex)"
  elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    invoking_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"

    if [[ -n "$invoking_home" && -x "${invoking_home}/.local/bin/codex" ]]; then
      candidate="${invoking_home}/.local/bin/codex"
    fi
  fi

  [[ -n "$candidate" ]] || \
    fail "Codex CLI was not found. Install the official standalone Codex CLI first, or use --codex-bin PATH"

  [[ -e "$candidate" ]] || \
    fail "Codex path does not exist: $candidate"

  readlink -f -- "$candidate"
}

CODEX_SOURCE="$(find_codex_source)"

[[ -f "$CODEX_SOURCE" ]] || \
  fail "resolved Codex executable is not a regular file: $CODEX_SOURCE"

[[ -x "$CODEX_SOURCE" ]] || \
  fail "resolved Codex executable is not executable: $CODEX_SOURCE"

ELF_MAGIC="$(
  head -c 4 -- "$CODEX_SOURCE" |
    od -An -tx1 |
    tr -d '[:space:]'
)"

[[ "$ELF_MAGIC" == "7f454c46" ]] || \
  fail "Codex source is not a native Linux ELF executable. V1 requires the official standalone Linux Codex CLI"

CODEX_VERSION="$("$CODEX_SOURCE" --version 2>&1)" || \
  fail "Codex executable failed the version check"

info "Detected Codex runtime: $CODEX_VERSION"
info "Resolved executable: $CODEX_SOURCE"

EXEC_HELP="$("$CODEX_SOURCE" exec --help 2>&1)" || \
  fail "Codex exec help could not be read"

for flag in \
  "--model" \
  "--ephemeral" \
  "--ignore-user-config" \
  "--ignore-rules" \
  "--skip-git-repo-check" \
  "--sandbox" \
  "--color"
do
  grep -Fq -- "$flag" <<<"$EXEC_HELP" || \
    fail "installed Codex CLI does not support required option: $flag"
done

for path in \
  "$PROGRAM_DIR" \
  "$CONFIG_DIR" \
  "$STATE_DIR" \
  "$RUNTIME_CODEX_BIN" \
  "$SERVICE_DST" \
  "$TIMER_DST"
do
  [[ ! -e "$path" && ! -L "$path" ]] || \
    fail "existing path would collide with this installation: $path"
done

[[ ! -e "${UNIT_DIR}/timers.target.wants/${TIMER_NAME}" && \
   ! -L "${UNIT_DIR}/timers.target.wants/${TIMER_NAME}" ]] || \
  fail "an existing timer enablement link would collide with this installation"

if getent passwd "$SERVICE_USER" >/dev/null 2>&1; then
  fail "the service user already exists and will not be taken over automatically: $SERVICE_USER"
fi

if getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
  fail "the service group already exists and will not be taken over automatically: $SERVICE_GROUP"
fi

info "Preflight checks passed."
info "Beginning installation."

MUTATION_STARTED=1

install -d -o root -g root -m 0755 "$CONFIG_DIR"
write_meta

useradd \
  --user-group \
  --create-home \
  --home-dir "$SERVICE_HOME" \
  --shell /bin/bash \
  "$SERVICE_USER"

chmod 0700 "$SERVICE_HOME"
chown "$SERVICE_USER:$SERVICE_GROUP" "$SERVICE_HOME"

SERVICE_USER_UID="$(id -u "$SERVICE_USER")"
write_meta

install -d -o root -g root -m 0755 "$PROGRAM_DIR"
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0700 "$STATE_DIR"
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0700 "$WORK_DIR"

install \
  -o root \
  -g root \
  -m 0755 \
  "$CODEX_SOURCE" \
  "$RUNTIME_CODEX_BIN"

if command -v restorecon >/dev/null 2>&1; then
  if ! restorecon -F "$RUNTIME_CODEX_BIN"; then
    info "Warning: restorecon reported a problem; the systemd execution probe will determine whether execution is permitted"
  fi
fi

runuser -u "$SERVICE_USER" -- \
  "$RUNTIME_CODEX_BIN" --version >/dev/null || \
  fail "Codex runtime could not execute as $SERVICE_USER"

PROBE_UNIT="codex-window-anchor-probe-$$"

if ! systemd-run \
  --wait \
  --unit="$PROBE_UNIT" \
  --property="User=$SERVICE_USER" \
  --property="Group=$SERVICE_GROUP" \
  "$RUNTIME_CODEX_BIN" --version
then
  fail "systemd could not execute the Codex runtime. On SELinux systems, inspect the audit log and docs/TROUBLESHOOTING.md"
fi

systemctl reset-failed "${PROBE_UNIT}.service" >/dev/null 2>&1 || true

install \
  -o root \
  -g root \
  -m 0755 \
  "$RUNNER_SRC" \
  "$RUNNER_DST"

cat >"$CONFIG_FILE" <<EOF
# Managed-By: codex-window-anchor
# Non-secret runtime configuration.

CODEX_BIN=${RUNTIME_CODEX_BIN}
CODEX_MODEL=${CODEX_MODEL}
EOF

chmod 0644 "$CONFIG_FILE"
chown root:root "$CONFIG_FILE"

install \
  -o root \
  -g root \
  -m 0644 \
  "$SERVICE_SRC" \
  "$SERVICE_DST"

install \
  -o root \
  -g root \
  -m 0644 \
  "$TIMER_SRC" \
  "$TIMER_DST"

if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify "$SERVICE_DST" "$TIMER_DST" || \
    fail "systemd unit verification failed"
fi

systemctl daemon-reload

systemctl disable --now "$TIMER_NAME" >/dev/null 2>&1 || true

TIMER_STATE="$(systemctl is-enabled "$TIMER_NAME" 2>/dev/null || true)"

[[ "$TIMER_STATE" != "enabled" ]] || \
  fail "timer unexpectedly remained enabled"

INSTALL_STATE="complete"
write_meta

INSTALL_COMPLETE=1

cat <<EOF

Codex Window Anchor installation files are ready.

Detected source:
  ${CODEX_VERSION}

Anchor runtime:
  ${RUNTIME_CODEX_BIN}

Service user:
  ${SERVICE_USER}

Configured model:
  ${CODEX_MODEL}

IMPORTANT:
  No ChatGPT login was performed.
  No Anchor request was sent.
  The systemd timer is NOT enabled.

Next steps:

1. Authenticate the dedicated service user with ChatGPT:

   sudo -u ${SERVICE_USER} -H env \
     CODEX_HOME=${SERVICE_HOME}/.codex \
     ${RUNTIME_CODEX_BIN} login --device-auth

2. Verify authentication:

   sudo -u ${SERVICE_USER} -H env \
     CODEX_HOME=${SERVICE_HOME}/.codex \
     ${RUNTIME_CODEX_BIN} login status

3. Run one manual Anchor only after authentication:

   sudo systemctl start ${SERVICE_NAME}

4. Review the timer schedule and timezone:

   sudoedit ${TIMER_DST}

5. Reload systemd after editing:

   sudo systemctl daemon-reload

6. Explicitly enable scheduling only when ready:

   sudo systemctl enable --now ${TIMER_NAME}

NOTE:
  The Anchor uses a runtime snapshot of the Codex executable detected during
  installation. Updating another Codex installation on the host does not
  automatically replace this Anchor runtime.

EOF
