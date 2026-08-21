#!/usr/bin/env bats
# tests/test_devtools.bats — Unit tests for lib/modules/dev/devtools.sh

setup() {
  TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP"
  
  source "${BATS_TEST_DIRNAME}/../lib/core/core.sh"
  source "${BATS_TEST_DIRNAME}/../lib/core/utils.sh"
  source "${BATS_TEST_DIRNAME}/../lib/modules/dev/devtools.sh"

  export DRY_RUN=true
  export SKIP_CONFIRM=true
  export VERBOSE=false

  # Clean tracking arrays
  MODULE_NAMES=()
  MODULE_CATEGORIES=()
  MODULE_STATUS=()
  MODULE_FREED=()
  MODULE_SCANNED=()
  MODULE_PROJECTED=()

  export DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  export DEVTOOLS_EXCLUDE_PATHS=()
  export PYCACHE_EXCLUDE_PATHS=()
}

teardown() {
  rm -rf "$TEST_TMP"
}



@test "devtools::_rust_targets: skips target/ without Cargo.toml" {
  if ! command -v cargo &>/dev/null; then skip "cargo not installed"; fi

  mkdir -p "$HOME/Developer/fake_rust/target"
  echo "data" > "$HOME/Developer/fake_rust/target/file"

  _DEV_RUST_TOTAL=0
  devtools::_rust_targets >/dev/null 2>&1
  [ "$_DEV_RUST_TOTAL" -eq 0 ]
}

@test "devtools::_rust_targets: detects target with Cargo.toml" {
  if ! command -v cargo &>/dev/null; then skip "cargo not installed"; fi

  mkdir -p "$HOME/Developer/real_rust/target"
  touch "$HOME/Developer/real_rust/Cargo.toml"
  echo "data" > "$HOME/Developer/real_rust/target/file"

  _DEV_RUST_TOTAL=0
  devtools::_rust_targets >/dev/null 2>&1
  [ "$_DEV_RUST_TOTAL" -gt 0 ]
}

@test "devtools::_python_cache: detects __pycache__ directories" {
  mkdir -p "$HOME/Developer/pyapp/__pycache__"
  echo "data" > "$HOME/Developer/pyapp/__pycache__/module.pyc"

  _DEV_PYTHON_TOTAL=0
  devtools::_python_cache >/dev/null 2>&1
  [ "$_DEV_PYTHON_TOTAL" -gt 0 ]
}

@test "devtools::_gradle_cache: detects gradle caches and daemon" {
  mkdir -p "$HOME/.gradle/caches/mock"
  echo "data" > "$HOME/.gradle/caches/mock/file"
  
  mkdir -p "$HOME/.gradle/daemon/7.0"
  echo "log" > "$HOME/.gradle/daemon/7.0/file"

  _DEV_GRADLE_TOTAL=0
  devtools::_gradle_cache >/dev/null 2>&1
  [ "$_DEV_GRADLE_TOTAL" -gt 0 ]
}

@test "devtools::_android: detects android sdk cache" {
  mkdir -p "$HOME/.android/cache"
  echo "data" > "$HOME/.android/cache/file"

  # Also add avd snapshots
  mkdir -p "$HOME/.android/avd/nexus5.avd/snapshots/default_boot"
  echo "snap" > "$HOME/.android/avd/nexus5.avd/snapshots/default_boot/snap.img"

  _DEV_ANDROID_TOTAL=0
  devtools::_android >/dev/null 2>&1
  [ "$_DEV_ANDROID_TOTAL" -gt 0 ]
}

