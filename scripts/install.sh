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
readonly SCHEDULE_HELPER_DST="/usr/local/bin/codex-window-anchor-schedule"
readonly LEGACY_SCHEDULE_HELPER_DST="/usr/local/sbin/codex-window-anchor-schedule"

readonly CONFIG_DIR="/etc/codex-window-anchor"
readonly CONFIG_FILE="${CONFIG_DIR}/anchor.conf"
readonly META_FILE="${CONFIG_DIR}/install.meta"

readonly STATE_DIR="/var/lib/codex-window-anchor"
readonly WORK_DIR="${STATE_DIR}/work"
readonly SQLITE_DIR="${STATE_DIR}/sqlite"

readonly UNIT_DIR="/etc/systemd/system"
readonly SERVICE_NAME="codex-window-anchor.service"
readonly TIMER_NAME="codex-window-anchor.timer"
readonly SERVICE_DST="${UNIT_DIR}/${SERVICE_NAME}"
readonly TIMER_DST="${UNIT_DIR}/${TIMER_NAME}"
readonly PROBE_USER="nobody"

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"

readonly RUNNER_SRC="${REPO_ROOT}/scripts/run-anchor.sh"
readonly SCHEDULE_HELPER_SRC="${REPO_ROOT}/scripts/configure-schedule.sh"
readonly SERVICE_SRC="${REPO_ROOT}/systemd/codex-window-anchor.service"

CODEX_SOURCE_ARG=""
CODEX_MODEL="gpt-5.6-luna"

SERVICE_USER_UID=""
SERVICE_GROUP_GID=""
RUNTIME_CODEX_SHA256=""
INSTALL_STATE="preparing"
REUSE_PRESERVED_IDENTITY=0
REMOVE_LEGACY_SCHEDULE_HELPER=0
STAGED_SOURCE=""
PROBE_GROUP=""

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

V1 reference target: AlmaLinux 8.10, systemd 239, SELinux enforcing.
No additional distribution support is claimed without integration testing.

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

  if [[ -n "$STAGED_SOURCE" ]]; then
    rm -f -- "$STAGED_SOURCE" 2>/dev/null || true
  fi

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

is_exact_managed_schedule_helper() {
  local path="$1"

  [[ -f "$path" && ! -L "$path" ]] || return 1
  [[ "$(stat -c '%U:%G' "$path" 2>/dev/null || true)" == "root:root" ]] || return 1
  [[ "$(stat -c '%a' "$path" 2>/dev/null || true)" == "755" ]] || return 1
  grep -Fqx '# Managed-By: codex-window-anchor' "$path"
}

plan_legacy_schedule_helper_removal() {
  if [[ ! -e "$LEGACY_SCHEDULE_HELPER_DST" && ! -L "$LEGACY_SCHEDULE_HELPER_DST" ]]; then
    return 0
  fi

  is_exact_managed_schedule_helper "$LEGACY_SCHEDULE_HELPER_DST" || \
    fail "legacy schedule-command path is not an exact project-managed file: $LEGACY_SCHEDULE_HELPER_DST"
  REMOVE_LEGACY_SCHEDULE_HELPER=1
}

write_meta() {
  local meta_tmp=""

  meta_tmp="$(mktemp "${CONFIG_DIR}/.install.meta.XXXXXX")" || \
    fail "could not create an installation metadata temporary file"

  if ! cat >"$meta_tmp" <<EOF
MANAGED_BY=codex-window-anchor
FORMAT_VERSION=${FORMAT_VERSION}
INSTALL_STATE=${INSTALL_STATE}
SERVICE_USER=${SERVICE_USER}
SERVICE_GROUP=${SERVICE_GROUP}
SERVICE_HOME=${SERVICE_HOME}
SERVICE_USER_UID=${SERVICE_USER_UID}
SERVICE_GROUP_GID=${SERVICE_GROUP_GID}
RUNTIME_CODEX_SHA256=${RUNTIME_CODEX_SHA256}
EOF
  then
    rm -f -- "$meta_tmp"
    fail "could not write installation metadata"
  fi

  if ! chmod 0644 "$meta_tmp" || ! chown root:root "$meta_tmp"; then
    rm -f -- "$meta_tmp"
    fail "could not secure installation metadata"
  fi

  if ! mv -f -- "$meta_tmp" "$META_FILE"; then
    rm -f -- "$meta_tmp"
    fail "could not atomically replace installation metadata"
  fi
}

