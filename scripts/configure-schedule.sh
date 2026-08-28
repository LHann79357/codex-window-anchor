#!/usr/bin/env bash
# Managed-By: codex-window-anchor
#
# Generate a user-selected Codex Window Anchor systemd timer.

set -Eeuo pipefail
umask 077

readonly FORMAT_VERSION="1"
readonly SERVICE_USER_EXPECTED="codex-anchor"
readonly SERVICE_GROUP_EXPECTED="codex-anchor"
readonly SERVICE_HOME_EXPECTED="/home/codex-anchor"

readonly CONFIG_DIR="/etc/codex-window-anchor"
readonly CONFIG_FILE="${CONFIG_DIR}/anchor.conf"
readonly META_FILE="${CONFIG_DIR}/install.meta"

readonly RUNNER_DST="/usr/local/libexec/codex-window-anchor/run-anchor.sh"
readonly RUNTIME_CODEX_BIN="/usr/local/bin/codex-window-anchor"
readonly SCHEDULE_HELPER_DST="/usr/local/sbin/codex-window-anchor-schedule"

readonly UNIT_DIR="/etc/systemd/system"
readonly SERVICE_NAME="codex-window-anchor.service"
readonly TIMER_NAME="codex-window-anchor.timer"
readonly SERVICE_DST="${UNIT_DIR}/${SERVICE_NAME}"
readonly TIMER_DST="${UNIT_DIR}/${TIMER_NAME}"
readonly ZONEINFO_DIR="/usr/share/zoneinfo"

TIMEZONE=""
TIMEZONE_COUNT=0
TIMER_PRESENT=0
TIMER_TMP=""
declare -a REQUESTED_TIMES=()
declare -a TIMES=()

usage() {
  cat <<'EOF'
Usage:
  sudo codex-window-anchor-schedule \
    --timezone AREA/CITY \
    --time HH:MM [--time HH:MM ...]

Choose exactly one installed IANA timezone and one or more 24-hour times.
Duplicate times are removed and the generated schedule is sorted.

This command creates or replaces only a recognized Codex Window Anchor timer.
It never enables or starts the timer and never sends an Anchor request.
EOF
}

info() {
  printf '[codex-window-anchor] %s\n' "$*"
}

fail() {
  printf '[codex-window-anchor] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$TIMER_TMP" ]]; then
    rm -f -- "$TIMER_TMP" 2>/dev/null || true
  fi
}

trap cleanup EXIT

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

  [[ -f "$path" && ! -L "$path" ]] || return 1
  grep -Fqx '# Managed-By: codex-window-anchor' "$path"
}