@test "devtools::_vscode: detects vscode and cursor cache" {
  mkdir -p "$HOME/Library/Application Support/Code/logs/2023"
  echo "log" > "$HOME/Library/Application Support/Code/logs/2023/main.log"

  mkdir -p "$HOME/Library/Application Support/Cursor/Cache"
  echo "data" > "$HOME/Library/Application Support/Cursor/Cache/data.v"

  # Workspace storage stale
  mkdir -p "$HOME/Library/Application Support/Code/User/workspaceStorage/stale1"
  echo "data" > "$HOME/Library/Application Support/Code/User/workspaceStorage/stale1/state.json"
  # Touch it to be older than 30 days securely using touch
  touch -t 202001010101 "$HOME/Library/Application Support/Code/User/workspaceStorage/stale1/state.json"
  touch -t 202001010101 "$HOME/Library/Application Support/Code/User/workspaceStorage/stale1"

  _DEV_VSCODE_TOTAL=0
  devtools::_vscode >/dev/null 2>&1
  [ "$_DEV_VSCODE_TOTAL" -gt 0 ]
}

@test "devtools::_bun_tnpm: skips if not installed" {
  if command -v bun &>/dev/null; then skip "bun is installed natively"; fi
  
  _DEV_BUNTNPM_TOTAL=0
  devtools::_bun_tnpm >/dev/null 2>&1
  [ "$_DEV_BUNTNPM_TOTAL" -eq 0 ]
}

@test "devtools::clean: registers module properly" {
  # To avoid full disk scan, we just test that calling devtools::clean adds the module to report arrays
  # We do not mock. We will just let it run on our small $TEST_TMP environment
  devtools::clean >/dev/null 2>&1
  [[ "${MODULE_NAMES[0]}" == "Dev Artifacts" ]]
  [[ "${MODULE_CATEGORIES[0]}" == "Developer Tools" ]]
}

# ── Stale project artifacts ───────────────────────────────────────────────────
# The old scan looked for node_modules with no nearby package.json — a condition
# that essentially never holds, so it walked $HOME and reported 0 B every run.

_make_project() {
  local name="$1" age_days="$2" artifact="${3:-node_modules}"
  local dir="$HOME/Developer/$name"
  mkdir -p "$dir/$artifact"
  echo '{"name":"x"}' > "$dir/package.json"
  dd if=/dev/zero of="$dir/$artifact/blob" bs=1024 count=256 2>/dev/null
  if (( age_days > 0 )); then
    local stamp
    stamp=$(date -r "$(( $(date +%s) - age_days * 86400 ))" +%Y%m%d%H%M.%S)
    touch -t "$stamp" "$dir/package.json"
  fi
}

@test "devtools: build artifacts in a dormant project are reported" {
  _make_project dormant 200
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  STALE_PROJECT_DAYS=90
  PURGE_STALE=false
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()

  run devtools::_node_modules
  [ "$status" -eq 0 ]
  [[ "$output" == *"dormant/node_modules"* ]]
  [[ "$output" == *"1 in inactive projects"* ]]
}

@test "devtools: an actively worked project is left alone" {
  _make_project active 0
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  STALE_PROJECT_DAYS=90
  PURGE_STALE=false

  run devtools::_node_modules
  [[ "$output" == *"none"* ]]
  [[ "$output" != *"active/node_modules"* ]]
}

@test "devtools: stale artifacts are report-only until --purge-stale" {
  _make_project dormant 200
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  STALE_PROJECT_DAYS=90
  PURGE_STALE=false
  DRY_RUN=false
  ACTION_LABELS=(); ACTION_BYTES=(); ACTION_COMMANDS=()

  devtools::_node_modules >/dev/null 2>&1

  # Nothing deleted, and it does not inflate this run's reclaimable total.
  [ -d "$HOME/Developer/dormant/node_modules" ]
  [ "$_DEV_NODE_TOTAL" -eq 0 ]
  # It is offered as a decision instead.
  [ "${#ACTION_LABELS[@]}" -eq 1 ]
  [[ "${ACTION_COMMANDS[0]}" == *"--purge-stale"* ]]
}

@test "devtools: --purge-stale deletes the dormant project's artifacts" {
  _make_project dormant 200
  _make_project active 0
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  STALE_PROJECT_DAYS=90
  PURGE_STALE=true
  DRY_RUN=false

  devtools::_node_modules >/dev/null 2>&1

  [ ! -d "$HOME/Developer/dormant/node_modules" ]
  [ -d "$HOME/Developer/active/node_modules" ]
  [ "$_DEV_NODE_TOTAL" -gt 0 ]
}

