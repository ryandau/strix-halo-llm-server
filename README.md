# Local coding AI on a Strix Halo mini PC

Self-hosted MiniMax M2.7 on a 128 GB AMD Ryzen AI Max+ 395 box, served by llama.cpp on Vulkan and used from VS Code. Set up by an AI agent from one prompt.

**What you get:** MiniMax M2.7 answering on your own network at about 30 tokens a second, plus fast autocomplete and code search. No cloud, no subscription, works offline.

**How good is it?** Roughly Claude Sonnet 4.5. Fine for everyday coding, weaker on long multi-step jobs.

## Three steps

1. **Set up the box.** About 15 minutes at the keyboard. [Checklist](docs/ready-state.md)
2. **Hand it to your AI agent.** Paste one line, come back in a couple of hours.
   ```
   Read AGENTS.md and docs/build-guide.md. The box is <user>@<box-ip>. Build it.
   ```
3. **Open VS Code.** The model is in Continue's dropdown.

Already have a box from the old version of this repo? [Upgrade guide](docs/upgrade-guide.md).

## Hardware

Any 128 GB Ryzen AI Max+ 395 machine. Built and tested on a GMKtec EVO-X2.

## More

- [Build guide](docs/build-guide.md): every step, every flag, what to expect, what went wrong and how it was fixed.
- [AGENTS.md](AGENTS.md): the rules an agent follows on the box.
