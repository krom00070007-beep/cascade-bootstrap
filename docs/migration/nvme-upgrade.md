# MIG-001 T14 — NVMe upgrade (WD_BLACK SN7100 4 TB, ETA 2026-05-21)

**DO NOT execute until the drive physically arrives.** Stock 1 TB NVMe stays as the OS/system drive; the new 4 TB goes in M.2 slot 2 as a data drive (mounted `D:` in Windows, `/mnt/big` in WSL2).

## Prerequisites

- SER10 functional and validated via T17 (`13-validate.sh`).
- Power off, ESD-grounded workspace.
- Drive: WD_BLACK SN7100 4 TB NVMe PCIe Gen5 M.2 2280.

## Steps

### 1. Hardware install

1. Shutdown Windows (full shutdown, not Fast Startup): `shutdown /s /f /t 0`
2. Unplug power cable, hold power button 10s to discharge.
3. Open the bottom panel of the Beelink chassis (4 screws, then slide).
4. Locate M.2 slot 2 (the empty one — slot 1 has the stock 1 TB).
5. Insert SN7100 at ~30° angle, push in fully, lay flat, secure with the M.2 screw (use the standoff that matches 2280 length).
6. Close the chassis.

### 2. First boot — verify Windows sees it

1. Power on; boot into Windows.
2. Open **Disk Management** (`diskmgmt.msc`).
3. New disk should appear as `Disk 1` (Disk 0 = stock 1 TB), labelled `Unallocated`.
4. Right-click → **Initialize Disk** (choose GPT).
5. Right-click the unallocated space → **New Simple Volume** → 4 TB, NTFS, label `Cascade-Big`, drive letter `D:`.

### 3. Mount in WSL2

Inside WSL Ubuntu-24.04:

```bash
sudo mkdir -p /mnt/big
sudo mount -t drvfs D: /mnt/big
# Verify
df -h /mnt/big
ls /mnt/big
```

To make persistent across WSL restarts:

```bash
echo 'D: /mnt/big drvfs metadata,uid=1000,gid=1000,umask=0022,fmask=0011 0 0' | sudo tee -a /etc/fstab
sudo mount -a
```

### 4. Move heavy stores to `/mnt/big`

Suggested layout (do this for whichever applies — not all may exist yet):

```bash
# Docker (if you've installed Docker Desktop or rootless Docker in WSL)
# Edit /etc/docker/daemon.json:
#   { "data-root": "/mnt/big/docker" }
# Then: sudo systemctl restart docker

# Ollama models (after T15 RAM upgrade, you'll pull 70 B models — they're 40+ GB each)
mkdir -p /mnt/big/ollama
sudo systemctl stop ollama
# move existing
if [ -d ~/.ollama/models ]; then
    rsync -av ~/.ollama/models/ /mnt/big/ollama/models/
    rm -rf ~/.ollama/models
fi
ln -sf /mnt/big/ollama/models ~/.ollama/models
sudo systemctl start ollama

# restic cache (cascade NAS backup staging)
mkdir -p /mnt/big/restic-cache
export RESTIC_CACHE_DIR=/mnt/big/restic-cache
# Add to ~/.bashrc to persist

# WSL2 swap (helpful with future 70B loads)
# Edit %USERPROFILE%\.wslconfig on Windows:
#   [wsl2]
#   swap=16GB
#   swapfile=D:\\wsl-swap.vhdx
# Then: wsl --shutdown && wsl
```

### 5. Verify post-move

```bash
df -h /mnt/big          # should show ~4 TB available
ls -la ~/.ollama/models # should be a symlink → /mnt/big/ollama/models
ollama list             # models still listed
```

### 6. Update state

After successful mount + migration:

```bash
cd ~/projects/cascade-state
# Edit state/nodes.md → ser10-tha-1 entry: add "Storage: 1 TB NVMe + 4 TB SN7100 (D:)"
# Edit state/current.md → "Recently closed" with "T14: NVMe upgrade done 2026-05-21"
git add state/nodes.md state/current.md
git commit -m "MIG-001 T14: SER10 NVMe expansion (+4 TB SN7100)"
git push origin main
```

## Stop conditions (escalate)

- **BIOS doesn't detect the drive** — re-seat M.2 connector; check BIOS PCIe lane allocation (some boards disable slot 2 if slot 1 is at x4)
- **Disk Management shows "Not Initialized" errors** — try different SATA cable / re-seat; if still bad, RMA WD warranty
- **WSL2 can't mount D:** — confirm with `wsl --shutdown` then reopen; check `.wslconfig`; verify Win-side `D:` is accessible from PowerShell

## Notes

- Keep stock 1 TB clean — Windows + WSL system drive only. Don't symlink user data away from it; OS expects that path.
- The 4 TB drive is the "expand zone": Docker, Ollama, restic, video, scratch.
- After T15 (RAM upgrade), the 4 TB makes a much bigger swap area possible if you need it.