@test "devtools: the staleness threshold is configurable" {
  _make_project midaged 120
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  PURGE_STALE=false

  STALE_PROJECT_DAYS=200
  run devtools::_node_modules
  [[ "$output" == *"none"* ]]

  STALE_PROJECT_DAYS=30
  run devtools::_node_modules
  [[ "$output" == *"midaged/node_modules"* ]]
}

@test "devtools: artifact kinds beyond node_modules are covered" {
  _make_project rustproj 200 target
  _make_project webproj 200 .next
  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  STALE_PROJECT_DAYS=90
  PURGE_STALE=false

  run devtools::_node_modules
  [[ "$output" == *"rustproj/target"* ]]
  [[ "$output" == *"webproj/.next"* ]]
}

@test "devtools: staleness is judged from the project root, not the artifact's parent" {
  # A Flutter app's android/.gradle sits two levels under the pubspec.yaml that
  # dates the project. Judging from android/ found no source files and reported
  # the artifact as untouched since the epoch — 20685 days.
  local app="$HOME/Developer/flutterapp"
  mkdir -p "$app/android/.gradle"
  echo 'name: flutterapp' > "$app/pubspec.yaml"
  dd if=/dev/zero of="$app/android/.gradle/blob" bs=1024 count=256 2>/dev/null

  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  STALE_PROJECT_DAYS=90
  PURGE_STALE=false

  # pubspec.yaml is fresh, so the whole app is active.
  run devtools::_node_modules
  [[ "$output" != *".gradle"* ]]
  [[ "$output" != *"20685"* ]]
}

@test "devtools: an undatable directory is skipped, never reported with a bogus age" {
  # No project marker anywhere above it.
  mkdir -p "$HOME/Developer/loose/node_modules"
  dd if=/dev/zero of="$HOME/Developer/loose/node_modules/blob" bs=1024 count=256 2>/dev/null

  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  STALE_PROJECT_DAYS=90
  PURGE_STALE=false

  run devtools::_node_modules
  [ "$status" -eq 0 ]
  [[ "$output" != *"untouched 2"*"d)"* ]] || [[ "$output" == *"none"* ]]
  [[ "$output" != *"20685"* ]]
}

@test "devtools: reported paths are distinguishable between projects" {
  # Eleven rows all labelled "android/.gradle" tell the user nothing.
  local a="$HOME/Developer/appone" b="$HOME/Developer/apptwo"
  local stamp
  stamp=$(date -r "$(( $(date +%s) - 200 * 86400 ))" +%Y%m%d%H%M.%S)
  for app in "$a" "$b"; do
    mkdir -p "$app/android/.gradle"
    echo 'name: x' > "$app/pubspec.yaml"
    dd if=/dev/zero of="$app/android/.gradle/blob" bs=1024 count=256 2>/dev/null
    touch -t "$stamp" "$app/pubspec.yaml"
  done

  DEVTOOLS_SCAN_DIRS=("$HOME/Developer")
  STALE_PROJECT_DAYS=90
  PURGE_STALE=false

  run devtools::_node_modules
  [[ "$output" == *"appone/android/.gradle"* ]]
  [[ "$output" == *"apptwo/android/.gradle"* ]]
}

# ── Editor workspace storage ──────────────────────────────────────────────────
# v0.4.3 selected workspaceStorage directories with `find -mtime +30` alone,
# which answers "not opened recently", not "no longer needed". On the
# development machine that flagged 27 workspaces whose projects still existed —
# 862 MB of live editor state, including the repo open at the time — against 3
# that were genuinely dead.

