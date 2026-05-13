# MIG-001 — SER10 Pattaya-1 deployment runbook

End-to-end order of operations to bring Beelink SER10 MAX online as the **PRIMARY** Cascade control point. MSI demotes to BACKUP at the end.

Hardware in scope:
- **SER10 stock** (32 GB DDR5 + 1 TB NVMe) — today's target
- **+4 TB NVMe** WD_BLACK SN7100 — ETA 2026-05-21 (T14, deferred)
- **+96 GB RAM** Crucial CT2K48G56C46S5 — ETA 2026-05-28 (T15, deferred)

Pre-flight decisions (already taken via T1):
- Hostname: `ser10-tha-1`
- Win user: `krom0`
- SSH key: **new ed25519** generated on SER10
- Bearer token: **new** (different from MSI's)
- Tailscale account: `krom00070007@gmail.com`

## Order of operations (today's session — stock hardware)

| Step | File | Where to run | Est. time | Notes |
|---|---|---|---|---|
| T2 | `01-windows-preflight.ps1` | Win admin PowerShell | 5-15 min | May trigger reboot if WSL feature was off |
| (reboot if needed) | — | — | 2 min | |
| T3 | `02-wsl-install.ps1` | Win admin PowerShell | 5-10 min | Ubuntu interactive prompt: username=`usersstas` + password |
| T4 | `03-wsl-base.sh` | WSL Ubuntu | 5-10 min | apt deps + SSH keygen + ~/.ssh/config |
| — | (manual) GitHub SSH key registration | github.com/settings/keys | 1 min | Paste pubkey printed at end of T4 |
| T5 | `04-claude-code.sh` | WSL Ubuntu | 2-5 min | Native installer + ld-linux wrapper, NOT npm |
| T6 | `05-tailscale-join.ps1` | Win admin PowerShell | 2 min | Browser OAuth — pick krom00070007@gmail.com |
| T7 | `06-repos-clone.sh` | WSL Ubuntu | 1-2 min | Requires GitHub SSH key from T4 step registered |
| T8 | `07-cascade-browser-setup.sh` | WSL Ubuntu | 3-5 min | venv + pytest 59/59 + new Bearer token |
| T9 | `08-systemd-install.sh` | WSL Ubuntu | 2 min | First run may add systemd=true to /etc/wsl.conf and require `wsl --shutdown` |
| T10 | `09-funnel-setup.md` (manual) | mixed | 5-10 min | Patch `allowed_hosts` in server.py + commit; `tailscale.exe funnel --bg 8767`; HTTPS Certificates + Funnel must be toggled on in admin.tailscale.com |
| T11 | `10-ssh-distribute.sh` | WSL Ubuntu | 3-5 min per node | ssh-copy-id to 5 nodes + special path for MSI |
| T12 | `11-state-init.sh` | WSL Ubuntu | 5 min (manual editing) | Prints templates; you paste into `state/nodes.md` + `state/current.md` |
| T13 | `../docs/migration/chrome-extension-ser10.md` (manual) | Chrome on Win + WSL | 10 min | Load unpacked extension; register Native Host registry key |
| T16 | `12-ollama-prep.sh` | WSL Ubuntu | 5 min | Ollama install + qwen2.5-coder:1.5b smoke test (don't pull 70 B yet) |
| T17 | `13-validate.sh` | WSL Ubuntu | 1 min | 14 checks — must all pass to consider deployment SUCCESS |
| T18 | (manual git commit) | WSL Ubuntu | 1 min | Commit T12 state edits; auto-push to opus via post-commit |

**Total elapsed time: ~60-90 minutes** for stock hardware, mostly waiting on apt/pip/winget downloads.

## Order for the deferred upgrades

When the hardware arrives:

| Date (est.) | Doc | Brief |
|---|---|---|
| 2026-05-21 | `../docs/migration/nvme-upgrade.md` | T14: Insert WD SN7100 4 TB in M.2 slot 2; mount `D:` in Win, `/mnt/big` in WSL; migrate Docker/Ollama/restic |
| 2026-05-28 | `../docs/migration/ram-upgrade.md` | T15: Swap stock 2×16 GB → Crucial 2×48 GB DDR5-5600; `.wslconfig` memory=80GB; unlocks LAI-001 70 B-class models |

## Hard-rule sanity checks

Before any script touches the fleet, confirm in your head:

- [ ] `--ssh=false` in T6 — Tailscale SSH is **forbidden** org-wide
- [ ] T11 `10-ssh-distribute.sh` ALLOWED_NODES does NOT include:
  - gl-mt6000-1, gl-mt6000 Thai, glkvm, beget-cascade-in/out
- [ ] T16 does NOT pull 70 B models on stock 32 GB RAM
- [ ] T14 NVMe + T15 RAM scripts marked as **DO NOT EXECUTE** until physical arrival
- [ ] T5 Claude Code via `curl install.sh`, NOT via npm
- [ ] T8 generates a **new** Bearer token; do NOT copy MSI's

## Stop conditions (escalate)

Reasons to pause, gather logs, and ping rather than auto-continue:

- `wsl --update` doesn't yield kernel 6.6.x — possible BIOS virt off; check VT-x/SVM
- T6 Tailscale OAuth browser doesn't open — manual login at `https://login.tailscale.com/admin/machines`
- T5 Claude Code fails even via ld-linux — diff `file`/`ldd` with MSI's working binary
- T9 systemd unit fails — `journalctl -u cascade-browser -n 100 --no-pager`
- T10 Funnel cert provisioning > 60s — check admin.tailscale.com HTTPS/Funnel toggles
- T10 Funnel returns 421 with valid Bearer — `allowed_hosts` patch missing or service not restarted
- T17 validation has ANY ✗ — do not call deployment complete; resolve before T18

## After T18 (post-deployment)

- Claude.ai → Settings → Connectors → cascade-browser entry: switch URL to `https://ser10-tha-1.tail80c5d4.ts.net/mcp`, paste new Bearer.
- (Optional) keep MSI Connector as a second entry labelled "backup" with its own URL + token.
- MSI doesn't need to be powered off — it remains as a BACKUP peer, can serve the same MCP tools if SER10 is down.
- The `cascade-state-push` symlink (T7 step 7.3) on SER10 means state commits from SER10 mirror to opus automatically — same workflow as MSI used.

## Where the new Bearer token lives

`~/.cascade-browser/bearer.txt` on SER10 (chmod 600). After T8 you should also:

```bash
tg-send-text "cascade-browser SER10 Bearer (issued $(date +%Y-%m-%d)): $(cat ~/.cascade-browser/bearer.txt)"
```

Saved Messages becomes the cross-device handoff for the token.
