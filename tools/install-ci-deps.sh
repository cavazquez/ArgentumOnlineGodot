#!/bin/sh
# Use Ubuntu's signed sources without unrelated repositories preloaded on runners.
set -eu
test "${GITHUB_ACTIONS:-}" = true
test -f /etc/apt/sources.list.d/ubuntu.sources

run_apt() {
  pyao_apt_stage=$1
  pyao_apt_limit=$2
  shift 2
  pyao_apt_attempt=1
  while [ "$pyao_apt_attempt" -le 2 ]; do
    printf '%s APT %s attempt=%s start\n' "$(date -u +%FT%TZ)" "$pyao_apt_stage" "$pyao_apt_attempt"
    if timeout --signal=TERM --kill-after=15s "$pyao_apt_limit" sudo apt-get \
      -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/ubuntu.sources \
      -o Dir::Etc::sourceparts=- \
      -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 \
      -o Acquire::Retries=2 -o DPkg::Lock::Timeout=60 "$@"; then
      printf '%s APT %s complete\n' "$(date -u +%FT%TZ)" "$pyao_apt_stage"
      return 0
    else
      pyao_apt_status=$?
      printf '%s APT %s attempt=%s failed status=%s\n' "$(date -u +%FT%TZ)" "$pyao_apt_stage" "$pyao_apt_attempt" "$pyao_apt_status" >&2
    fi
    if [ "$pyao_apt_attempt" -eq 2 ]; then return "$pyao_apt_status"; fi
    pyao_apt_attempt=$((pyao_apt_attempt + 1))
    sleep 5
  done
}

run_apt update 120s update
run_apt install 600s install --no-install-recommends -y "$@"
