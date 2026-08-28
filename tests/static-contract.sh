#!/usr/bin/env bash
# Non-mutating static checks for the confirmed Public V1 safety corrections.

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(cd -- "${TEST_DIR}/.." && pwd -P)"
readonly INSTALL="${REPO_ROOT}/scripts/install.sh"
readonly RUNNER="${REPO_ROOT}/scripts/run-anchor.sh"
readonly UNINSTALL="${REPO_ROOT}/scripts/uninstall.sh"

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

# The original defect was a syntactically valid standalone EOF command after
# the final conditional. A successful fall-through must now end at the closing
# `fi`, whose successful branch command determines a zero completion status.
last_uninstall_statement="$(awk 'NF { line=$0 } END { print line }' "$UNINSTALL")"
[[ "$last_uninstall_statement" == "fi" ]] || \
  fail "uninstall completion path does not end at its final conditional"

for script in "$INSTALL" "$RUNNER" "$UNINSTALL"; do
  bash -n "$script"
done

printf 'static-contract: PASS\n'
