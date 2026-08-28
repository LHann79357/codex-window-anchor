#!/usr/bin/env bash
# Non-mutating static checks for the Public V1 safety and schedule contracts.

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(cd -- "${TEST_DIR}/.." && pwd -P)"
readonly INSTALL="${REPO_ROOT}/scripts/install.sh"
readonly RUNNER="${REPO_ROOT}/scripts/run-anchor.sh"
readonly UNINSTALL="${REPO_ROOT}/scripts/uninstall.sh"
readonly SCHEDULE="${REPO_ROOT}/scripts/configure-schedule.sh"
readonly README="${REPO_ROOT}/README.md"
readonly SCHEDULE_EXAMPLE="${REPO_ROOT}/examples/schedule.example"
readonly TIMER_TEMPLATE="${REPO_ROOT}/systemd/codex-window-anchor.timer.template"
readonly LIVE_TIMER_SOURCE="${REPO_ROOT}/systemd/codex-window-anchor.timer"

fail() {
  printf 'static-contract: FAIL: %s\n' "$*" >&2
  exit 1
}

require_literal() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || fail "missing required contract in ${file#$REPO_ROOT/}: $text"
}

reject_literal() {
  local file="$1"
  local text="$2"
  if grep -Fq -- "$text" "$file"; then
    fail "forbidden contract remains in ${file#$REPO_ROOT/}: $text"
  fi
}

reject_command() {
  local file="$1"
  local pattern="$2"
  if grep -Eq -- "$pattern" "$file"; then
    fail "forbidden command remains in ${file#$REPO_ROOT/}: $pattern"
  fi
}

[[ -f "$SCHEDULE" ]] || fail "missing scripts/configure-schedule.sh"
[[ -x "$SCHEDULE" ]] || fail "scripts/configure-schedule.sh is not executable in the working tree"

[[ ! -e "$LIVE_TIMER_SOURCE" ]] || fail "repository still contains a live timer source"
[[ -f "$TIMER_TEMPLATE" ]] || fail "missing non-live timer template"

require_literal "$INSTALL" 'runuser -u "$PROBE_USER" -- /usr/bin/env -i'
require_literal "$INSTALL" 'readonly PROBE_USER="nobody"'
reject_literal "$INSTALL" '"$CODEX_SOURCE" --version'
reject_literal "$INSTALL" '"$CODEX_SOURCE" exec --help'
reject_literal "$INSTALL" '"$CODEX_SOURCE" \'
reject_literal "$INSTALL" 'systemctl disable --now'
require_literal "$INSTALL" 'runuser -u "$staging_user" -- /bin/cat -- "$CODEX_SOURCE"'
require_literal "$INSTALL" 'direct-root installation refuses a group/world-writable Codex source'
require_literal "$INSTALL" 'reject_systemd_collision "${PROBE_UNIT}.service"'
require_literal "$INSTALL" 'reject_systemd_collision "$SERVICE_NAME"'
require_literal "$INSTALL" 'reject_systemd_collision "$TIMER_NAME"'
require_literal "$INSTALL" '/etc/systemd/system.control'
require_literal "$INSTALL" '/run/systemd/system.control'
require_literal "$INSTALL" '/run/systemd/transient'
require_literal "$INSTALL" 'service-home collision appeared immediately before user creation'
require_literal "$INSTALL" 'mktemp "${CONFIG_DIR}/.install.meta.XXXXXX"'
require_literal "$INSTALL" 'mv -f -- "$meta_tmp" "$META_FILE"'
require_literal "$INSTALL" 'plan_identity_ids'
require_literal "$INSTALL" 'groupadd --gid "$SERVICE_GROUP_GID"'
require_literal "$INSTALL" 'useradd \'
require_literal "$INSTALL" 'reject_identity_name_collision passwd "$SERVICE_USER"'
require_literal "$INSTALL" 'readonly SCHEDULE_HELPER_DST="/usr/local/bin/codex-window-anchor-schedule"'
require_literal "$INSTALL" 'readonly LEGACY_SCHEDULE_HELPER_DST="/usr/local/sbin/codex-window-anchor-schedule"'
require_literal "$INSTALL" 'is_exact_managed_schedule_helper "$LEGACY_SCHEDULE_HELPER_DST"'
require_literal "$INSTALL" 'rm -f -- "$LEGACY_SCHEDULE_HELPER_DST"'
require_literal "$INSTALL" '"$SCHEDULE_HELPER_SRC" \'
require_literal "$INSTALL" 'restorecon -F "$SCHEDULE_HELPER_DST"'
require_literal "$INSTALL" 'No Anchor schedule was created.'
reject_literal "$INSTALL" 'sudo codex-window-anchor-schedule'
reject_literal "$INSTALL" 'readonly TIMER_SRC='
reject_literal "$INSTALL" '"$TIMER_SRC"'

