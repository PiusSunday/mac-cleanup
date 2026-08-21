#!/usr/bin/env bash
# lib/core/protect.sh — Centralized deletion-protection policy.
#
# Every destructive path in mac-cleanup funnels through protect::verdict.
# Keeping the policy in one file means a path can never be protected by one
# module and deleted by another, which is how v0.4.x leaked live databases and
# OS service caches into the delete queue.
#
# protect::verdict prints a short machine-readable reason and returns:
#   0  path is protected — skip it
#   1  path is eligible for deletion

[[ -n "${MAC_CLEANUP_PROTECT_LOADED:-}" ]] && return 0
MAC_CLEANUP_PROTECT_LOADED=1

# Reason of the most recent protect::verdict call (empty when eligible).
PROTECT_REASON=""

# ── Escape hatches ────────────────────────────────────────────────────────────
# Paths that live under a protected root but are genuinely disposable caches.
# Checked before every deny rule.
protect::_is_exception() {
  case "${1%/}" in
    "$HOME/.aws/cli/cache" | "$HOME/.aws/cli/cache/"*)
      return 0
      ;;
    # system_deep intentionally rotates these two log stores under /private/var/db
    /private/var/db/diagnostics | /private/var/db/diagnostics/* | \
      /private/var/db/powerlog | /private/var/db/powerlog/* | \
      /private/var/db/reportmemoryexception | /private/var/db/reportmemoryexception/*)
      return 0
      ;;
  esac
  return 1
}

# ── a) System paths ───────────────────────────────────────────────────────────
# Deleting anything here breaks or bricks the OS.
protect::_is_system_path() {
  case "${1%/}" in
    "" | / | /System | /System/* | \
      /bin | /bin/* | /sbin | /sbin/* | \
      /usr | /usr/bin | /usr/bin/* | /usr/sbin | /usr/sbin/* | \
      /usr/lib | /usr/lib/* | /usr/libexec | /usr/libexec/* | \
      /etc | /etc/* | /private/etc | /private/etc/* | \
      /private/var/db | /private/var/db/* | \
      /Library/Apple | /Library/Apple/* | \
      /Library/Extensions | /Library/Extensions/* | \
      /Library/Keychains | /Library/Keychains/* | \
      /Applications | /Volumes | /Users | /Users/*/..)
      return 0
      ;;
  esac
  return 1
}

# ── b) User data roots ────────────────────────────────────────────────────────
# The directories themselves are never removable. Contents stay eligible so
# system_deep can still evict a stale macOS installer from ~/Downloads and the
# .DS_Store sweep can still run across ~/Desktop.
protect::_is_user_data_root() {
  local p="${1%/}"
  local dir
  for dir in Documents Desktop Pictures Movies Music Downloads Library Applications Public; do
    [[ "$p" == "$HOME/$dir" ]] && return 0
  done
  [[ "$p" == "$HOME" ]] && return 0
  return 1
}

# ── c) Credentials and keys ───────────────────────────────────────────────────
protect::_is_credential_path() {
  local p="${1%/}"
  local root
  for root in \
    "$HOME/.ssh" "$HOME/.gnupg" "$HOME/.aws" "$HOME/.kube/config" \
    "$HOME/.docker/config.json" "$HOME/.config/gh" "$HOME/.netrc" \
    "$HOME/Library/Keychains" "$HOME/Library/Application Support/com.apple.TCC"; do
    [[ "$p" == "$root" || "$p" == "$root/"* ]] && return 0
  done

  # Anything whose basename advertises secret material.
  local base
  base=$(basename "$p")
  case "$base" in
    *credential* | *Credential* | id_rsa* | id_ed25519* | *.pem | *.p12 | *.keychain | *.keychain-db)
      return 0
      ;;
  esac
  return 1
}

