#!/usr/bin/env bash
set -euo pipefail

# Baseline as it stood at the end of the languages-and-cloud-tools phase.
# mise builds PHP from source rather than downloading a prebuilt binary, so
# PHP's curl/GD/intl/zip/mbstring extensions each need their own apt "-dev"
# package installed BEFORE mise ever runs - otherwise PHP's own ./configure
# step fails partway through the build looking for headers/pkg-config
# metadata that only a "-dev" package ships.
#
# TODO(this lesson): extend the package list below with the five "-dev"
# packages PHP's curl, GD, intl, zip, and mbstring extensions each need to
# configure successfully. See the lesson's Walkthrough for which extension
# needs which package and why. Don't remove or reorder anything already
# here.
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
