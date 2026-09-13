# Build guide: agent runbook

| | |
|---|---|
| **Version** | 3.0 |
| **Last verified** | September 2026 |
| **Applies to** | AMD Ryzen AI Max+ 395 ("Strix Halo") systems with 128 GB unified memory, such as the GMKtec EVO-X2, Framework Desktop, and HP Z2 Mini G1a |
| **Target** | Ubuntu Server 26.04 LTS, llama.cpp b9969 or newer, MiniMax-M2.7 UD-Q3_K_S, Ollama, Continue 2.0 |

This document is written for an AI coding agent to execute over SSH after the human has completed [ready-state.md](ready-state.md). Each phase ends with an acceptance check. Run it, show the output, and stop on failure. Follow the rules in [AGENTS.md](../AGENTS.md) throughout. A human can follow the same steps by hand; nothing here requires an agent.

## Goal

A headless server that boots into a llama.cpp endpoint serving MiniMax M2.7 (230B MoE, about 10B active, 32K context, about 30 tok/s) on port 8080, an Ollama sidecar on 11434 for autocomplete and embeddings, and a Continue config on the workstation that uses both. Everything on Vulkan; ROCm is not used.

## Design decisions

- Vulkan instead of ROCm. ROCm on gfx1151 has a history of kernel-version pain; the RADV driver ships with Ubuntu and works immediately.
- llama.cpp directly, no wrapper. One binary, one systemd unit, full control over the flags that matter when a model barely fits: KV-cache quantisation, layer offload, mmap, batch sizes.
- Ubuntu Server, stock kernel. Custom kernels are the main cause of instability on this platform.
- An MoE model. 128 GB of memory but only about 256 GB/s of bandwidth; a model that activates about 10B of 230B parameters per token runs at usable speed where a dense model of similar quality would not.
- Q3_K_S rather than Q3_K_XL. 94 GB leaves room for a 32K context inside the 96 GB GPU carveout; 102 GB does not.

## Phase 0: Preflight

```bash
ssh -o BatchMode=yes <user>@<box-ip> '
echo "=== os"; lsb_release -ds; uname -r
echo "=== sudo"; sudo -n true && echo SUDO_OK
echo "=== disk"; df -h / | tail -1; lsblk -o NAME,SIZE,TYPE | grep -E "disk|lvm"
echo "=== mem"; free -g | head -2
echo "=== gpu"; lspci | grep -i vga; cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null
echo "=== net"; ip route show default; curl -s -m 10 -o /dev/null -w "%{speed_download} B/s\n" https://huggingface.co/unsloth/MiniMax-M2.7-GGUF/resolve/main/UD-Q3_K_S/MiniMax-M2.7-UD-Q3_K_S-00001-of-00003.gguf'
```

**Acceptance:** Ubuntu 26.04; `SUDO_OK`; a VGA line naming an AMD device; VRAM total about 103 GB (96 GiB carveout) or whatever the BIOS was set to; a default route. Note the download speed: at 10 MB/s the model takes about 2.5 hours, at 1 MB/s about a day. Tell the user the estimate before starting Phase 3.

## Phase 1: OS preparation

The installer allocates only about 100 GB. Expand the root filesystem online, then install the GPU stack.

```bash
sudo -n lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv && sudo -n resize2fs /dev/ubuntu-vg/ubuntu-lv
sudo -n apt-get update && sudo -n DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo -n apt-get install -y mesa-vulkan-drivers vulkan-tools radeontop libgomp1 tmux python3-pip curl
sudo -n usermod -aG render,video <user>
```

If `apt upgrade` installs a new kernel, `/var/run/reboot-required` appears. Tell the user; a reboot now is cheap, later it interrupts a serving model. Group membership needs a fresh login; the next SSH call gets it automatically.

```bash
vulkaninfo --summary 2>/dev/null | grep -i devicename
df -h / | tail -1
```

**Acceptance:** `deviceName = Radeon 8060S Graphics (RADV STRIX_HALO)` (an extra `llvmpipe` line is normal headless); root filesystem now spans the disk. A `DISPLAY` warning from vulkaninfo is normal.

## Phase 2: llama.cpp

