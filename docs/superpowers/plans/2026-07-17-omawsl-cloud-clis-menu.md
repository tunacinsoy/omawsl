# omawsl Cloud CLIs Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carve Azure CLI out of the "Languages & cloud tools" picker into a new, first-class `cloud` category (parallel to `language`/`editor`/`storage`), and add working install/uninstall/doctor/update support for it plus two new tools: AWS CLI and GCP CLI.

**Architecture:** A new `install/terminal/cloud-clis.sh` (install side) and `uninstall/cloud-clis.sh` (uninstall side) hold the three tools' install/uninstall functions - Azure CLI moved verbatim from `cloud-tools.sh`/`dev-language.sh`, GCP CLI added with the same apt-repo shape, AWS CLI added with a curl/unzip/sudo-installer shape split into a guarded entry point and an unguarded `_install_steps` function (so it can also join the orphan-tools registry, since it has no native updater). `bin/omawsl-sub/items.sh` gains a `cloud` category; `install.sh`/`uninstall.sh`/`doctor.sh`/`first-run-choices.sh` each gain the same `cloud` handling their `storage` category already has, one function per file, mirroring that existing pattern exactly.

**Tech Stack:** Bash (`set -euo pipefail`), `gum choose --no-limit`/`--selected` (existing picker convention), `apt-get`/`gpg`/`curl` (Azure CLI/GCP CLI repo-add, same shape as `install/terminal/cloud-tools.sh`), `curl`+`unzip`+`sudo` (AWS CLI's official v2 installer), `dpkg --print-architecture` (existing arch-detection idiom, reused for AWS CLI's arch-specific download URL), bats-core for tests (`tests/helpers/stubs.bash`).

## Global Constraints