require_literal "$RUNNER" 'exec /usr/bin/env -i'
require_literal "$RUNNER" '"CODEX_SQLITE_HOME=$SQLITE_DIR"'
require_literal "$RUNNER" 'OPENAI_FEDERATION_RULE_ID'
require_literal "$RUNNER" 'CODEX_CA_CERTIFICATE SSL_CERT_FILE'
reject_literal "$RUNNER" 'export HOME='

require_literal "$UNINSTALL" 'INSTALL_STATE=uninstalled-preserved-identity'
require_literal "$UNINSTALL" 'meta_value FORMAT_VERSION'
require_literal "$UNINSTALL" 'identity_was_never_created'
require_literal "$UNINSTALL" '[[ "$passwd_status" -eq 2 && "$group_status" -eq 2 ]] || return 1'
require_literal "$UNINSTALL" 'NSS passwd lookup failed while checking whether identity was created'
require_literal "$UNINSTALL" 'NSS group lookup failed while checking whether identity was created'
require_literal "$UNINSTALL" 'service user is absent but recorded service home remains; refusing purge and retaining metadata'
require_literal "$UNINSTALL" 'service user is absent but recorded service home remains; it was preserved:'
require_literal "$UNINSTALL" 'group_gid" != "$META_SERVICE_GID"'
require_literal "$UNINSTALL" 'installation metadata was retained for a safe retry'
require_literal "$UNINSTALL" 'prove_timer_disabled'
require_literal "$UNINSTALL" 'prove_inactive "$TIMER_NAME"'
require_literal "$UNINSTALL" 'readonly SCHEDULE_HELPER_DST="/usr/local/bin/codex-window-anchor-schedule"'
require_literal "$UNINSTALL" 'readonly LEGACY_SCHEDULE_HELPER_DST="/usr/local/sbin/codex-window-anchor-schedule"'
require_literal "$UNINSTALL" 'remove_managed_text_file "$SCHEDULE_HELPER_DST"'
require_literal "$UNINSTALL" 'remove_managed_text_file "$LEGACY_SCHEDULE_HELPER_DST"'

