#!/usr/bin/env bash
# practice/13-cloud-clis-menu/cloud-clis.sh
#
# New file - the install side of the new "cloud" picker category. See
# docs/curriculum/13-cloud-clis-menu.md, section 3 (Exercise), for the
# full behavior spec. This header is a quick reference, not a substitute
# for reading that section.
#
# Source lib.sh (for omawsl_list_has) the same way cloud-tools.sh next to
# this file does. You don't need items.sh here - omawsl_cloud_clis reads
# OMAWSL_CLOUD_CLIS and matches against the three exact label strings
# directly, the same way the real project's own omawsl_cloud_clis does.
#
# Functions required, exact names:
#
#   omawsl_install_azure_cli
#     Idempotent (command -v az guard). Moved out of cloud-tools.sh (see
#     that file's TODO) - adapt or move verbatim, your call.
#
#   omawsl_install_gcp_cli
#     Idempotent (command -v gcloud guard). Same shape as
#     omawsl_install_azure_cli, installing "google-cloud-cli" instead of
#     "azure-cli" via apt.
#
#   omawsl_aws_cli_install_steps
#     UNGUARDED - the actual install commands, no command -v check. Make
#     a temp dir (`mktemp -d`), then exactly this shape (matches AWS's
#     own documented v2 installer, and matters for the check below,
#     which intercepts real commands at these exact call sites):
#       curl -fsSL <awscli zip url> -o "$tmp_dir/awscliv2.zip"
#       unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir"
#       sudo "$tmp_dir/aws/install" --update
#     (the zip is documented to unpack into an "aws/" directory
#     containing an "install" script - you don't need to construct that
#     structure yourself, curl/unzip do it for real; here they're stubbed,
#     but the *call shape* your code makes is what's being checked). Must
#     return a non-zero exit status if any step fails (this one detail
#     matters - see the lesson's Walkthrough for why a real bug shipped
#     from getting it backwards).
#
#   omawsl_install_aws_cli
#     The GUARDED wrapper install.sh actually calls: command -v aws guard,
#     then calls omawsl_aws_cli_install_steps but SWALLOWS its failure (a
#     failed install here must not abort the rest of an install.sh run
#     under set -e).
#
#   omawsl_cloud_clis
#     Reads OMAWSL_CLOUD_CLIS (a comma-delimited string of exactly these
#     labels: "Azure CLI", "AWS CLI", "GCP CLI" - use omawsl_list_has,
#     whole-token match) and calls whichever of the three install
#     functions above are selected. Nothing pre-selected by default;
#     an empty/missing OMAWSL_CLOUD_CLIS is a valid no-op that installs
#     nothing.
#
# TODO: implement all five functions above.