- Every new/modified script starts with `#!/usr/bin/env bash` + `set -euo pipefail`, matching every existing script in this repo.
- Comma-delimited list membership always goes through `omawsl_list_has` (`install/lib.sh`) — never a bare substring/`==` check.
- Every apt-repo-based install function isolates a repo-add/apt-get failure with `{ ... } || ok=0`, removes any partially-written sources file on failure (so a retry doesn't inherit a broken repo), and reports-but-doesn't-abort — the exact shape `install/terminal/cloud-tools.sh`'s `omawsl_install_terraform`/`omawsl_install_azure_cli` already use.
- AWS CLI's install function must be split into an unguarded `omawsl_aws_cli_install_steps` (the actual commands) and a guarded `omawsl_install_aws_cli` (checks `command -v aws` first) — the unguarded one is what `bin/omawsl-sub/orphan-tools.sh`'s update-apply path calls directly, bypassing the guard, exactly like `app-opencode.sh`'s `omawsl_opencode_install_steps`/`omawsl_install_opencode` split.
- Azure CLI and GCP CLI are **not** added to the orphan-tools registry — both are apt-installed, so `sudo apt upgrade` already covers them (same reason Terraform is excluded today).
- Terraform is **not** moving — it stays in the `language` category exactly as today. Only Azure CLI moves category (to `cloud`); AWS CLI and GCP CLI are new additions to `cloud`.
- **Never run git commands through `wsl.exe`** — this repo lives on the Windows filesystem; only plain Windows-native `git` is safe here. `wsl.exe` is only for running bash scripts/bats tests.
- **Do NOT run `git clean` for any reason** inside any worktree used for this work.
- Source of truth: `docs/superpowers/specs/2026-07-17-omawsl-cloud-clis-menu-design.md`. Section references (`§N`) below point there.

---

## File structure for this feature

```
install/terminal/
├── libraries.sh          # add `unzip` to the base apt package list (Task 1)
├── cloud-tools.sh        # shrink to Terraform-only, Azure CLI moves out (Task 3)
├── cloud-clis.sh         # NEW - Azure CLI (moved), AWS CLI (new), GCP CLI (new) (Task 4)
└── terminal.sh           # wire cloud-clis.sh into the fixed script order (Task 5)
uninstall/
├── dev-language.sh       # Azure CLI case removed (Task 6)
└── cloud-clis.sh         # NEW - inverse of install/terminal/cloud-clis.sh (Task 6)
bin/omawsl-sub/
├── items.sh              # new `cloud` category: azure/aws/gcp slugs+labels (Task 2)
├── install.sh            # cloud category wiring (Task 7)
├── uninstall.sh          # cloud category wiring (Task 8)
├── doctor.sh             # cloud category wiring (Task 9)
└── orphan-tools.sh       # AWS CLI joins as the 8th orphan tool (Task 11)
bin/omawsl                 # usage text tweak (Task 7)
install/first-run-choices.sh  # new "Cloud CLIs" prompt (Task 10)
README.md                  # what-you-get list (Task 12)
docs/updating.md            # new Cloud CLIs section (Task 12)
tests/
├── libraries_test.bats               # extended (Task 1)
├── omawsl_uninstall_command_test.bats # extended (Tasks 2, 8)
├── cloud_tools_test.bats             # Azure CLI cases removed (Task 3)
├── cloud_clis_test.bats              # NEW (Task 4)
├── uninstall_dev_language_test.bats  # Azure CLI case removed (Task 6)
├── uninstall_cloud_clis_test.bats    # NEW (Task 6)
├── omawsl_install_command_test.bats  # extended (Task 7)
├── omawsl_doctor_test.bats           # extended (Task 9)
├── first_run_choices_test.bats       # extended (Task 10)
├── install_test.bats                 # gum response order fixed (Task 10)
└── omawsl_orphan_tools_test.bats     # extended (Task 11)
```

---

### Task 1: `unzip` joins the base package list

AWS CLI's official installer needs `unzip`, which isn't currently installed anywhere in this repo. `install/terminal/libraries.sh` already runs before `cloud-tools.sh`/`cloud-clis.sh` in `install/terminal.sh`'s fixed order, so adding it there guarantees it's present by the time AWS CLI's installer needs it.

**Files:**
- Modify: `install/terminal/libraries.sh:6-13`
- Test: `tests/libraries_test.bats`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new (this task only adds an apt package to an existing install command).

- [ ] **Step 1: Write the failing test**

Add this assertion inside the existing `@test "installs the full Omakub-parity native-build/library set"` in `tests/libraries_test.bats` (after the `postgresql-client-common` assertion, line 22):

```bash
  [[ "$calls" == *"unzip"* ]]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/libraries_test.bats"`
Expected: FAIL (`unzip` not found in the apt-get call).

- [ ] **Step 3: Add `unzip` to the package list**

In `install/terminal/libraries.sh`, change:

```bash
    postgresql-client postgresql-client-common
```

to:

```bash
    postgresql-client postgresql-client-common \
    unzip
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/libraries_test.bats"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install/terminal/libraries.sh tests/libraries_test.bats
git commit -m "feat: install unzip as a base package (needed by AWS CLI's installer)"
```

---

### Task 2: `items.sh` gains the `cloud` category

**Files:**
- Modify: `bin/omawsl-sub/items.sh:9-61`
- Test: `tests/omawsl_uninstall_command_test.bats:15-36`

**Interfaces:**
- Consumes: nothing new.
- Produces: `omawsl_item_category azure|aws|gcp` → `"cloud"`; `omawsl_item_label aws` → `"AWS CLI"`, `omawsl_item_label gcp` → `"GCP CLI"` (azure's existing `"Azure CLI"` label is unchanged); `omawsl_item_slugs cloud` → `azure`, `aws`, `gcp` (one per line, in that order).

- [ ] **Step 1: Write the failing tests**

In `tests/omawsl_uninstall_command_test.bats`, replace the existing `@test "omawsl_item_category classifies every known slug correctly"` (lines 15-23) with:

```bash
@test "omawsl_item_category classifies every known slug correctly" {
  [[ "$(omawsl_item_category go)" == "language" ]]
  [[ "$(omawsl_item_category terraform)" == "language" ]]
  [[ "$(omawsl_item_category azure)" == "cloud" ]]
  [[ "$(omawsl_item_category aws)" == "cloud" ]]
  [[ "$(omawsl_item_category gcp)" == "cloud" ]]
  [[ "$(omawsl_item_category vscode)" == "editor" ]]
  [[ "$(omawsl_item_category gh-copilot)" == "editor" ]]
  [[ "$(omawsl_item_category mysql)" == "storage" ]]
  [[ "$(omawsl_item_category docker)" == "docker" ]]
  ! omawsl_item_category not-a-real-slug
}
```

Replace `@test "omawsl_item_label maps every slug to its exact picker label"` (lines 25-30) with:

```bash
@test "omawsl_item_label maps every slug to its exact picker label" {
  [[ "$(omawsl_item_label ruby)" == "Ruby on Rails" ]]
  [[ "$(omawsl_item_label vscode)" == "VS Code" ]]
  [[ "$(omawsl_item_label gh-copilot)" == "GitHub Copilot CLI" ]]
  [[ "$(omawsl_item_label postgresql)" == "PostgreSQL" ]]
  [[ "$(omawsl_item_label azure)" == "Azure CLI" ]]
  [[ "$(omawsl_item_label aws)" == "AWS CLI" ]]
  [[ "$(omawsl_item_label gcp)" == "GCP CLI" ]]
}
```

Replace `@test "omawsl_item_slugs lists all 10 language slugs, 8 editor slugs, 3 storage slugs"` (lines 32-36) with:

```bash
@test "omawsl_item_slugs lists all 9 language slugs, 3 cloud slugs, 8 editor slugs, 3 storage slugs" {
  [[ "$(omawsl_item_slugs language | wc -l)" -eq 9 ]]
  [[ "$(omawsl_item_slugs language)" != *"azure"* ]]
  [[ "$(omawsl_item_slugs cloud | wc -l)" -eq 3 ]]
  [[ "$(omawsl_item_slugs cloud)" == *"azure"* ]]
  [[ "$(omawsl_item_slugs cloud)" == *"aws"* ]]
  [[ "$(omawsl_item_slugs cloud)" == *"gcp"* ]]
  [[ "$(omawsl_item_slugs editor | wc -l)" -eq 8 ]]
  [[ "$(omawsl_item_slugs storage | wc -l)" -eq 3 ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_uninstall_command_test.bats"`
Expected: FAIL (azure still classified as `language`; no `aws`/`gcp` slugs yet).

- [ ] **Step 3: Update `items.sh`**

In `bin/omawsl-sub/items.sh`, change `omawsl_item_category` (lines 9-17) from:

```bash
omawsl_item_category() {
  case "$1" in
    ruby|node|go|php|python|elixir|rust|java|terraform|azure) echo "language" ;;
    vscode|neovim|opencode|cursor|claude|codex|gh-copilot|gemini) echo "editor" ;;
    mysql|redis|postgresql) echo "storage" ;;
    docker) echo "docker" ;;
    *) return 1 ;;
  esac
}
```

to:

```bash
omawsl_item_category() {
  case "$1" in
    ruby|node|go|php|python|elixir|rust|java|terraform) echo "language" ;;
    azure|aws|gcp) echo "cloud" ;;
    vscode|neovim|opencode|cursor|claude|codex|gh-copilot|gemini) echo "editor" ;;
    mysql|redis|postgresql) echo "storage" ;;
    docker) echo "docker" ;;
    *) return 1 ;;
  esac
}
```

Change `omawsl_item_label` (lines 24-49) by adding two new case arms right after the existing `azure) echo "Azure CLI" ;;` line:

```bash
    azure) echo "Azure CLI" ;;
    aws) echo "AWS CLI" ;;
    gcp) echo "GCP CLI" ;;
```

Change `omawsl_item_slugs` (lines 54-61) from:

```bash
omawsl_item_slugs() {
  case "$1" in
    language) printf '%s\n' ruby node go php python elixir rust java terraform azure ;;
    editor) printf '%s\n' vscode neovim opencode cursor claude codex gh-copilot gemini ;;
    storage) printf '%s\n' mysql redis postgresql ;;
    *) return 1 ;;
  esac
}
```

to:

```bash
omawsl_item_slugs() {
  case "$1" in
    language) printf '%s\n' ruby node go php python elixir rust java terraform ;;
    cloud) printf '%s\n' azure aws gcp ;;
    editor) printf '%s\n' vscode neovim opencode cursor claude codex gh-copilot gemini ;;
    storage) printf '%s\n' mysql redis postgresql ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_uninstall_command_test.bats"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/items.sh tests/omawsl_uninstall_command_test.bats
git commit -m "feat: add a cloud category to the item registry (azure/aws/gcp)"
```

---

### Task 3: Shrink `cloud-tools.sh` to Terraform only

Azure CLI's install function moves to the new `install/terminal/cloud-clis.sh` in Task 4. This task only removes it from here and from the `OMAWSL_LANGUAGES`-driven dispatcher.

**Files:**
- Modify: `install/terminal/cloud-tools.sh`
- Test: `tests/cloud_tools_test.bats`

**Interfaces:**
- Consumes: nothing new.
- Produces: `omawsl_cloud_tools()` now only ever installs Terraform (reads `OMAWSL_LANGUAGES`). `omawsl_install_azure_cli` no longer exists in this file (moves to Task 4).

- [ ] **Step 1: Update the test file first (defines the new expected shape)**

In `tests/cloud_tools_test.bats`, delete the entire `# --- omawsl_install_azure_cli -------------------------------------------------` block (lines 104-171, every `@test "azure-cli: ..."` case) and delete the `OMAWSL_AZURE_CLI_APT_SOURCES_FILE`/`OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR` exports from `setup()` (lines 24-25) and the `stub_hide_command terraform az` call's `az` argument (line 16, becomes `stub_hide_command terraform`). Replace the `# --- omawsl_cloud_tools ---` section (lines 195-227) with:

```bash
# --- omawsl_cloud_tools --------------------------------------------------------

@test "cloud_tools: installs terraform when selected" {
  stub_command curl
  export OMAWSL_LANGUAGES="Terraform"
  omawsl_cloud_tools
  [[ "$(stub_calls)" == *"apt-get install -y terraform"* ]]
}

@test "cloud_tools: selecting nothing installs nothing" {
  export OMAWSL_LANGUAGES="Go,Rust"
  omawsl_cloud_tools
  [[ "$(stub_calls)" != *"terraform"* ]]
}
```

The full updated `setup()` block (lines 5-26) becomes:

```bash
setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/cloud-tools.sh"
  stub_command sudo
  stub_command gpg
  # This WSL instance has real terraform installed on it (from a real
  # Task 6 verification run) - hide it so `command -v terraform` behaves
  # the same on this machine as on a fresh one, regardless of what's
  # actually installed.
  stub_hide_command terraform
  # Same reason: this instance also has a real, already-configured
  # /etc/apt/sources.list.d/hashicorp.list. The omawsl_cloud_tools-level
  # tests below call the dispatcher with no explicit paths, which falls
  # back to the real system paths - override via env var so they always
  # see a fresh, non-existent sources file regardless of host state.
  export OMAWSL_TERRAFORM_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/hashicorp-default.list"
  export OMAWSL_TERRAFORM_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings-default"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/cloud_tools_test.bats"`
Expected: FAIL (`omawsl_cloud_tools` still tries to install azure-cli when asked, since the source file hasn't changed yet - or PASS-by-accident is fine too since the new tests don't select Azure CLI at all; either way, proceed to Step 3 to make the file match the new shape).

- [ ] **Step 3: Remove Azure CLI from `cloud-tools.sh`**

In `install/terminal/cloud-tools.sh`, delete the entire `omawsl_install_azure_cli` function (lines 69-109) and its preceding comment. Change `omawsl_cloud_tools` (lines 111-128) from:

```bash
# omawsl_cloud_tools
# Reads OMAWSL_LANGUAGES (Terraform/Azure CLI live in the same picker as
# the 8 languages - design spec §6) and installs each selected tool.
# Nothing pre-selected by default; selecting neither is a valid no-op.
# Each install function already swallows its own failure internally and
# always returns 0, so no extra isolation logic is needed here - a failed
# Terraform install simply doesn't stop Azure CLI from still being tried.
omawsl_cloud_tools() {
  local languages="${OMAWSL_LANGUAGES:-}"

  if omawsl_list_has "$languages" "Terraform"; then
    omawsl_install_terraform
  fi

  if omawsl_list_has "$languages" "Azure CLI"; then
    omawsl_install_azure_cli
  fi
}
```

to:

```bash
# omawsl_cloud_tools
# Reads OMAWSL_LANGUAGES (Terraform lives in the same picker as the 8
# languages - design spec §6) and installs it if selected. Cloud provider
# CLIs (Azure/AWS/GCP) live in their own OMAWSL_CLOUD_CLIS-driven picker -
# see install/terminal/cloud-clis.sh.
omawsl_cloud_tools() {
  local languages="${OMAWSL_LANGUAGES:-}"

  if omawsl_list_has "$languages" "Terraform"; then
    omawsl_install_terraform
  fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/cloud_tools_test.bats"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install/terminal/cloud-tools.sh tests/cloud_tools_test.bats
git commit -m "refactor: move Azure CLI out of cloud-tools.sh into its own cloud-clis picker"
```

---

### Task 4: `install/terminal/cloud-clis.sh` — Azure CLI (moved), AWS CLI (new), GCP CLI (new)

**Files:**
- Create: `install/terminal/cloud-clis.sh`
- Test: `tests/cloud_clis_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (`install/lib.sh`, existing).
- Produces: `omawsl_install_azure_cli [apt_sources_file] [keyrings_dir]`, `omawsl_install_gcp_cli [apt_sources_file] [keyrings_dir]`, `omawsl_aws_cli_arch` (prints `x86_64` or `aarch64`), `omawsl_aws_cli_install_steps` (unguarded), `omawsl_install_aws_cli` (guarded), `omawsl_cloud_clis()` (reads `OMAWSL_CLOUD_CLIS`). Later tasks (5, 7, 11) call `omawsl_cloud_clis`, `omawsl_install_azure_cli`/`omawsl_install_aws_cli`/`omawsl_install_gcp_cli` directly, and `omawsl_aws_cli_install_steps` directly (bypassing its guard).

- [ ] **Step 1: Write the failing tests**

Create `tests/cloud_clis_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/cloud-clis.sh"
  stub_command sudo
  stub_command gpg
  stub_hide_command az gcloud aws
  export OMAWSL_AZURE_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/azure-cli-default.list"
  export OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings-default"
  export OMAWSL_GCP_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/google-cloud-sdk-default.list"
  export OMAWSL_GCP_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings-default"
}

# --- omawsl_install_azure_cli (moved from cloud-tools.sh, same behavior) ---

@test "azure-cli: installs via apt when not already present" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/azure-cli.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_azure_cli "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL -o /dev/null https://packages.microsoft.com/repos/azure-cli/dists/"*"/Release"* ]]
  [[ "$(stub_calls)" == *"curl -fsSL https://packages.microsoft.com/keys/microsoft.asc"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --yes --dearmor -o $keyrings_dir/microsoft.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo tee $sources_file"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y azure-cli"* ]]
}