# ── d) Live SQLite databases ──────────────────────────────────────────────────
# A cache directory routinely holds an app's working database. Removing the
# -wal/-shm sidecars of an open database corrupts it, so the whole family is
# refused whenever any member is open.
protect::is_sqlite_family() {
  local base="${1%/}"
  base="${base%-wal}"
  base="${base%-shm}"
  base="${base%-journal}"
  case "$base" in
    *.db | *.sqlite | *.sqlite3 | *.DB | *.SQLite) return 0 ;;
  esac
  return 1
}

protect::_sqlite_base() {
  local p="${1%/}"
  case "$p" in
    *-wal) printf '%s\n' "${p%-wal}" ;;
    *-shm) printf '%s\n' "${p%-shm}" ;;
    *-journal) printf '%s\n' "${p%-journal}" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

# Returns 0 when the database looks open (or cannot be proven closed).
protect::_sqlite_in_use() {
  local base
  base=$(protect::_sqlite_base "$1")

  # A live -shm means a writer holds the WAL index right now.
  [[ -e "${base}-shm" ]] && return 0

  command -v lsof >/dev/null 2>&1 || return 1

  local candidate
  for candidate in "$base" "${base}-wal"; do
    [[ -e "$candidate" ]] || continue
    if lsof -F n -- "$candidate" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# ── e) OS service caches ──────────────────────────────────────────────────────
# These are rebuilt by background daemons within minutes of deletion, so wiping
# them inflates the reclaimed number without freeing durable space. Several are
# also expensive to rebuild: e5bundlecache holds Neural Engine models compiled
# from every CoreML model on the machine, GeoServices holds downloaded map
# tiles. Opt in with --include-system-caches.
protect::_is_os_service_cache() {
  [[ "${INCLUDE_SYSTEM_CACHES:-false}" == "true" ]] && return 1

  local p="${1%/}"
  local caches="$HOME/Library/Caches"
  [[ "$p" == "$caches/"* ]] || return 1

  local entry="${p#"$caches"/}"
  entry="${entry%%/*}"

  case "$entry" in
    com.apple.* | GeoServices | CloudKit | FamilyCircle | Ostrich)
      return 0
      ;;
  esac
  return 1
}

# The Apple Neural Engine compiled-model cache is protected even when the user
# opts into system caches: rebuilding it recompiles every CoreML model on the
# machine, which costs minutes of CPU and reclaims nothing durable.
protect::_is_compiled_model_cache() {
  local p="${1%/}"
  [[ "$p" == *"/com.apple.e5rt.e5bundlecache" ]] && return 0
  [[ -d "$p/com.apple.e5rt.e5bundlecache" ]] && return 0
  return 1
}

# ── f) System preference domains ──────────────────────────────────────────────
# Bare-named plists under ~/Library/Preferences belong to macOS daemons even
# though they carry no com.apple. prefix. Deleting loginwindow.plist or
# .GlobalPreferences costs the user their session and system settings.
PROTECT_SYSTEM_PREF_DOMAINS=(
  loginwindow
  .GlobalPreferences
  .GlobalPreferences_m
  ByHost
  MobileMeAccounts
  corespotlightd
  sharedfilelistd
  mbuseragent
  icloudmailagent
  networkserviceproxy
  icdd
  knowledge-agent
  pbs
  universalaccess
  systemsound
  Bluetooth
  Audio
)

protect::is_system_pref_domain() {
  local name="$1"
  name="${name%.plist}"
  [[ "$name" == com.apple.* ]] && return 0

  local domain
  for domain in ${PROTECT_SYSTEM_PREF_DOMAINS[@]+"${PROTECT_SYSTEM_PREF_DOMAINS[@]}"}; do
    [[ "$name" == "$domain" ]] && return 0
  done

  # Daemon-style names: lowercase word ending in 'd' with no dots (e.g. icdd).
  if [[ "$name" != *.* && "$name" =~ ^[a-z][a-z0-9-]*d$ ]]; then
    return 0
  fi
  return 1
}

