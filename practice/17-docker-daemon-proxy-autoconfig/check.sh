#!/usr/bin/env bash
set -euo pipefail

# Behavioral check for lesson 17 (docker-daemon-proxy-autoconfig).
#
# The real functions this exercise rebuilds ultimately write a file under
# /etc/systemd/system/docker.service.d and restart the real Docker daemon
# via `sudo systemctl restart docker` - neither of those is confined to
# $HOME, so a HOME override alone provides zero containment here (see
# check-generation.md's Strategy B decision rule). This check instead:
#   1. Always passes an explicit scratch directory as the `dir` argument
#      (the testable seam the exercise asks the implementation to honor),
#      so nothing is ever pointed at the real docker.service.d path.
#   2. Replaces `sudo` with a stand-in shell function for the whole check,
#      so even if a solution ever fell back to its real-path default,
#      nothing would actually reach the real filesystem or the real
#      systemd/docker daemon. The stand-in forwards safe, containable
#      operations (mkdir/tee/cat/rm/chmod) to the real commands - operating
#      only on paths inside the scratch directory - and no-ops systemctl
#      entirely, while logging every call so assertions can check what
#      *would* have happened.
#
# This check never spawns the learner's script as a separate `bash`
# process - it sources docker-proxy.sh directly and calls its functions in
# this same shell, so the `sudo` stand-in (an ordinary shell function, no
# `export -f` needed) is guaranteed to be what any `sudo ...` call inside
# the sourced functions resolves to, in every scenario below.

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

script="$(cd "$(dirname "$0")" && pwd)/docker-proxy.sh"

record="$scratch/sudo-calls.log"
: > "$record"
sudo() {
  echo "sudo $*" >> "$record"
  case "$1" in
    mkdir) shift; command mkdir "$@" ;;
    tee) shift; command tee "$@" ;;
    cat) shift; command cat "$@" ;;
    rm) shift; command rm "$@" 2>/dev/null || true ;;
    chmod) shift; command chmod "$@" ;;
    systemctl) : ;;
    *) : ;;
  esac
}

# Hermetic: never let this machine's own ambient proxy settings (if any)
# leak into the assertions below.
unset HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy 2>/dev/null || true

source "$script"

# --- omawsl_detect_proxy_env -------------------------------------------

export HTTP_PROXY="http://upper.example:8080"
export http_proxy="http://lower.example:8080"
result="$(omawsl_detect_proxy_env HTTP_PROXY 2>/dev/null || echo '<error>')"
if [[ "$result" == "http://upper.example:8080" ]]; then
  echo "PASS: detect_proxy_env prefers the uppercase form when both are set"
else
  echo "FAIL: detect_proxy_env(HTTP_PROXY) with both forms set was '$result', expected 'http://upper.example:8080'"
  failed=1
fi

unset HTTP_PROXY 2>/dev/null || true
export http_proxy="http://lower.example:8080"
result="$(omawsl_detect_proxy_env HTTP_PROXY 2>/dev/null || echo '<error>')"
if [[ "$result" == "http://lower.example:8080" ]]; then
  echo "PASS: detect_proxy_env falls back to the lowercase form when uppercase is unset"
else
  echo "FAIL: detect_proxy_env(HTTP_PROXY) with only lowercase set was '$result', expected 'http://lower.example:8080'"
  failed=1
fi

unset HTTP_PROXY http_proxy 2>/dev/null || true
result="$(omawsl_detect_proxy_env HTTP_PROXY 2>/dev/null || echo '<error>')"
if [[ -z "$result" ]]; then
  echo "PASS: detect_proxy_env is empty when neither form is set"
else
  echo "FAIL: detect_proxy_env(HTTP_PROXY) with neither form set was '$result', expected empty"
  failed=1
fi

# --- omawsl_docker_proxy_conflict ---------------------------------------

conflict_probe_dir="$scratch/conflict-probe"
mkdir -p "$conflict_probe_dir"
printf '[Service]\nEnvironment="HTTP_PROXY=http://other:8080"\n' > "$conflict_probe_dir/other.conf"
if omawsl_docker_proxy_conflict "$conflict_probe_dir" "$conflict_probe_dir/omawsl-proxy.conf" 2>/dev/null; then
  echo "PASS: docker_proxy_conflict is true when another .conf file already sets a proxy"
else
  echo "FAIL: docker_proxy_conflict was false even though another file in the directory sets a proxy"
  failed=1
fi

empty_probe_dir="$scratch/empty-probe"
mkdir -p "$empty_probe_dir"
if omawsl_docker_proxy_conflict "$empty_probe_dir" "$empty_probe_dir/omawsl-proxy.conf" 2>/dev/null; then
  echo "FAIL: docker_proxy_conflict was true for an empty directory, expected false"
  failed=1
else
  echo "PASS: docker_proxy_conflict is false when the directory has no other proxy-setting file"
fi

# --- omawsl_configure_docker_proxy: conflict back-off -------------------

unset HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy 2>/dev/null || true
export HTTP_PROXY="http://mine.example:8080"

conflict_dir="$scratch/conflict"
mkdir -p "$conflict_dir"
corp_conf="$conflict_dir/corp-managed.conf"
printf '[Service]\nEnvironment="HTTP_PROXY=http://corp-own.example:8080"\n' > "$corp_conf"
corp_conf_before="$(cat "$corp_conf")"