@test "azure-cli: no-ops when already installed" {
  stub_command curl
  stub_command az
  run omawsl_install_azure_cli "$BATS_TEST_TMPDIR/azure-cli.list" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "azure-cli: isolates a repo-add failure instead of aborting" {
  stub_command curl 1
  sources_file="$BATS_TEST_TMPDIR/azure-cli-fail.list"
  run omawsl_install_azure_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Azure CLI install failed"* ]]
  [[ "$(stub_calls)" != *"apt-get install -y azure-cli"* ]]
}

# --- omawsl_install_gcp_cli -------------------------------------------------

@test "gcp-cli: installs via apt when not already present" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/google-cloud-sdk.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_gcp_cli "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --yes --dearmor -o $keyrings_dir/google.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo tee $sources_file"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y google-cloud-cli"* ]]
}

@test "gcp-cli: no-ops when already installed" {
  stub_command curl
  stub_command gcloud
  run omawsl_install_gcp_cli "$BATS_TEST_TMPDIR/google-cloud-sdk.list" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "gcp-cli: skips the repo-add step when the sources file already exists" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/google-cloud-sdk-existing.list"
  : > "$sources_file"
  run omawsl_install_gcp_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y google-cloud-cli"* ]]
}

@test "gcp-cli: isolates a repo-add failure instead of aborting" {
  stub_command curl 1
  sources_file="$BATS_TEST_TMPDIR/google-cloud-sdk-fail.list"
  run omawsl_install_gcp_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GCP CLI install failed"* ]]
  [[ "$(stub_calls)" != *"apt-get install -y google-cloud-cli"* ]]
}

@test "gcp-cli: removes the sources file when apt-get itself fails, so a retry doesn't inherit a broken repo listing" {
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    if [[ "$1" == "apt-get" ]]; then
      return 1
    fi
    if [[ "$1" == "rm" ]]; then
      shift
      command rm "$@"
      return $?
    fi
    return 0
  }
  export -f sudo
  sources_file="$BATS_TEST_TMPDIR/google-cloud-sdk-preexisting.list"
  : > "$sources_file"
  run omawsl_install_gcp_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [ ! -f "$sources_file" ]
  [[ "$output" == *"GCP CLI install failed"* ]]
}

# --- AWS CLI -----------------------------------------------------------------

@test "aws-cli-arch: maps dpkg's arm64 to aarch64, everything else to x86_64" {
  dpkg() { echo "arm64"; }
  export -f dpkg
  [ "$(omawsl_aws_cli_arch)" = "aarch64" ]

  dpkg() { echo "amd64"; }
  export -f dpkg
  [ "$(omawsl_aws_cli_arch)" = "x86_64" ]
}

@test "aws-cli: install_steps downloads the right arch zip, unzips, and runs the installer" {
  dpkg() { echo "amd64"; }
  export -f dpkg
  stub_command curl
  stub_command unzip
  omawsl_aws_cli_install_steps
  [[ "$(stub_calls)" == *"curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "* ]]
  [[ "$(stub_calls)" == *"unzip -q"* ]]
  [[ "$(stub_calls)" == *"sudo"*"/aws/install --update"* ]]
}

@test "aws-cli: install_steps isolates a download failure instead of aborting" {
  dpkg() { echo "amd64"; }
  export -f dpkg
  stub_command curl 1
  run omawsl_aws_cli_install_steps
  [ "$status" -eq 0 ]
  [[ "$output" == *"AWS CLI install failed"* ]]
}

@test "aws-cli: omawsl_install_aws_cli no-ops when already installed" {
  stub_command aws
  run omawsl_install_aws_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "aws-cli: omawsl_install_aws_cli calls install_steps when not already installed" {
  omawsl_aws_cli_install_steps() { echo "aws-install-steps-called" >> "$STUB_LOG"; }
  export -f omawsl_aws_cli_install_steps
  run omawsl_install_aws_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"aws-install-steps-called"* ]]
}

# --- omawsl_cloud_clis ---------------------------------------------------------

@test "cloud_clis: installs all three when all three are selected" {
  stub_command curl
  omawsl_aws_cli_install_steps() { echo "aws-installed" >> "$STUB_LOG"; }
  export -f omawsl_aws_cli_install_steps
  export OMAWSL_CLOUD_CLIS="Azure CLI,AWS CLI,GCP CLI"
  omawsl_cloud_clis
  [[ "$(stub_calls)" == *"apt-get install -y azure-cli"* ]]
  [[ "$(stub_calls)" == *"aws-installed"* ]]
  [[ "$(stub_calls)" == *"apt-get install -y google-cloud-cli"* ]]
}

@test "cloud_clis: installs only the one selected" {
  stub_command curl
  export OMAWSL_CLOUD_CLIS="Azure CLI"
  omawsl_cloud_clis
  [[ "$(stub_calls)" == *"apt-get install -y azure-cli"* ]]
  [[ "$(stub_calls)" != *"google-cloud-cli"* ]]
  [[ "$(stub_calls)" != *"aws"* ]]
}

