# Build guide: agent runbook

| | |
|---|---|
| **Version** | 4.0 |
| **Last verified** | September 2026 |
| **Applies to** | AMD Ryzen AI Max+ 395 ("Strix Halo") systems with 128 GB unified memory, such as the GMKtec EVO-X2, Framework Desktop, and HP Z2 Mini G1a |
| **Target** | Ubuntu Server 26.04 LTS, llama.cpp b11057 or newer, Qwen3.8-27B UD-Q6_K with MTP speculative decoding, Kilo Code |

This document is written for an AI coding agent to execute over SSH after the human has completed [ready-state.md](ready-state.md). Each phase ends with an acceptance check. Run it, show the output, and stop on failure. Follow the rules in [AGENTS.md](../AGENTS.md) throughout. A human can follow the same steps by hand; nothing here requires an agent.

## Goal

A headless server that boots into a llama.cpp endpoint serving Qwen3.8-27B (dense 27B, 128K context, 17 to 19 tok/s) on port 8080, recovers on its own from the GPU faults this platform produces, and a Kilo Code config on the workstation that uses it. Everything on Vulkan; ROCm is not used.

## Design decisions

- **Vulkan instead of ROCm.** ROCm on gfx1151 has a history of kernel-version pain and out-of-memory failures near the carve-out limit; the RADV driver ships with Ubuntu and works immediately. ROCm wins on prompt processing by 20 to 40 per cent in published tests, Vulkan wins on generation.
- **llama.cpp directly, no wrapper.** One binary, one systemd unit, full control over the flags that matter: KV-cache type, batch sizes, speculative decoding, load mode.
- **Ubuntu Server, stock kernel.** Custom kernels are the main cause of instability on this platform. Two kernel parameters are added; see Phase 5.
- **A dense 27B at Q6, not a 230B MoE at Q3.** The previous version of this repo ran MiniMax M2.7 squeezed to 3.3 bits per weight because that was what fit. MiniMax's architecture (no shared expert) degrades badly under quantisation, and independent measurements put its Q3 quants far from the full model. Qwen3.8-27B at Q6_K is close to lossless, scores higher than full-precision M2.7 on independent indices, needs 28 GB instead of 100 GB, and has room for 128K of context. It generates more slowly (17 against 21 tok/s at 20K context) and the trade is worth it.
- **MTP speculative decoding.** Qwen3.8 ships a multi-token-prediction draft head as a 1.4 GB sidecar. llama.cpp drafts with it and verifies in parallel, which is where the dense model gets its usable speed: about 19 tok/s at short context instead of about 14 without it.

## Phase 0: Preflight

```bash
ssh -o BatchMode=yes <user>@<box-ip> '
echo "=== os"; lsb_release -ds; uname -r
echo "=== sudo"; sudo -n true && echo SUDO_OK
echo "=== disk"; df -h / | tail -1; lsblk -o NAME,SIZE,TYPE | grep -E "disk|lvm"
echo "=== mem"; free -g | head -2
echo "=== gpu"; lspci | grep -iE "vga|display"; cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null
echo "=== net"; ip -br addr | grep -v "^lo"; ip route show default; curl -s -m 10 -o /dev/null -w "%{speed_download} B/s\n" https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-Q6_K.gguf'
```

**Acceptance:** Ubuntu 26.04; `SUDO_OK`; a line naming an AMD display controller; a VRAM total of at least 32 GB; a default route. Note which interface carries the default route (wired `eno1` or Wi-Fi `wlp*`); Phase 5 needs it. Note the download speed: at 10 MB/s the model takes about 40 minutes. Tell the user the estimate before starting Phase 3.

## Phase 1: OS preparation

The installer allocates only about 100 GB. Expand the root filesystem online, then install the GPU stack.

```bash
sudo -n lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv && sudo -n resize2fs /dev/ubuntu-vg/ubuntu-lv
sudo -n apt-get update && sudo -n DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo -n apt-get install -y mesa-vulkan-drivers vulkan-tools radeontop libgomp1 tmux python3-pip curl iw
sudo -n usermod -aG render,video <user>
```

If `apt upgrade` installs a new kernel, `/var/run/reboot-required` appears. Phase 5 reboots anyway, so carry on. Group membership needs a fresh login; the next SSH call gets it automatically.