meta_value() {
  local key="$1"
  local line=""

  line="$(grep -m1 -E "^${key}=" "$META_FILE" || true)"
  [[ -n "$line" ]] || return 1
  printf '%s\n' "${line#*=}"
}

validate_preserved_identity() {
  local passwd_entry=""
  local group_entry=""
  local recorded_uid=""
  local recorded_gid=""
  local current_uid=""
  local passwd_gid=""
  local group_gid=""
  local current_home=""
  local current_group_name=""
  local extra_entry=""

  [[ -f "$META_FILE" && ! -L "$META_FILE" ]] || return 1
  [[ "$(stat -c '%U:%G' "$META_FILE" 2>/dev/null || true)" == "root:root" ]] || return 1
  [[ "$(meta_value MANAGED_BY || true)" == "codex-window-anchor" ]] || return 1
  [[ "$(meta_value FORMAT_VERSION || true)" == "$FORMAT_VERSION" ]] || return 1
  [[ "$(meta_value INSTALL_STATE || true)" == "uninstalled-preserved-identity" ]] || return 1
  [[ "$(meta_value SERVICE_USER || true)" == "$SERVICE_USER" ]] || return 1
  [[ "$(meta_value SERVICE_GROUP || true)" == "$SERVICE_GROUP" ]] || return 1
  [[ "$(meta_value SERVICE_HOME || true)" == "$SERVICE_HOME" ]] || return 1
  [[ "$(stat -c '%a' "$META_FILE" 2>/dev/null || true)" == "644" ]] || return 1

  extra_entry="$(find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 ! -name 'install.meta' -print -quit 2>/dev/null || true)"
  [[ -z "$extra_entry" ]] || return 1

  recorded_uid="$(meta_value SERVICE_USER_UID || true)"
  recorded_gid="$(meta_value SERVICE_GROUP_GID || true)"
  [[ "$recorded_uid" =~ ^[0-9]+$ && "$recorded_gid" =~ ^[0-9]+$ ]] || return 1

  passwd_entry="$(getent passwd "$SERVICE_USER" 2>/dev/null || true)"
  group_entry="$(getent group "$SERVICE_GROUP" 2>/dev/null || true)"
  [[ -n "$passwd_entry" && -n "$group_entry" ]] || return 1

  IFS=: read -r _ _ current_uid passwd_gid _ current_home _ <<<"$passwd_entry"
  IFS=: read -r current_group_name _ group_gid _ <<<"$group_entry"

  [[ "$current_uid" == "$recorded_uid" ]] || return 1
  [[ "$passwd_gid" == "$recorded_gid" ]] || return 1
  [[ "$group_gid" == "$recorded_gid" ]] || return 1
  [[ "$current_group_name" == "$SERVICE_GROUP" ]] || return 1
  [[ "$current_home" == "$SERVICE_HOME" ]] || return 1
  [[ -d "$SERVICE_HOME" && ! -L "$SERVICE_HOME" ]] || return 1
  [[ "$(stat -c '%u:%g' "$SERVICE_HOME" 2>/dev/null || true)" == "${recorded_uid}:${recorded_gid}" ]] || return 1

  SERVICE_USER_UID="$recorded_uid"
  SERVICE_GROUP_GID="$recorded_gid"
  return 0
}