@test "cloud_clis: selecting none installs nothing" {
  export OMAWSL_CLOUD_CLIS=""
  omawsl_cloud_clis
  [[ "$(stub_calls)" != *"azure-cli"* ]]
  [[ "$(stub_calls)" != *"google-cloud-cli"* ]]
  [[ "$(stub_calls)" != *"aws"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/cloud_clis_test.bats"`
Expected: FAIL (`install/terminal/cloud-clis.sh` doesn't exist yet).

- [ ] **Step 3: Create `install/terminal/cloud-clis.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_azure_cli [apt_sources_file] [keyrings_dir]
# Moved verbatim from install/terminal/cloud-tools.sh - Azure CLI now lives
# in its own OMAWSL_CLOUD_CLIS-driven picker, alongside AWS CLI and GCP CLI
# (design spec §3), not mixed in with the 8 programming languages.
omawsl_install_azure_cli() {
  local apt_sources_file="${1:-${OMAWSL_AZURE_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/azure-cli.list}}"
  local keyrings_dir="${2:-${OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if command -v az &>/dev/null; then
    return 0
  fi

  local ok=1
  {
    if [[ ! -f "$apt_sources_file" ]]; then
      local codename
      codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
      # Microsoft's azure-cli apt repo lags behind new Ubuntu releases - fall
      # back to "jammy" (the same default Microsoft's own installer uses)
      # when the detected codename isn't published yet.
      curl -fsSL -o /dev/null "https://packages.microsoft.com/repos/azure-cli/dists/$codename/Release" || codename="jammy"
      sudo install -m 0755 -d "$keyrings_dir" &&
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --yes --dearmor -o "$keyrings_dir/microsoft.gpg" &&
      sudo tee "$apt_sources_file" >/dev/null <<< "deb [arch=$(dpkg --print-architecture) signed-by=$keyrings_dir/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $codename main" &&
      sudo apt-get update -qq
    fi &&
    sudo apt-get install -y azure-cli
  } || ok=0

  if [[ "$ok" -eq 0 ]]; then
    sudo rm -f "$apt_sources_file"
    echo "omawsl: Azure CLI install failed (repo unreachable?) - skipping, continuing with the rest of the run."
  fi
}

# omawsl_install_gcp_cli [apt_sources_file] [keyrings_dir]
# Same idempotent + failure-isolated shape as omawsl_install_azure_cli, for
# Google's apt repo instead of Microsoft's. Simpler than Azure CLI's: Google's
# repo isn't pinned to a Ubuntu codename (a single "cloud-sdk" suite covers
# every release), so there's no jammy-style fallback needed.
omawsl_install_gcp_cli() {
  local apt_sources_file="${1:-${OMAWSL_GCP_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/google-cloud-sdk.list}}"
  local keyrings_dir="${2:-${OMAWSL_GCP_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if command -v gcloud &>/dev/null; then
    return 0
  fi

  local ok=1
  {
    if [[ ! -f "$apt_sources_file" ]]; then
      sudo install -m 0755 -d "$keyrings_dir" &&
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --yes --dearmor -o "$keyrings_dir/google.gpg" &&
      sudo tee "$apt_sources_file" >/dev/null <<< "deb [signed-by=$keyrings_dir/google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" &&
      sudo apt-get update -qq
    fi &&
    sudo apt-get install -y google-cloud-cli
  } || ok=0

  if [[ "$ok" -eq 0 ]]; then
    sudo rm -f "$apt_sources_file"
    echo "omawsl: GCP CLI install failed (repo unreachable?) - skipping, continuing with the rest of the run."
  fi
}

# omawsl_aws_cli_arch
# Maps dpkg's architecture name to the naming AWS's own installer zip uses -
# reuses the same `dpkg --print-architecture` check the apt-based installers
# above already rely on, rather than introducing new arch-detection
# machinery.
omawsl_aws_cli_arch() {
  case "$(dpkg --print-architecture)" in
    arm64) echo "aarch64" ;;
    *) echo "x86_64" ;;
  esac
}

# omawsl_aws_cli_install_steps
# The actual install commands, no guard - called both by
# omawsl_install_aws_cli below (guarded) and by bin/omawsl-sub/orphan-tools.sh's
# own update-apply phase (guard bypassed), since AWS CLI has no apt/mise
# native updater of its own (design spec §8). `--update` is always passed:
# it's required to re-run the installer over an already-installed AWS CLI
# (the update path's use case), and is also accepted harmlessly on a fresh
# install (this function's own normal use case via the guarded wrapper).
omawsl_aws_cli_install_steps() {
  local tmp_dir; tmp_dir="$(mktemp -d)"
  local arch; arch="$(omawsl_aws_cli_arch)"
  local ok=1
  {
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$arch.zip" -o "$tmp_dir/awscliv2.zip" &&
    unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir" &&
    sudo "$tmp_dir/aws/install" --update
  } || ok=0
  rm -rf "$tmp_dir"

  if [[ "$ok" -eq 0 ]]; then
    echo "omawsl: AWS CLI install failed (download unreachable?) - skipping, continuing with the rest of the run."
  fi
}

# omawsl_install_aws_cli
# Guarded entry point - what omawsl_cloud_clis (and bin/omawsl-sub/install.sh)
# call. Idempotent via a command -v guard, since the AWS installer script
# needs an explicit --update flag to touch an already-installed AWS CLI.
omawsl_install_aws_cli() {
  if command -v aws &>/dev/null; then
    return 0
  fi

  omawsl_aws_cli_install_steps
}

# omawsl_cloud_clis
# Reads OMAWSL_CLOUD_CLIS (Azure CLI/AWS CLI/GCP CLI live in their own picker,
# separate from the 8 languages/Terraform - design spec §3/§4) and installs
# each selected tool. Nothing pre-selected by default; selecting none is a
# valid no-op. Each install function already swallows its own failure
# internally and always returns 0, so no extra isolation logic is needed here
# - matches install/terminal/cloud-tools.sh's omawsl_cloud_tools shape.
omawsl_cloud_clis() {
  local cloud_clis="${OMAWSL_CLOUD_CLIS:-}"

  if omawsl_list_has "$cloud_clis" "Azure CLI"; then
    omawsl_install_azure_cli
  fi

  if omawsl_list_has "$cloud_clis" "AWS CLI"; then
    omawsl_install_aws_cli
  fi

  if omawsl_list_has "$cloud_clis" "GCP CLI"; then
    omawsl_install_gcp_cli
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_cloud_clis
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/cloud_clis_test.bats"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install/terminal/cloud-clis.sh tests/cloud_clis_test.bats
git commit -m "feat: add cloud-clis.sh with Azure CLI (moved), AWS CLI, and GCP CLI installers"
```

---

### Task 5: Wire `cloud-clis.sh` into `install/terminal.sh`

**Files:**
- Modify: `install/terminal.sh:17-60`

**Interfaces:**
- Consumes: `omawsl_cloud_clis` (Task 4).
- Produces: nothing new (registers an existing function into the fixed script-run order).

- [ ] **Step 1: Write the failing test**

This is exercised end-to-end by `tests/install_test.bats`, updated in Task 10 (adding a `Cloud CLIs` gum response makes that test require `cloud-clis.sh` to actually run). No standalone test file exists for `terminal.sh`'s ordering array itself; skip straight to the change and let Task 10's end-to-end test confirm it.

- [ ] **Step 2: Update `install/terminal.sh`**

In the `OMAWSL_TERMINAL_SCRIPTS` array, change:

```bash
  "terminal/cloud-tools.sh"
  "terminal/select-dev-storage.sh"
```

to:

```bash
  "terminal/cloud-tools.sh"
  "terminal/cloud-clis.sh"
  "terminal/select-dev-storage.sh"
```

In the `SCRIPT_FUNCTIONS` associative array, change:

```bash
    ["terminal/cloud-tools.sh"]="omawsl_cloud_tools"
    ["terminal/select-dev-storage.sh"]="omawsl_install_storage"
```

to:

```bash
    ["terminal/cloud-tools.sh"]="omawsl_cloud_tools"
    ["terminal/cloud-clis.sh"]="omawsl_cloud_clis"
    ["terminal/select-dev-storage.sh"]="omawsl_install_storage"
```

- [ ] **Step 3: Commit**

```bash
git add install/terminal.sh
git commit -m "feat: run cloud-clis.sh as part of the fixed terminal install sequence"
```

(Verification of this wiring happens end-to-end in Task 10, once `first-run-choices.sh` actually produces an `OMAWSL_CLOUD_CLIS` value for it to read.)

---

### Task 6: Uninstall side — `uninstall/cloud-clis.sh`, trim `dev-language.sh`

**Files:**
- Create: `uninstall/cloud-clis.sh`
- Modify: `uninstall/dev-language.sh:49-63,86-87`
- Test: `tests/uninstall_cloud_clis_test.bats` (new), `tests/uninstall_dev_language_test.bats`

**Interfaces:**
- Consumes: nothing new.
- Produces: `omawsl_uninstall_azure_cli [apt_sources_file] [keyrings_dir]`, `omawsl_uninstall_gcp_cli [apt_sources_file] [keyrings_dir]`, `omawsl_uninstall_aws_cli`, `omawsl_uninstall_cloud_cli <label>` (dispatches on `"Azure CLI"`/`"AWS CLI"`/`"GCP CLI"`) — consumed by Task 8's `bin/omawsl-sub/uninstall.sh`.

- [ ] **Step 1: Write the failing tests**

Create `tests/uninstall_cloud_clis_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/cloud-clis.sh"
  stub_command sudo
}

@test "omawsl_uninstall_azure_cli purges azure-cli and removes its apt source" {
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    if [[ "$1" == "rm" ]]; then
      shift
      command rm "$@"
      return $?
    fi
    return 0
  }
  export -f sudo
  export OMAWSL_AZURE_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/azure-cli.list"
  export OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  touch "$OMAWSL_AZURE_CLI_APT_SOURCES_FILE"
  stub_command az
  run omawsl_uninstall_azure_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y azure-cli"* ]]
  [ ! -f "$OMAWSL_AZURE_CLI_APT_SOURCES_FILE" ]
}

@test "omawsl_uninstall_azure_cli no-ops cleanly when never installed" {
  stub_hide_command az
  run omawsl_uninstall_azure_cli
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  [[ "$(stub_calls)" != *"apt-get purge"* ]]
}

@test "omawsl_uninstall_gcp_cli purges google-cloud-cli and removes its apt source" {
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    if [[ "$1" == "rm" ]]; then
      shift
      command rm "$@"
      return $?
    fi
    return 0
  }
  export -f sudo
  export OMAWSL_GCP_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/google-cloud-sdk.list"
  export OMAWSL_GCP_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  touch "$OMAWSL_GCP_CLI_APT_SOURCES_FILE"
  stub_command gcloud
  run omawsl_uninstall_gcp_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y google-cloud-cli"* ]]
  [ ! -f "$OMAWSL_GCP_CLI_APT_SOURCES_FILE" ]
}

@test "omawsl_uninstall_gcp_cli no-ops cleanly when never installed" {
  stub_hide_command gcloud
  run omawsl_uninstall_gcp_cli
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  [[ "$(stub_calls)" != *"apt-get purge"* ]]
}

@test "omawsl_uninstall_aws_cli removes the documented install paths" {
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    return 0
  }
  export -f sudo
  stub_command aws
  run omawsl_uninstall_aws_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws /usr/local/bin/aws_completer"* ]]
}

@test "omawsl_uninstall_aws_cli no-ops cleanly when never installed" {
  stub_hide_command aws
  run omawsl_uninstall_aws_cli
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  [[ "$(stub_calls)" != *"rm -rf"* ]]
}

@test "omawsl_uninstall_cloud_cli dispatches by label" {
  omawsl_uninstall_azure_cli() { echo "azure-uninstalled" >> "$STUB_LOG"; }
  export -f omawsl_uninstall_azure_cli
  run omawsl_uninstall_cloud_cli "Azure CLI"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"azure-uninstalled"* ]]
}

@test "omawsl_uninstall_cloud_cli rejects an unknown label" {
  run omawsl_uninstall_cloud_cli "Not A Real Cloud CLI"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown"* ]]
}
```

In `tests/uninstall_dev_language_test.bats`, delete the `@test "omawsl_uninstall_language purges azure-cli and removes its apt source"` block (lines 76-97).

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_cloud_clis_test.bats tests/uninstall_dev_language_test.bats"`
Expected: `uninstall_cloud_clis_test.bats` FAILs (file doesn't exist yet); `uninstall_dev_language_test.bats` still PASSes (its Azure CLI test just got deleted, nothing new to fail) - that's fine, proceed.

- [ ] **Step 3: Create `uninstall/cloud-clis.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_azure_cli [apt_sources_file] [keyrings_dir]
# Moved verbatim from uninstall/dev-language.sh - inverse of
# install/terminal/cloud-clis.sh's omawsl_install_azure_cli.
omawsl_uninstall_azure_cli() {
  local apt_sources_file="${1:-${OMAWSL_AZURE_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/azure-cli.list}}"
  local keyrings_dir="${2:-${OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if ! command -v az &>/dev/null; then
    echo "omawsl: Azure CLI isn't installed - nothing to do."
    return 0
  fi

  sudo apt-get purge -y azure-cli
  sudo rm -f "$apt_sources_file" "$keyrings_dir/microsoft.gpg"
  echo "omawsl: Azure CLI removed."
}

# omawsl_uninstall_gcp_cli [apt_sources_file] [keyrings_dir]
# Inverse of omawsl_install_gcp_cli.
omawsl_uninstall_gcp_cli() {
  local apt_sources_file="${1:-${OMAWSL_GCP_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/google-cloud-sdk.list}}"
  local keyrings_dir="${2:-${OMAWSL_GCP_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if ! command -v gcloud &>/dev/null; then
    echo "omawsl: GCP CLI isn't installed - nothing to do."
    return 0
  fi

  sudo apt-get purge -y google-cloud-cli
  sudo rm -f "$apt_sources_file" "$keyrings_dir/google.gpg"
  echo "omawsl: GCP CLI removed."
}

# omawsl_uninstall_aws_cli
# Removes the three paths AWS's own v2 installer documents
# (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#cliv2-linux-uninstall) -
# the install directory plus its two symlinks.
omawsl_uninstall_aws_cli() {
  if ! command -v aws &>/dev/null; then
    echo "omawsl: AWS CLI isn't installed - nothing to do."
    return 0
  fi

  sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws /usr/local/bin/aws_completer
  echo "omawsl: AWS CLI removed."
}

# omawsl_uninstall_cloud_cli <label>
# Takes the exact picker label (matches OMAWSL_CLOUD_CLIS's own comma-list
# values), same shape as uninstall/dev-language.sh's omawsl_uninstall_language.
omawsl_uninstall_cloud_cli() {
  local label="$1"
  case "$label" in
    "Azure CLI") omawsl_uninstall_azure_cli ;;
    "AWS CLI")   omawsl_uninstall_aws_cli ;;
    "GCP CLI")   omawsl_uninstall_gcp_cli ;;
    *)
      echo "omawsl: unknown cloud CLI '$label'" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_cloud_cli "$@"
fi
```

- [ ] **Step 4: Remove Azure CLI from `uninstall/dev-language.sh`**

Delete the `omawsl_uninstall_azure_cli` function (lines 49-63) and its preceding comment. In `omawsl_uninstall_language`'s case statement, delete the line:

```bash
    "Azure CLI")      omawsl_uninstall_azure_cli ;;
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_cloud_clis_test.bats tests/uninstall_dev_language_test.bats"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add uninstall/cloud-clis.sh uninstall/dev-language.sh tests/uninstall_cloud_clis_test.bats tests/uninstall_dev_language_test.bats
git commit -m "feat: add uninstall/cloud-clis.sh, move Azure CLI's uninstall out of dev-language.sh"
```

---

### Task 7: `bin/omawsl-sub/install.sh` gains the `cloud` category

**Files:**
- Modify: `bin/omawsl-sub/install.sh`
- Modify: `bin/omawsl:32` (usage text)
- Test: `tests/omawsl_install_command_test.bats`

**Interfaces:**
- Consumes: `omawsl_item_slugs cloud`, `omawsl_item_label` (Task 2); `omawsl_cloud_clis` (Task 4, via `install/terminal/cloud-clis.sh`).
- Produces: `omawsl_install_apply_cloud <picked_labels_csv> <existing_labels_csv>`, `omawsl_install_category_cloud`; `omawsl_install_direct`/`omawsl_install_interactive`/`omawsl_install_command` all accept `cloud`/`"Cloud CLIs"`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/omawsl_install_command_test.bats` (after the existing `"omawsl install storage mysql"` test):

```bash
@test "omawsl install cloud azure - installs azure directly and merges it into OMAWSL_CLOUD_CLIS" {
  stub_command curl
  run omawsl_install_command cloud azure
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_CLOUD_CLIS)" == "Azure CLI" ]]
}

@test "omawsl install rejects a cloud item that doesn't belong to the cloud category" {
  run omawsl_install_command cloud go
  [ "$status" -ne 0 ]
  [[ "$output" == *"isn't in the 'cloud' category"* ]]
}
```

Update the setup's `stub_hide_command` line to also hide `gcloud aws`:

```bash
  stub_hide_command docker terraform az gcloud aws code cursor claude codex gemini opencode
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_install_command_test.bats"`
Expected: FAIL (`cloud` category unknown yet).

- [ ] **Step 3: Update `bin/omawsl-sub/install.sh`**

Add a new function right after `omawsl_install_apply_storage`:

```bash
# omawsl_install_apply_cloud <picked_labels_csv> <existing_labels_csv>
omawsl_install_apply_cloud() {
  local picked="$1" existing="$2"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_CLOUD_CLIS="$merged"
  omawsl_save_choice OMAWSL_CLOUD_CLIS "$merged"
  # shellcheck source=/dev/null
  source "$OMAWSL_ROOT_DIR/install/terminal/cloud-clis.sh"
  omawsl_cloud_clis
}
```

Add a new function right after `omawsl_install_category_storage`:

```bash
# omawsl_install_category_cloud
omawsl_install_category_cloud() {
  local existing; existing="$(omawsl_load_choice OMAWSL_CLOUD_CLIS)"
  local labels=() slug
  while IFS= read -r slug; do labels+=("$(omawsl_item_label "$slug")"); done < <(omawsl_item_slugs cloud)
  local picked
  picked="$(omawsl_install_prompt_multi "Cloud CLIs (already-installed items are pre-checked)" "$existing" "${labels[@]}")" || picked=""
  omawsl_install_apply_cloud "$picked" "$existing"
}
```

In `omawsl_install_direct`, change:

```bash
  case "$category" in
    language) omawsl_install_apply_language "$label" "$(omawsl_load_choice OMAWSL_LANGUAGES)" ;;
    editor)   omawsl_install_apply_editor   "$label" "$(omawsl_load_choice OMAWSL_EDITORS)" ;;
    storage)  omawsl_install_apply_storage  "$label" "$(omawsl_load_choice OMAWSL_STORAGE)" ;;
  esac
```

to:

```bash
  case "$category" in
    language) omawsl_install_apply_language "$label" "$(omawsl_load_choice OMAWSL_LANGUAGES)" ;;
    cloud)    omawsl_install_apply_cloud    "$label" "$(omawsl_load_choice OMAWSL_CLOUD_CLIS)" ;;
    editor)   omawsl_install_apply_editor   "$label" "$(omawsl_load_choice OMAWSL_EDITORS)" ;;
    storage)  omawsl_install_apply_storage  "$label" "$(omawsl_load_choice OMAWSL_STORAGE)" ;;
  esac
```

In `omawsl_install_interactive`, change:

```bash
  category="$(gum choose --header "What do you want to add?" "Language/tool" "Editors & AI tooling" "Storage")" || category=""
  [[ -n "$category" ]] || return 0
  case "$category" in
    "Language/tool")         omawsl_install_category_language ;;
    "Editors & AI tooling")  omawsl_install_category_editor ;;
    "Storage")               omawsl_install_category_storage ;;
  esac
```

to:

```bash
  category="$(gum choose --header "What do you want to add?" "Language/tool" "Cloud CLIs" "Editors & AI tooling" "Storage")" || category=""
  [[ -n "$category" ]] || return 0
  case "$category" in
    "Language/tool")         omawsl_install_category_language ;;
    "Cloud CLIs")            omawsl_install_category_cloud ;;
    "Editors & AI tooling")  omawsl_install_category_editor ;;
    "Storage")               omawsl_install_category_storage ;;
  esac
```

In `omawsl_install_command`, change:

```bash
  case "$category" in
    language|editor|storage) omawsl_install_direct "$category" "$item" ;;
    *)
      echo "omawsl: unknown category '$category' (expected language, editor, or storage)" >&2
      return 1
      ;;
  esac
```

to:

```bash
  case "$category" in
    language|cloud|editor|storage) omawsl_install_direct "$category" "$item" ;;
    *)
      echo "omawsl: unknown category '$category' (expected language, cloud, editor, or storage)" >&2
      return 1
      ;;
  esac
```

And the "no item" usage message:

```bash
    echo "Categories: language, editor, storage" >&2
```

to:

```bash
    echo "Categories: language, cloud, editor, storage" >&2
```

- [ ] **Step 4: Update `bin/omawsl` usage text**

Change:

```
  install [category] [item] Add a language/editor/storage item. With no
                             args, choose interactively.
```

to:

```
  install [category] [item] Add a language/cloud/editor/storage item. With
                             no args, choose interactively.
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_install_command_test.bats"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add bin/omawsl-sub/install.sh bin/omawsl tests/omawsl_install_command_test.bats
git commit -m "feat: add cloud category support to bin/omawsl install"
```

---

### Task 8: `bin/omawsl-sub/uninstall.sh` gains the `cloud` category

**Files:**
- Modify: `bin/omawsl-sub/uninstall.sh`
- Test: `tests/omawsl_uninstall_command_test.bats`

**Interfaces:**
- Consumes: `omawsl_uninstall_cloud_cli` (Task 6, via `uninstall/cloud-clis.sh`); `omawsl_item_category` (Task 2).
- Produces: `omawsl_uninstall_dispatch azure|aws|gcp` now routes to `uninstall/cloud-clis.sh`; `omawsl_uninstall_deselect` now handles the `cloud` category (deselects from `OMAWSL_CLOUD_CLIS`).

- [ ] **Step 1: Write the failing tests**

Add to `tests/omawsl_uninstall_command_test.bats` (after the existing storage-deselect test):

```bash
@test "omawsl_uninstall_command dispatches azure to uninstall/cloud-clis.sh" {
  stub_command sudo
  stub_command az
  run omawsl_uninstall_command azure
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y azure-cli"* ]]
}

@test "omawsl_uninstall_command deselects a cloud CLI from OMAWSL_CLOUD_CLIS" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  stub_command sudo
  stub_command az
  omawsl_save_choice OMAWSL_CLOUD_CLIS "Azure CLI,AWS CLI"
  run omawsl_uninstall_command azure
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_CLOUD_CLIS)" == "AWS CLI" ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_uninstall_command_test.bats"`
Expected: FAIL (`azure` still unknown to `omawsl_uninstall_dispatch`).

- [ ] **Step 3: Update `bin/omawsl-sub/uninstall.sh`**

In `omawsl_uninstall_dispatch`, change:

```bash
    ruby|node|go|php|python|elixir|rust|java|terraform|azure)
      label="$(omawsl_item_label "$slug")"
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/dev-language.sh"
      omawsl_uninstall_language "$label"
      ;;
```

to:

```bash
    ruby|node|go|php|python|elixir|rust|java|terraform)
      label="$(omawsl_item_label "$slug")"
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/dev-language.sh"
      omawsl_uninstall_language "$label"
      ;;
    azure|aws|gcp)
      label="$(omawsl_item_label "$slug")"
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/cloud-clis.sh"
      omawsl_uninstall_cloud_cli "$label"
      ;;
```

In `omawsl_uninstall_deselect`, change:

```bash
  local key
  case "$category" in
    language) key=OMAWSL_LANGUAGES ;;
    editor)   key=OMAWSL_EDITORS ;;
    storage)  key=OMAWSL_STORAGE ;;
    *) return 0 ;;
  esac
```

to:

```bash
  local key
  case "$category" in
    language) key=OMAWSL_LANGUAGES ;;
    cloud)    key=OMAWSL_CLOUD_CLIS ;;
    editor)   key=OMAWSL_EDITORS ;;
    storage)  key=OMAWSL_STORAGE ;;
    *) return 0 ;;
  esac
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_uninstall_command_test.bats"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/uninstall.sh tests/omawsl_uninstall_command_test.bats
git commit -m "feat: add cloud category support to bin/omawsl uninstall"
```

---

### Task 9: `bin/omawsl-sub/doctor.sh` gains the `cloud` category

**Files:**
- Modify: `bin/omawsl-sub/doctor.sh`
- Test: `tests/omawsl_doctor_test.bats`

**Interfaces:**
- Consumes: `omawsl_item_slugs cloud`/`omawsl_item_label` (Task 2), `omawsl_doctor_report_category` (existing, unchanged).
- Produces: `omawsl_doctor_cloud_installed <slug>`; `omawsl_doctor` prints a "Cloud CLIs:" section.

- [ ] **Step 1: Write the failing test**

Add to `tests/omawsl_doctor_test.bats` (after the existing PENDING-language test):

```bash
@test "omawsl_doctor reports PENDING for a selected-but-missing cloud CLI" {
  omawsl_save_choice OMAWSL_CLOUD_CLIS "AWS CLI"
  stub_hide_command aws
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"[PENDING] AWS CLI - run: omawsl install cloud aws"* ]]
}

@test "omawsl_doctor reports OK for an installed, selected cloud CLI" {
  omawsl_save_choice OMAWSL_CLOUD_CLIS "GCP CLI"
  stub_command gcloud
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]      GCP CLI"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_doctor_test.bats"`
Expected: FAIL (no "Cloud CLIs" section printed yet, and `omawsl_item_slugs cloud`/labels not yet wired into doctor.sh's report loop).

- [ ] **Step 3: Update `bin/omawsl-sub/doctor.sh`**

Change `omawsl_doctor_language_installed` from:

```bash
omawsl_doctor_language_installed() {
  local slug="$1"
  case "$slug" in
    terraform) command -v terraform &>/dev/null ;;
    azure) command -v az &>/dev/null ;;
    *)
```

to:

```bash
omawsl_doctor_language_installed() {
  local slug="$1"
  case "$slug" in
    terraform) command -v terraform &>/dev/null ;;
    *)
```

Add a new function right after `omawsl_doctor_language_installed`:

```bash
# omawsl_doctor_cloud_installed <slug>
omawsl_doctor_cloud_installed() {
  local slug="$1"
  case "$slug" in
    azure) command -v az &>/dev/null ;;
    aws) command -v aws &>/dev/null ;;
    gcp) command -v gcloud &>/dev/null ;;
  esac
}
```

In `omawsl_doctor`, change:

```bash
  echo "Languages & cloud tools:"
  omawsl_doctor_report_category language omawsl_doctor_language_installed OMAWSL_LANGUAGES
  echo
  echo "Editors & AI tooling:"
```

to:

```bash
  echo "Languages & cloud tools:"
  omawsl_doctor_report_category language omawsl_doctor_language_installed OMAWSL_LANGUAGES
  echo
  echo "Cloud CLIs:"
  omawsl_doctor_report_category cloud omawsl_doctor_cloud_installed OMAWSL_CLOUD_CLIS
  echo
  echo "Editors & AI tooling:"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_doctor_test.bats"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/doctor.sh tests/omawsl_doctor_test.bats
git commit -m "feat: add cloud category support to bin/omawsl doctor"
```

---

### Task 10: New "Cloud CLIs" first-run prompt

This is the highest-risk task in the plan: `install/first-run-choices.sh`'s `gum` calls happen in a fixed order, and `tests/install_test.bats`'s end-to-end tests feed `gum` responses positionally via a queue (`gum_stub_respond`). Inserting a new prompt shifts every response *after* it - both `install_test.bats` tests must get an extra response inserted at the right position, or they'll silently consume the wrong queued value for every later prompt (docker/font/identification).

**Files:**
- Modify: `install/first-run-choices.sh`
- Test: `tests/first_run_choices_test.bats`, `tests/install_test.bats`

**Interfaces:**
- Consumes: `omawsl_prompt_multi` (existing, unchanged).
- Produces: `OMAWSL_CLOUD_CLIS` (exported + persisted via `omawsl_save_choice`), prompted right after `OMAWSL_LANGUAGES` and before `OMAWSL_STORAGE`.

- [ ] **Step 1: Write the failing tests**

In `tests/first_run_choices_test.bats`, update the first test (`"persists all six choices..."`) - rename it and insert a new response + assertions:

```bash
@test "persists all seven choices and exports them for the current run" {
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond $'VS Code\nNeovim'
  gum_stub_respond $'Go\nRust'
  gum_stub_respond $'Azure CLI\nAWS CLI'
  gum_stub_respond "PostgreSQL"
  gum_stub_respond "Nerd Font (enhanced)"

  omawsl_first_run_choices

  [ "$OMAWSL_NETWORK_MODE" = "Personal / unrestricted" ]
  [ "$OMAWSL_DOCKER_MODE" = "Docker Engine only, inside WSL (recommended)" ]
  [ "$OMAWSL_EDITORS" = "VS Code,Neovim" ]
  [ "$OMAWSL_LANGUAGES" = "Go,Rust" ]
  [ "$OMAWSL_CLOUD_CLIS" = "Azure CLI,AWS CLI" ]
  [ "$OMAWSL_STORAGE" = "PostgreSQL" ]
  [ "$OMAWSL_FONT_MODE" = "Nerd Font (enhanced)" ]

  run omawsl_load_choice OMAWSL_LANGUAGES
  [ "$output" = "Go,Rust" ]
  run omawsl_load_choice OMAWSL_CLOUD_CLIS
  [ "$output" = "Azure CLI,AWS CLI" ]
  run omawsl_load_choice OMAWSL_STORAGE
  [ "$output" = "PostgreSQL" ]
  run omawsl_load_choice OMAWSL_FONT_MODE
  [ "$output" = "Nerd Font (enhanced)" ]
}
```

Update the second test (`"selecting nothing in a multi-select..."`) to insert one more empty response and assert on `OMAWSL_CLOUD_CLIS`:

```bash
@test "selecting nothing in a multi-select persists an empty string, not an error" {
  gum_stub_respond "Corporate / restricted network"
  gum_stub_respond "Docker Desktop for Windows"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Cascadia Mono (zero install)"

  run omawsl_first_run_choices
  [ "$status" -eq 0 ]

  omawsl_first_run_choices
  [ "$OMAWSL_EDITORS" = "" ]
  [ "$OMAWSL_LANGUAGES" = "" ]
  [ "$OMAWSL_CLOUD_CLIS" = "" ]
  [ "$OMAWSL_STORAGE" = "" ]
}
```

In `tests/install_test.bats`, insert one new `gum_stub_respond ""` between the `Go\nTerraform` languages response and the storage response in **both** `@test` blocks (`"runs the full install end to end..."` and `"choosing Docker Desktop surfaces..."`). For the first test, change:

```bash
  gum_stub_respond $'Go\nTerraform'
  gum_stub_respond ""
  gum_stub_respond "Nerd Font (enhanced)"
```

to:

```bash
  gum_stub_respond $'Go\nTerraform'
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Nerd Font (enhanced)"
```

For the second test, change:

```bash
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Cascadia Mono (zero install)"
```

to:

```bash
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Cascadia Mono (zero install)"
```

Also add `gcloud aws` to that file's `stub_hide_command` line (currently `stub_hide_command docker terraform az lazydocker zellij code cursor claude codex gemini opencode`):

```bash
  stub_hide_command docker terraform az gcloud aws lazydocker zellij code cursor claude codex gemini opencode
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/first_run_choices_test.bats tests/install_test.bats"`
Expected: FAIL (no `OMAWSL_CLOUD_CLIS` prompt exists yet in `first-run-choices.sh`, so the response queues are consumed one step ahead of where these updated tests expect).

- [ ] **Step 3: Update `install/first-run-choices.sh`**

Change:

```bash
  OMAWSL_LANGUAGES="$(omawsl_prompt_multi "Languages & cloud tools" \
    "Ruby on Rails" "Node.js" "Go" "PHP" "Python" "Elixir" "Rust" "Java" \
    "Terraform" "Azure CLI")"

  OMAWSL_STORAGE="$(omawsl_prompt_multi "Storage (Docker containers)" \
    "MySQL" "Redis" "PostgreSQL")"
```

to:

```bash
  OMAWSL_LANGUAGES="$(omawsl_prompt_multi "Languages & cloud tools" \
    "Ruby on Rails" "Node.js" "Go" "PHP" "Python" "Elixir" "Rust" "Java" \
    "Terraform")"

  OMAWSL_CLOUD_CLIS="$(omawsl_prompt_multi "Cloud CLIs" \
    "Azure CLI" "AWS CLI" "GCP CLI")"

  OMAWSL_STORAGE="$(omawsl_prompt_multi "Storage (Docker containers)" \
    "MySQL" "Redis" "PostgreSQL")"
```

Change:

```bash
  export OMAWSL_NETWORK_MODE OMAWSL_DOCKER_MODE OMAWSL_EDITORS OMAWSL_LANGUAGES OMAWSL_STORAGE OMAWSL_FONT_MODE

  omawsl_save_choice OMAWSL_NETWORK_MODE "$OMAWSL_NETWORK_MODE"
  omawsl_save_choice OMAWSL_DOCKER_MODE "$OMAWSL_DOCKER_MODE"
  omawsl_save_choice OMAWSL_EDITORS "$OMAWSL_EDITORS"
  omawsl_save_choice OMAWSL_LANGUAGES "$OMAWSL_LANGUAGES"
  omawsl_save_choice OMAWSL_STORAGE "$OMAWSL_STORAGE"
  omawsl_save_choice OMAWSL_FONT_MODE "$OMAWSL_FONT_MODE"
```

to:

```bash
  export OMAWSL_NETWORK_MODE OMAWSL_DOCKER_MODE OMAWSL_EDITORS OMAWSL_LANGUAGES OMAWSL_CLOUD_CLIS OMAWSL_STORAGE OMAWSL_FONT_MODE

  omawsl_save_choice OMAWSL_NETWORK_MODE "$OMAWSL_NETWORK_MODE"
  omawsl_save_choice OMAWSL_DOCKER_MODE "$OMAWSL_DOCKER_MODE"
  omawsl_save_choice OMAWSL_EDITORS "$OMAWSL_EDITORS"
  omawsl_save_choice OMAWSL_LANGUAGES "$OMAWSL_LANGUAGES"
  omawsl_save_choice OMAWSL_CLOUD_CLIS "$OMAWSL_CLOUD_CLIS"
  omawsl_save_choice OMAWSL_STORAGE "$OMAWSL_STORAGE"
  omawsl_save_choice OMAWSL_FONT_MODE "$OMAWSL_FONT_MODE"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/first_run_choices_test.bats tests/install_test.bats"`
Expected: PASS

- [ ] **Step 5: Run the full suite once to catch any other gum-order assumption this change might have broken**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/*.bats"`
Expected: PASS across the board (no other test file feeds a positional `gum` response queue through `omawsl_first_run_choices`/`install.sh` besides the two files just updated - confirmed by grep for `gum_stub_respond` usage alongside `first-run-choices.sh`/`install.sh` sourcing).

- [ ] **Step 6: Commit**

```bash
git add install/first-run-choices.sh tests/first_run_choices_test.bats tests/install_test.bats
git commit -m "feat: add a Cloud CLIs first-run prompt (Azure CLI, AWS CLI, GCP CLI)"
```

---

### Task 11: AWS CLI joins the orphan-tools registry

Azure CLI and GCP CLI are apt-installed, so `sudo apt upgrade` already keeps them current (same reason Terraform is excluded from this registry today). AWS CLI's installer has no native updater, so it becomes this registry's 8th entry.

**Files:**
- Modify: `bin/omawsl-sub/orphan-tools.sh`
- Test: `tests/omawsl_orphan_tools_test.bats`

**Interfaces:**
- Consumes: `omawsl_aws_cli_install_steps` (Task 4, via `install/terminal/cloud-clis.sh`), `omawsl_item_label aws` (Task 2).
- Produces: `omawsl_orphan_tool_slugs` now includes `aws`; `omawsl_orphan_tool_label`/`_installed`/`_version_installed`/`_version_latest`/`_apply_update` all handle `aws`.

- [ ] **Step 1: Write the failing tests**

Update the existing test (line 15-26):

```bash
@test "omawsl_orphan_tool_slugs lists all 8 orphan tools" {
  run omawsl_orphan_tool_slugs
  [ "$status" -eq 0 ]
  [[ "$output" == *"zellij"* ]]
  [[ "$output" == *"lazydocker"* ]]
  [[ "$output" == *"opencode"* ]]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"codex"* ]]
  [[ "$output" == *"gemini"* ]]
  [[ "$output" == *"gh-copilot"* ]]
  [[ "$output" == *"aws"* ]]
  [ "$(omawsl_orphan_tool_slugs | wc -l)" -eq 8 ]
}
```

Update the label test (line 28-33) to add an `aws` assertion:

```bash
@test "omawsl_orphan_tool_label returns Zellij/LazyDocker directly and reuses items.sh for the rest" {
  [ "$(omawsl_orphan_tool_label zellij)" = "Zellij" ]
  [ "$(omawsl_orphan_tool_label lazydocker)" = "LazyDocker" ]
  [ "$(omawsl_orphan_tool_label codex)" = "$(omawsl_item_label codex)" ]
  [ "$(omawsl_orphan_tool_label gh-copilot)" = "GitHub Copilot CLI" ]
  [ "$(omawsl_orphan_tool_label aws)" = "AWS CLI" ]
}
```

Update the "every function ... actually exists" test (line 107-114):

```bash
@test "every function omawsl_orphan_tool_apply_update dispatches to actually exists" {
  for fn in omawsl_zellij_install_steps omawsl_lazydocker_install_steps \
            omawsl_opencode_install_steps omawsl_claude_cli_install_steps \
            omawsl_codex_cli_install_steps omawsl_gemini_cli_install_steps \
            omawsl_gh_copilot_update_steps omawsl_aws_cli_install_steps; do
    declare -F "$fn" >/dev/null || { echo "missing function: $fn"; return 1; }
  done
}
```

Add new tests after the existing `omawsl_orphan_tool_installed` tests:

```bash
@test "omawsl_orphan_tool_installed checks aws via command -v" {
  stub_hide_command aws
  run omawsl_orphan_tool_installed aws
  [ "$status" -ne 0 ]
  stub_command aws
  run omawsl_orphan_tool_installed aws
  [ "$status" -eq 0 ]
}

@test "omawsl_orphan_tool_version_installed extracts aws-cli's semver from its --version output" {
  aws() { echo "aws-cli/2.15.30 Python/3.11.6 Linux/6.18.33.2 exe/x86_64.ubuntu.26"; }
  export -f aws
  [ "$(omawsl_orphan_tool_version_installed aws)" = "2.15.30" ]
}

@test "omawsl_orphan_tool_version_latest resolves aws via the aws/aws-cli GitHub repo" {
  curl() { echo '{"tag_name":"2.19.0"}'; }
  export -f curl
  [ "$(omawsl_orphan_tool_version_latest aws)" = "2.19.0" ]
}

@test "omawsl_orphan_tool_apply_update calls aws_cli_install_steps for aws" {
  omawsl_aws_cli_install_steps() { echo "aws-cli-updated" >> "$STUB_LOG"; }
  export -f omawsl_aws_cli_install_steps
  run omawsl_orphan_tool_apply_update aws
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"aws-cli-updated"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats"`
Expected: FAIL (`aws` not yet recognized anywhere in `orphan-tools.sh`).

- [ ] **Step 3: Update `bin/omawsl-sub/orphan-tools.sh`**

`orphan-tools.sh` already defines `SCRIPT_DIR`/`OMAWSL_ROOT_DIR` at the top and sources its sibling app-*.sh files with them (lines 4-21). Add one more source line to that existing block, right after the `app-gh-copilot.sh` line:

```bash
# shellcheck source=../../install/terminal/app-gh-copilot.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-gh-copilot.sh"
```

becomes:

```bash
# shellcheck source=../../install/terminal/app-gh-copilot.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-gh-copilot.sh"
# shellcheck source=../../install/terminal/cloud-clis.sh
source "$OMAWSL_ROOT_DIR/install/terminal/cloud-clis.sh"
```

Change `omawsl_orphan_tool_slugs`:

```bash
omawsl_orphan_tool_slugs() {
  printf '%s\n' zellij lazydocker opencode claude codex gemini gh-copilot
}
```

to:

```bash
omawsl_orphan_tool_slugs() {
  printf '%s\n' zellij lazydocker opencode claude codex gemini gh-copilot aws
}
```

Change `omawsl_orphan_tool_label`:

```bash
omawsl_orphan_tool_label() {
  case "$1" in
    zellij) echo "Zellij" ;;
    lazydocker) echo "LazyDocker" ;;
    opencode|claude|codex|gemini|gh-copilot) omawsl_item_label "$1" ;;
    *) return 1 ;;
  esac
}
```

to:

```bash
omawsl_orphan_tool_label() {
  case "$1" in
    zellij) echo "Zellij" ;;
    lazydocker) echo "LazyDocker" ;;
    opencode|claude|codex|gemini|gh-copilot|aws) omawsl_item_label "$1" ;;
    *) return 1 ;;
  esac
}
```

Change `omawsl_orphan_tool_installed`:

```bash
    gh-copilot) gh extension list 2>/dev/null | grep -q 'github/gh-copilot' ;;
    *) return 1 ;;
  esac
}
```

to:

```bash
    gh-copilot) gh extension list 2>/dev/null | grep -q 'github/gh-copilot' ;;
    aws) command -v aws &>/dev/null ;;
    *) return 1 ;;
  esac
}
```

Change `omawsl_orphan_tool_version_installed`:

```bash
    gh-copilot) omawsl_orphan_extract_semver "$(gh extension list 2>/dev/null | grep 'github/gh-copilot' || true)" ;;
    *) return 1 ;;
  esac
}
```

to:

```bash
    gh-copilot) omawsl_orphan_extract_semver "$(gh extension list 2>/dev/null | grep 'github/gh-copilot' || true)" ;;
    aws) omawsl_orphan_extract_semver "$(aws --version 2>/dev/null || true)" ;;
    *) return 1 ;;
  esac
}
```

Change `omawsl_orphan_tool_version_latest`:

```bash
    gh-copilot) omawsl_orphan_latest_from_github github/gh-copilot ;;
    *) return 1 ;;
  esac
}
```

to:

```bash
    gh-copilot) omawsl_orphan_latest_from_github github/gh-copilot ;;
    aws) omawsl_orphan_latest_from_github aws/aws-cli ;;
    *) return 1 ;;
  esac
}
```

Change `omawsl_orphan_tool_apply_update`:

```bash
    gh-copilot) omawsl_gh_copilot_update_steps || ok=0 ;;
    *) echo "omawsl: unknown orphan tool slug '$slug'" >&2; return 1 ;;
  esac
```

to:

```bash
    gh-copilot) omawsl_gh_copilot_update_steps || ok=0 ;;
    aws) omawsl_aws_cli_install_steps || ok=0 ;;
    *) echo "omawsl: unknown orphan tool slug '$slug'" >&2; return 1 ;;
  esac
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/orphan-tools.sh tests/omawsl_orphan_tools_test.bats
git commit -m "feat: add AWS CLI to the orphan-tools update registry"
```

---

### Task 12: Documentation — `README.md`, `docs/updating.md`

**Files:**
- Modify: `README.md:44-48`
- Modify: `docs/updating.md`

**Interfaces:**
- Consumes: nothing (prose only).
- Produces: nothing (prose only).

- [ ] **Step 1: Update `README.md`**

Change:

```
Fully automated on the WSL/Linux side: shell and terminal tooling (zellij, btop, fastfetch,
lazygit, lazydocker, `gh`), Docker (native Engine by default, or Docker Desktop detect-and-defer
if you opt in), your choice of language runtimes and cloud CLIs via `mise` (Ruby on Rails,
Node.js, Go, PHP, Python, Elixir, Rust, Java, Terraform, Azure CLI), containerized storage
(MySQL, Redis, PostgreSQL), and your choice of editors/AI tooling (VS Code, Neovim, opencode,
Cursor, Claude Code CLI, Codex CLI, GitHub Copilot CLI, Gemini CLI). Nothing in any picker is
pre-selected - what you get is exactly what you choose, every time.
```

to:

```
Fully automated on the WSL/Linux side: shell and terminal tooling (zellij, btop, fastfetch,
lazygit, lazydocker, `gh`), Docker (native Engine by default, or Docker Desktop detect-and-defer
if you opt in), your choice of language runtimes (Ruby on Rails, Node.js, Go, PHP, Python,
Elixir, Rust, Java, Terraform), your choice of cloud provider CLIs (Azure CLI, AWS CLI, GCP
CLI), containerized storage (MySQL, Redis, PostgreSQL), and your choice of editors/AI tooling
(VS Code, Neovim, opencode, Cursor, Claude Code CLI, Codex CLI, GitHub Copilot CLI, Gemini CLI).
Nothing in any picker is pre-selected - what you get is exactly what you choose, every time.
```

- [ ] **Step 2: Update `docs/updating.md`**

Replace the entire file with:

```markdown
# Updating what omawsl installed

`omawsl update` pulls the latest omawsl and runs any pending migrations - but not everything
omawsl installs is updated the same way. Five groups, five answers:

## omawsl itself

Run `omawsl update`. This is always the first thing it does: `git pull` inside your omawsl
checkout, then pending migrations.

## Language runtimes

Ruby, Node.js, Go, PHP, Python, Elixir, Rust, Java - all managed by [mise](https://mise.jdx.dev).
Terraform - apt-managed, not mise. Either run `mise upgrade` (languages) or `sudo apt upgrade`
(Terraform) yourself, or re-run `omawsl install language <name>` (e.g. `omawsl install language
go`), which re-installs/re-pins to the latest release the same way the first install did.

## Cloud CLIs

Azure CLI and GCP CLI - both apt-managed. Run `sudo apt upgrade` yourself, or re-run `omawsl
install cloud <name>` (e.g. `omawsl install cloud azure`), which re-installs the latest package
the same way the first install did. AWS CLI has no native updater of its own - see "The rest"
below.

## System packages

Everything installed via `apt` - fzf, ripgrep, bat, eza, zoxide, Docker Engine, Neovim,
LazyGit, and the rest of the always-on terminal tool set. Run `sudo apt upgrade` like you would
for anything else on the system.

**Windows-side GUI apps** (VS Code, Cursor) aren't touched by omawsl at all, ever - they run
their own update lifecycle on Windows (VS Code's built-in updater, Cursor's own auto-update),
the same way omawsl never auto-installs them in the first place.

## The rest: `omawsl update`

Eight tools have no update command of their own - no apt package, no mise tool, nothing to
run yourself. `omawsl update` checks each one that's currently installed against its real
latest release, then offers a picker (pre-checked for anything outdated) to bring them
current:

- Zellij
- LazyDocker
- opencode
- Claude Code CLI
- Codex CLI
- Gemini CLI
- GitHub Copilot CLI
- AWS CLI

If everything here is already confirmed up to date, `omawsl update` says so and skips the
picker - there's nothing for it to offer.
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/updating.md
git commit -m "docs: document the new Cloud CLIs menu and AWS CLI's place in omawsl update"
```

---

## Final verification

- [ ] **Run the entire bats suite once more, end to end**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/*.bats"`
Expected: PASS across every file - no regressions in any test this plan didn't directly touch.
