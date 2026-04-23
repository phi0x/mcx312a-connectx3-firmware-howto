# Upstream bug: mstflint 4.33.0 segfaults on ConnectX-3

File at: <https://bugs.launchpad.net/ubuntu/+source/mstflint/+filebug>

Prefilled URL: see `launchpad-filebug-url.txt` in this directory (long URL).

---

## Title

```
mstflint 4.33.0 segfaults on ConnectX-3 during query/burn
```

## Body

mstflint 4.33.0+1-1 as packaged in Ubuntu 24.04 (noble) segfaults on
ConnectX-3 (`15b3:1003`, MT27500 family) devices during routine commands
including `query` and `burn`, making firmware management with the packaged
tool impossible on this generation of card.

### Reproducer

```
$ sudo apt install mstflint
$ mstflint -v
mstflint, mstflint 4.33.0, Git SHA Hash: d431e08
$ sudo mstflint -d 41:00.0 query
Segmentation fault (core dumped)
```

### dmesg

```
mstflint[3916579]: segfault at f0013 ip 00005937b212da5a sp 00007ffee44f0c40 error 4 in mstflint[c0a5a,5937b2082000+c6000] likely on CPU 33
Code: 6c 3d ff ff ff 03 77 78 49 89 d1 48 8b 97 b0 01 00 00 41 89 f0 48 89 f9 8b 72 08 85 f6 75 29 48 8b 41 60 41 c1 e8 02 8b 49 68 <42> 8b 14 80 85 c9 89 d0 0f c8 0f 45 c2 41 89 01 b8 04 00 00 00 c9
```

Consistently reproducible across `query`, `--qq query`, and `hw query`.

### Root cause

In `mtcr_ul/mtcr_ul_com.c`:

- `MTCR_MAP_SIZE` is hard-coded to `0x4000000` (64 MiB) at line 53.
- `mtcr_sysfs_get_offset()` (line 551) requires the PCI BAR resource to be
  exactly `MTCR_MAP_SIZE - 1` bytes long (line 568):
  `if ((cnt != 3) || (end != start + MTCR_MAP_SIZE - 1))` → `error`.
- `mtcr_mmap()` (line 613) then unconditionally calls
  `mmap(NULL, MTCR_MAP_SIZE, …)` at line 631.

ConnectX-3 BAR0 is 1 MiB, so `mmap(64 MiB)` returns `EINVAL`. In 4.33.0 the
error-handling path dereferences through the failed mapping (or uninitialised
state derived from it) and segfaults. Confirmed via strace:

```
openat("/sys/bus/pci/devices/0000:41:00.0/resource0", O_RDWR|O_SYNC) = 4
mmap(NULL, 67108864, PROT_READ|PROT_WRITE, MAP_SHARED, 4, 0) = -1 EINVAL (Invalid argument)
```

### Upstream status

Current upstream (mstflint 4.35.0, github.com/Mellanox/mstflint HEAD) fails
gracefully with a diagnostic error instead of segfaulting:

```
FATAL - crspace read (0xf0014) failed: Invalid argument
-E- Cannot open Device: 41:00.0. Invalid argument. MFE_GENERAL_ERROR
```

In 4.35.0 ConnectX-3 can be fully managed via the `pciconf-<BDF>` device
syntax, which forces the PCI-config-cycle access path via the
`mstflint_access` DKMS kernel module (shipped alongside as the
`mstflint-dkms` package) and bypasses the broken mmap path. The underlying
mmap logic is still incorrect for 1-MiB BARs, but the user-visible crash is
gone.

### Requested fix

Update the `mstflint` package in Ubuntu to 4.35.0 or newer. Also consider
adding `mstflint-dkms` (also produced by upstream `debian/` packaging) so
ConnectX-3 users can access the config-cycle path out of the box.

### Workaround for affected users

Rebuilt 4.35.0 `.deb`s for Ubuntu 24.04 are available at:
<https://github.com/phi0x/mcx312a-connectx3-firmware-howto/releases>

### System info

- **Distro**: Ubuntu 24.04 (noble)
- **Package**: mstflint 4.33.0+1-1
- **Kernel**: 6.17.0-22-generic
- **Arch**: x86_64
- **Hardware**: Mellanox ConnectX-3, `MCX312A-XCBT` (`15b3:1003`),
  subsystem `15b3:0049`, BAR0 1 MiB
