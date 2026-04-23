#!/usr/bin/env bash
# Clone upstream mstflint and build the userland + DKMS .debs.
# Output goes to ./dist/.
set -euo pipefail

SRC_URL="https://github.com/Mellanox/mstflint.git"
WORK=$(mktemp -d)
OUT="$(pwd)/dist"
trap 'rm -rf "$WORK"' EXIT

need=(autoconf automake libtool dh-dkms debhelper libexpat1-dev libibmad-dev
      libibverbs-dev liblzma-dev libssl-dev zlib1g-dev pkg-config bzip2 dpkg-dev git)
missing=()
for p in "${need[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done
if (( ${#missing[@]} )); then
  echo "Missing build deps: ${missing[*]}"
  echo "Install with: sudo apt install ${missing[*]}"
  exit 1
fi

echo "==> Cloning $SRC_URL"
git clone --depth 1 "$SRC_URL" "$WORK/mstflint"

echo "==> Building .debs (this takes a few minutes)"
cd "$WORK/mstflint"
dpkg-buildpackage -b -uc -us

mkdir -p "$OUT"
cp "$WORK"/mstflint_*_*.deb "$WORK"/mstflint-dkms_*_all.deb "$OUT/"

echo
echo "==> Done. Packages in $OUT:"
ls -1 "$OUT"/*.deb
echo
echo "To install:"
echo "  sudo apt install $OUT/mstflint_*.deb $OUT/mstflint-dkms_*.deb"
