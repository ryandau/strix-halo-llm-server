# Your own coding AI on a small desktop PC

This guide turns a [GMKtec EVO-X2](https://www.gmktec.com/products/amd-ryzen%E2%84%A2-ai-max-395-evo-x2-ai-mini-pc?variant=46826048585882) (or any PC with the same AMD Ryzen AI Max+ 395 chip and 128 GB of memory) into a coding assistant that runs entirely in your home or office. It works inside VS Code, and an AI agent does the setup for you from a single instruction.

**What you get**

- A capable coding assistant that answers from a box on your own network.
- No subscription, no usage limits, works with the internet off.
- It writes and edits code, runs commands, and reads your project, the same way the cloud tools do.
- It remembers a long working session, roughly the length of a short novel, before it needs to start fresh.

**How good is it?**

The model is Qwen3.8-27B. Among free, downloadable models of its size it currently ranks first on the [Artificial Analysis](https://artificialanalysis.ai/models/qwen3-8-27b) leaderboard. It handles everyday coding, shell scripting and systems work well, and can carry out multi-step tasks on its own. Frontier models are still stronger on long, complicated jobs. It answers at about 17 to 19 words a second, a comfortable reading pace.

**What it costs**

The hardware, once. The model and all the software are free.

## Three steps

1. **Set up the box.** About 15 minutes at the keyboard, mostly installing Ubuntu. [Checklist](docs/ready-state.md)
2. **Hand it to your AI agent.** Paste one line, come back in about an hour.
   ```
   Read AGENTS.md and docs/build-guide.md. The box is <user>@<box-ip>. Build it.
   ```
3. **Open VS Code.** Pick the model in [Kilo Code](https://kilocode.ai) and start working.

## Hardware

Any PC with an AMD Ryzen AI Max+ 395 and 128 GB of memory. Built and tested on a GMKtec EVO-X2. The model only needs about 28 GB, so a 64 GB machine works too.

## More

- [Build guide](docs/build-guide.md): every step and setting, what to expect, and what went wrong along the way and how it was fixed.
- [AGENTS.md](AGENTS.md): the rules the AI agent follows while it works on the box.