_make_workspace() {
  local editor="$1" hash="$2" json="$3"
  local dir="$HOME/Library/Application Support/$editor/User/workspaceStorage/$hash"
  mkdir -p "$dir"
  dd if=/dev/zero of="$dir/state.vscdb" bs=1024 count=256 2>/dev/null
  [[ "$json" == "NONE" ]] || printf '%s' "$json" > "$dir/workspace.json"
  # Older than the 30-day gate so only the folder check decides.
  touch -t "$(date -r "$(( $(date +%s) - 200 * 86400 ))" +%Y%m%d%H%M.%S)" "$dir"
  printf '%s\n' "$dir"
}

@test "devtools: a workspace whose project still exists is kept" {
  local proj="$HOME/Developer/liveproject"
  mkdir -p "$proj"
  local ws
  ws=$(_make_workspace Code alive "{\"folder\": \"file://$proj\"}")

  run devtools::_workspace_is_dead "$ws"
  [ "$status" -ne 0 ]
}

@test "devtools: a workspace whose project was deleted is reclaimable" {
  local ws
  ws=$(_make_workspace Code dead '{"folder": "file:///Users/nobody/deleted-project"}')

  run devtools::_workspace_is_dead "$ws"
  [ "$status" -eq 0 ]
}

@test "devtools: a percent-encoded project path is decoded before checking" {
  # "SoCode Flutter Projects" is stored as SoCode%20Flutter%20Projects; failing
  # to decode means concluding a live folder is gone.
  local proj="$HOME/Developer/Space Named Project"
  mkdir -p "$proj"
  local encoded="${proj// /%20}"
  local ws
  ws=$(_make_workspace Code encoded "{\"folder\": \"file://$encoded\"}")

  run devtools::_workspace_folder "$ws/workspace.json"
  [ "$output" = "$proj" ]

  run devtools::_workspace_is_dead "$ws"
  [ "$status" -ne 0 ]
}

@test "devtools: a workspace with no workspace.json is kept, never guessed at" {
  local ws
  ws=$(_make_workspace Code nojson NONE)

  run devtools::_workspace_is_dead "$ws"
  [ "$status" -ne 0 ]
}

@test "devtools: an unparseable workspace.json is kept" {
  local ws
  ws=$(_make_workspace Code broken 'not json at all {{{')

  run devtools::_workspace_is_dead "$ws"
  [ "$status" -ne 0 ]
}

@test "devtools: a remote workspace is kept — its folder cannot be checked here" {
  local ws
  ws=$(_make_workspace Code remote '{"folder": "vscode-remote://ssh-remote%2Bbox/home/me/proj"}')

  run devtools::_workspace_is_dead "$ws"
  [ "$status" -ne 0 ]
}

@test "devtools: a .code-workspace file entry is understood too" {
  local ws
  ws=$(_make_workspace Code multiroot '{"workspace": "file:///Users/nobody/gone.code-workspace"}')

  run devtools::_workspace_is_dead "$ws"
  [ "$status" -eq 0 ]
}

@test "devtools: the editor sweep deletes only the dead workspace" {
  local proj="$HOME/Developer/stillhere"
  mkdir -p "$proj"
  local alive dead nojson
  alive=$(_make_workspace Code w-alive "{\"folder\": \"file://$proj\"}")
  dead=$(_make_workspace Code w-dead '{"folder": "file:///Users/nobody/gone"}')
  nojson=$(_make_workspace Code w-nojson NONE)

  DRY_RUN=false
  run devtools::_vscode
  [ "$status" -eq 0 ]

  [ -d "$alive" ]
  [ -d "$nojson" ]
  [ ! -d "$dead" ]
}

@test "devtools: mtime alone never selects a workspace" {
  # The regression: an old directory for a project that still exists.
  local proj="$HOME/Developer/oldbutalive"
  mkdir -p "$proj"
  local ws
  ws=$(_make_workspace Code ancient "{\"folder\": \"file://$proj\"}")
  touch -t 200001010000.00 "$ws"

  DRY_RUN=false
  devtools::_vscode >/dev/null 2>&1
  [ -d "$ws" ]
}
