#!/usr/bin/env bash
# Managed-By: codex-window-anchor
#
# Safely remove Codex Window Anchor-managed resources.
#
# Default uninstall preserves:
# - the dedicated codex-anchor user;
# - the dedicated user's home directory;
# - Codex ChatGPT authentication stored in that home;
# - the user's original/global Codex installation;
# - system journal history;
# - swap and /etc/fstab;
# - firewall, proxy, SELinux, and unrelated services.
#
# Use --purge-user only when you explicitly want to remove the dedicated
# service user and its home directory, including Codex authentication state.

set -Eeuo pipefail
umask 077

readonly FORMAT_VERSION="1"
readonly SERVICE_USER_EXPECTED="codex-anchor"
readonly SERVICE_GROUP_EXPECTED="codex-anchor"
readonly SERVICE_HOME_EXPECTED="/home/codex-anchor"

readonly PROGRAM_DIR="/usr/local/libexec/codex-window-anchor"
readonly RUNNER_DST="${PROGRAM_DIR}/run-anchor.sh"
readonly RUNTIME_CODEX_BIN="/usr/local/bin/codex-window-anchor"

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

PURGE_USER=0
ASSUME_YES=0

META_INSTALL_STATE=""
META_SERVICE_USER=""
META_SERVICE_GROUP=""
META_SERVICE_HOME=""
META_SERVICE_UID=""
META_SERVICE_GID=""
META_RUNTIME_SHA256=""
RESIDUALS=0
IDENTITY_WAS_NEVER_CREATED=0

usage() {
  cat <<'EOF'
Usage:
  sudo ./scripts/uninstall.sh [options]

Options:
  --purge-user   Also remove the dedicated codex-anchor user and its home.
                 This removes Codex authentication stored under that home.

  --yes          Skip the interactive purge confirmation.
                 Valid only together with --purge-user.

  -h, --help     Show this help.

Default uninstall removes only Codex Window Anchor-managed project files
and preserves the dedicated user and its authentication state.

V1 reference target: AlmaLinux 8.10, systemd 239, SELinux enforcing.
No additional distribution support is claimed without integration testing.
EOF
}

info() {
  printf '[codex-window-anchor] %s\n' "$*"
}

warn() {
  printf '[codex-window-anchor] WARNING: %s\n' "$*" >&2
}

fail() {
  printf '[codex-window-anchor] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || \
    fail "required command was not found: $1"
}

meta_value() {
  local key="$1"
  local line=""

  line="$(grep -m1 -E "^${key}=" "$META_FILE" || true)"

  [[ -n "$line" ]] || return 1

  printf '%s\n' "${line#*=}"
}

is_managed_text_file() {
  local path="$1"

  [[ -f "$path" ]] || return 1
  [[ ! -L "$path" ]] || return 1

  grep -Fqx '# Managed-By: codex-window-anchor' "$path"
}

remove_managed_text_file() {
  local path="$1"

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi

  if [[ -L "$path" ]]; then
    warn "skipping unexpected symbolic link: $path"
    RESIDUALS=1
    return 0
  fi

  if ! is_managed_text_file "$path"; then
    warn "skipping file without Codex Window Anchor ownership marker: $path"
    RESIDUALS=1
    return 0
  fi

  rm -f -- "$path"
  info "Removed: $path"
}

