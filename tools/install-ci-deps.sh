#!/bin/sh
# Use Ubuntu's signed sources without unrelated repositories preloaded on runners.
set -eu
test "${GITHUB_ACTIONS:-}" = true
test -f /etc/apt/sources.list.d/ubuntu.sources

pyao_build=false
if [ "${1:-}" = --build ]; then
  pyao_build=true
  shift
fi

# Conservar paquetes ya presentes evita actualizar el stack gráfico del runner
# sólo por ejecutar un binario. Al compilar, APT resuelve el stack completo para
# mantener coherentes las cabeceras, bibliotecas y drivers del editor.
pyao_remaining=0
if [ "$pyao_build" = false ]; then pyao_remaining=$#; fi
while [ "$pyao_remaining" -gt 0 ]; do
  pyao_package=$1
  shift
  pyao_status=$(dpkg-query --show --showformat='${db:Status-Status} ${Version}' -- "$pyao_package" 2>/dev/null || true)
  case "$pyao_status" in
    installed\ *) printf 'APT keep %s: %s\n' "$pyao_package" "$pyao_status" ;;
    *) set -- "$@" "$pyao_package" ;;
  esac
  pyao_remaining=$((pyao_remaining - 1))
done
if [ "$#" -eq 0 ]; then
  printf 'APT: all requested dependencies are already installed\n'
  exit 0
fi

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
