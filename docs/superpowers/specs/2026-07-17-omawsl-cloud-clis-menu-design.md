# omawsl Cloud CLIs Menu — Design Spec

Date: 2026-07-17
Status: Draft — pending user review of this file

## 1. Purpose

Azure CLI currently lives inside the "Languages & cloud tools" picker
(`install/first-run-choices.sh`), mixed in with the 8 programming languages and Terraform. There's
no AWS CLI or GCP CLI (`gcloud`) support at all today. This muddles a menu that's conceptually
about language runtimes with an unrelated concern (cloud provider CLIs), and leaves two of the
three major cloud providers unsupported.

This spec carves cloud provider CLIs out into their own first-class picker category — `cloud` —
parallel to the existing `language`/`editor`/`storage` categories, and adds working install/
uninstall/doctor/update support for all three (Azure CLI, AWS CLI, GCP CLI).

## 2. Scope

**In scope:**
- A new `cloud` category: Azure CLI (moved out of `language`), AWS CLI (new), GCP CLI (new).
- A new `OMAWSL_CLOUD_CLIS` first-run choice and picker, install/uninstall/doctor coverage, and
  `bin/omawsl install|uninstall cloud <slug>` direct-dispatch support — the full plumbing that
  `storage` already has.
- AWS CLI joining the "orphan tools" registry (`bin/omawsl-sub/orphan-tools.sh`) so `omawsl update`
  covers it, since its install method has no native updater.
- `unzip` added to the base package list (`install/terminal/libraries.sh`), a real new dependency
  introduced by AWS CLI's official installer.

**Out of scope:**
- Terraform stays in the `language` category exactly as today — it's not moving.
- Azure CLI's and GCP CLI's own update lifecycle — both are apt-installed, so `sudo apt upgrade`
  already covers them (same reasoning that excludes Terraform from the orphan-tools list today).
- Any change to how `mise`-managed languages work.

## 3. New category inventory

| Slug | Label | Install method | Uninstall method | Idempotency check |
|---|---|---|---|---|
| `azure` | Azure CLI | apt repo (`packages.microsoft.com/repos/azure-cli`) — moved as-is from `install/terminal/cloud-tools.sh` | `apt-get purge azure-cli` + remove sources file/gpg key — moved as-is from `uninstall/dev-language.sh` | `command -v az` |
| `gcp` | GCP CLI | apt repo (`packages.cloud.google.com/apt cloud-sdk main`), package `google-cloud-cli` | `apt-get purge google-cloud-cli` + remove sources file/gpg key | `command -v gcloud` |
| `aws` | AWS CLI | AWS's official v2 installer: curl `awscli-exe-linux-<arch>.zip` → `unzip` → `sudo <tmp>/aws/install` | `sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws /usr/local/bin/aws_completer` (AWS's own documented uninstall paths) | `command -v aws` |

GCP CLI's apt repo, unlike Azure's, isn't pinned to a Ubuntu codename (Google publishes a single
`cloud-sdk` suite), so it needs no jammy-style fallback logic.

AWS CLI's download URL is architecture-specific (`awscli-exe-linux-x86_64.zip` vs
`awscli-exe-linux-aarch64.zip`). Reuses the same `dpkg --print-architecture` check the apt-based
installers already use (mapped `amd64`→`x86_64`, `arm64`→`aarch64`), rather than introducing new
arch-detection machinery.

## 4. Menu/UX changes

`install/first-run-choices.sh` gains a new prompt, placed right after the Languages menu (which
drops "Azure CLI" from its option list — Terraform stays):

```
OMAWSL_LANGUAGES="$(omawsl_prompt_multi "Languages & cloud tools" \
  "Ruby on Rails" "Node.js" "Go" "PHP" "Python" "Elixir" "Rust" "Java" "Terraform")"

OMAWSL_CLOUD_CLIS="$(omawsl_prompt_multi "Cloud CLIs" \
  "Azure CLI" "AWS CLI" "GCP CLI")"
```

`bin/omawsl-sub/install.sh`'s no-args interactive picker gains `"Cloud CLIs"` as a fourth category
option alongside `"Language/tool"`, `"Editors & AI tooling"`, `"Storage"`.

## 5. Install-side implementation

