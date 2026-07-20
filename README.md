# strix-halo-llm-server

Build a self-hosted LLM inference server on a 128 GB AMD Strix Halo (Ryzen AI Max+ 395) mini PC: Ubuntu Server 26.04 headless, llama.cpp on Vulkan serving MiniMax M2.5, wired into VS Code over the LAN.

Written from a real build, including every trap hit along the way (the 100 GB disk default, ROCm avoidance, misleading download bars, missing shared libraries). If you have a GMKtec EVO-X2, Framework Desktop, HP Z2 Mini G1a or similar 128 GB Strix Halo machine, this repo takes you from USB stick to a working AI server.

## What you end up with

| Model | Served by | systemd unit | Port | Speed |
|---|---|---|---|---|
| MiniMax M2.5 UD-Q3_K_XL | llama.cpp `llama-server` (Vulkan) | `minimax` | 8080 | about 33 tok/s |

The server starts on boot and exposes an OpenAI-compatible API plus a built-in chat UI. VS Code (Cline or Continue) connects to it directly. MiniMax M2.5 at Q3 sits roughly at last year's frontier, which is the best coding quality that fits in 128 GB today. Additional GGUF models can run as extra `llama-server` units on other ports using the same pattern.

## Start here

- [docs/build-guide.md](docs/build-guide.md): the full build, from USB stick to VS Code integration

## Reference hardware

GMKtec EVO-X2: AMD Ryzen AI Max+ 395 (16C/32T Zen 5), Radeon 8060S iGPU (gfx1151), 128 GB LPDDR5X-8000 at about 256 GB/s, 2 TB NVMe. Any 128 GB Strix Halo system should behave the same.

## Quick reference (once built)

```bash
ssh <user>@<box-ip>
systemctl status minimax               # the llama.cpp service
radeontop                              # GPU load
du -sh ~/models/*                      # disk usage by model
```
