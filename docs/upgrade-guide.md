# Upgrade guide: agent runbook

For a box that already runs a llama.cpp server from an earlier version of this repo (v3.0 served MiniMax M2.7 UD-Q3_K_S at 32K context on Continue; v2.0 served MiniMax M2.5) or any similar setup. The user hands you `<user>@<box-ip>`. Follow [AGENTS.md](../AGENTS.md) throughout. Never delete the serving model until the new one passes Phase 4.

The target state is the one described in [build-guide.md](build-guide.md); refer to it for flag explanations, expectations and troubleshooting.

## Why upgrade

The v3.0 model was a 230B mixture-of-experts squeezed to 3.3 bits per weight because that was what fit in the carve-out. That architecture degrades badly under quantisation, and users saw it as weak coding and malformed tool calls. Qwen3.8-27B at Q6_K is close to lossless, scores higher on independent indices than full-precision M2.7, needs 28 GB instead of 100 GB, and runs with 128K of context. It generates somewhat more slowly (17 against 21 tok/s at 20K context).

## Phase 0: Inventory

Collect and show, in one SSH call:

```bash
lsb_release -ds; uname -r; cat /proc/cmdline; free -g | head -2; df -h / | tail -1
systemctl list-units --type=service --no-pager | grep -iE "llama|minimax|qwen|ollama"
cat /etc/systemd/system/minimax.service 2>/dev/null
ls ~/llama; for b in ~/llama/llama-*/llama-server; do "$b" --version 2>&1 | head -1; done
du -sh ~/models/* 2>/dev/null
ollama list 2>/dev/null
ip -br addr | grep -v "^lo"; ip route show default
sudo -n true && echo SUDO_OK
```

Also on the workstation: `cat ~/.continue/config.yaml` and `cat ~/.config/kilo/kilo.jsonc` if they exist, and whether the Kilo Code extension is installed.

**Acceptance:** you can name the current model, quant, context, llama.cpp build, free disk and the uplink interface. Free disk must exceed 30 GB. `SUDO_OK` must print; otherwise stop and send the user to [ready-state.md](ready-state.md) step 4.

## Phase 1: llama.cpp

The v3.0 build (b9969) predates the MTP and flag changes this version depends on. Install b11057 or newer into a new directory per build-guide Phase 2. Leave the old directory; the old unit still uses it until the swap succeeds.

## Phase 2: Download alongside

Build-guide Phase 3, into `~/models/qwen38-27b`. The old model keeps serving throughout. At 23 GB this takes about 40 minutes at 10 MB/s.

**Acceptance:** both files present and size-verified; old service still `active`.

## Phase 3: Unit, watchdog, platform fixes

Write the new unit as `qwen38.service` per build-guide Phase 5a, with one addition in `[Unit]` so the two servers, which share port 8080 and the GPU, can never run together:

```
Conflicts=minimax.service
```

Install it but do not start it yet:

```bash
sudo -n install -m 644 ~/qwen38.service /etc/systemd/system/ && rm ~/qwen38.service && sudo -n systemctl daemon-reload
```

Install the watchdog (5b) and the platform fixes (5c: GRUB parameter and, on Wi-Fi boxes, the power-save rule). The reboot in 5c can wait until after the swap; do the swap first so the user can test.

## Phase 4: Swap and verify

Save the old unit's ExecStart line in your notes, then:

```bash
sudo -n systemctl start qwen38          # Conflicts= stops minimax automatically
until curl -s -m 3 localhost:8080/health | grep -q ok; do sleep 5; done
systemctl is-active qwen38 minimax
awk '{printf "vram %.1f GB\n", $1/1e9}' /sys/class/drm/card*/device/mem_info_vram_used | head -1
```

Run the build-guide Phase 4 checks: coding prompt with `max_tokens` 6000 and executed asserts, the tool-call round trip, and the 20K benchmark.

**Acceptance:** `qwen38` active and `minimax` inactive; VRAM about 28 GB; correct code; tool call round trip; generation at or above 16 tok/s at 20K; prompt processing at or above 240 tok/s.

**Rollback:** `sudo -n systemctl start minimax` (which stops qwen38). The old model is still on disk and its unit unchanged.

Once the checks pass, make the new server the boot default:

```bash
sudo -n systemctl disable minimax && sudo -n systemctl enable qwen38 qwen38-watch.timer
```

Then tell the user a reboot is pending for the kernel parameter and let them choose the moment. Verify per 5c afterwards.

## Phase 5: Workstation

Build-guide Phase 7. Two things specific to an upgrade:

- The old Continue entry named `MiniMax-M2.7` still points at port 8080. llama-server ignores the model name, so that entry now silently drives Qwen with M2.7's 32K limit and sampling. Replace it rather than leaving it in the picker.
- If the user is moving from Continue to Kilo Code, the Ollama sidecar has nothing left to serve. List its models and ask before removing them (Phase 6).

## Phase 6: Clean up

Only after Phase 4 passed and the user has used the new model for real work and said they are happy:

- `~/models/minimax27` (about 88 GB) and the old llama.cpp directory.
- `minimax.service` (`sudo -n systemctl disable minimax; sudo -n rm /etc/systemd/system/minimax.service; sudo -n systemctl daemon-reload`).
- Ollama and its models if nothing uses them (`sudo -n systemctl disable --now ollama`).
- Staging copies in the home directory, scratch scripts, `/tmp` test files.
- `sudo -n apt-get autoremove --purge -y && sudo -n apt-get clean`.

Ask before deleting the old model if the user hasn't confirmed they're happy with the new one.

## Phase 7: Report

Produce the build-guide Phase 8 table, plus a line for what was upgraded from (old model, quant, context, build) and a list of anything left for the user.