reject_systemd_collision() {
  local unit="$1"
  local root=""
  local found=""
  local manager_units=""
  local unit_files=""

  for root in \
    /etc/systemd/system.control \
    /run/systemd/system.control \
    /etc/systemd/system \
    /run/systemd/system \
    /run/systemd/transient \
    /usr/local/lib/systemd/system \
    /usr/lib/systemd/system \
    /lib/systemd/system \
    /run/systemd/generator \
    /run/systemd/generator.early \
    /run/systemd/generator.late
  do
    [[ -d "$root" ]] || continue
    found="$(find "$root" \( -name "$unit" -o -name "${unit}.d" \) -print -quit 2>/dev/null || true)"
    [[ -z "$found" ]] || fail "existing systemd namespace object would collide: $found"
  done

  if ! manager_units="$(systemctl list-units --all --full --no-legend "$unit" 2>/dev/null)"; then
    fail "could not query the systemd manager namespace for $unit"
  fi
  [[ -z "$manager_units" ]] || \
    fail "a same-name systemd unit is already loaded or active: $unit"

  if ! unit_files="$(systemctl list-unit-files --full --no-legend "$unit" 2>/dev/null)"; then
    fail "could not query persistent/runtime systemd unit-file state for $unit"
  fi
  [[ -z "$unit_files" ]] || \
    fail "a same-name systemd unit file, alias, or enablement already exists: $unit"
}