- `install/terminal/cloud-tools.sh` shrinks to just Terraform: `omawsl_install_terraform` and
  `omawsl_cloud_tools()` (still reads `OMAWSL_LANGUAGES`, Azure CLI case removed). Unchanged
  behavior, unchanged tests, minus the azure-cli portion.
- New `install/terminal/cloud-clis.sh`:
  - `omawsl_install_azure_cli` — moved verbatim from `cloud-tools.sh`, byte-for-byte.
  - `omawsl_install_gcp_cli` — same apt-repo/gpg-key/failure-isolation shape as
    `omawsl_install_azure_cli` (the `{ ... } || ok=0`, "remove sources file on apt-get failure so a
    retry doesn't inherit a broken repo" pattern), targeting Google's repo instead.
  - `omawsl_aws_cli_install_steps` — unguarded actual install commands (curl zip → unzip → sudo
    install → clean up temp dir), same failure-isolation shape.
  - `omawsl_install_aws_cli` — guarded wrapper (`command -v aws` check) that calls
    `omawsl_aws_cli_install_steps`. Split this way (mirroring `app-opencode.sh`'s
    `omawsl_opencode_install_steps` / `omawsl_install_opencode` pattern) specifically so
    `orphan-tools.sh`'s update-apply path (§8) can bypass the guard on an already-installed AWS
    CLI, the same way every other orphan tool's update works today.
  - `omawsl_cloud_clis()` — reads `OMAWSL_CLOUD_CLIS`, calls whichever of the three install
    functions are selected. Each install function already isolates its own failure internally, so
    (matching `omawsl_cloud_tools`'s existing comment) no extra isolation logic is needed here.
- `install/terminal/libraries.sh` gains `unzip` in its `apt-get install` package list.
- `install/terminal.sh`'s fixed `OMAWSL_TERMINAL_SCRIPTS` order gains
  `"terminal/cloud-clis.sh"` → `omawsl_cloud_clis`, placed right after `cloud-tools.sh` (so
  `libraries.sh`'s `unzip` install has already run by the time AWS CLI's installer needs it).

## 6. Uninstall-side implementation

- New `uninstall/cloud-clis.sh`:
  - `omawsl_uninstall_azure_cli` — moved verbatim from `uninstall/dev-language.sh`.
  - `omawsl_uninstall_gcp_cli` — apt purge + remove sources file/gpg key, mirroring
    `omawsl_uninstall_azure_cli`'s shape.
  - `omawsl_uninstall_aws_cli` — `sudo rm -rf` the three AWS-documented install paths, guarded by
    a `command -v aws` "nothing to do" check (same shape as every other uninstall function).
  - `omawsl_uninstall_cloud_cli <label>` — dispatches on label ("Azure CLI"/"AWS CLI"/"GCP CLI"),
    same shape as `omawsl_uninstall_language`/`omawsl_uninstall_storage`.
- `uninstall/dev-language.sh` loses its `"Azure CLI")` case from `omawsl_uninstall_language`.

## 7. CLI plumbing (`bin/omawsl-sub/*.sh`)

- `items.sh`:
  - `omawsl_item_category`: `azure|aws|gcp` → `cloud` (azure moves out of the `language` arm).
  - `omawsl_item_label`: add `aws) echo "AWS CLI"` and `gcp) echo "GCP CLI"`.
  - `omawsl_item_slugs`: add `cloud) printf '%s\n' azure aws gcp`.
- `install.sh`: new `omawsl_install_apply_cloud`/`omawsl_install_category_cloud` (same shape as
  the `storage` pair), `cloud` added to `omawsl_install_direct`'s category switch, `"Cloud CLIs"`
  added to the interactive category menu (§4) and to `omawsl_install_command`'s category
  validation/usage text.
- `uninstall.sh`: dispatch case `azure|aws|gcp` → source `uninstall/cloud-clis.sh` →
  `omawsl_uninstall_cloud_cli`; `omawsl_uninstall_deselect`'s category→key map gains
  `cloud) key=OMAWSL_CLOUD_CLIS`.
- `doctor.sh`: new `omawsl_doctor_cloud_installed` (`azure`→`command -v az`, `gcp`→`command -v
  gcloud`, `aws`→`command -v aws`) plus a new `omawsl_doctor_report_category cloud
  omawsl_doctor_cloud_installed OMAWSL_CLOUD_CLIS` call, same shape as the existing
  language/editor/storage calls. `omawsl_doctor_language_installed`'s existing `azure)` case is
  removed (moved to the new function).

## 8. AWS CLI joins the orphan-tools registry

Azure CLI and GCP CLI are apt-installed, so `sudo apt upgrade` already keeps them current —
excluded from this registry for the same reason Terraform is excluded today. AWS CLI's installer
has no native updater, so it becomes the registry's 8th entry in `bin/omawsl-sub/orphan-tools.sh`:

- Source `install/terminal/cloud-clis.sh` (for `omawsl_aws_cli_install_steps`).
- `omawsl_orphan_tool_slugs` → add `aws`.
- `omawsl_orphan_tool_label` → `aws` joins the `omawsl_item_label` reuse arm (already registered in
  `items.sh`, same as `opencode`/`claude`/etc.).
- `omawsl_orphan_tool_installed` → `aws) command -v aws &>/dev/null`.
- `omawsl_orphan_tool_version_installed` → `omawsl_orphan_extract_semver "$(aws --version
  2>/dev/null || true)"`. AWS's `--version` output starts `aws-cli/X.Y.Z Python/...`, so the
  existing first-match regex already extracts the right token with no special-casing.
- `omawsl_orphan_tool_version_latest` → `omawsl_orphan_latest_from_github aws/aws-cli`.
- `omawsl_orphan_tool_apply_update` → `aws) omawsl_aws_cli_install_steps || ok=0`.

## 9. Documentation updates

- `README.md`: the languages line drops "Azure CLI"; a new line documents the Cloud CLIs menu
  (Azure CLI, AWS CLI, GCP CLI).
- `docs/updating.md` (from the update-mechanism feature): its "Language runtimes & cloud tools"
  group's tool list drops "Azure CLI" and gains "GCP CLI" (both apt/mise-updated, unchanged
  mechanism); AWS CLI moves into the "orphan tools, `omawsl update`'s picker" group.

## 10. Error handling

Every new install/uninstall function follows this codebase's established failure-isolation
pattern exactly (`cloud-tools.sh`'s existing Terraform/Azure CLI handling):
- apt-based installs (`gcp`) isolate a repo-add failure with `{ ... } || ok=0`, remove a
  partially-written sources file on failure so a retry starts clean, and report-but-don't-abort.
- AWS CLI's installer isolates a curl/unzip/install failure the same way, and always cleans up its
  temp directory regardless of success/failure.
- `omawsl_cloud_clis()` calls all three selected installers unconditionally — one tool's internal
  failure (already swallowed by its own function) never prevents the others from being attempted,
  matching `omawsl_cloud_tools()`'s existing behavior today.

## 11. Testing

Follows this repo's existing bats conventions:
- `tests/cloud_tools_test.bats` loses its Azure CLI cases (Terraform-only test file going forward).
- New `tests/cloud_clis_test.bats` covers `omawsl_install_azure_cli` (moved, same assertions),
  `omawsl_install_gcp_cli`, `omawsl_aws_cli_install_steps`/`omawsl_install_aws_cli`, and
  `omawsl_cloud_clis()`'s selection logic — stubbing `curl`/`sudo`/`gpg`/`unzip` per this repo's
  `tests/helpers/stubs.bash` pattern, no real network/installs.
- New `tests/uninstall_cloud_clis_test.bats` covers the three uninstall functions and the label
  dispatcher; `tests/uninstall_dev_language_test.bats` loses its Azure CLI case.
- `tests/first_run_choices_test.bats`, `tests/omawsl_install_command_test.bats`,
  `tests/omawsl_uninstall_command_test.bats` gain `cloud` category coverage (new prompt, direct
  dispatch, deselect-on-uninstall).
- `tests/omawsl_orphan_tools_test.bats` gains AWS CLI's slug through the same stubbed
  `--version`/GitHub-API assertions the other 7 tools already have.

## 12. Open questions for the implementation plan

- None — every install/uninstall mechanism here follows an existing, already-verified pattern in
  this codebase (apt-repo shape from Azure CLI/Terraform, orphan-tool shape from opencode/claude).
