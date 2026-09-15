#!/usr/bin/env bash
# practice/13-cloud-clis-menu/doctor-cloud.sh
#
# New file - the "is it actually installed right now" check for the new
# "cloud" category, the same job the real project's doctor.sh does per
# category. See docs/curriculum/13-cloud-clis-menu.md, section 3
# (Exercise).
#
# Function required, exact name:
#
#   omawsl_doctor_cloud_installed <slug>
#     azure -> true (exit 0) iff `command -v az` succeeds
#     aws   -> true (exit 0) iff `command -v aws` succeeds
#     gcp   -> true (exit 0) iff `command -v gcloud` succeeds
#     any other slug -> return 1 (unrecognized)
#
#     This is a pure read-only check - it must never install, uninstall,
#     or modify anything. It only reports what's already true.
#
# TODO: implement this function.
