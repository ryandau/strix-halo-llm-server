# strix-halo-llm-server

Build a self-hosted LLM inference server on a 128 GB AMD Strix Halo (Ryzen AI Max+ 395) mini PC: Ubuntu Server 26.04 headless, Ollama for fast models, llama.cpp for MiniMax M2.5, everything on Vulkan, wired into VS Code over the LAN.

Written from a real build, including every trap hit along the way (the 100 GB disk default, ROCm avoidance, Ollama's 4K context, misleading download bars). If you have a GMKtec EVO-X2, Framework Desktop, HP Z2 Mini G1a or similar 128 GB Strix Halo machine, this repo takes you from USB stick to a working two-tier AI server.

## What you end up with

| Model | Served by | systemd unit | Port | Speed |
|---|---|---|---|---|
| Qwen3-Coder 30B | Ollama (Vulkan) | `ollama` | 11434 | 70 to 100 tok/s |
| MiniMax M2.5 UD-Q3_K_XL | llama.cpp `llama-server` (Vulkan) | `minimax` | 8080 | about 33 tok/s |

Both start on boot. VS Code (Continue) connects to either endpoint: the fast model for everyday iteration, MiniMax as the escalation path for hard problems. MiniMax M2.5 at Q3 sits roughly at last year's frontier, which is the best coding quality that fits in 128 GB today.

## Start here

- [docs/build-guide.md](docs/build-guide.md) — the full build, from USB stick to VS Code integration
- [config/](config/) — the systemd unit and Ollama override, as deployed on the reference build

## Reference hardware

GMKtec EVO-X2: AMD Ryzen AI Max+ 395 (16C/32T Zen 5), Radeon 8060S iGPU (gfx1151), 128 GB LPDDR5X-8000 at about 256 GB/s, 2 TB NVMe. Any 128 GB Strix Halo system should behave the same.

## Quick reference (once built)

```bash
ssh <user>@<box-ip>
systemctl status ollama minimax        # both services (minimax = the llama.cpp unit)
radeontop                              # GPU load
du -sh ~/models/*                      # disk usage by model
```