validate_complete_installation() {
  local recorded_uid=""
  local recorded_gid=""
  local recorded_sha=""
  local actual_sha=""
  local passwd_entry=""
  local passwd_status=0
  local group_entry=""
  local group_status=0
  local current_uid=""
  local passwd_gid=""
  local current_home=""
  local group_name=""
  local group_gid=""
  local current_group_name=""

  [[ -f "$META_FILE" && ! -L "$META_FILE" ]] || \
    fail "recognized installation metadata was not found: $META_FILE"
  [[ "$(stat -c '%U:%G' "$META_FILE" 2>/dev/null || true)" == "root:root" ]] || \
    fail "installation metadata is not root-owned"
  [[ "$(stat -c '%a' "$META_FILE" 2>/dev/null || true)" == "644" ]] || \
    fail "installation metadata has an unexpected mode"
  [[ "$(meta_value MANAGED_BY || true)" == "codex-window-anchor" ]] || \
    fail "installation metadata is not Codex Window Anchor-managed"
  [[ "$(meta_value FORMAT_VERSION || true)" == "$FORMAT_VERSION" ]] || \
    fail "installation metadata has an unsupported format version"
  [[ "$(meta_value INSTALL_STATE || true)" == "complete" ]] || \
    fail "schedule configuration requires a complete installation"
  [[ "$(meta_value SERVICE_USER || true)" == "$SERVICE_USER_EXPECTED" ]] || \
    fail "installation metadata contains an unexpected service user"
  [[ "$(meta_value SERVICE_GROUP || true)" == "$SERVICE_GROUP_EXPECTED" ]] || \
    fail "installation metadata contains an unexpected service group"
  [[ "$(meta_value SERVICE_HOME || true)" == "$SERVICE_HOME_EXPECTED" ]] || \
    fail "installation metadata contains an unexpected service home"

  recorded_uid="$(meta_value SERVICE_USER_UID || true)"
  recorded_gid="$(meta_value SERVICE_GROUP_GID || true)"
  recorded_sha="$(meta_value RUNTIME_CODEX_SHA256 || true)"
  [[ "$recorded_uid" =~ ^[0-9]+$ && "$recorded_gid" =~ ^[0-9]+$ ]] || \
    fail "installation metadata does not contain valid numeric identity evidence"
  [[ "$recorded_sha" =~ ^[0-9a-fA-F]{64}$ ]] || \
    fail "installation metadata does not contain valid runtime fingerprint evidence"

  set +e
  passwd_entry="$(getent passwd "$SERVICE_USER_EXPECTED" 2>/dev/null)"
  passwd_status=$?
  group_entry="$(getent group "$SERVICE_GROUP_EXPECTED" 2>/dev/null)"
  group_status=$?
  set -e
  [[ "$passwd_status" -eq 0 ]] || \
    fail "could not validate the exact installed service user through NSS"
  [[ "$group_status" -eq 0 ]] || \
    fail "could not validate the exact installed service group through NSS"

  IFS=: read -r _ _ current_uid passwd_gid _ current_home _ <<<"$passwd_entry"
  IFS=: read -r group_name _ group_gid _ <<<"$group_entry"
  [[ "$current_uid" == "$recorded_uid" ]] || \
    fail "service user UID does not match installation metadata"
  [[ "$passwd_gid" == "$recorded_gid" ]] || \
    fail "service user primary GID does not match installation metadata"
  [[ "$group_name" == "$SERVICE_GROUP_EXPECTED" && "$group_gid" == "$recorded_gid" ]] || \
    fail "service group name/GID does not match installation metadata"
  [[ "$current_home" == "$SERVICE_HOME_EXPECTED" ]] || \
    fail "service user home does not match installation metadata"
  current_group_name="$(id -gn "$SERVICE_USER_EXPECTED" 2>/dev/null)" || \
    fail "could not validate the service user's primary group"
  [[ "$current_group_name" == "$SERVICE_GROUP_EXPECTED" ]] || \
    fail "service user's primary group name does not match installation metadata"
  [[ -d "$SERVICE_HOME_EXPECTED" && ! -L "$SERVICE_HOME_EXPECTED" ]] || \
    fail "service home is missing or is not a safe directory"
  [[ "$(stat -c '%u:%g' "$SERVICE_HOME_EXPECTED" 2>/dev/null || true)" == "${recorded_uid}:${recorded_gid}" ]] || \
    fail "service home ownership does not match installation metadata"

  is_managed_text_file "$SERVICE_DST" || \
    fail "recognized Anchor service unit was not found: $SERVICE_DST"
  [[ "$(stat -c '%U:%G' "$SERVICE_DST" 2>/dev/null || true)" == "root:root" ]] || \
    fail "Anchor service unit is not root-owned"
  [[ "$(stat -c '%a' "$SERVICE_DST" 2>/dev/null || true)" == "644" ]] || \
    fail "Anchor service unit has an unexpected mode"

  is_managed_text_file "$RUNNER_DST" || \
    fail "recognized Anchor runner was not found: $RUNNER_DST"
  [[ "$(stat -c '%U:%G' "$RUNNER_DST" 2>/dev/null || true)" == "root:root" && \
     "$(stat -c '%a' "$RUNNER_DST" 2>/dev/null || true)" == "755" ]] || \
    fail "Anchor runner ownership or mode is unexpected"
  is_managed_text_file "$CONFIG_FILE" || \
    fail "recognized Anchor configuration was not found: $CONFIG_FILE"
  [[ "$(stat -c '%U:%G' "$CONFIG_FILE" 2>/dev/null || true)" == "root:root" && \
     "$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || true)" == "644" ]] || \
    fail "Anchor configuration ownership or mode is unexpected"
  is_managed_text_file "$SCHEDULE_HELPER_DST" || \
    fail "recognized installed schedule command was not found: $SCHEDULE_HELPER_DST"
  [[ "$(stat -c '%U:%G' "$SCHEDULE_HELPER_DST" 2>/dev/null || true)" == "root:root" && \
     "$(stat -c '%a' "$SCHEDULE_HELPER_DST" 2>/dev/null || true)" == "755" ]] || \
    fail "installed schedule command ownership or mode is unexpected"
  [[ -f "$RUNTIME_CODEX_BIN" && ! -L "$RUNTIME_CODEX_BIN" ]] || \
    fail "recognized Anchor runtime snapshot was not found: $RUNTIME_CODEX_BIN"
  [[ "$(stat -c '%U:%G' "$RUNTIME_CODEX_BIN" 2>/dev/null || true)" == "root:root" && \
     "$(stat -c '%a' "$RUNTIME_CODEX_BIN" 2>/dev/null || true)" == "755" ]] || \
    fail "Anchor runtime snapshot ownership or mode is unexpected"
  actual_sha="$(sha256sum "$RUNTIME_CODEX_BIN")"
  actual_sha="${actual_sha%% *}"
  [[ "$actual_sha" == "$recorded_sha" ]] || \
    fail "Anchor runtime snapshot does not match installation metadata"
}

