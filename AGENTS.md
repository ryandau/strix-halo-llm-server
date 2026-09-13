# Operating rules for an AI agent on this project

You are driving a remote Linux inference server over SSH from the user's workstation. The user is not sitting at the box. These rules exist because each one was learned the hard way.

## Connecting

- The box is `<user>@<box-ip>`; the user gives you the values. Use key auth only: `ssh -o BatchMode=yes <user>@<box-ip>`. If that fails, stop and point the user at [docs/ready-state.md](docs/ready-state.md) step 5.
- Privileged commands use `sudo -n`. If `sudo -n true` fails, stop and point the user at ready-state step 4. Do not try to pipe a password.
- Prefer one SSH call per logical step with clear `===` section headers in the output. Avoid `cd` in compound commands; use absolute paths.

## Safety on the box

- Never run `pkill -f` or `pgrep -f` with a pattern that could match your own SSH command line. It will kill your session mid-script. Match on `pgrep -x <binary>` and inspect `/proc/<pid>/cmdline` instead.
- Any job that may outlive an SSH session (model download, benchmark, long apt run) runs inside a named `tmux` session, logging to a file, and writes a `DONE_EXIT=<code>` marker line to that log on exit. Poll the marker; never assume silence is success.
- Never delete a model that is currently serving until its replacement has passed the acceptance checks in the guide. Download new models into a separate directory.
- Before a service swap, stage the new unit file in the home directory, then install it. Keep the old unit's ExecStart line in your notes for rollback.
- Do not upgrade the kernel or reboot unless the guide's phase calls for it or the user asks. If a reboot is needed, say so and let the user choose the moment.
- Leave the box tidy: remove tarballs, download caches, scratch scripts, `/tmp` test files and unused Ollama models before you report done.

## Verification

- Every phase in the guides ends with an acceptance check. Run it, show the output, and do not proceed on failure.
- After a service (re)start, wait for `curl localhost:8080/health` to return `ok` rather than sleeping a fixed time. Then confirm VRAM use with `cat /sys/class/drm/card*/device/mem_info_vram_used`.
- Verify every downloaded shard against the size and `lfs.oid` SHA-256 from the Hugging Face tree API before using it.
- Speed claims come from `journalctl -u minimax | grep print_timing`, not from wall-clock guesses.

## Diagnosing "it's slow"

Slowness on this platform is almost always prompt processing, not generation. Check the `prompt eval time` lines in the journal first. A 14K-token prompt legitimately takes about 60 seconds before the first token. See "What to expect" in the build guide.

## Workstation side

You may edit `~/.continue/config.yaml` and `~/.continue/.continuerc.json` on the workstation. Back up the existing config first, and use [client/continue.config.yaml](client/continue.config.yaml) as the template.

## Reporting

Finish every run with the report table from the guide's final phase: model, quant, llama.cpp build, context, generation tok/s, prompt tok/s at two sizes, VRAM used, disk free, and anything you left undone with the reason.
