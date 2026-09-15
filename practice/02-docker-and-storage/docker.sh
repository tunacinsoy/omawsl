#!/usr/bin/env bash
set -euo pipefail

OMAWSL_DOCKER_SH_SRC="${BASH_SOURCE[0]}"
case "$OMAWSL_DOCKER_SH_SRC" in
  */*) SCRIPT_DIR="$(cd "${OMAWSL_DOCKER_SH_SRC%/*}" && pwd)" ;;
  *)   SCRIPT_DIR="$(pwd)" ;;
esac
source "$SCRIPT_DIR/lib.sh"

OMAWSL_DOCKER_MODE_DESKTOP="Docker Desktop for Windows"

# TODO(Lesson 2): implement all of the following. Each is described in the
# lesson's Exercise section - build them in this order, since later ones
# call earlier ones:
#
#   omawsl_docker_desktop
#   omawsl_check_docker_path_collision [which_a_docker_output]
#   omawsl_install_docker_ce [apt_sources_file] [keyrings_dir]
#   omawsl_docker_engine [wsl_conf_file] [apt_sources_file] [keyrings_dir]
#   omawsl_docker_final_reminder
#   omawsl_docker

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_docker
fi