stage_codex_source() {
  local staging_user=""
  local source_owner=""
  local source_mode=""
  local source_fd=""
  local opened_path=""

  STAGED_SOURCE="$(mktemp "${CONFIG_DIR}/.codex-source.XXXXXX")" || \
    fail "could not create a root-private Codex staging file"

  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] && \
     getent passwd "$SUDO_USER" >/dev/null 2>&1
  then
    staging_user="$SUDO_USER"
    if ! runuser -u "$staging_user" -- /bin/cat -- "$CODEX_SOURCE" >"$STAGED_SOURCE"; then
      fail "the invoking non-root operator could not read the selected Codex source"
    fi
  else
    exec {source_fd}<"$CODEX_SOURCE" || \
      fail "could not open the direct-root Codex source"
    opened_path="$(readlink -f -- "/proc/self/fd/${source_fd}" 2>/dev/null || true)"
    source_owner="$(stat -c '%u' "/proc/self/fd/${source_fd}" 2>/dev/null || true)"
    source_mode="$(stat -c '%a' "/proc/self/fd/${source_fd}" 2>/dev/null || true)"
    [[ "$opened_path" == "$CODEX_SOURCE" ]] || {
      exec {source_fd}<&-
      fail "direct-root Codex source changed while it was being opened"
    }
    [[ "$source_owner" == "0" && "$source_mode" =~ ^[0-7]{3,4}$ ]] || \
      fail "direct-root installation requires a root-owned Codex source with a valid mode"
    (( (8#$source_mode & 022) == 0 )) || \
      fail "direct-root installation refuses a group/world-writable Codex source"
    /bin/cat <&"$source_fd" >"$STAGED_SOURCE" || \
      fail "could not read the trusted root-owned Codex source"
    exec {source_fd}<&-
  fi

  chmod 0600 "$STAGED_SOURCE"
  chown root:root "$STAGED_SOURCE"
}

login_defs_value() {
  local wanted="$1"
  local fallback="$2"
  local key=""
  local value=""
  local rest=""

  if [[ -r /etc/login.defs ]]; then
    while read -r key value rest; do
      if [[ "$key" == "$wanted" && "$value" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$value"
        return 0
      fi
    done </etc/login.defs
  fi

  printf '%s\n' "$fallback"
}

plan_identity_ids() {
  local uid_min=""
  local uid_max=""
  local gid_min=""
  local gid_max=""
  local range_min=""
  local range_max=""
  local candidate=""
  local passwd_status=0
  local group_status=0

  uid_min="$(login_defs_value UID_MIN 1000)"
  uid_max="$(login_defs_value UID_MAX 60000)"
  gid_min="$(login_defs_value GID_MIN 1000)"
  gid_max="$(login_defs_value GID_MAX 60000)"

  (( uid_min > gid_min )) && range_min="$uid_min" || range_min="$gid_min"
  (( uid_max < gid_max )) && range_max="$uid_max" || range_max="$gid_max"
  (( range_min <= range_max )) || fail "UID/GID allocation ranges do not overlap"

  for (( candidate=range_min; candidate<=range_max; candidate++ )); do
    set +e
    getent passwd "$candidate" >/dev/null 2>&1
    passwd_status=$?
    getent group "$candidate" >/dev/null 2>&1
    group_status=$?
    set -e

    [[ "$passwd_status" -eq 0 || "$passwd_status" -eq 2 ]] || \
      fail "NSS passwd lookup failed while planning UID $candidate"
    [[ "$group_status" -eq 0 || "$group_status" -eq 2 ]] || \
      fail "NSS group lookup failed while planning GID $candidate"

    if [[ "$passwd_status" -eq 2 && "$group_status" -eq 2 ]]; then
      SERVICE_USER_UID="$candidate"
      SERVICE_GROUP_GID="$candidate"
      return 0
    fi
  done

  fail "no common free UID/GID is available in the configured login.defs ranges"
}

reject_identity_name_collision() {
  local database="$1"
  local name="$2"
  local status=0

  set +e
  getent "$database" "$name" >/dev/null 2>&1
  status=$?
  set -e

  case "$status" in
    0)
      fail "the service $database name already exists and will not be taken over automatically: $name"
      ;;
    2)
      return 0
      ;;
    *)
      fail "NSS $database lookup failed while checking the reserved name: $name"
      ;;
  esac
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
  fail "V1 reference target is AlmaLinux 8.10; the installer requires Linux"

for cmd in \
  systemctl \
  systemd-run \
  install \
  useradd \
  groupadd \
  getent \
  id \
  sha256sum \
  stat \
  find \
  mktemp \
  mv \
  rm \
  cat \
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

[[ -f "$SCHEDULE_HELPER_SRC" ]] || \
  fail "repository file is missing: $SCHEDULE_HELPER_SRC"

[[ -f "$SERVICE_SRC" ]] || \
  fail "repository file is missing: $SERVICE_SRC"

[[ "$CODEX_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || \
  fail "model identifier contains unsupported characters"

[[ -x /usr/bin/env ]] || \
  fail "required executable was not found: /usr/bin/env"

[[ -d /usr/local/bin && ! -L /usr/local/bin ]] || \
  fail "required public command directory is unavailable: /usr/local/bin"
[[ "$(stat -c '%U:%G' /usr/local/bin 2>/dev/null || true)" == "root:root" && \
   "$(stat -c '%a' /usr/local/bin 2>/dev/null || true)" == "755" ]] || \
  fail "public command directory ownership or mode is unsafe: /usr/local/bin"

getent passwd "$PROBE_USER" >/dev/null 2>&1 || \
  fail "required unprivileged probe identity was not found: $PROBE_USER"

PROBE_GROUP="$(id -gn "$PROBE_USER")"
[[ -n "$PROBE_GROUP" ]] || \
  fail "could not determine the unprivileged probe group for $PROBE_USER"

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

[[ -f "$CODEX_SOURCE" && ! -L "$CODEX_SOURCE" ]] || \
  fail "resolved Codex executable is not a regular file: $CODEX_SOURCE"

[[ -x "$CODEX_SOURCE" ]] || \
  fail "resolved Codex executable is not executable: $CODEX_SOURCE"

info "Codex source selected by the root operator: $CODEX_SOURCE"
info "The installer does not establish publisher provenance; the operator is responsible for selecting an official standalone Codex executable."

plan_legacy_schedule_helper_removal

for path in \
  "$PROGRAM_DIR" \
  "$STATE_DIR" \
  "$RUNTIME_CODEX_BIN" \
  "$SCHEDULE_HELPER_DST" \
  "$SERVICE_DST" \
  "$TIMER_DST"
do
  [[ ! -e "$path" && ! -L "$path" ]] || \
    fail "existing path would collide with this installation: $path"
done

reject_systemd_collision "$SERVICE_NAME"
reject_systemd_collision "$TIMER_NAME"

if [[ -e "$CONFIG_DIR" || -L "$CONFIG_DIR" ]]; then
  if [[ -d "$CONFIG_DIR" && ! -L "$CONFIG_DIR" ]] && validate_preserved_identity; then
    REUSE_PRESERVED_IDENTITY=1
    info "Validated the exact Anchor-owned identity preserved by a prior default uninstall."
  else
    fail "existing configuration/identity state is not an exact preserved Anchor identity: $CONFIG_DIR"
  fi
fi

if (( REUSE_PRESERVED_IDENTITY == 0 )); then
  [[ ! -e "$SERVICE_HOME" && ! -L "$SERVICE_HOME" ]] || \
    fail "existing service-home object would collide with this installation: $SERVICE_HOME"
  reject_identity_name_collision passwd "$SERVICE_USER"
  reject_identity_name_collision group "$SERVICE_GROUP"
fi

info "Preflight checks passed."
info "Beginning installation."

MUTATION_STARTED=1

if (( REUSE_PRESERVED_IDENTITY == 0 )); then
  install -d -o root -g root -m 0755 "$CONFIG_DIR"
  plan_identity_ids
fi
write_meta

if (( REUSE_PRESERVED_IDENTITY == 0 )); then
  [[ ! -e "$SERVICE_HOME" && ! -L "$SERVICE_HOME" ]] || \
    fail "service-home collision appeared before identity creation: $SERVICE_HOME"

  groupadd --gid "$SERVICE_GROUP_GID" "$SERVICE_GROUP"

  [[ ! -e "$SERVICE_HOME" && ! -L "$SERVICE_HOME" ]] || \
    fail "service-home collision appeared immediately before user creation: $SERVICE_HOME"

  useradd \
    --uid "$SERVICE_USER_UID" \
    --gid "$SERVICE_GROUP" \
    --create-home \
    --home-dir "$SERVICE_HOME" \
    --shell /bin/bash \
    "$SERVICE_USER"

  [[ "$(id -u "$SERVICE_USER")" == "$SERVICE_USER_UID" ]] || \
    fail "created service user UID does not match the recorded plan"
  [[ "$(getent group "$SERVICE_GROUP" | cut -d: -f3)" == "$SERVICE_GROUP_GID" ]] || \
    fail "created service group GID does not match the recorded plan"

  # Atomically reconfirm the already-persisted identity plan immediately after
  # creation and before chmod/chown or any other fallible installation work.
  write_meta

  chmod 0700 "$SERVICE_HOME"
  chown "$SERVICE_USER:$SERVICE_GROUP" "$SERVICE_HOME"
fi

install -d -o root -g root -m 0755 "$PROGRAM_DIR"
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0700 "$STATE_DIR"
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0700 "$WORK_DIR"
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0700 "$SQLITE_DIR"

stage_codex_source

install \
  -o root \
  -g root \
  -m 0755 \
  "$STAGED_SOURCE" \
  "$RUNTIME_CODEX_BIN"

rm -f -- "$STAGED_SOURCE"
STAGED_SOURCE=""

# All executable inspection is performed on the immutable, root-owned snapshot
# as the dedicated unprivileged identity. The mutable source path is never run.
ELF_MAGIC="$(
  head -c 4 -- "$RUNTIME_CODEX_BIN" |
    od -An -tx1 |
    tr -d '[:space:]'
)"

[[ "$ELF_MAGIC" == "7f454c46" ]] || \
  fail "staged Codex snapshot is not a native Linux ELF executable"

RUNTIME_CODEX_SHA256="$(
  sha256sum "$RUNTIME_CODEX_BIN" | cut -d' ' -f1
)"

[[ "$RUNTIME_CODEX_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] || \
  fail "could not calculate the Anchor runtime SHA-256"

write_meta

CODEX_VERSION="$(runuser -u "$PROBE_USER" -- /usr/bin/env -i \
  HOME=/nonexistent USER="$PROBE_USER" LOGNAME="$PROBE_USER" \
  PATH=/usr/local/bin:/usr/bin:/bin \
  "$RUNTIME_CODEX_BIN" --version 2>&1)" || \
  fail "staged Codex snapshot failed the unprivileged version check"

EXEC_HELP="$(runuser -u "$PROBE_USER" -- /usr/bin/env -i \
  HOME=/nonexistent USER="$PROBE_USER" LOGNAME="$PROBE_USER" \
  PATH=/usr/local/bin:/usr/bin:/bin \
  "$RUNTIME_CODEX_BIN" exec --help 2>&1)" || \
  fail "staged Codex exec help could not be read as $PROBE_USER"

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
    fail "staged Codex CLI does not support required option: $flag"
done

info "Detected staged Codex runtime: $CODEX_VERSION"

if command -v restorecon >/dev/null 2>&1; then
  if ! restorecon -F "$RUNTIME_CODEX_BIN"; then
    info "Warning: restorecon reported a problem; the systemd execution probe will determine whether execution is permitted"
  fi
fi

[[ -r /proc/sys/kernel/random/uuid ]] || \
  fail "kernel UUID source is unavailable for transient probe isolation"

PROBE_UNIT="codex-window-anchor-probe-$(tr -d '-' </proc/sys/kernel/random/uuid)"
PROBE_STATUS=0

reject_systemd_collision "${PROBE_UNIT}.service"

set +e
systemd-run \
  --wait \
  --unit="$PROBE_UNIT" \
  --property="User=$PROBE_USER" \
  --property="Group=$PROBE_GROUP" \
  /usr/bin/env -i \
  HOME=/nonexistent USER="$PROBE_USER" LOGNAME="$PROBE_USER" \
  PATH=/usr/local/bin:/usr/bin:/bin \
  "$RUNTIME_CODEX_BIN" --version
PROBE_STATUS=$?
set -e

systemctl stop "${PROBE_UNIT}.service" >/dev/null 2>&1 || true
systemctl reset-failed "${PROBE_UNIT}.service" >/dev/null 2>&1 || true

(( PROBE_STATUS == 0 )) || \
  fail "systemd could not execute the Codex runtime; inspect the system journal and SELinux audit log"

install \
  -o root \
  -g root \
  -m 0755 \
  "$RUNNER_SRC" \
  "$RUNNER_DST"

install \
  -o root \
  -g root \
  -m 0755 \
  "$SCHEDULE_HELPER_SRC" \
  "$SCHEDULE_HELPER_DST"

if command -v restorecon >/dev/null 2>&1; then
  restorecon -F "$SCHEDULE_HELPER_DST" || \
    fail "could not restore the SELinux context for the schedule command"
fi

if (( REMOVE_LEGACY_SCHEDULE_HELPER == 1 )); then
  is_exact_managed_schedule_helper "$LEGACY_SCHEDULE_HELPER_DST" || \
    fail "legacy schedule command changed after preflight; refusing removal"
  rm -f -- "$LEGACY_SCHEDULE_HELPER_DST" || \
    fail "could not remove the legacy project-managed schedule command"
  info "Removed legacy schedule command: $LEGACY_SCHEDULE_HELPER_DST"
fi

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

if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify "$SERVICE_DST" || \
    fail "systemd service verification failed"
fi

systemctl daemon-reload

# Installation creates no timer unit. Recheck the complete timer namespace
# after daemon-reload so a live schedule cannot appear during installation.
reject_systemd_collision "$TIMER_NAME"

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
  No Anchor schedule was created.
  No systemd timer is enabled or active.

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

4. Choose your own timezone and one or more Anchor times:

   codex-window-anchor-schedule \
     --timezone <Area/City> \
     --time <HH:MM> \
     [--time <HH:MM> ...]

5. Review the generated schedule:

   systemctl cat ${TIMER_NAME}
   systemctl list-timers ${TIMER_NAME}

6. Explicitly enable scheduling only when ready:

   sudo systemctl enable --now ${TIMER_NAME}

NOTE:
  The Anchor uses a runtime snapshot of the Codex executable detected during
  installation. Updating another Codex installation on the host does not
  automatically replace this Anchor runtime.

EOF
