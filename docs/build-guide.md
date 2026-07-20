# How to build a local AI server on a Strix Halo mini PC

| | |
|---|---|
| **Version** | 2.0 |
| **Last verified** | July 2026 |
| **Applies to** | AMD Ryzen AI Max+ 395 ("Strix Halo") systems with 128 GB unified memory, such as the GMKtec EVO-X2, Framework Desktop, and HP Z2 Mini G1a |
| **Software** | Ubuntu Server 26.04 LTS, llama.cpp b9969, MiniMax-M2.5 UD-Q3_K_XL |

## Goal

A headless server that boots into a llama.cpp inference endpoint serving MiniMax M2.5 (230B MoE, about 33 tok/s) over the LAN, reachable from VS Code and any OpenAI-compatible client. Everything runs on Vulkan; ROCm is not used.

## Prerequisites

- A 128 GB Strix Halo machine
- A second computer with an SSH client and VS Code
- A USB stick, plus a monitor and USB keyboard for the initial install only
- About 100 GB of download bandwidth for the model
- No Linux experience needed beyond copy-pasting shell commands

## Design decisions

Read once, skip on re-use.

- Vulkan instead of ROCm. ROCm on gfx1151 has a history of kernel-version pain. The RADV driver ships with Ubuntu and works immediately.
- llama.cpp directly, no wrapper. One binary, one systemd unit, full control over the flags that matter when a model barely fits in memory (KV-cache quantisation, layer offload, mmap behaviour).
- Ubuntu Server instead of Desktop. No GUI means less to break and more RAM for models.
- Stock kernel only. Custom kernels are the main cause of instability on this platform, and 26.04's stock kernel supports the chip natively.
- An MoE model. The platform has plenty of memory (128 GB unified) but modest bandwidth (about 256 GB/s). MiniMax M2.5 activates only about 10B of its 230B parameters per token, which is why it runs at usable speed where a dense model of similar quality would not.

## 1. Install Ubuntu Server

> [!NOTE]
> The monitor and keyboard are needed for this section only, about 15 minutes.

1. Download Ubuntu Server 26.04 LTS and flash it to USB with balenaEtcher.
2. Boot the box from USB (`Del` or `F7` at power-on).
3. In the installer: accept defaults, use the entire disk, and select **Install OpenSSH server**. Skip the featured snaps.
4. Optional: check **UMA Frame Buffer Size** in BIOS. Either extreme works with Vulkan; the reference build uses a 96 GB carveout. Verify later without a monitor: `cat /sys/class/drm/card*/device/mem_info_vram_total`.
5. After boot, log in at the console and record the IP (`ip a`). Reserve it against the machine's MAC address in your router.

Everything from here is over SSH:

```console
$ ssh <user>@<box-ip>
```

### 1.1 Expand the root filesystem

> [!WARNING]
> The installer allocates only about 100 GB of the disk by default. The model download will fail with "no space left" unless you fix this now.

```console
$ df -h /                                              # ~98G total means you're affected
$ sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
$ sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
$ df -h /                                              # now shows the full disk
```

This resizes online. No reboot, no data loss.

### 1.2 Update and install the GPU stack

```console
$ sudo apt update && sudo apt upgrade -y
$ sudo apt install -y mesa-vulkan-drivers vulkan-tools radeontop libgomp1 tmux
$ sudo usermod -aG render,video $USER
```

Log out and back in, then confirm the GPU is visible:

```console
$ vulkaninfo --summary | grep -i devicename
deviceName = Radeon 8060S Graphics (RADV STRIX_HALO)
```

> [!NOTE]
> A `'DISPLAY' environment variable not set` warning and a `llvmpipe` CPU device are normal on a headless system.

## 2. Install llama.cpp

