# MCX312A (ConnectX-3) firmware how-to

Notes + tooling for managing Mellanox `MCX312A-XCBT` (ConnectX-3, PSID `MT_1080120023`) on
modern Ubuntu. Captures a gotcha that cost a few hours the first time:
Ubuntu 24.04's `mstflint` 4.33.0 segfaults on ConnectX-3, and the packaged
`mstfwreset` / `mft` no longer support this generation at all.

This repo ships rebuilt upstream `mstflint` `.deb`s (userland + DKMS kernel
module) that work on CX-3, plus a short runbook for querying / backing up /
flashing / activating firmware.

---

## What's in here

- `build.sh` — clones upstream mstflint, runs `dpkg-buildpackage`, drops two
  `.deb`s into `./dist/`.
- `scripts/query.sh` — load the DKMS module (if needed) and dump firmware info
  for a PCI device.
- `scripts/activate.sh` — unbind `mlx4_core`, PCI hot-reset the device, rebind.
  Use after a burn to load the new firmware without a reboot.
- GitHub Releases — prebuilt `.deb`s for the host this was built on
  (`x86_64`, Ubuntu 24.04, kernel 6.17). If you're on a different kernel,
  DKMS will rebuild the module itself; if you're on a different distro or
  arch, run `build.sh` instead.

---

## Quick start — install prebuilt packages

Grab `mstflint_*.deb` and `mstflint-dkms_*.deb` from the latest
[Release](../../releases), then:

```
sudo apt install ./mstflint_*.deb ./mstflint-dkms_*.deb
```

This replaces the distro `mstflint` (`/usr/bin/mstflint`) with 4.35.0 and
registers the `mstflint_access` kernel module with DKMS, so it rebuilds on
every kernel upgrade. Module is signed with the system MOK — fine under
Secure Boot.

Verify:

```
mstflint -v                          # should report 4.35.0
sudo modprobe mstflint_access
lsmod | grep mstflint                # mstflint_access loaded
```

---

## Firmware upgrade walkthrough

### 1. Find the card and confirm identity

```
lspci -nn | grep -i mellanox                     # note the PCI BDF, e.g. 41:00.0
lspci -vvs 41:00.0 | grep -E 'Part number|Eng'   # confirm MCX312A-XCBT
```

### 2. Load the access module

```
sudo modprobe mstflint_access
```

This creates `/dev/0000:<BB>:<DD>.<F>_mstconf`. You don't address it by path;
you address the card with the `pciconf-<domain>:<bus>:<dev>.<func>` pseudo-name
(see below).

### 3. Query current firmware

```
sudo mstflint -d pciconf-0000:41:00.0 query
```

Expected fields: `FW Version`, `Rom Info` (FlexBoot/PXE version), `PSID`.
**Write the PSID down.** The firmware file you flash **must** have a matching
PSID or you risk bricking the card.

### 4. Back up current flash

```
sudo mstflint -d pciconf-0000:41:00.0 ri ./cx3-backup-$(date +%F).bin
sudo mstflint -i ./cx3-backup-$(date +%F).bin query    # sanity-check the dump
```

Keep this file. If a future flash goes wrong, you can burn it back with
`mstflint ... -i <backup> burn`.

### 5. Download the matching firmware

NVIDIA's CX-3 firmware is hosted at
<https://network.nvidia.com/support/firmware/connectx3en/>. Pick the file for
your exact PSID (e.g. `MT_1080120023` → `fw-ConnectX3-rel-X_Y_ZZZZ-MCX312A-XCB_A2-A6-FlexBoot-V.V.VVV.bin.zip`).
Unzip, then:

```
mstflint -i fw-ConnectX3-rel-...bin query
```

Confirm the image's PSID matches the card's PSID **exactly**.

### 6. Burn

```
sudo mstflint -d pciconf-0000:41:00.0 -i fw-ConnectX3-rel-...bin --use_image_rom -y burn
```

`--use_image_rom` replaces the on-flash PXE/FlexBoot with the one in the image
(default behaviour is to preserve the existing ROM). Drop that flag if you
want to keep the old ROM.

### 7. Verify

```
sudo mstflint -d pciconf-0000:41:00.0 verify
sudo mstflint -d pciconf-0000:41:00.0 query
```

Until activation, `query` will show two lines:

```
FW Version:          <new>       # on flash
FW Version(Running): <old>       # in card RAM
```

### 8. Activate

Either reboot, or run the hot-reset script:

```
sudo ./scripts/activate.sh 0000:41:00.0
```

After activation, `FW Version(Running)` disappears from the `query` output —
flash and running versions match.

**Bond-safety note.** If the card is an active member of a bond carrying your
only path to the machine, either wait for a maintenance window or make sure
another slave is up and carrying traffic before running the reset.

---

## Building from source

If you're on a different distro/arch, or just want fresh binaries:

```
./build.sh
ls dist/
# mstflint_4.35.0-1_amd64.deb
# mstflint-dkms_4.35.0-1_all.deb
```

Requires `autoconf automake libtool dh-dkms debhelper libexpat1-dev libibmad-dev libibverbs-dev liblzma-dev libssl-dev zlib1g-dev pkg-config bzip2 dpkg-dev`.

---

## Why not the distro `mstflint`?

Ubuntu 24.04's `mstflint` 4.33.0 (and the NVIDIA `mft` 4.33.0.3004 from their
local driver repo) **segfault on ConnectX-3** during `query` and `burn`.

Root cause: `mtcr_ul/mtcr_ul_com.c` hard-codes `MTCR_MAP_SIZE = 0x4000000`
(64 MiB) and insists the PCI BAR be exactly that size. ConnectX-3's BAR0 is
1 MiB, so the `mmap` call returns `EINVAL` and later code dereferences
through the failed mapping.

Workarounds:
1. **Use upstream mstflint ≥ 4.35.0 with `pciconf-<BDF>` device syntax.** That
   forces the config-cycle access path (via the `mstflint_access` kernel
   module) instead of mmap. This repo packages that.
2. Patch `MTCR_MAP_SIZE` down to `0x100000` for CX-3 — haven't tried, would
   need a compile-time switch so it doesn't break newer cards.

There's also `mstfwreset` — NVIDIA dropped CX-3 support from it in recent
releases (`-E- Unsupported Device: ... (ConnectX3)`). For activation, use
the manual unbind / PCI reset / rebind flow in `scripts/activate.sh`.

### Filing this upstream

The bug is worth reporting to Ubuntu / Debian:

- Ubuntu: <https://bugs.launchpad.net/ubuntu/+source/mstflint>
- Debian: <https://bugs.debian.org/cgi-bin/pkgreport.cgi?src=mstflint>

Reproducer: install `mstflint` 4.33.0 on a host with a ConnectX-3 card, run
`mstflint -d <BDF> query`. Segfaults reliably with `error 4` (read page
fault) at the mmap return path.

---

## License

Documentation and scripts: MIT. Rebuilt `.deb`s contain upstream mstflint
which is BSD-3-Clause — see
<https://github.com/Mellanox/mstflint/blob/master/LICENSE>.