# ── Public entry point ────────────────────────────────────────────────────────
# Usage: protect::verdict "/abs/path" && echo "skip: $PROTECT_REASON"
protect::verdict() {
  local path="${1:-}"
  PROTECT_REASON=""

  if [[ -z "$path" ]]; then
    PROTECT_REASON="empty-path"
    return 0
  fi

  if [[ "$path" != /* ]]; then
    PROTECT_REASON="relative-path"
    return 0
  fi

  if [[ "$path" =~ (^|/)\.\.(/|$) ]]; then
    PROTECT_REASON="path-traversal"
    return 0
  fi

  if [[ "$path" == *$'\n'* ]]; then
    PROTECT_REASON="control-character"
    return 0
  fi

  if protect::_is_exception "$path"; then
    return 1
  fi

  if protect::_is_system_path "$path"; then
    PROTECT_REASON="system-path"
    return 0
  fi

  if protect::_is_user_data_root "$path"; then
    PROTECT_REASON="user-data-root"
    return 0
  fi

  if protect::_is_credential_path "$path"; then
    PROTECT_REASON="credentials"
    return 0
  fi

  if protect::_is_compiled_model_cache "$path"; then
    PROTECT_REASON="compiled-model-cache"
    return 0
  fi

  if protect::_is_os_service_cache "$path"; then
    PROTECT_REASON="os-service-cache"
    return 0
  fi

  if protect::is_sqlite_family "$path" && protect::_sqlite_in_use "$path"; then
    PROTECT_REASON="database-in-use"
    return 0
  fi

  return 1
}

# ── Claim ledger ──────────────────────────────────────────────────────────────
# Modules overlap by design: the user-cache sweep, the browser module and the
# container sweep all reach the same directories. Without a ledger each pass
# counted the same bytes again, so the dry-run preview reported far more than a
# live run could ever free. A path is claimable once per run; anything nested
# under an already-claimed path is a no-op.
PROTECT_CLAIMED_FILE="${PROTECT_CLAIMED_FILE:-}"
PROTECT_CLAIM_COUNT=0

protect::claim_reset() {
  PROTECT_CLAIMED_FILE=$(mktemp "${TMPDIR:-/tmp}/mac-cleanup-claims.XXXXXX") || PROTECT_CLAIMED_FILE=""
  PROTECT_CLAIM_COUNT=0
}

protect::claim_release() {
  [[ -n "$PROTECT_CLAIMED_FILE" && -f "$PROTECT_CLAIMED_FILE" ]] && rm -f -- "$PROTECT_CLAIMED_FILE"
  PROTECT_CLAIMED_FILE=""
}

# Returns 0 when this run has already accounted for the path (or an ancestor).
#
# Rather than testing the candidate against every claimed path — which is
# quadratic, and a machine with thousands of __pycache__ directories has
# thousands of claims — walk the candidate's own ancestors and look for an exact
# match. The ancestor list is bounded by path depth, so one grep settles it.
protect::is_claimed() {
  local path="${1%/}"
  # Test the ledger file, not the in-memory counter: a claim made inside a
  # subshell reaches the file but never the parent's counter.
  [[ -n "$PROTECT_CLAIMED_FILE" && -s "$PROTECT_CLAIMED_FILE" ]] || return 1

  local -a ancestors=()
  local node="$path"
  while [[ -n "$node" && "$node" != "/" ]]; do
    ancestors+=("$node")
    node="${node%/*}"
  done
  (( ${#ancestors[@]} > 0 )) || return 1

  printf '%s\n' "${ancestors[@]}" | grep -qxFf - "$PROTECT_CLAIMED_FILE"
}

# Claim a path for this run. Returns 1 if it was already claimed.
protect::claim() {
  local path="${1%/}"
  [[ -n "$path" ]] || return 1
  [[ -n "$PROTECT_CLAIMED_FILE" && -f "$PROTECT_CLAIMED_FILE" ]] || return 0

  if protect::is_claimed "$path"; then
    return 1
  fi
  printf '%s\n' "$path" >> "$PROTECT_CLAIMED_FILE"
  PROTECT_CLAIM_COUNT=$(( PROTECT_CLAIM_COUNT + 1 ))
  return 0
}
