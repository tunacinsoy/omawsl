#!/usr/bin/env bash
set -euo pipefail

# Lesson 17: Docker daemon proxy auto-configuration.
#
# Implement the three functions below. This file is meant to be `source`d
# by other scripts (like check.sh) - do NOT add an unconditional dispatcher
# or `main` call at the bottom; it should only define functions.
#
# See docs/curriculum/17-docker-daemon-proxy-autoconfig.md for the full
# spec of each function's behavior before you start.

# omawsl_detect_proxy_env <VAR>
#
# Given an uppercase proxy env var name (e.g. HTTP_PROXY), print its value
# if set and non-empty. Otherwise fall back to the lowercase form
# (http_proxy) and print that. Otherwise print an empty string. Must not
# error under `set -u` when neither form is set.
omawsl_detect_proxy_env() {
  : # TODO: implement
}

# omawsl_docker_proxy_conflict <dir> <own_file>
#
# Return success (0) if some *other* .conf file in <dir> (i.e. not
# <own_file> itself) already contains a line matching `Environment=.*PROXY`.
# Return failure (1) if <dir> doesn't exist, is empty, or no *other* file
# in it mentions a proxy.
omawsl_docker_proxy_conflict() {
  : # TODO: implement
}

# omawsl_configure_docker_proxy [dir]
#
# dir defaults to ${OMAWSL_DOCKER_SERVICE_D_DIR:-/etc/systemd/system/docker.service.d}
# when not passed explicitly. The managed file is always
# "$dir/omawsl-proxy.conf". See the lesson's Exercise section for the full
# five-step behavior (no-proxy no-op, conflict back-off, content build,
# idempotent skip, write-and-restart).
omawsl_configure_docker_proxy() {
  : # TODO: implement
}
