#!/bin/sh
# Use Ubuntu's signed sources without unrelated repositories preloaded on runners.
set -eu
test "${GITHUB_ACTIONS:-}" = true
test -f /etc/apt/sources.list.d/ubuntu.sources
sudo apt-get -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/ubuntu.sources -o Dir::Etc::sourceparts=- update
sudo apt-get -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/ubuntu.sources -o Dir::Etc::sourceparts=- install -y "$@"