Download the current Ubuntu x64 Vulkan asset from the [llama.cpp releases page](https://github.com/ggml-org/llama.cpp/releases). The filename looks like `llama-<build>-bin-ubuntu-vulkan-x64.tar.gz`.

```console
$ mkdir -p ~/llama && cd ~/llama
$ curl -LO https://github.com/ggml-org/llama.cpp/releases/download/b9969/llama-b9969-bin-ubuntu-vulkan-x64.tar.gz
$ tar -xzf llama-b9969-bin-ubuntu-vulkan-x64.tar.gz
$ ~/llama/llama-b9969/llama-server --version
version: 9969 (76f279805)
```

Substitute the current build number. If `--version` reports a missing shared library, install the matching package (for example `sudo apt install -y libgomp1`) and retry.

## 3. Download the model

The model is about 95 GB. Run the download inside `tmux` so it survives SSH disconnection.

```console
$ sudo apt install -y python3-pip
$ pip install -U "huggingface_hub[cli]" --break-system-packages
$ mkdir -p ~/models
$ tmux
$ hf download unsloth/MiniMax-M2.5-GGUF --include "*UD-Q3_K_XL*" --local-dir ~/models/minimax
```

Detach with `Ctrl+B`, `D`. Reattach with `tmux attach`.

> [!TIP]
> The progress bars mislead. Shards accumulate in a hidden `.cache` directory until each one completes, so track real progress with `du -sh ~/models/minimax`. An interrupted download resumes when you re-run the same command.

The download is finished when the `hf` process exits and `ls -lh ~/models/minimax/UD-Q3_K_XL/` lists four `.gguf` files totalling about 95 GB. Uneven shard sizes (7.9M, 47G, 47G, 1.7G) are expected.

## 4. First run

```console
$ ~/llama/llama-b9969/llama-server \
    --model ~/models/minimax/UD-Q3_K_XL/MiniMax-M2.5-UD-Q3_K_XL-00001-of-00004.gguf \
    -ngl 999 -c 16384 --flash-attn on \
    --cache-type-k q4_0 --cache-type-v q4_0 \
    --no-mmap --jinja --host 0.0.0.0 --port 8080
```

Point `--model` at the first shard and the rest are found automatically. `-ngl 999` puts all layers on the GPU, the `q4_0` cache flags compress the KV cache so the model fits in 128 GB, `-c 16384` is the practical context ceiling at this size, and `--jinja` enables the model's chat template.

> [!NOTE]
> The first load takes several minutes with little output while 95 GB is read from disk. A `special_eos_id is not in special_eog_ids` warning at startup is a known harmless quirk of MiniMax GGUFs.

Wait for `server listening on 0.0.0.0:8080`, then open `http://<box-ip>:8080` from another machine. llama.cpp serves a built-in chat UI with a reasoning-trace viewer. Expect 30 tok/s or better.

To verify GPU offload, run `radeontop` in a second session while the model generates. The graphics pipe should be busy with roughly 99 GB of VRAM in use. A GPU at 0% with the CPU saturated means it fell back to CPU; recheck section 1.2.

## 5. Run as a service

Paste this whole block as one command. It creates the service file with your username and paths filled in automatically:

```console
$ sudo tee /etc/systemd/system/minimax.service > /dev/null << EOF
[Unit]
Description=MiniMax M2.5 llama.cpp server
After=network.target

[Service]
User=$USER
ExecStart=$HOME/llama/llama-b9969/llama-server --model $HOME/models/minimax/UD-Q3_K_XL/MiniMax-M2.5-UD-Q3_K_XL-00001-of-00004.gguf -ngl 999 -c 16384 --flash-attn on --cache-type-k q4_0 --cache-type-v q4_0 --no-mmap --jinja --host 0.0.0.0 --port 8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
```

```console
$ sudo systemctl daemon-reload
$ sudo systemctl enable --now minimax
$ systemctl status minimax
```

The endpoint now starts on every boot on `:8080`. To serve additional GGUF models, repeat the pattern: download the model, copy the unit file under a new name, change the model path and port.

## 6. IDE integration

Install Cline (agentic) or Continue (chat and autocomplete) in VS Code on your workstation and register the provider:

| Provider | Type | Endpoint |
|---|---|---|
| MiniMax M2.5 | OpenAI-compatible | `http://<box-ip>:8080/v1` (any API key) |

Paste compiler or runtime errors back into the same conversation rather than starting over; the model fixes its own mistakes readily when shown the error.

## What to expect

MiniMax M2.5 at Q3 quantisation sits roughly at last year's frontier, around the Claude Sonnet/Opus 4 class. It usually gets architecture right and occasionally fumbles version-specific API details. Current cloud models still win on the hardest 10 to 15% of tasks.

Generation runs at about 33 tok/s. Prompt processing is the platform's weak side and there is no local prompt caching, so long agentic sessions pay a per-turn wait.

The 16K context fills quickly under agentic tools. If that becomes the limit, look at the pruned `MiniMax-M2.5-REAP-139B` variant, which keeps most of the quality with far more headroom, or run a smaller model alongside for quick tasks.

The point of the build is not to beat cloud models. It is to move most of your token volume to inference that is free, private, and works offline, with cloud as the escalation path.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| `No space left on device` at ~90 GB | Installer's 100 GB LVM default | §1.1 |
| `error while loading shared libraries: libgomp.so.1` | Prebuilt binary dependency | `sudo apt install libgomp1` |
| `unzip` rejects the release archive | Releases ship as `.tar.gz` | `tar -xzf` |
| Download appears reset after resume | Shards hidden in `.cache` until complete | Trust `du -sh`, not the bars |
| Model load hangs | mmap behaviour on unified memory | Toggle `--no-mmap` |
| GPU at 0%, CPU saturated | CPU fallback | Recheck §1.2 driver check |
| General instability | Non-stock kernel | Stock kernel only |

## Hardware reference

GMKtec EVO-X2 as built: AMD Ryzen AI Max+ 395 "Strix Halo" (16C/32T Zen 5), Radeon 8060S iGPU (40 CU RDNA 3.5, `gfx1151`), 128 GB LPDDR5X-8000 on a 256-bit bus at about 256 GB/s, 2 TB NVMe.