require_literal "$SCHEDULE" '# Managed-By: codex-window-anchor'
require_literal "$SCHEDULE" 'readonly SCHEDULE_HELPER_DST="/usr/local/bin/codex-window-anchor-schedule"'
require_literal "$SCHEDULE" 'declare -a ORIGINAL_ARGS=("$@")'
require_literal "$SCHEDULE" '(( EUID != 0 )) || return 0'
require_literal "$SCHEDULE" '[[ "$resolved_path" == "$SCHEDULE_HELPER_DST" ]] || return 1'
require_literal "$SCHEDULE" '[[ "$(/usr/bin/stat -c '\''%U:%G'\'' /usr/local/bin 2>/dev/null || true)" == "root:root" ]] || return 1'
require_literal "$SCHEDULE" 'exec /usr/bin/sudo -- "$self_path" "${ORIGINAL_ARGS[@]}"'
reject_literal "$SCHEDULE" 'sudo codex-window-anchor-schedule'
reject_literal "$SCHEDULE" 'sudo -E'
require_literal "$SCHEDULE" '[[ "$TIMEZONE" != /* ]]'
require_literal "$SCHEDULE" '[[ "$TIMEZONE" != *..* ]]'
require_literal "$SCHEDULE" 'readlink -f -- "${zoneinfo_root}/${TIMEZONE}"'
require_literal "$SCHEDULE" '^([01][0-9]|2[0-3]):[0-5][0-9]$'
require_literal "$SCHEDULE" 'passwd_entry="$(getent passwd "$SERVICE_USER_EXPECTED"'
require_literal "$SCHEDULE" 'group_entry="$(getent group "$SERVICE_GROUP_EXPECTED"'
require_literal "$SCHEDULE" 'service home ownership does not match installation metadata'
require_literal "$SCHEDULE" 'Anchor runner ownership or mode is unexpected'
require_literal "$SCHEDULE" 'Anchor configuration ownership or mode is unexpected'
require_literal "$SCHEDULE" "printf 'OnCalendar=*-*-* %s:00 %s\\n'"
require_literal "$SCHEDULE" 'AccuracySec=30s'
require_literal "$SCHEDULE" 'RandomizedDelaySec=0'
require_literal "$SCHEDULE" 'Persistent=false'
require_literal "$SCHEDULE" 'Unit=codex-window-anchor.service'
require_literal "$SCHEDULE" 'mv -f -- "$TIMER_TMP" "$TIMER_DST"'
require_literal "$SCHEDULE" 'restorecon -F "$TIMER_DST"'
require_literal "$SCHEDULE" 'systemctl daemon-reload'
require_literal "$SCHEDULE" 'prove_timer_disabled_and_inactive'
require_literal "$SCHEDULE" 'sudo systemctl disable --now $TIMER_NAME'
require_literal "$SCHEDULE" '--property=FragmentPath'
require_literal "$SCHEDULE" '--property=DropInPaths'
require_literal "$SCHEDULE" '--property=Names'
require_literal "$SCHEDULE" 'Same-basename symlinks below a target directory are ordinary'
require_literal "$SCHEDULE" 'systemd alias or drop-in conflicts with the Anchor timer'
reject_command "$SCHEDULE" '^[[:space:]]*systemctl[[:space:]]+enable([[:space:]]|$)'
reject_command "$SCHEDULE" '^[[:space:]]*systemctl[[:space:]]+start([[:space:]]|$)'
reject_literal "$SCHEDULE" 'timedatectl'
reject_literal "$SCHEDULE" 'codex exec'

for file in "$INSTALL" "$UNINSTALL" "$SCHEDULE"; do
  reject_literal "$file" '/etc/sudoers'
  reject_literal "$file" 'sudoers.d'
  reject_literal "$file" '/etc/profile'
  reject_literal "$file" '/etc/environment'
done
reject_literal "$SCHEDULE" 'PATH='

require_literal "$TIMER_TEMPLATE" '# Non-live reference structure only.'
require_literal "$TIMER_TEMPLATE" 'Persistent=false'
reject_literal "$TIMER_TEMPLATE" '08:00:00'
reject_literal "$TIMER_TEMPLATE" '13:05:00'
reject_literal "$TIMER_TEMPLATE" '18:10:00'

require_literal "$README" '**Codex Window Anchor does not choose your schedule for you.**'
require_literal "$README" 'codex-window-anchor-schedule \'
require_literal "$README" '  --timezone Asia/Shanghai \'
require_literal "$README" '  --time 08:00 \'
require_literal "$README" '  --time 13:05 \'
require_literal "$README" '  --time 18:10'
require_literal "$README" 'The helper requests sudo only when it needs to update the systemd timer.'
require_literal "$README" 'More scheduled Anchors do **not** create additional quota.'
reject_literal "$README" 'sudo codex-window-anchor-schedule'
reject_literal "$README" '/usr/local/sbin/codex-window-anchor-schedule'
reject_literal "$SCHEDULE_EXAMPLE" 'sudo codex-window-anchor-schedule'

# The original defect was a syntactically valid standalone EOF command after
# the final conditional. A successful fall-through must now end at the closing
# `fi`, whose successful branch command determines a zero completion status.
last_uninstall_statement="$(awk 'NF { line=$0 } END { print line }' "$UNINSTALL")"
[[ "$last_uninstall_statement" == "fi" ]] || \
  fail "uninstall completion path does not end at its final conditional"

for script in "$INSTALL" "$RUNNER" "$UNINSTALL" "$SCHEDULE"; do
  bash -n "$script"
done

for script_path in scripts/install.sh scripts/uninstall.sh scripts/configure-schedule.sh; do
  script_mode="$(git -C "$REPO_ROOT" ls-files -s -- "$script_path" | awk '{ print $1 }')"
  [[ "$script_mode" == "100755" ]] || \
    fail "$script_path must be tracked with Git mode 100755 (current: ${script_mode:-untracked})"
done

printf 'static-contract: PASS\n'
