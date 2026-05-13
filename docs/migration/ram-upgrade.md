# MIG-001 T15 — RAM upgrade (Crucial 96 GB DDR5 SODIMM kit, ETA 2026-05-28)

**DO NOT execute until the kit physically arrives.** Stock 32 GB (2×16 GB DDR5-5600) gets replaced with Crucial **CT2K48G56C46S5** (2×48 GB DDR5-5600 CL46 SODIMM 1.1 V).

Order Amazon US №480, ~$1150 incl. shipping.

## Prerequisites

- SER10 functional and validated via T17 (`13-validate.sh`).
- Optional but recommended: NVMe T14 done — the bigger swap helps if 96 GB feels tight later.
- ESD-grounded workspace.

## Steps

### 1. Hardware swap

1. Shutdown Windows (full shutdown, not Fast Startup): `shutdown /s /f /t 0`
2. Unplug power, hold power button 10s.
3. Open the bottom panel.
4. Locate the two SODIMM slots (under the M.2 area, behind a metal shield on most Beelink SER models — service manual: https://www.bee-link.com/support/ser10).
5. Release the side clips on each stock 16 GB module — they pop up at ~30°.
6. Pull both modules out, ESD-bag them (keep as warranty backup / for an emergency revert).
7. Insert Crucial 48 GB modules one at a time: 30° insert, then push flat until both clips click.
8. Close the chassis.

### 2. BIOS check

1. Power on. Tap **Del** or **F2** repeatedly to enter BIOS.
2. Find the RAM panel — should report **96 GB** at **5600 MT/s** with the CL46 timings. If it reports 4800 MT/s instead, enable EXPO/XMP profile and reboot.
3. Save & exit.

### 3. Windows verify

1. Boot Windows; `Task Manager` → **Performance** → **Memory** — should show **96 GB**.
2. `wmic memorychip get capacity,speed,partnumber` for sanity:
   ```
   PartNumber: CT2K48G56C46S5
   Speed: 5600
   Capacity: 51539607552  (each — 2 modules = 96 GB total)
   ```

### 4. WSL2 sizing

Edit `%USERPROFILE%\.wslconfig` (create if absent):

```ini
[wsl2]
memory=80GB
processors=16
swap=16GB
swapfile=D:\wsl-swap.vhdx       # only if T14 NVMe done — else default
```

Apply:

```powershell
wsl --shutdown
```

Wait 10 seconds, then reopen WSL and confirm:

```bash
free -h
# Should show ~80 GB total. (Linux kernel reserves a few GB for I/O caches.)
```

### 5. Now you can run the big LLMs

Now T16-style commands become live:

```bash
ollama pull qwen2.5-coder:32b              # ~20 GB; 15-25 tok/s on this hardware
ollama pull llama3.3:70b-instruct-q4_K_M   # ~45 GB; 4-7 tok/s
ollama pull deepseek-r1:70b                # ~45 GB; reasoning model
```

Pull one at a time; each takes minutes/hours depending on connection. After pull, smoke-test:

```bash
echo "say hi" | ollama run qwen2.5-coder:32b
```

### 6. Update state

```bash
cd ~/projects/cascade-state
# Edit state/nodes.md → ser10-tha-1 RAM: "96 GB Crucial CT2K48G56C46S5 (since 2026-05-28)"
# Edit state/current.md → "Recently closed" with "T15: SER10 RAM 32→96 GB"
git add state/nodes.md state/current.md
git commit -m "MIG-001 T15: SER10 RAM 32→96 GB; LAI-001 unblocked"
git push origin main
```

## Stop conditions (escalate)

- **BIOS reports < 96 GB** — re-seat both modules; check if board needs MEMOK / re-train cycle; if still bad, RMA Crucial
- **System POSTs but fails at 5600 MT/s** — try JEDEC 4800 fallback (single-rank fallback). 4800 is OK, just slower. EXPO support is platform-dependent on the AMD HX 470.
- **Random crashes in Windows after upgrade** — run `mdsched.exe` (Windows memory diagnostic). 96 GB is at the high end of stock support — verify with the Memory Test Tool first before trusting it under load.

## Why this matters (LAI-001 dependency)

The LAI-001 track (local LLMs on SER10) is gated on this upgrade. With 32 GB you're stuck at small 1.5-7 B models; with 96 GB you unlock 70 B-class with quantization — that's the big jump in capability.
