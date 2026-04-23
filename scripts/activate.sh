#!/usr/bin/env bash
# Activate newly-burned firmware on a ConnectX-3 without rebooting:
# unbind mlx4_core from the device, trigger a PCI hot-reset (reloads FW from
# flash), rebind. Network interfaces on this card drop briefly.
#
# Usage: sudo ./activate.sh <pci-bdf>    e.g. sudo ./activate.sh 0000:41:00.0
set -euo pipefail

bdf="${1:-}"
if [[ -z "$bdf" ]]; then
  echo "usage: $0 <domain:bus:dev.func>    e.g. 0000:41:00.0" >&2
  exit 2
fi

sys="/sys/bus/pci/devices/$bdf"
[[ -d "$sys" ]] || { echo "no such PCI device: $sys" >&2; exit 1; }

drv=$(basename "$(readlink "$sys/driver" 2>/dev/null)" 2>/dev/null || true)
if [[ "$drv" != "mlx4_core" ]]; then
  echo "warning: expected driver mlx4_core, found '${drv:-none}'" >&2
fi

echo "==> unbinding $drv from $bdf"
echo "$bdf" > /sys/bus/pci/drivers/"${drv:-mlx4_core}"/unbind
sleep 1

echo "==> PCI hot-reset on $bdf"
echo 1 > "$sys/reset"
sleep 1

echo "==> rebinding mlx4_core to $bdf"
echo "$bdf" > /sys/bus/pci/drivers/mlx4_core/bind
sleep 2

echo "==> current running firmware:"
if ! lsmod | grep -q '^mstflint_access'; then
  modprobe mstflint_access
fi
mstflint -d "pciconf-$bdf" query | grep -E 'FW Version|Rom Info|PSID'