: > "$record"
if omawsl_configure_docker_proxy "$conflict_dir" >/dev/null 2>&1; then
  configure_call_ok=1
else
  configure_call_ok=0
fi

if [[ "$configure_call_ok" -eq 1 ]]; then
  echo "PASS: configure_docker_proxy returns success on the back-off path"
else
  echo "FAIL: configure_docker_proxy exited with an error when it should have backed off quietly"
  failed=1
fi

if [[ ! -f "$conflict_dir/omawsl-proxy.conf" ]]; then
  echo "PASS: configure_docker_proxy does not write its own file when another file already configures a proxy"
else
  echo "FAIL: configure_docker_proxy wrote omawsl-proxy.conf even though another file already configures a proxy"
  failed=1
fi

corp_conf_after="$(cat "$corp_conf" 2>/dev/null || echo '<missing>')"
if [[ "$corp_conf_after" == "$corp_conf_before" ]]; then
  echo "PASS: the pre-existing conflicting file is left completely untouched"
else
  echo "FAIL: the pre-existing conflicting file's content changed - it should never be modified"
  failed=1
fi

if grep -q 'systemctl restart docker' "$record" 2>/dev/null; then
  echo "FAIL: configure_docker_proxy restarted docker on back-off even though it had no stale file of its own to remove"
  failed=1
else
  echo "PASS: configure_docker_proxy does not restart docker on back-off when it had nothing of its own to remove"
fi

# --- omawsl_configure_docker_proxy: fresh write, content/format ---------

unset HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy 2>/dev/null || true
export HTTP_PROXY="http://webproxy.example:8080"
export HTTPS_PROXY="http://webproxy.example:8080"
export NO_PROXY="localhost,127.0.0.1"

fresh_dir="$scratch/fresh"
mkdir -p "$fresh_dir"
own_file="$fresh_dir/omawsl-proxy.conf"

: > "$record"
if omawsl_configure_docker_proxy "$fresh_dir" >/dev/null 2>&1; then
  fresh_call_ok=1
else
  fresh_call_ok=0
fi

if [[ "$fresh_call_ok" -eq 1 && -f "$own_file" ]]; then
  echo "PASS: configure_docker_proxy writes omawsl-proxy.conf when a proxy is set and nothing conflicts"
else
  echo "FAIL: configure_docker_proxy did not write $own_file when a proxy was set and no conflict existed"
  failed=1
fi

content="$(cat "$own_file" 2>/dev/null || echo '<missing>')"

if [[ "$content" == *'[Service]'* ]]; then
  echo "PASS: the drop-in starts with a [Service] section header"
else
  echo "FAIL: the drop-in is missing the [Service] section header - got: $content"
  failed=1
fi

if [[ "$content" == *'Environment="HTTP_PROXY=http://webproxy.example:8080"'* ]]; then
  echo "PASS: the drop-in contains a correctly formatted HTTP_PROXY Environment= line"
else
  echo "FAIL: the drop-in is missing a correctly formatted HTTP_PROXY line - got: $content"
  failed=1
fi

if [[ "$content" == *'Environment="HTTPS_PROXY=http://webproxy.example:8080"'* ]]; then
  echo "PASS: the drop-in contains a correctly formatted HTTPS_PROXY Environment= line"
else
  echo "FAIL: the drop-in is missing a correctly formatted HTTPS_PROXY line - got: $content"
  failed=1
fi

if [[ "$content" == *'Environment="NO_PROXY=localhost,127.0.0.1"'* ]]; then
  echo "PASS: the drop-in contains a correctly formatted NO_PROXY Environment= line"
else
  echo "FAIL: the drop-in is missing a correctly formatted NO_PROXY line - got: $content"
  failed=1
fi

# --- omawsl_configure_docker_proxy: idempotent re-run --------------------

: > "$record"
if omawsl_configure_docker_proxy "$fresh_dir" >/dev/null 2>&1; then
  idempotent_call_ok=1
else
  idempotent_call_ok=0
fi

if [[ "$idempotent_call_ok" -eq 1 ]] && ! grep -qE 'tee|systemctl restart' "$record" 2>/dev/null; then
  echo "PASS: re-running with unchanged proxy values does not rewrite the file or restart docker"
else
  echo "FAIL: re-running with unchanged proxy values re-wrote the file and/or restarted docker - the content comparison should have short-circuited"
  failed=1
fi

# --- no-proxy no-op -------------------------------------------------------

unset HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy 2>/dev/null || true

noproxy_dir="$scratch/noproxy"
mkdir -p "$noproxy_dir"
: > "$record"
if omawsl_configure_docker_proxy "$noproxy_dir" >/dev/null 2>&1; then
  noproxy_call_ok=1
else
  noproxy_call_ok=0
fi

if [[ "$noproxy_call_ok" -eq 1 && ! -f "$noproxy_dir/omawsl-proxy.conf" && ! -s "$record" ]]; then
  echo "PASS: configure_docker_proxy is a silent no-op when no proxy is set in the environment"
else
  echo "FAIL: configure_docker_proxy should do nothing at all (no file, no sudo calls) when no proxy is set"
  failed=1
fi

exit "$failed"
