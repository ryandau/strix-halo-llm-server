# Local coding AI on a Strix Halo mini PC

Self-hosted Qwen3.8-27B on a [128 GB AMD Ryzen AI Max+ 395](https://www.gmktec.com/products/amd-ryzen%E2%84%A2-ai-max-395-evo-x2-ai-mini-pc?variant=46826048585882) box, served by llama.cpp on Vulkan and used from VS Code through Kilo Code. Set up by an AI agent from one prompt.

**What you get:** a 128K-context coding model answering on your own network at 17 to 19 tokens a second, with tool calling that works in an agent harness. No cloud, no subscription, works offline.

**How good is it?** Qwen3.8-27B scores 34 on the [Artificial Analysis Intelligence Index](https://artificialanalysis.ai/models/qwen3-8-27b), first of 142 open-weight models in its size class (median 8). The vendor reports 61.7 on SWE-bench Pro and 90.3 on LiveCodeBench v6. This build runs it at Q6_K, which is close to lossless, so those numbers largely carry over. It is good at everyday coding, shell and systems work, and multi-step agent tasks up to about 60K tokens of context. Past that it slows down sharply.

## Three steps

1. **Set up the box.** About 15 minutes at the keyboard. [Checklist](docs/ready-state.md)
2. **Hand it to your AI agent.** Paste one line, come back in about an hour.
   ```
   Read AGENTS.md and docs/build-guide.md. The box is <user>@<box-ip>. Build it.
   ```
3. **Open VS Code.** The model is in Kilo Code's model picker.

Already have a box from the previous version of this repo (MiniMax M2.7)? [Upgrade guide](docs/upgrade-guide.md).

## Hardware

Any 128 GB Ryzen AI Max+ 395 machine. Built and tested on a GMKtec EVO-X2. The model itself needs only about 28 GB of GPU memory, so a 64 GB machine would also work.

## More

- [Build guide](docs/build-guide.md): every step, every flag, what to expect, what went wrong and how it was fixed.
- [AGENTS.md](AGENTS.md): the rules an agent follows on the box.
