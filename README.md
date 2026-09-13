# strix-halo-llm-server

Turn a 128 GB AMD Strix Halo (Ryzen AI Max+ 395) mini PC into a private AI coding server: Ubuntu Server headless, llama.cpp on Vulkan serving MiniMax M2.7, small Ollama models for autocomplete and code search, all wired into VS Code over the LAN.

The build is written as a runbook for an AI coding agent. You spend about 15 minutes at the keyboard getting the box to a ready state. Then you hand it to the agent, which connects over SSH and does the rest by following the runbook in this repo, including the model download, the tuning, the service, and your VS Code config. A person can follow the same runbook by hand.

Written from a real build and a real upgrade, including every trap hit along the way.

## What you end up with

| Model | Served by | systemd unit | Port | Speed |
|---|---|---|---|---|
| MiniMax M2.7 UD-Q3_K_S | llama.cpp `llama-server` (Vulkan) | `minimax` | 8080 | about 30 tok/s generation, 240 to 330 tok/s prompt |
| Qwen2.5-Coder 1.5B (autocomplete), Nomic Embed (embeddings) | Ollama | `ollama` | 11434 | about 60 tok/s |

The server starts on boot and exposes an OpenAI-compatible API plus a built-in chat UI with a 32K context. VS Code (Continue) uses it for chat, edit, autocomplete and codebase search. MiniMax M2.7 at Q3 sits within a few points of the leading closed models on the vendor's coding benchmarks, the best coding quality that fits in 128 GB today.

## How the build works

**1. Ready state. You, at the PC, about 15 minutes.**
Install Ubuntu Server with OpenSSH, note the IP, enable passwordless sudo, copy your SSH key across. Checklist: [docs/ready-state.md](docs/ready-state.md). Unplug the monitor when it passes.

**2. Build. The agent, over SSH, about 2 to 3 hours, mostly the model download.**
Clone this repo on your workstation, open it in your AI coding agent, and paste:

```
Read AGENTS.md and docs/build-guide.md. The box is <user>@<box-ip>.
Build it through every phase to the acceptance checks and give me the final report table.
```

The agent works through [docs/build-guide.md](docs/build-guide.md) phase by phase, verifying each one before moving on, and configures Continue on your workstation at the end. [AGENTS.md](AGENTS.md) holds the operating rules it follows on the box.

**3. Verify. You, 2 minutes.**
Open `http://<box-ip>:8080` in a browser and ask it something. In VS Code, Continue's model dropdown shows MiniMax M2.7.

## Already have a box?

If you built from an earlier version of this repo (MiniMax M2.5, 16K context) or have any llama.cpp server running, use [docs/upgrade-guide.md](docs/upgrade-guide.md). Same handoff:

```
Read AGENTS.md and docs/upgrade-guide.md. The box is <user>@<box-ip>.
Upgrade it and give me the final report table.
```

## Reference hardware

GMKtec EVO-X2: AMD Ryzen AI Max+ 395 (16C/32T Zen 5), Radeon 8060S iGPU (gfx1151), 128 GB LPDDR5X-8000 at about 256 GB/s, 2 TB NVMe, 96 GB UMA carveout. Any 128 GB Strix Halo system should behave the same.

## Quick reference (once built)

```bash
ssh <user>@<box-ip>
systemctl status minimax                       # the llama.cpp service
journalctl -u minimax -f | grep print_timing   # per-request prompt and generation timings
radeontop                                      # GPU load
du -sh ~/models/*                              # disk usage by model
```

Or just ask your agent: "check the box".
