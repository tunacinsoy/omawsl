#!/usr/bin/env bash
set -euo pipefail

omawsl_install_libraries() {
  sudo apt-get update -qq
  sudo apt-get install -y \
    build-essential pkg-config autoconf bison clang rustc pipx \
    libssl-dev libreadline-dev zlib1g-dev libyaml-dev libncurses5-dev \
    libffi-dev libgdbm-dev libjemalloc2 \
    libvips imagemagick libmagickwand-dev mupdf mupdf-tools \
    redis-tools sqlite3 libsqlite3-0 libsqlite3-dev libmysqlclient-dev libpq-dev \
    postgresql-client postgresql-client-common
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_libraries
fi