```bash
vulkaninfo --summary 2>/dev/null | grep -i devicename
df -h / | tail -1
```

**Acceptance:** `deviceName = Radeon 8060S Graphics (RADV STRIX_HALO)` (an extra `llvmpipe` line is normal headless); root filesystem now spans the disk. A `DISPLAY` warning from vulkaninfo is normal.

## Phase 2: llama.cpp

Use the newest Ubuntu x64 Vulkan release from [github.com/ggml-org/llama.cpp/releases](https://github.com/ggml-org/llama.cpp/releases); b11057 is the verified minimum.

```bash
B=<build>   # e.g. b11057
mkdir -p ~/llama && cd ~/llama
curl -LO https://github.com/ggml-org/llama.cpp/releases/download/$B/llama-$B-bin-ubuntu-vulkan-x64.tar.gz
mkdir -p llama-$B && tar -xzf llama-$B-bin-ubuntu-vulkan-x64.tar.gz -C llama-$B --strip-components=1 && rm llama-$B-bin-ubuntu-vulkan-x64.tar.gz
~/llama/llama-$B/llama-server --version
~/llama/llama-$B/llama-server --help | grep -cE -- "--spec-type|--load-mode|--device "
```

**Acceptance:** `--version` prints the build number; the grep prints `3` (these flags changed names in mid-2026 and the unit file below depends on the new ones). A missing shared library means an apt package; `libgomp.so.1` is `libgomp1`.

## Phase 3: Model download

Two files, about 23 GB total: the model and its MTP draft head. Plain `curl` with resume; no Hugging Face client needed.

```bash
mkdir -p ~/models/qwen38-27b && cd ~/models/qwen38-27b
B=https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main
tmux new-session -d -s dl "curl -L -C - --retry 20 --retry-delay 10 -sS -o Qwen3.8-27B-UD-Q6_K.gguf $B/Qwen3.8-27B-UD-Q6_K.gguf && curl -L -C - --retry 20 -sS -o mtp-Qwen3.8-27B-Q4_0.gguf $B/MTP/mtp-Qwen3.8-27B-Q4_0.gguf; echo DONE_EXIT=\$? >> download.log"
```

Monitoring, every 5 minutes or on request:

```bash
grep DONE_EXIT ~/models/qwen38-27b/download.log || echo running
ls -l ~/models/qwen38-27b/*.gguf
```

Verification:

```bash
curl -s https://huggingface.co/api/models/unsloth/Qwen3.8-27B-GGUF/tree/main | python3 -c 'import sys,json;[print(f["size"],f["path"]) for f in json.load(sys.stdin) if "UD-Q6_K.gguf" in f["path"]]'
curl -s https://huggingface.co/api/models/unsloth/Qwen3.8-27B-GGUF/tree/main/MTP | python3 -c 'import sys,json;[print(f["size"],f["path"]) for f in json.load(sys.stdin) if "Q4_0" in f["path"]]'
ls -l ~/models/qwen38-27b/*.gguf | awk '{print $5, $9}'
rm -f ~/models/qwen38-27b/download.log
```

**Acceptance:** `DONE_EXIT=0`; both local sizes match the API byte for byte (21,983,677,344 and 1,369,590,656 at the time of writing). If a size is short, rerun the same `curl -C -` line; it resumes.

## Phase 4: First run and benchmark

Run in tmux so a slow load or crash does not take the SSH session with it.

```bash
tmux new-session -d -s srv '~/llama/llama-<build>/llama-server --device Vulkan0 --model ~/models/qwen38-27b/Qwen3.8-27B-UD-Q6_K.gguf --model-draft ~/models/qwen38-27b/mtp-Qwen3.8-27B-Q4_0.gguf --spec-type draft-mtp --spec-draft-n-max 3 -ngl 999 -c 131072 --parallel 1 -b 2048 -ub 512 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --cache-ram 8192 --load-mode none --jinja --reasoning-budget 8192 --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --host 0.0.0.0 --port 8080 2>&1 | tee ~/srv.log'
until curl -s -m 3 localhost:8080/health | grep -q ok; do sleep 5; done; echo UP
awk '{printf "vram %.1f GB\n", $1/1e9}' /sys/class/drm/card*/device/mem_info_vram_used | head -1
```

| Flag | Why |
|---|---|
| `--device Vulkan0` | Refuse to start if the GPU is not available, instead of silently running on the CPU at a tenth of the speed. Matters at boot, when llama-server can start before amdgpu is ready |
| `--model-draft ... --spec-type draft-mtp --spec-draft-n-max 3` | MTP speculative decoding with the sidecar draft head. Generation went from 15.1 to 17.0 tok/s at 20K context when the draft length was raised from 2 to 3; about 46 per cent of drafted tokens are accepted |
| `-ngl 999` | All layers on the GPU |
| `-c 131072` | 128K context. The hybrid Gated DeltaNet architecture keeps the KV cache small (about 4 GB at 128K with q8_0), so this costs little memory. The clients cap sessions lower; see "What to expect" |
| `--parallel 1` | One slot gets the whole context instead of several sharing it |
| `-b 2048 -ub 512` | Micro-batch of 512 is the stable setting for long prompt processing on RADV; larger values raise the risk of a GPU timeout |
| `--cache-type-k/v q8_0` | KV cache at 8 bits. Small saving here; kept for consistency with long sessions |
| `--cache-ram 8192` | Host-RAM prompt cache budget. Sessions under about 60K tokens fit; the OS has only the memory outside the BIOS carve-out, so do not raise this far |
| `--load-mode none` | Load into memory rather than mmap. The old `--no-mmap` flag, renamed in 2026. Loading takes 7 seconds |
| `--jinja` | Enables the chat template, including the reasoning channel and tool-call parsing |
| `--reasoning-budget 8192` | Caps thinking at 8K tokens so a hard question cannot consume a whole reply |
| `--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0` | Qwen's recommended sampling for thinking mode |

Quality check: send a coding prompt with a generous `max_tokens` (the model reasons first, for 2,000 to 3,000 tokens on a question like this), extract the code block and execute it.

```bash
curl -s localhost:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"messages":[{"role":"user","content":"Write a Python function that parses an ISO 8601 duration like P3DT4H5M into total seconds, with two asserts. No explanation."}],"max_tokens":6000}' > /tmp/q.json
python3 -c 'import json;d=json.load(open("/tmp/q.json"));t=d["timings"];print("gen_tps=%.1f finish=%s"%(t["predicted_per_second"],d["choices"][0]["finish_reason"]));open("/tmp/q.py","w").write(d["choices"][0]["message"]["content"])'
python3 -c 'import re;s=open("/tmp/q.py").read();m=re.search(r"```(?:python)?\n(.*?)```",s,re.S);exec(m.group(1) if m else s);print("asserts passed")'
```

Tool-call check: send a request with one `tools` entry, confirm the reply has `finish_reason: tool_calls` with valid JSON arguments, then send the tool result back (include the assistant message's `reasoning_content` field) and confirm a normal answer.

Prompt-processing benchmark: send a prompt of about 20K tokens with `max_tokens` 700 and read `timings.prompt_per_second` and `timings.predicted_per_second`. Use fresh content each time so the cache cannot hit.

**Acceptance:** health ok; VRAM about 28 GB; `finish=stop` with asserts passed; tool call round trip works; generation at or above 18 tok/s at short context and 16 tok/s at 20K; prompt processing at or above 240 tok/s at 20K. Then `tmux kill-session -t srv` and `rm ~/srv.log /tmp/q.*`.

## Phase 5: Service, watchdog and platform fixes

Three things go in here: the systemd unit, a watchdog for the fault the unit cannot see, and two platform fixes that need a reboot.

### 5a. The unit

```bash
cat > ~/qwen38.service <<EOF
[Unit]
Description=Qwen3.8-27B llama.cpp server (MTP speculative decoding)
After=network.target
# allow 5 restarts per 5 min instead of 5 per 10 s (GPU may not be ready at boot)
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
User=<user>
ExecStart=/home/<user>/llama/llama-<build>/llama-server --device Vulkan0 --model /home/<user>/models/qwen38-27b/Qwen3.8-27B-UD-Q6_K.gguf --model-draft /home/<user>/models/qwen38-27b/mtp-Qwen3.8-27B-Q4_0.gguf --spec-type draft-mtp --spec-draft-n-max 3 -ngl 999 -c 131072 --parallel 1 -b 2048 -ub 512 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --cache-ram 8192 --load-mode none --jinja --reasoning-budget 8192 --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --host 0.0.0.0 --port 8080
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo -n install -m 644 ~/qwen38.service /etc/systemd/system/qwen38.service && rm ~/qwen38.service
sudo -n systemctl daemon-reload && sudo -n systemctl enable --now qwen38
until curl -s -m 3 localhost:8080/health | grep -q ok; do sleep 5; done; systemctl is-active qwen38
```

### 5b. GPU watchdog

When the GPU compute queue times out and resets (it did during the reference build, at 90K tokens of context), llama-server keeps running and `/health` keeps returning `ok`, but every request fails with `decode() failed: vk::Queue::submit: ErrorDeviceLost`. `Restart=on-failure` never fires because the process never exits. A one-minute timer watches the journal for that string and restarts the service.

```bash
cat > ~/qwen38-watch.service <<'EOF'
[Unit]
Description=Restart qwen38 if the GPU was lost (llama-server stays up but every decode fails)

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'journalctl -u qwen38.service --since -90s -o cat | grep -q "ErrorDeviceLost" && systemctl try-restart qwen38.service || true'
EOF
cat > ~/qwen38-watch.timer <<'EOF'
[Unit]
Description=Check qwen38 for GPU device-lost every minute

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF
sudo -n install -m 644 ~/qwen38-watch.service ~/qwen38-watch.timer /etc/systemd/system/ && rm ~/qwen38-watch.*
sudo -n systemctl daemon-reload && sudo -n systemctl enable --now qwen38-watch.timer
systemctl list-timers qwen38-watch.timer --no-pager
```

### 5c. Platform fixes

**GPU timeout.** Kernel 7.x cut the amdgpu compute-queue timeout to 2 seconds. A long attention step at deep context can exceed that, and the driver then resets the queue and the model is lost until restart. Raising the compute timeout to 60 seconds (the second value; the four are gfx, compute, sdma, video) fixed it on the reference box.

**Wi-Fi power saving.** If the box's uplink is Wi-Fi, power saving adds 50 to 120 ms of latency and heavy jitter to every packet. Measured from the workstation: 55 ms average with it on, 11 ms with it off. Skip this block if the default route is wired.

```bash
sudo -n sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 amdgpu.lockup_timeout=10000,60000,10000,10000"/' /etc/default/grub
grep CMDLINE_LINUX_DEFAULT /etc/default/grub
sudo -n update-grub
# Wi-Fi uplink only; substitute the interface from Phase 0
W=<wifi-iface>
printf 'ACTION=="add", SUBSYSTEM=="net", KERNEL=="%s", RUN+="/usr/sbin/iw dev %s set power_save off"\n' "$W" "$W" | sudo -n tee /etc/udev/rules.d/70-wifi-nops.rules
```

Now tell the user a reboot is needed and let them choose the moment. After it:

```bash
grep -o "amdgpu.lockup_timeout=[0-9,]*" /proc/cmdline
iw dev <wifi-iface> get power_save 2>/dev/null
systemctl is-active qwen38 qwen38-watch.timer; curl -s localhost:8080/health
```

**Acceptance:** the kernel parameter is in `/proc/cmdline`; `Power save: off` (Wi-Fi boxes); both units `active`; health ok; `journalctl -u qwen38 -b | grep listening` shows port 8080.

## Phase 6: Ollama sidecar (optional, Continue only)

Kilo Code needs nothing else. If the user still uses Continue and wants inline autocomplete and codebase embeddings, two small models on Ollama sit beside the main server in about 1.3 GB. Otherwise skip this phase.

```bash
curl -fsSL https://ollama.com/install.sh | sh
sudo -n mkdir -p /etc/systemd/system/ollama.service.d
printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0"\nEnvironment="OLLAMA_VULKAN=1"\nEnvironment="OLLAMA_CONTEXT_LENGTH=32768"\n' | sudo -n tee /etc/systemd/system/ollama.service.d/override.conf
sudo -n systemctl daemon-reload && sudo -n systemctl restart ollama
ollama pull qwen2.5-coder:1.5b-base && ollama pull nomic-embed-text
curl -s localhost:11434/api/generate -d '{"model":"qwen2.5-coder:1.5b-base","prompt":"def fib(n):\n    ","stream":false,"options":{"num_predict":30}}' | python3 -c 'import sys,json;d=json.load(sys.stdin);print("tps=%.0f"%(d["eval_count"]/(d["eval_duration"]/1e9)))'
curl -s localhost:11434/api/embed -d '{"model":"nomic-embed-text","input":"hello"}' | python3 -c 'import sys,json;print("dims",len(json.load(sys.stdin)["embeddings"][0]))'
curl -s localhost:8080/health
```

**Acceptance:** autocomplete at or above 40 tok/s; `dims 768`; main server health still ok.

## Phase 7: Workstation

On the workstation, not the box:

1. Kilo Code: back up `~/.config/kilo/kilo.jsonc` if it exists, then copy [client/kilo.jsonc](../client/kilo.jsonc) over it with `BOX_IP` replaced. The file is JSONC; comments are allowed.
2. Continue (legacy, optional): back up `~/.continue/config.yaml`, then copy [client/continue.config.yaml](../client/continue.config.yaml) with `BOX_IP` replaced. Remove the two Ollama entries if Phase 6 was skipped.
3. Confirm end to end from the workstation:

```bash
curl -s http://<box-ip>:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"messages":[{"role":"user","content":"Reply with exactly: READY"}],"max_tokens":2000}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["choices"][0]["message"]["content"].strip())'
```

**Acceptance:** `READY`. Tell the user to restart VS Code, pick "Qwen3.8 27B (local)" in Kilo's model picker, and, on macOS, to allow VS Code under Privacy & Security → Local Network if Kilo reports it cannot connect (see ready-state step 6).

Two things about Kilo worth telling the user:

- Its fixed prompt (system prompt plus tool schemas) is about 14K tokens. The first request of every session pays about a minute of prompt processing; later turns hit the cache and are fast.
- Kilo phones home to its own services by default. To turn that off: set the VS Code setting `telemetry.telemetryLevel` to `off`, and set the environment variables `KILO_TELEMETRY_LEVEL=off`, `KILO_DISABLE_SHARE=1` and `KILO_DISABLE_SESSION_INGEST=1` for VS Code's process (on macOS, `launchctl setenv` from a LaunchAgent). The shipped config already sets `"share": "disabled"`. Do not sign in to a Kilo account; session upload requires one.

## Phase 8: Tidy and report

On the box: no tarballs in `~/llama`, nothing of yours in `/tmp`, no staging unit files in the home directory, no tmux sessions, `sudo -n apt-get clean`. Then report:

| Item | Value |
|---|---|
| Model / quant | |
| llama.cpp build | |
| Context | |
| Generation tok/s (short / 20K) | |
| Prompt tok/s at 20K | |
| VRAM used | |
| Disk used / free | |
| Kernel parameter present | |
| Watchdog timer active | |
| Wi-Fi power save | |
| Ollama models (if any) | |
| Client config | path and backup path |
| Left for the user | reboot pending? anything skipped and why |

## What to expect

**Quality.** Qwen3.8-27B scores 34 on the [Artificial Analysis Intelligence Index](https://artificialanalysis.ai/models/qwen3-8-27b), the highest of 142 open-weight models in its size class; the vendor reports 61.7 on SWE-bench Pro, 73.0 on Terminal-Bench 2.1 and 90.3 on LiveCodeBench v6. This build runs Q6_K, which independent KL-divergence measurements put within a few per cent of the full model, so those numbers largely apply. Frontier cloud models are still ahead on long agentic runs.

**Knowledge.** A 27B model knows less trivia than a 230B one. For work that depends on obscure detail (register maps, protocol specifics, device-tree bindings), put the datasheet or header in the context rather than relying on recall. Context is cheap on this model.

**Speed.** Generation runs at about 19 tok/s at short context and 17 tok/s with 20K tokens in the window. Prompt processing runs at about 260 tok/s, so a 20K-token prompt waits about 80 seconds before the first token; the prefix cache removes that cost when a session grows by appending.

**The context cliff.** Past about 85K tokens, prompt processing on this hardware collapses to 3 or 4 tok/s and every turn pays several seconds even for a short message. The shipped client configs cap sessions at 80K so compaction happens first. Start a fresh session per task; treat 50K tokens as the point where a session has become expensive. `journalctl -u qwen38 -f | grep print_timing` shows exactly where the time goes.

**Reasoning.** The model thinks before it answers, typically 500 to 3,000 tokens. Clients must send that reasoning back with the conversation (Kilo does with the shipped config; Continue does only with `provider: deepseek`). Without it the model loses the thread between tool calls and looks much less capable than it is.

## Day to day

```bash
ssh <user>@<box-ip>
systemctl status qwen38 qwen38-watch.timer         # is the model server up, is the watchdog armed
journalctl -u qwen38 -f | grep print_timing        # how long each request took, and why
journalctl -u qwen38 -b | grep -c ErrorDeviceLost  # GPU faults since boot (the watchdog restarts on these)
radeontop                                          # GPU load
```

Or run [check-health.sh](../check-health.sh) on the box, or ask your agent: "check the box".

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| `No space left on device` | Installer's 100 GB LVM default | Phase 1 |
| `error while loading shared libraries: libgomp.so.1` | Prebuilt binary dependency | `sudo apt install libgomp1` |
| `invalid argument: --no-mmap` | Flag renamed in 2026 builds | Use `--load-mode none` |
| `invalid device: Vulkan0` at start | GPU not initialised yet, or driver missing | Normal at boot for one or two restarts (the unit retries). Persistent: recheck Phase 1 driver check and group membership |
| `decode() failed: vk::Queue::submit: ErrorDeviceLost` | GPU compute queue timed out and reset; kernel log shows `ring comp_1.2.0 timeout` | The watchdog restarts the service within a minute. If it recurs, confirm `amdgpu.lockup_timeout` is in `/proc/cmdline` (Phase 5c) and keep sessions under 80K tokens |
| Every request takes 5+ seconds even when short | Session past the 85K context cliff | Start a new session; check client context caps |
| Empty reply, `finish_reason: length` | Reasoning consumed the token budget | Raise `max_tokens` to 8192 or more in the client |
| Model seems to forget what it was doing between tool calls | Client not sending `reasoning_content` back | Kilo: check `"interleaved"` in the model entry. Continue: `provider: deepseek` with a trailing `/` on `apiBase` |
| 50 to 120 ms ping to the box, jittery | Wi-Fi power saving | Phase 5c udev rule; or use a cable |
| Box vanishes from the network entirely | Wi-Fi-only uplink lost (driver fault, regulatory-domain change, access point restart) | Power-cycle; then plug in a cable, which removes the failure mode |
| Kilo: "Unable to connect. Is the computer able to access the url?" while `curl` from a terminal works | macOS Local Network privacy permission | System Settings → Privacy & Security → Local Network → enable Visual Studio Code, restart VS Code |
| SSH refused for 2 minutes after boot with "System is booting up" | `systemd-networkd-wait-online` waiting on an unplugged wired port | Harmless. To remove: add `optional: true` under `eno1` in `/etc/netplan/*.yaml` and `sudo netplan apply` |
| SSH session dies mid-script | `pkill -f` matched your own command line | Kill by PID from `pgrep -x` |
| General instability | Non-stock kernel | Stock kernel only |

## Security note

As built, the model server accepts requests from any device on the LAN with no API key, and the tool calls a client makes on its behalf run on the workstation with the user's permissions. That is fine on a network you control. On a shared network, add `--api-key <random>` to the unit and the matching key to the client configs, or bind `--host 127.0.0.1` and reach the box through an SSH tunnel.

## Hardware reference

GMKtec EVO-X2 as built: AMD Ryzen AI Max+ 395 "Strix Halo" (16C/32T Zen 5), Radeon 8060S iGPU (40 CU RDNA 3.5, `gfx1151`), 128 GB LPDDR5X-8000 on a 256-bit bus at about 256 GB/s, 2 TB NVMe, MediaTek MT7925 Wi-Fi, Realtek 2.5 GbE. Idle at about 60 °C CPU and GPU with the model loaded.