validate_timezone() {
  local zoneinfo_root=""
  local resolved_zone=""

  [[ -n "$TIMEZONE" ]] || fail "exactly one --timezone AREA/CITY is required"
  [[ "$TIMEZONE" != /* ]] || fail "timezone must not be an absolute path"
  [[ "$TIMEZONE" != *..* ]] || fail "timezone must not contain '..'"
  [[ "$TIMEZONE" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)+$ ]] || \
    fail "timezone must use safe AREA/CITY syntax"

  zoneinfo_root="$(readlink -f -- "$ZONEINFO_DIR" 2>/dev/null || true)"
  [[ -n "$zoneinfo_root" && -d "$zoneinfo_root" ]] || \
    fail "installed zoneinfo directory was not found: $ZONEINFO_DIR"
  resolved_zone="$(readlink -f -- "${zoneinfo_root}/${TIMEZONE}" 2>/dev/null || true)"
  [[ -n "$resolved_zone" && -f "$resolved_zone" ]] || \
    fail "timezone is not present in installed zoneinfo data: $TIMEZONE"
  [[ "$resolved_zone" == "${zoneinfo_root}/"* ]] || \
    fail "timezone resolves outside installed zoneinfo data"
}

normalize_times() {
  local value=""
  declare -A seen=()

  (( ${#REQUESTED_TIMES[@]} > 0 )) || fail "at least one --time HH:MM is required"

  for value in "${REQUESTED_TIMES[@]}"; do
    [[ "$value" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || \
      fail "invalid 24-hour time: $value"
    seen["$value"]=1
  done

  mapfile -t TIMES < <(printf '%s\n' "${!seen[@]}" | LC_ALL=C sort)
}

assert_namespace_paths_safe() {
  local root=""
  local candidate=""
  local found=""
  local find_status=0

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
    for candidate in "${root}/${TIMER_NAME}" "${root}/${TIMER_NAME}.d"; do
      [[ ! -e "$candidate" && ! -L "$candidate" ]] && continue
      [[ "$candidate" == "$TIMER_DST" && "$TIMER_PRESENT" -eq 1 ]] && continue
      fail "systemd namespace object conflicts with the Anchor timer: $candidate"
    done

    [[ -d "$root" ]] || continue
    set +e
    if (( TIMER_PRESENT == 1 )); then
      # Same-basename symlinks below a target directory are ordinary
      # enablement links. The exact is-enabled query below handles them and
      # prints the required pause instruction. Different-name links are aliases.
      found="$(find "$root" -mindepth 1 -maxdepth 4 ! -path "$TIMER_DST" \
        \( \( -name "$TIMER_NAME" \
                ! -path "${root}/*.wants/${TIMER_NAME}" \
                ! -path "${root}/*.requires/${TIMER_NAME}" \) -o \
           -name "${TIMER_NAME}.d" -o \
           \( -type l ! -name "$TIMER_NAME" \
              \( -lname "$TIMER_NAME" -o -lname "*/${TIMER_NAME}" \) \) \) \
        -print -quit 2>/dev/null)"
    else
      found="$(find "$root" -mindepth 1 -maxdepth 4 \
        \( -name "$TIMER_NAME" -o -name "${TIMER_NAME}.d" -o \
           \( -type l \( -lname "$TIMER_NAME" -o -lname "*/${TIMER_NAME}" \) \) \) \
        -print -quit 2>/dev/null)"
    fi
    find_status=$?
    set -e
    [[ "$find_status" -eq 0 ]] || \
      fail "could not inspect the systemd namespace under: $root"
    [[ -z "$found" ]] || \
      fail "systemd alias or drop-in conflicts with the Anchor timer: $found"
  done
}

query_timer_namespace() {
  local manager_units=""
  local manager_state=""
  local unit_files=""
  local first_field=""
  local load_state=""
  local fragment_path=""
  local dropin_paths=""
  local names=""

  manager_units="$(systemctl list-units --all --full --no-legend "$TIMER_NAME" 2>/dev/null)" || \
    fail "could not query the systemd manager namespace for $TIMER_NAME"
  unit_files="$(systemctl list-unit-files --full --no-legend "$TIMER_NAME" 2>/dev/null)" || \
    fail "could not query systemd unit-file state for $TIMER_NAME"
  if (( TIMER_PRESENT == 0 )); then
    [[ -z "$manager_units" && -z "$unit_files" ]] || \
      fail "ambiguous same-name timer state exists; refusing schedule configuration"
    return 0
  fi

  manager_state="$(systemctl show "$TIMER_NAME" \
    --property=LoadState \
    --property=FragmentPath \
    --property=DropInPaths \
    --property=Names 2>/dev/null)" || \
    fail "could not query detailed systemd state for $TIMER_NAME"

  load_state="$(grep -m1 '^LoadState=' <<<"$manager_state" || true)"
  load_state="${load_state#LoadState=}"
  fragment_path="$(grep -m1 '^FragmentPath=' <<<"$manager_state" || true)"
  fragment_path="${fragment_path#FragmentPath=}"
  dropin_paths="$(grep -m1 '^DropInPaths=' <<<"$manager_state" || true)"
  dropin_paths="${dropin_paths#DropInPaths=}"
  names="$(grep -m1 '^Names=' <<<"$manager_state" || true)"
  names="${names#Names=}"

  if [[ -n "$manager_units" ]]; then
    first_field="${manager_units%%[[:space:]]*}"
    [[ "$first_field" == "$TIMER_NAME" && "$manager_units" != *$'\n'* ]] || \
      fail "ambiguous systemd manager state exists for $TIMER_NAME"
  fi

  [[ -n "$unit_files" ]] || fail "systemd did not report the existing managed timer file"
  first_field="${unit_files%%[[:space:]]*}"
  [[ "$first_field" == "$TIMER_NAME" && "$unit_files" != *$'\n'* ]] || \
    fail "ambiguous systemd unit-file state exists for $TIMER_NAME"
  [[ "$load_state" == "loaded" && "$fragment_path" == "$TIMER_DST" ]] || \
    fail "systemd did not load the exact managed Anchor timer fragment"
  [[ -z "$dropin_paths" ]] || fail "Anchor timer drop-ins are not permitted"
  [[ "$names" == "$TIMER_NAME" ]] || fail "Anchor timer aliases are not permitted"
}

prove_timer_disabled_and_inactive() {
  local state=""
  local status=0

  set +e
  state="$(systemctl is-enabled "$TIMER_NAME" 2>/dev/null)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    fail "timer is enabled; pause it first with: sudo systemctl disable --now $TIMER_NAME"
  fi
  [[ "$status" -eq 1 && "$state" == "disabled" ]] || \
    fail "could not prove $TIMER_NAME disabled (status=$status, state=${state:-unknown})"

  set +e
  state="$(systemctl is-active "$TIMER_NAME" 2>/dev/null)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    fail "timer is active; pause it first with: sudo systemctl disable --now $TIMER_NAME"
  fi
  [[ "$status" -eq 3 && "$state" == "inactive" ]] || \
    fail "could not prove $TIMER_NAME inactive (status=$status, state=${state:-unknown})"
}

validate_timer_target() {
  TIMER_PRESENT=0

  if [[ -e "$TIMER_DST" || -L "$TIMER_DST" ]]; then
    is_managed_text_file "$TIMER_DST" || \
      fail "same-name timer is not positively recognized as Anchor-managed: $TIMER_DST"
    [[ "$(stat -c '%U:%G' "$TIMER_DST" 2>/dev/null || true)" == "root:root" ]] || \
      fail "existing Anchor timer is not root-owned"
    [[ "$(stat -c '%a' "$TIMER_DST" 2>/dev/null || true)" == "644" ]] || \
      fail "existing Anchor timer has an unexpected mode"
    TIMER_PRESENT=1
  fi

  assert_namespace_paths_safe
  query_timer_namespace
  if (( TIMER_PRESENT == 1 )); then
    prove_timer_disabled_and_inactive
  fi
}

write_timer_candidate() {
  local value=""

  TIMER_TMP="$(mktemp "${UNIT_DIR}/.${TIMER_NAME}.XXXXXX.timer")" || \
    fail "could not create a timer temporary file"

  {
    cat <<EOF
# Managed-By: codex-window-anchor

[Unit]
Description=Codex Window Anchor Schedule
Documentation=https://github.com/LHann79357/codex-window-anchor

[Timer]
EOF
    for value in "${TIMES[@]}"; do
      printf 'OnCalendar=*-*-* %s:00 %s\n' "$value" "$TIMEZONE"
    done
    cat <<'EOF'

AccuracySec=30s
RandomizedDelaySec=0
Persistent=false

Unit=codex-window-anchor.service

[Install]
WantedBy=timers.target
EOF
  } >"$TIMER_TMP" || fail "could not write the timer candidate"

  chmod 0644 "$TIMER_TMP" || fail "could not set timer candidate mode"
  chown root:root "$TIMER_TMP" || fail "could not set timer candidate ownership"

  if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify "$SERVICE_DST" "$TIMER_TMP" || \
      fail "generated systemd timer verification failed"
  fi
}

while (( $# > 0 )); do
  case "$1" in
    --timezone)
      (( $# >= 2 )) || fail "--timezone requires AREA/CITY"
      (( TIMEZONE_COUNT == 0 )) || fail "exactly one --timezone may be specified"
      TIMEZONE="$2"
      TIMEZONE_COUNT=1
      shift 2
      ;;
    --time)
      (( $# >= 2 )) || fail "--time requires HH:MM"
      REQUESTED_TIMES+=("$2")
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

(( TIMEZONE_COUNT == 1 )) || fail "exactly one --timezone AREA/CITY is required"

(( EUID == 0 )) || fail "run this schedule command with sudo or as root"
[[ "$(uname -s)" == "Linux" ]] || \
  fail "V1 reference target is AlmaLinux 8.10; schedule configuration requires Linux"

for cmd in systemctl grep getent id stat sha256sum readlink sort find mktemp mv chmod chown rm cat; do
  require_cmd "$cmd"
done

validate_timezone
normalize_times
validate_complete_installation
validate_timer_target
write_timer_candidate

# Recheck collision and timer state immediately before the atomic replacement.
validate_timer_target
mv -f -- "$TIMER_TMP" "$TIMER_DST" || fail "could not atomically replace the Anchor timer"
TIMER_TMP=""

if command -v restorecon >/dev/null 2>&1; then
  restorecon -F "$TIMER_DST" || fail "could not restore the SELinux context for the Anchor timer"
fi

systemctl daemon-reload || fail "systemd daemon-reload failed after timer replacement"

TIMER_PRESENT=1
assert_namespace_paths_safe
query_timer_namespace
prove_timer_disabled_and_inactive

cat <<EOF

Configured timezone:
  ${TIMEZONE}

Configured Anchor times:
EOF
for value in "${TIMES[@]}"; do
  printf '  %s\n' "$value"
done
cat <<EOF

Timer state:
  disabled / inactive

No Anchor request was sent.

Review:

  systemctl cat ${TIMER_NAME}
  systemctl list-timers ${TIMER_NAME}

Enable only when ready:

  sudo systemctl enable --now ${TIMER_NAME}
EOF
