#!/usr/bin/env bash
# Load the mstflint access module (if needed) and query a ConnectX-3 card.
# Usage: ./query.sh <pci-bdf>    e.g. ./query.sh 0000:41:00.0
set -euo pipefail

bdf="${1:-}"
if [[ -z "$bdf" ]]; then
  echo "usage: $0 <domain:bus:dev.func>    e.g. 0000:41:00.0" >&2
  exit 2
fi

if ! lsmod | grep -q '^mstflint_access'; then
  sudo modprobe mstflint_access
fi

sudo mstflint -d "pciconf-$bdf" query
