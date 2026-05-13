# cascade-bootstrap

**Public, infra-only mirror of the MIG-001 deployment scripts** for the Cascade fleet. Used to bootstrap a fresh Beelink SER10 (Pattaya-1) from an empty Win11 install to a full Cascade peer with WSL2, Tailscale, Claude Code, and the cascade-browser MCP stack.

Sibling repos:
- **cascade-state** (private) — current state, nodes, handoffs, ADRs. Cloned by SER10 _after_ T7 once the SSH key is registered on GitHub.
- **cascade-browser** (public) — the MCP Chrome bridge itself. Cloned by SER10 at T7.

## One-shot bootstrap

PowerShell **as Administrator** on a fresh SER10:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
iwr -UseBasicParsing https://raw.githubusercontent.com/krom00070007-beep/cascade-bootstrap/main/scripts/migration/00-bootstrap.ps1 -OutFile $env:TEMP\bootstrap.ps1
& $env:TEMP\bootstrap.ps1
```

That downloads the repo ZIP into `C:\Cascade\state\` and hands off to `01-windows-preflight.ps1`. From there follow `scripts/migration/README.md` for the rest of the runbook (T2..T18, estimated ~60-90 minutes).

## Offline fallback

If the SER10 has no internet on first boot, use `ser10-starter-kit.tar.gz` (distributed via Telegram Saved Messages). It carries `00-bootstrap.ps1` + the first three PowerShell scripts + this README, enough to get through T2 + T3 + T6 (Tailscale up). After Tailscale connects, internet is reachable and the rest can pull from this repo via the one-liner above.

## What's NOT in this repo

- Any Bearer tokens (those are generated per-machine, stored at `~/.cascade-browser/bearer.txt` chmod 0600)
- SSH private keys (generated per-machine at T4)
- State files (live in private `cascade-state`)
- Handoff documents

## Layout

```
scripts/migration/
├── 00-bootstrap.ps1                 # this entry point
├── 01-windows-preflight.ps1         # T2 — WSL feature + Tailscale + Git
├── 02-wsl-install.ps1               # T3 — Ubuntu-24.04
├── 03-wsl-base.sh                   # T4 — apt + ssh-keygen + ~/.ssh/config
├── 04-claude-code.sh                # T5 — Claude Code via curl install.sh
├── 05-tailscale-join.ps1            # T6 — tailscale up (--ssh=false!)
├── 06-repos-clone.sh                # T7 — git clone cascade-state + cascade-browser
├── 07-cascade-browser-setup.sh      # T8 — venv + pytest + bearer.txt
├── cascade-browser.service          # systemd unit
├── 08-systemd-install.sh            # T9 — enable + start service
├── 09-funnel-setup.md               # T10 — allowed_hosts patch + tailscale funnel
├── 10-ssh-distribute.sh             # T11 — ssh-copy-id to 5 nodes + MSI
├── 11-state-init.sh                 # T12 — manual edit templates
├── 12-ollama-prep.sh                # T16 — Ollama install (no 70B until T15)
├── 13-validate.sh                   # T17 — 14 E2E checks
└── README.md                        # full runbook + safety rules

docs/migration/
├── chrome-extension-ser10.md        # T13 — load unpacked extension
├── nvme-upgrade.md                  # T14 — WD SN7100 4TB swap (ETA 2026-05-21)
└── ram-upgrade.md                   # T15 — Crucial 96GB swap (ETA 2026-05-28)
```

## Safety rules baked into the scripts

- `--ssh=false` for Tailscale always (org-wide rule)
- `gl-mt6000-1`, `gl-mt6000 Thai`, `glkvm`, `beget-*` never appear in distribution targets
- Bearer tokens never copied between machines — each generates its own
- Claude Code installed via `curl claude.ai/install.sh`, never npm (binary breaks on WSL2)
- Hardware-swap scripts (NVMe / RAM) marked DO NOT EXECUTE until physical arrival
- Ollama 70 B-class models gated on T15 RAM upgrade (>32 GB system)

See `scripts/migration/README.md` for the full runbook with stop conditions and operator timings.
