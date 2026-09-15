#!/usr/bin/env bash
# practice/13-cloud-clis-menu/uninstall-cloud-clis.sh
#
# New file - the uninstall side of the new "cloud" picker category, the
# mirror image of cloud-clis.sh. See docs/curriculum/13-cloud-clis-menu.md,
# section 3 (Exercise), for the full behavior spec.
#
# Source lib.sh the same way uninstall-language.sh next to this file
# does.
#
# Functions required, exact names:
#
#   omawsl_uninstall_azure_cli
#     Moved out of uninstall-language.sh (see that file's TODO) - adapt
#     or move verbatim. Guarded: if `command -v az` fails, print that
#     there's nothing to do and return 0 without touching anything.
#
#   omawsl_uninstall_gcp_cli
#     Same shape, for "google-cloud-cli" / `command -v gcloud`.
#
#   omawsl_uninstall_aws_cli
#     Guarded by `command -v aws`. AWS's own v2 installer documents three
#     paths its install creates: /usr/local/aws-cli,
#     /usr/local/bin/aws, /usr/local/bin/aws_completer. Remove all three
#     (`sudo rm -rf`).
#
#   omawsl_uninstall_cloud_cli <label>
#     Takes the exact picker label ("Azure CLI" / "AWS CLI" / "GCP CLI")
#     and dispatches to the matching function above - same shape as
#     uninstall-language.sh's own omawsl_uninstall_language. An unknown
#     label must print an error to stderr and return non-zero, not
#     silently succeed.
#
# TODO: implement all four functions above.
