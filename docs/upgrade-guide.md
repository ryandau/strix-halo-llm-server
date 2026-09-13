# Upgrade guide: agent runbook

For a box that already runs a llama.cpp server from an earlier version of this repo (v2.0 served MiniMax M2.5 UD-Q3_K_XL at 16K context) or any similar setup. The user hands you `<user>@<box-ip>`. Follow [AGENTS.md](../AGENTS.md) throughout. Never delete the serving model until the new one passes Phase 4.

The target state is the one described in [build-guide.md](build-guide.md); refer to it for flag explanations, expectations and troubleshooting.

## Phase 0: Inventory

Collect and show, in one SSH call:

```bash
lsb_release -ds; uname -r; free -g | head -2; df -h / | tail -1
systemctl list-units --type=service --no-pager | grep -iE "llama|minimax|ollama"
cat /etc/systemd/system/minimax.service 2>/dev/null
ls ~/llama; for b in ~/llama/llama-*/llama-server; do "$b" --version 2>&1 | head -1; done
du -sh ~/models/* ~/models/*/.cache 2>/dev/null
ollama list 2>/dev/null
cat /sys/class/drm/card*/device/mem_info_vram_total
sudo -n true && echo SUDO_OK
```

Also on the workstation: `cat ~/.continue/config.yaml` if it exists.

**Acceptance:** you can name the current model, quant, context, llama.cpp build, free disk and any stale `.cache` directories. Free disk must exceed 110 GB; if not, delete stale `.cache` directories first (never the model). `SUDO_OK` must print; otherwise stop and send the user to [ready-state.md](ready-state.md) step 4.

## Phase 1: Decide the target

The target is MiniMax M2.7 UD-Q3_K_S unless the user names something else. Before downloading, check the Unsloth GGUF tree for anything newer that fits: total file size at or below 95 GB and about 10B active parameters or fewer. If something newer qualifies, tell the user and let them choose; do not switch silently.

If the box already serves the target model with the target flags, say so and skip to Phase 5.

## Phase 2: Download alongside

Same as build-guide Phase 3, into a new directory (`~/models/minimax27` for M2.7). The old model keeps serving throughout. Verify every shard's size and SHA-256 against the Hugging Face tree API. Delete the new directory's `.cache` when done.

**Acceptance:** all shards present and hash-verified; old service still `active`.

## Phase 3: llama.cpp

The build in place works if it is b9969 or newer. Only replace it if the new model fails to load with an architecture error; then follow build-guide Phase 2 into a new directory and leave the old one until the swap succeeds.

## Phase 4: Swap and verify

1. Write the new unit to `~/minimax27.service` with the full flag set from build-guide Phase 5, keeping the same unit name `minimax` and port 8080 so clients need no change.
2. Save the old unit's ExecStart line in your notes.
3. `sudo -n install -m 644 ~/minimax27.service /etc/systemd/system/minimax.service && sudo -n systemctl daemon-reload && sudo -n systemctl restart minimax`
4. Poll `curl -s localhost:8080/health` until `ok`.
5. Run the build-guide Phase 4 checks: coding prompt with `max_tokens` 3000 and executed asserts, then the prompt-processing benchmark at two sizes.

**Acceptance:** health ok, VRAM about 100 GB, generation at or above 28 tok/s at short context, prompt processing at or above 220 tok/s on a 14K prompt, correct code from the test prompt.

**Rollback:** if any check fails, reinstall the old ExecStart line, `daemon-reload`, `restart`, confirm health, and report what failed. The old model is still on disk.

## Phase 5: Sidecar and workstation

Follow build-guide Phase 6 (Ollama with the two small models) if not already present, and Phase 7 for Continue. On an upgraded box check for leftover Ollama models that Continue no longer references and list them for the user; remove only with their say-so.

## Phase 6: Clean up

Only after Phase 4 passed and the user has used the new model:

- Old model directory and its `.cache`.
- Old llama.cpp directory if replaced, and any release tarballs.
- `~/minimax27.service` staging copy, scratch scripts, `/tmp` test files.
- `sudo -n apt-get autoremove --purge -y` and `sudo -n apt-get clean`.

Ask before deleting the old model if the user hasn't confirmed they're happy with the new one.

## Phase 7: Report

Produce the build-guide Phase 8 table, plus a line for what was upgraded from (old model, quant, context, flags) and a list of anything left for the user.