Use the newest Ubuntu x64 Vulkan release from [github.com/ggml-org/llama.cpp/releases](https://github.com/ggml-org/llama.cpp/releases); b9969 is the verified minimum.

```bash
B=<build>   # e.g. b9969
mkdir -p ~/llama && cd ~/llama
curl -LO https://github.com/ggml-org/llama.cpp/releases/download/$B/llama-$B-bin-ubuntu-vulkan-x64.tar.gz
tar -xzf llama-$B-bin-ubuntu-vulkan-x64.tar.gz && rm llama-$B-bin-ubuntu-vulkan-x64.tar.gz
~/llama/llama-$B/llama-server --version
```

**Acceptance:** `--version` prints the build number. A missing shared library means an apt package; `libgomp.so.1` is `libgomp1`.

## Phase 3: Model download

About 94 GB in three shards. Run inside tmux with a log and an exit marker.

```bash
pip install -U "huggingface_hub[cli]" --break-system-packages
mkdir -p ~/models/minimax27
tmux new-session -d -s dl '~/.local/bin/hf download unsloth/MiniMax-M2.7-GGUF --include "*UD-Q3_K_S*" --local-dir ~/models/minimax27 2>&1 | tee ~/models/minimax27/download.log; echo DONE_EXIT=$? >> ~/models/minimax27/download.log'
```

Monitoring, every 5 minutes or on request:

```bash
grep DONE_EXIT ~/models/minimax27/download.log || echo running
du -sm ~/models/minimax27 | cut -f1
r0=$(cat /sys/class/net/$(ip route show default | awk "{print \$5}")/statistics/rx_bytes); sleep 30; r1=$(cat /sys/class/net/$(ip route show default | awk "{print \$5}")/statistics/rx_bytes); echo "rx_MBps=$(( (r1-r0)/30/1000000 ))"
```

Two traps:

- **Progress reporting misleads.** Shards live in `.cache` until complete, and the Xet client buffers in memory and flushes in bursts, so folder size jumps rather than climbs. Trust the network counter.
- **A stall does not resume.** If the network counter reads zero for two consecutive checks with no established HTTPS connections and the process still alive, the client has hung. Killing it and re-running `hf download` starts the affected shard again from byte zero. If the shard is mostly done, finish it by hand: move its `.incomplete` file to the final path, `truncate` it back by 64 MB, fetch the remaining range from `https://huggingface.co/unsloth/MiniMax-M2.7-GGUF/resolve/main/UD-Q3_K_S/<shard>` with 16 parallel `curl -r start-end` segments, append them in order, and verify. Kill the hung process by PID found via `pgrep -x python3` plus `/proc/<pid>/cmdline`, never `pkill -f`.

Verification, for every shard:

```bash
curl -s https://huggingface.co/api/models/unsloth/MiniMax-M2.7-GGUF/tree/main/UD-Q3_K_S   # size and lfs.oid per file
ls -l ~/models/minimax27/UD-Q3_K_S/
sha256sum ~/models/minimax27/UD-Q3_K_S/*.gguf    # a few minutes on NVMe
rm -rf ~/models/minimax27/.cache ~/models/minimax27/download.log
```

**Acceptance:** `DONE_EXIT=0`; three files whose sizes and SHA-256 match the API; `.cache` removed.

## Phase 4: First run and benchmark

Run in tmux so a slow load or crash does not take the SSH session with it.

```bash
tmux new-session -d -s srv '~/llama/llama-<build>/llama-server --model ~/models/minimax27/UD-Q3_K_S/MiniMax-M2.7-UD-Q3_K_S-00001-of-00003.gguf -ngl 999 -c 32768 --parallel 1 --cache-reuse 256 -b 4096 -ub 2048 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --cache-ram 16384 --no-mmap --jinja --temp 1.0 --top-p 0.95 --top-k 40 --host 0.0.0.0 --port 8080 2>&1 | tee ~/srv.log'
until curl -s -m 3 localhost:8080/health | grep -q ok; do sleep 5; done; echo UP
awk '{printf "vram %.1f GB\n", $1/1e9}' /sys/class/drm/card*/device/mem_info_vram_used | head -1
```

| Flag | Why |
|---|---|
| `-ngl 999` | All layers on the GPU |
| `-c 32768` | 32K context. Fits with Q3_K_S; 16K ran out fast under agentic tools |
| `--parallel 1` | One slot gets the whole context instead of four sharing it |
| `--cache-reuse 256` | Prompt cache survives small prefix changes; a repeated prompt costs one token |
| `--cache-ram 16384` | Prompt cache budget in host RAM. Entries run about 1.4 GB, so the 8192 default holds roughly five and then evicts continuously |
| `-b 4096 -ub 2048` | Larger batches. Prompt processing went from 161 to 241 tok/s on a 14K prompt; the biggest single win on this platform |
| `--cache-type-k/v q8_0` | Compresses the KV cache so the model fits. q8_0 costs about 2 GB more than q4_0 at 32K and buys KV fidelity over a long session; generation speed is unchanged, 24.6 against 25.4 tok/s at 9K |
| `--jinja` | Enables the chat template, including the reasoning channel |
| `--temp 1.0 --top-p 0.95 --top-k 40` | MiniMax's recommended sampling for M2.7 |

A `special_eos_id is not in special_eog_ids` warning at load is a known harmless quirk of MiniMax GGUFs.

Quality check: send a coding prompt with `max_tokens` 3000 (the model reasons first; a small budget returns an empty reply), extract the code block and execute it.

```bash
curl -s localhost:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"messages":[{"role":"user","content":"Write a Python function that parses an ISO 8601 duration like P3DT4H5M into total seconds, with two asserts. No explanation."}],"max_tokens":3000}' > /tmp/q.json
python3 -c 'import json;d=json.load(open("/tmp/q.json"));t=d["timings"];print("gen_tps=%.1f finish=%s"%(t["predicted_per_second"],d["choices"][0]["finish_reason"]));open("/tmp/q.py","w").write(d["choices"][0]["message"]["content"])'
python3 -c 'import re;s=open("/tmp/q.py").read();m=re.search(r"```(?:python)?\n(.*?)```",s,re.S);exec(m.group(1) if m else s);print("asserts passed")'
```

Prompt-processing benchmark: send a synthetic prompt of about 14K tokens and one of about 3.6K, each with `max_tokens` 1, and read `timings.prompt_per_second` and `timings.prompt_n` from the response. Use fresh random content each time so the cache cannot hit.

**Acceptance:** health ok; VRAM about 100 GB of the 103 GB carveout; `finish=stop` with asserts passed; generation at or above 28 tok/s; prompt processing at or above 220 tok/s at 14K and 300 tok/s at 3.6K. Then `tmux kill-session -t srv` and `rm ~/srv.log /tmp/q.*`.

## Phase 5: Service

```bash
cat > ~/minimax.service <<EOF
[Unit]
Description=MiniMax M2.7 llama.cpp server
After=network.target

[Service]
User=<user>
ExecStart=/home/<user>/llama/llama-<build>/llama-server --model /home/<user>/models/minimax27/UD-Q3_K_S/MiniMax-M2.7-UD-Q3_K_S-00001-of-00003.gguf -ngl 999 -c 32768 --parallel 1 --cache-reuse 256 -b 4096 -ub 2048 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --cache-ram 16384 --no-mmap --jinja --temp 1.0 --top-p 0.95 --top-k 40 --host 0.0.0.0 --port 8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
sudo -n install -m 644 ~/minimax.service /etc/systemd/system/minimax.service && rm ~/minimax.service
sudo -n systemctl daemon-reload && sudo -n systemctl enable --now minimax
until curl -s -m 3 localhost:8080/health | grep -q ok; do sleep 5; done; systemctl is-active minimax
```

**Acceptance:** `active`, health ok, and `journalctl -u minimax -b | grep listening` shows port 8080. Additional GGUF models follow the same pattern on another port.

## Phase 6: Ollama sidecar

MiniMax is too slow for inline autocomplete and cannot produce embeddings. Two small models on Ollama sit beside it in about 2.4 GB.

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

**Acceptance:** autocomplete at or above 40 tok/s; `dims 768`; MiniMax health still ok. Remove any other Ollama models that nothing uses.

## Phase 7: Workstation

On the workstation, not the box:

1. Back up `~/.continue/config.yaml` if it exists.
2. Copy [client/continue.config.yaml](../client/continue.config.yaml) to `~/.continue/config.yaml` with `BOX_IP` replaced.
3. If `~/.continue/.continuerc.json` sets `"disableIndexing": true`, change it to `false` so codebase search uses the embedding model.
4. Confirm end to end from the workstation:

```bash
curl -s http://<box-ip>:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"MiniMax-M2.7","messages":[{"role":"user","content":"Reply with exactly: READY"}],"max_tokens":2000}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["choices"][0]["message"]["content"].strip())'
curl -s http://<box-ip>:11434/api/tags | python3 -c 'import sys,json;print([m["name"] for m in json.load(sys.stdin)["models"]])'
```

**Acceptance:** `READY`; both small models listed. Tell the user to reload the VS Code window if Continue's dropdown still shows old names, and that the backup exists.

## Phase 8: Tidy and report

On the box: no tarballs in `~/llama`, no `.cache` under `~/models`, nothing of yours in `/tmp`, no tmux sessions, `sudo -n apt-get clean`. Then report:

| Item | Value |
|---|---|
| Model / quant | |
| llama.cpp build | |
| Context | |
| Generation tok/s (short context) | |
| Prompt tok/s at 14K / 3.6K | |
| VRAM used | |
| Disk used / free | |
| Ollama models | |
| Continue config | path and backup path |
| Left for the user | reboot pending? indexing? anything skipped and why |

## What to expect

MiniMax M2.7 at Q3 sits within a few points of the leading closed models on the vendor's coding benchmarks (SWE-bench Pro 56.2, Terminal-Bench 2 57.0). One independent head-to-head found it matched a frontier cloud model on bug and vulnerability detection while trailing on architecture and defence in depth. Current cloud models still win the hardest 10 to 15% of tasks.

Generation runs at about 30 tok/s at short context, falling to about 22 tok/s with 16K tokens in the window.

Prompt processing is the platform's weak side. With the flags above it runs at 240 to 330 tok/s, so a 14K-token prompt waits about 60 seconds before the first token. The prefix cache removes that cost when a conversation grows by appending, but not when the client trims old messages off the front. Under Continue: start a fresh chat per task, avoid attaching whole large files, and treat 15K tokens as the point where a session has become expensive. `journalctl -u minimax -f | grep print_timing` shows exactly where the time goes.

The point of the build is not to beat cloud models. It is to move most of your token volume to inference that is free, private and offline, with cloud as the escalation path.

## Day to day

```bash
ssh <user>@<box-ip>
systemctl status minimax                       # is the model server up
journalctl -u minimax -f | grep print_timing   # how long each request took, and why
radeontop                                      # GPU load
du -sh ~/models/*                              # disk used by models
```

Or ask your agent: "check the box".

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| `No space left on device` at ~90 GB | Installer's 100 GB LVM default | Phase 1 |
| `error while loading shared libraries: libgomp.so.1` | Prebuilt binary dependency | `sudo apt install libgomp1` |
| Download folder size frozen, network busy | Xet client buffering | Normal; trust the network counter |
| Download at 0 B/s, process alive | Xet client hang; restart will not resume the shard | Phase 3 trap: finish the shard with range requests |
| Model load hangs | mmap behaviour on unified memory | Toggle `--no-mmap` |
| GPU at 0%, CPU saturated | CPU fallback | Recheck the Phase 1 driver check and group membership |
| Empty reply, `finish_reason: length` | Reasoning consumed the token budget | Raise `max_tokens` to 8192 or more |
| Minutes before the first token | Large prompt at 240 to 330 tok/s | Confirm `-ub 2048`; shorten Continue sessions |
| Repeated prompts reprocessing from scratch | Prompt cache evicting under the default budget | Grep the log for `making room for prompt cache`; raise `--cache-ram` |
| `Failed to parse tool call arguments as JSON` | Model emitted an unescaped newline inside a string argument. Observed at Q3; not compared against higher quants | Retry the call; if it persists, suspect the weight quantisation rather than the settings |
| `systemd-networkd-wait-online` failed | Wired port has no cable; box is on Wi-Fi | Harmless |
| SSH session dies mid-script | `pkill -f` matched your own command line | Kill by PID from `pgrep -x` |
| General instability | Non-stock kernel | Stock kernel only |

## Hardware reference

GMKtec EVO-X2 as built: AMD Ryzen AI Max+ 395 "Strix Halo" (16C/32T Zen 5), Radeon 8060S iGPU (40 CU RDNA 3.5, `gfx1151`), 128 GB LPDDR5X-8000 on a 256-bit bus at about 256 GB/s, 2 TB NVMe, 96 GB UMA carveout.