remove_runtime_binary() {
  local path="$1"
  local owner=""
  local actual_sha=""

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi

  if [[ -L "$path" ]]; then
    warn "skipping unexpected runtime symbolic link: $path"
    RESIDUALS=1
    return 0
  fi

  if [[ ! -f "$path" ]]; then
    warn "skipping unexpected runtime object: $path"
    RESIDUALS=1
    return 0
  fi

  owner="$(stat -c '%U:%G' "$path" 2>/dev/null || true)"

  if [[ "$owner" != "root:root" ]]; then
    warn "skipping runtime binary with unexpected ownership ($owner): $path"
    RESIDUALS=1
    return 0
  fi

  if [[ ! "$META_RUNTIME_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
    warn "runtime SHA-256 is unavailable in installation metadata; preserving: $path"
    RESIDUALS=1
    return 0
  fi

  actual_sha="$(sha256sum "$path")"
  actual_sha="${actual_sha%% *}"

  if [[ "$actual_sha" != "$META_RUNTIME_SHA256" ]]; then
    warn "runtime SHA-256 no longer matches installation metadata; preserving: $path"
    RESIDUALS=1
    return 0
  fi

  rm -f -- "$path"
  info "Removed Anchor runtime snapshot: $path"
}

remove_dir_if_empty() {
  local path="$1"

  if [[ ! -e "$path" ]]; then
    return 0
  fi

  if [[ -L "$path" ]]; then
    warn "skipping unexpected directory symbolic link: $path"
    RESIDUALS=1
    return 0
  fi

  if [[ ! -d "$path" ]]; then
    warn "skipping unexpected non-directory object: $path"
    RESIDUALS=1
    return 0
  fi

  if rmdir -- "$path" 2>/dev/null; then
    info "Removed empty directory: $path"
  else
    warn "directory is not empty and was preserved: $path"
    RESIDUALS=1
  fi
}

write_preserved_identity_meta() {
  local meta_tmp=""

  meta_tmp="$(mktemp "${CONFIG_DIR}/.install.meta.XXXXXX")" || \
    fail "could not create a preserved-identity metadata temporary file"

  if ! cat >"$meta_tmp" <<EOF
MANAGED_BY=codex-window-anchor
FORMAT_VERSION=${FORMAT_VERSION}
INSTALL_STATE=uninstalled-preserved-identity
SERVICE_USER=${META_SERVICE_USER}
SERVICE_GROUP=${META_SERVICE_GROUP}
SERVICE_HOME=${META_SERVICE_HOME}
SERVICE_USER_UID=${META_SERVICE_UID}
SERVICE_GROUP_GID=${META_SERVICE_GID}
RUNTIME_CODEX_SHA256=
EOF
  then
    rm -f -- "$meta_tmp"
    fail "could not write preserved-identity metadata"
  fi

  if ! chmod 0644 "$meta_tmp" || ! chown root:root "$meta_tmp"; then
    rm -f -- "$meta_tmp"
    fail "could not secure preserved-identity metadata"
  fi

  if ! mv -f -- "$meta_tmp" "$META_FILE"; then
    rm -f -- "$meta_tmp"
    fail "could not atomically preserve identity metadata"
  fi
}

validate_purge_identity() {
  local passwd_entry=""
  local passwd_status=0
  local current_uid=""
  local current_gid=""
  local current_home=""
  local current_group=""
  local group_entry=""
  local group_status=0
  local group_name=""
  local group_gid=""

  set +e
  passwd_entry="$(getent passwd "$META_SERVICE_USER" 2>/dev/null)"
  passwd_status=$?
  group_entry="$(getent group "$META_SERVICE_GROUP" 2>/dev/null)"
  group_status=$?
  set -e

  [[ "$passwd_status" -eq 0 || "$passwd_status" -eq 2 ]] || \
    fail "NSS passwd lookup failed while validating purge identity"
  [[ "$group_status" -eq 0 || "$group_status" -eq 2 ]] || \
    fail "NSS group lookup failed while validating purge identity"

  if identity_was_never_created; then
    IDENTITY_WAS_NEVER_CREATED=1
    info "No dedicated identity was created before the interrupted installation."
    return 0
  fi

  [[ "$META_SERVICE_GID" =~ ^[0-9]+$ ]] || \
    fail "install metadata does not contain a valid service group GID; refusing purge"

  if [[ -n "$group_entry" ]]; then
    IFS=: read -r group_name _ group_gid _ <<<"$group_entry"
    [[ "$group_name" == "$META_SERVICE_GROUP" && "$group_gid" == "$META_SERVICE_GID" ]] || \
      fail "service group name/GID no longer matches installation metadata; refusing purge"
  fi

  if [[ "$passwd_status" -eq 2 ]]; then
    [[ ! -e "$META_SERVICE_HOME" && ! -L "$META_SERVICE_HOME" ]] || \
      fail "service user is absent but recorded service home remains; refusing purge and retaining metadata"
    info "Dedicated service user is already absent; no user purge is required."
    return 0
  fi

  [[ -n "$group_entry" ]] || \
    fail "recorded service group is absent while the service user exists; refusing user purge"

  [[ -n "$META_SERVICE_UID" ]] || \
    fail "install metadata does not contain a service UID; refusing user purge"

  [[ "$META_SERVICE_UID" =~ ^[0-9]+$ ]] || \
    fail "install metadata contains an invalid service UID; refusing user purge"

  IFS=: read -r _ _ current_uid current_gid _ current_home _ <<<"$passwd_entry"

  [[ "$current_uid" == "$META_SERVICE_UID" ]] || \
    fail "service user UID no longer matches installation metadata; refusing user purge"

  [[ "$current_gid" == "$META_SERVICE_GID" ]] || \
    fail "service user's primary GID no longer matches installation metadata; refusing user purge"

  [[ "$current_home" == "$META_SERVICE_HOME" ]] || \
    fail "service user home no longer matches installation metadata; refusing user purge"

  current_group="$(id -gn "$META_SERVICE_USER")"

  [[ "$current_group" == "$META_SERVICE_GROUP" ]] || \
    fail "service user's primary group no longer matches installation metadata; refusing user purge"
}

identity_is_exact_for_preservation() {
  local passwd_entry=""
  local group_entry=""
  local current_uid=""
  local passwd_gid=""
  local current_home=""
  local group_name=""
  local group_gid=""

  [[ "$META_SERVICE_UID" =~ ^[0-9]+$ && "$META_SERVICE_GID" =~ ^[0-9]+$ ]] || return 1
  passwd_entry="$(getent passwd "$META_SERVICE_USER" 2>/dev/null || true)"
  group_entry="$(getent group "$META_SERVICE_GROUP" 2>/dev/null || true)"
  [[ -n "$passwd_entry" && -n "$group_entry" ]] || return 1

  IFS=: read -r _ _ current_uid passwd_gid _ current_home _ <<<"$passwd_entry"
  IFS=: read -r group_name _ group_gid _ <<<"$group_entry"

  [[ "$current_uid" == "$META_SERVICE_UID" ]] || return 1
  [[ "$passwd_gid" == "$META_SERVICE_GID" ]] || return 1
  [[ "$group_name" == "$META_SERVICE_GROUP" && "$group_gid" == "$META_SERVICE_GID" ]] || return 1
  [[ "$current_home" == "$META_SERVICE_HOME" ]] || return 1
  [[ -d "$META_SERVICE_HOME" && ! -L "$META_SERVICE_HOME" ]] || return 1
  [[ "$(stat -c '%u:%g' "$META_SERVICE_HOME" 2>/dev/null || true)" == "${META_SERVICE_UID}:${META_SERVICE_GID}" ]] || return 1
}

identity_was_never_created() {
  local passwd_status=0
  local group_status=0

  [[ "$META_INSTALL_STATE" == "preparing" ]] || return 1
  [[ ( -z "$META_SERVICE_UID" && -z "$META_SERVICE_GID" ) || \
     ( "$META_SERVICE_UID" =~ ^[0-9]+$ && "$META_SERVICE_GID" =~ ^[0-9]+$ ) ]] || return 1

  set +e
  getent passwd "$META_SERVICE_USER" >/dev/null 2>&1
  passwd_status=$?
  getent group "$META_SERVICE_GROUP" >/dev/null 2>&1
  group_status=$?
  set -e

  [[ "$passwd_status" -eq 0 || "$passwd_status" -eq 2 ]] || \
    fail "NSS passwd lookup failed while checking whether identity was created"
  [[ "$group_status" -eq 0 || "$group_status" -eq 2 ]] || \
    fail "NSS group lookup failed while checking whether identity was created"
  [[ "$passwd_status" -eq 2 && "$group_status" -eq 2 ]] || return 1
  [[ ! -e "$META_SERVICE_HOME" && ! -L "$META_SERVICE_HOME" ]] || return 1
}

confirm_purge() {
  local reply=""

  (( PURGE_USER == 1 )) || return 0

  if (( ASSUME_YES == 1 )); then
    return 0
  fi

  [[ -r /dev/tty ]] || \
    fail "--purge-user requires an interactive terminal or the explicit --yes option"

  cat >/dev/tty <<EOF

WARNING

You requested --purge-user.

This will remove:

  User:
    ${META_SERVICE_USER}

  Home:
    ${META_SERVICE_HOME}

The home directory may contain Codex ChatGPT authentication state.

Type the exact service username below to confirm:

  ${META_SERVICE_USER}

EOF

  read -r reply </dev/tty

  [[ "$reply" == "$META_SERVICE_USER" ]] || \
    fail "purge confirmation did not match; no uninstall changes were made"
}

purge_service_user() {
  local group_entry=""
  local group_status=0
  local group_gid=""
  local group_members=""
  local passwd_status=0
  local passwd_gid=""
  local group_in_use=0

  set +e
  getent passwd "$META_SERVICE_USER" >/dev/null 2>&1
  passwd_status=$?
  group_entry="$(getent group "$META_SERVICE_GROUP" 2>/dev/null)"
  group_status=$?
  set -e

  [[ "$passwd_status" -eq 0 || "$passwd_status" -eq 2 ]] || \
    fail "NSS passwd lookup failed while purging service identity"
  [[ "$group_status" -eq 0 || "$group_status" -eq 2 ]] || \
    fail "NSS group lookup failed while purging service identity"

  if [[ "$passwd_status" -eq 2 ]]; then
    if [[ -e "$META_SERVICE_HOME" || -L "$META_SERVICE_HOME" ]]; then
      warn "service user is absent but recorded service home remains; it was preserved: $META_SERVICE_HOME"
      RESIDUALS=1
      return 0
    fi
    info "Dedicated service user is already absent."
  else
    userdel --remove "$META_SERVICE_USER" || \
      fail "failed to remove dedicated service user: $META_SERVICE_USER"

    info "Removed dedicated service user and home: $META_SERVICE_USER"
  fi

  # Some distributions automatically remove a user-private group together
  # with the user. If it remains, remove it only when it is clearly unused.
  if [[ "$group_status" -eq 2 ]]; then
    return 0
  fi

  IFS=: read -r _ _ group_gid group_members <<<"$group_entry"

  if [[ ! "$META_SERVICE_GID" =~ ^[0-9]+$ || "$group_gid" != "$META_SERVICE_GID" ]]; then
    warn "service group GID no longer matches installation metadata and was preserved: $META_SERVICE_GROUP"
    RESIDUALS=1
    return 0
  fi

  while IFS=: read -r _ _ _ passwd_gid _; do
    if [[ "$passwd_gid" == "$group_gid" ]]; then
      group_in_use=1
      break
    fi
  done < <(getent passwd)

  if (( group_in_use == 1 )); then
    warn "service group is still a primary group for another account and was preserved: $META_SERVICE_GROUP"
    RESIDUALS=1
    return 0
  fi

  if [[ -n "$group_members" ]]; then
    warn "service group still has supplementary members and was preserved: $META_SERVICE_GROUP"
    RESIDUALS=1
    return 0
  fi

  if command -v groupdel >/dev/null 2>&1; then
    if groupdel "$META_SERVICE_GROUP"; then
      info "Removed unused dedicated service group: $META_SERVICE_GROUP"
    else
      warn "could not remove dedicated service group; it was preserved: $META_SERVICE_GROUP"
      RESIDUALS=1
    fi
  else
    warn "groupdel is unavailable; dedicated service group was preserved: $META_SERVICE_GROUP"
    RESIDUALS=1
  fi
}

prove_inactive() {
  local unit="$1"
  local state=""
  local status=0

  set +e
  state="$(systemctl is-active "$unit" 2>/dev/null)"
  status=$?
  set -e
  [[ "$status" -eq 3 && "$state" == "inactive" ]] || \
    fail "could not prove $unit inactive; installation metadata was retained (status=$status, state=${state:-unknown})"
}

prove_timer_disabled() {
  local state=""
  local status=0

  set +e
  state="$(systemctl is-enabled "$TIMER_NAME" 2>/dev/null)"
  status=$?
  set -e
  [[ "$status" -eq 1 && "$state" == "disabled" ]] || \
    fail "could not prove $TIMER_NAME disabled; installation metadata was retained (status=$status, state=${state:-unknown})"
}

assert_unowned_unit_not_active() {
  local unit="$1"
  local state=""
  local status=0

  set +e
  state="$(systemctl is-active "$unit" 2>/dev/null)"
  status=$?
  set -e

  if [[ "$status" -eq 3 && "$state" == "inactive" ]]; then
    return 0
  fi
  if [[ "$status" -eq 4 && "$state" == "unknown" ]]; then
    return 0
  fi

  fail "an unrecognized same-name unit may still be active; no managed files were removed and metadata was retained: $unit (status=$status, state=${state:-unknown})"
}

while (( $# > 0 )); do
  case "$1" in
    --purge-user)
      PURGE_USER=1
      shift
      ;;
    --yes)
      ASSUME_YES=1
      shift
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

if (( ASSUME_YES == 1 )) && (( PURGE_USER == 0 )); then
  fail "--yes is valid only together with --purge-user"
fi

(( EUID == 0 )) || \
  fail "run this uninstaller with sudo or as root"

[[ "$(uname -s)" == "Linux" ]] || \
  fail "V1 reference target is AlmaLinux 8.10; the uninstaller requires Linux"

for cmd in \
  systemctl \
  grep \
  getent \
  id \
  stat \
  sha256sum \
  mktemp \
  mv \
  chmod \
  chown \
  rm \
  rmdir
do
  require_cmd "$cmd"
done

if (( PURGE_USER == 1 )); then
  require_cmd userdel
fi

[[ -f "$META_FILE" ]] || \
  fail "installation metadata was not found: $META_FILE"

[[ ! -L "$META_FILE" ]] || \
  fail "installation metadata is unexpectedly a symbolic link; refusing uninstall"

[[ "$(stat -c '%U:%G' "$META_FILE" 2>/dev/null || true)" == "root:root" ]] || \
  fail "installation metadata is not root-owned; refusing uninstall"

[[ "$(meta_value MANAGED_BY || true)" == "codex-window-anchor" ]] || \
  fail "installation metadata is not recognized as Codex Window Anchor-managed"

[[ "$(meta_value FORMAT_VERSION || true)" == "$FORMAT_VERSION" ]] || \
  fail "installation metadata has an unsupported format version"

META_INSTALL_STATE="$(meta_value INSTALL_STATE || true)"
META_SERVICE_USER="$(meta_value SERVICE_USER || true)"
META_SERVICE_GROUP="$(meta_value SERVICE_GROUP || true)"
META_SERVICE_HOME="$(meta_value SERVICE_HOME || true)"
META_SERVICE_UID="$(meta_value SERVICE_USER_UID || true)"
META_SERVICE_GID="$(meta_value SERVICE_GROUP_GID || true)"
META_RUNTIME_SHA256="$(meta_value RUNTIME_CODEX_SHA256 || true)"

[[ "$META_INSTALL_STATE" == "preparing" || \
   "$META_INSTALL_STATE" == "complete" || \
   "$META_INSTALL_STATE" == "uninstalled-preserved-identity" ]] || \
  fail "installation metadata contains an unsupported installation state"

[[ "$META_SERVICE_USER" == "$SERVICE_USER_EXPECTED" ]] || \
  fail "installation metadata contains an unexpected service user"

[[ "$META_SERVICE_GROUP" == "$SERVICE_GROUP_EXPECTED" ]] || \
  fail "installation metadata contains an unexpected service group"

[[ "$META_SERVICE_HOME" == "$SERVICE_HOME_EXPECTED" ]] || \
  fail "installation metadata contains an unexpected service home"

if (( PURGE_USER == 1 )); then
  validate_purge_identity
  confirm_purge
elif identity_was_never_created; then
  IDENTITY_WAS_NEVER_CREATED=1
  info "Interrupted installation has no dedicated identity to preserve."
elif ! identity_is_exact_for_preservation; then
  warn "the dedicated identity no longer exactly matches its UID/GID/group/home evidence; it cannot be marked as preserved for reinstall"
  RESIDUALS=1
fi

info "Validated installation metadata (state: $META_INSTALL_STATE)."

TIMER_OWNED=0
SERVICE_OWNED=0

if is_managed_text_file "$TIMER_DST"; then
  TIMER_OWNED=1
elif [[ -e "$TIMER_DST" || -L "$TIMER_DST" ]]; then
  warn "timer unit exists but ownership marker is missing; it will not be modified"
  RESIDUALS=1
fi

if is_managed_text_file "$SERVICE_DST"; then
  SERVICE_OWNED=1
elif [[ -e "$SERVICE_DST" || -L "$SERVICE_DST" ]]; then
  warn "service unit exists but ownership marker is missing; it will not be modified"
  RESIDUALS=1
fi

if (( TIMER_OWNED == 1 )); then
  systemctl disable "$TIMER_NAME" || \
    fail "could not disable $TIMER_NAME; no managed files were removed and metadata was retained"
  systemctl stop "$TIMER_NAME" || \
    fail "could not stop $TIMER_NAME; no managed files were removed and metadata was retained"
  prove_timer_disabled
  prove_inactive "$TIMER_NAME"
  info "Disabled and stopped: $TIMER_NAME"
else
  assert_unowned_unit_not_active "$TIMER_NAME"
fi

if (( SERVICE_OWNED == 1 )); then
  systemctl stop "$SERVICE_NAME" || \
    fail "could not stop $SERVICE_NAME; no managed files were removed and metadata was retained"
  prove_inactive "$SERVICE_NAME"
  info "Stopped: $SERVICE_NAME"
else
  assert_unowned_unit_not_active "$SERVICE_NAME"
fi

remove_managed_text_file "$TIMER_DST"
remove_managed_text_file "$SERVICE_DST"

systemctl daemon-reload || \
  fail "systemd daemon-reload failed; installation metadata was retained"

systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true
systemctl reset-failed "$TIMER_NAME" >/dev/null 2>&1 || true

remove_managed_text_file "$RUNNER_DST"
remove_managed_text_file "$CONFIG_FILE"

remove_runtime_binary "$RUNTIME_CODEX_BIN"

# Runtime state is expected to remain empty. Never recursively delete an
# unexpected non-empty directory.
remove_dir_if_empty "$WORK_DIR"
remove_dir_if_empty "$SQLITE_DIR"
remove_dir_if_empty "$STATE_DIR"

if (( PURGE_USER == 1 )); then
  purge_service_user
fi

remove_dir_if_empty "$PROGRAM_DIR"

if (( RESIDUALS == 1 )); then
  warn "managed or identity resources remain; installation metadata was retained for a safe retry: $META_FILE"
  exit 1
fi

if (( PURGE_USER == 1 )) || (( IDENTITY_WAS_NEVER_CREATED == 1 )); then
  rm -f -- "$META_FILE"
  info "Removed installation metadata: $META_FILE"
  remove_dir_if_empty "$CONFIG_DIR"
else
  write_preserved_identity_meta
  info "Preserved verified identity metadata for a future reinstall: $META_FILE"
fi

cat <<EOF

Codex Window Anchor uninstall completed.

Removed when safely recognized as Anchor-managed:
  - Anchor systemd timer
  - Anchor systemd service
  - Anchor runner
  - Anchor runtime snapshot
  - Anchor configuration
  - empty Anchor runtime directories
  - obsolete runtime installation metadata

Preserved:
  - the user's original/global Codex installation
  - system journal history
  - swap and /etc/fstab
  - firewall configuration
  - proxy configuration
  - SELinux configuration
  - unrelated services and files
EOF

if (( IDENTITY_WAS_NEVER_CREATED == 1 )); then
  cat <<EOF

Identity:
  - no dedicated user, group, or home had been created
EOF
elif (( PURGE_USER == 1 )); then
  cat <<EOF

Purged:
  - dedicated service user/home and authentication state
EOF
else
  cat <<EOF
  - dedicated user: ${META_SERVICE_USER}
  - dedicated home: ${META_SERVICE_HOME}
  - Codex authentication state stored under that home

If you want the uninstaller itself to remove the dedicated user and
authentication state, use --purge-user during this uninstall.

The minimal preserved identity record permits reinstall only when the exact
username, UID, group, GID, home path, and home ownership still match.
EOF
fi
