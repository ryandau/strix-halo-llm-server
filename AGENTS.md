# Operating rules for an AI agent on this project

You are driving a remote Linux inference server over SSH from the user's workstation. The user is not sitting at the box. These rules exist because each one was learned the hard way.

## Connecting

- The box is `<user>@<box-ip>`. The user gives you the values. Use key auth only: `ssh -o BatchMode=yes <user>@<box-ip>`. If that fails, stop and point the user at [docs/ready-state.md](docs/ready-state.md) step 5.
- Privileged commands use `sudo -n`. If `sudo -n true` fails, stop and point the user at ready-state step 4. Do not try to pipe a password.
- Prefer one SSH call per logical step with clear `===` section headers in the output. Avoid `cd` in compound commands and use absolute paths.

## Safety on the box

- Never run `pkill -f` or `pgrep -f` with a pattern that could match your own SSH command line. It will kill your session mid-script. Match on `pgrep -x <binary>` and inspect `/proc/<pid>/cmdline` instead.
- Never touch the interface that carries the default route (`ip route show default`). No `ip link set down`, no regulatory-domain changes, no driver reloads. If the box is Wi-Fi-only, losing that link means someone has to walk over and press the power button.
- Any job that may outlive an SSH session (model download, benchmark, long apt run) runs inside a named `tmux` session, logging to a file, and writes a `DONE_EXIT=<code>` marker line to that log on exit. Poll the marker. Never assume silence is success.
- Never delete a model that is currently serving until its replacement has passed the acceptance checks in the guide. Download new models into a separate directory.
- Before changing a running service's unit file, stage the new file in the home directory, then install it. Keep the current ExecStart line in your notes so you can roll back.
- Do not upgrade the kernel or reboot unless the guide's phase calls for it or the user asks. If a reboot is needed, say so and let the user choose the moment. A restart of the model server drops the prompt cache, so ask before restarting while the user is mid-task.
- Leave the box tidy: remove tarballs, download logs, scratch scripts, `/tmp` test files and staging unit files before you report done.

## Verification

- Every phase in the guides ends with an acceptance check. Run it, show the output, and do not proceed on failure.
- After a service (re)start, wait for `curl localhost:8080/health` to return `ok` rather than sleeping a fixed time. Then confirm VRAM use with `cat /sys/class/drm/card*/device/mem_info_vram_used`.
- `/health` returning `ok` does not prove the GPU is working. After a `vk::Queue::submit: ErrorDeviceLost` the server stays up and healthy while every request fails. Check `journalctl -u qwen38 -b | grep -c ErrorDeviceLost` when something looks wrong.
- Verify every downloaded file's size against the Hugging Face tree API before using it.
- Speed claims come from `journalctl -u qwen38 | grep print_timing`, not from wall-clock guesses. Compare tok/s only at matching context depth, because generation at 200 tokens of context and at 20K are different numbers.

## Diagnosing "it's slow"

Slowness on this platform is almost always prompt processing, not generation. Check the `prompt eval time` lines in the journal first. A 20K-token prompt legitimately takes about 80 seconds before the first token. If every turn is slow even for short messages, read `n_tokens` on the `stop processing` lines: past about 85K the platform has hit its cliff and the session needs to be compacted or restarted. See "What to expect" in the build guide.

## Workstation side

You may edit `~/.config/kilo/kilo.jsonc` on the workstation. Back up the existing file first and use the template in [client/](client/). Never remove the `interleaved` block from the model entry. It carries the model's reasoning between turns, and without it the model gets visibly dumber.

## Reporting

Finish every run with the report table from the guide's final phase: model, quant, llama.cpp build, context, generation tok/s at short and 20K context, prompt tok/s at 20K, VRAM used, disk free, kernel parameter and watchdog status, and anything you left undone with the reason.
