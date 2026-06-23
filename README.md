# qwe

A fast, terminal-native CLI for asking local LLMs questions — no cloud, no subscription, no latency beyond your own GPU.

Built on [llama.cpp](https://github.com/ggml-org/llama.cpp) + [llama-swap](https://github.com/mostlygeek/llama-swap). You pick a model tier, `qwe` handles loading, hot-swapping, and server management automatically.

```
qwe "how do I sort a list of dicts by a key in python"
```

## Features

- **Four model tiers** — switch between fast/small and slow/smart with a single word
- **Smart spinner** — shows "Downloading", "Loading model", or "Generating" based on actual server state
- **Auto-start** — starts llama-swap automatically if nothing is running
- **Hot-swap** — switching tiers loads the new model immediately, no restart needed
- **Stop command** — `qwe stop` kills the server and frees GPU/RAM when you're done

## Model tiers

| Command | Model | RAM |
|---------|-------|-----|
| `qwe light` | Gemma 4 4B QAT-Q4 | ~3 GB |
| `qwe balanced` | Gemma 4 12B QAT-Q4 | ~8 GB |
| `qwe balanced+` | Gemma 4 12B UD-Q8\_K\_XL | ~14 GB |
| `qwe smart` | Qwen3.6 35B UD-Q6\_K | ~28 GB |

Models are downloaded from HuggingFace on first use and cached locally. Switching tiers persists your choice across sessions.

## Requirements

- macOS (Apple Silicon or x86) or Linux
- GPU recommended (Apple Metal, CUDA, or ROCm) — CPU-only works but is slow
- `curl`, `jq` — installed automatically via Homebrew if missing
- [llama.cpp](https://github.com/ggml-org/llama.cpp) — installed automatically
- [llama-swap](https://github.com/mostlygeek/llama-swap) — installed automatically

## Installation

```bash
git clone https://github.com/your-username/qwe.git
cd qwe
bash install.sh
```

`install.sh` will:
1. Symlink `qwe` and `qwe-setup` into `~/.local/bin/`
2. Add `~/.local/bin` to `PATH` in `~/.zshrc` (and `~/.bashrc` / `~/.bash_profile` if present)
3. Launch the interactive setup wizard to install dependencies and configure llama-swap

On first run the wizard will ask you which model tier to default to. The model downloads automatically when you first query it.

### What gets installed where

| Path | Purpose |
|------|---------|
| `~/.local/bin/qwe` | Main CLI (symlink → cloned repo) |
| `~/.local/bin/qwe-setup` | Setup helper (symlink → cloned repo) |
| `~/.config/qwe/config` | Active tier and endpoint |
| `~/.config/qwe/llama-swap.pid` | llama-swap PID for stop/restart |
| `~/.config/qwe/llama-swap.log` | llama-swap log output |
| `~/.config/llama-swap/config.yaml` | llama-swap model profiles |
| `~/.config/llama-swap/qwen3.6-froggeric.jinja` | Qwen3 chat template (smart tier) |
| `~/.cache/huggingface/hub/` | Downloaded model files (can be large) |

Because the scripts are symlinked from the repo, `git pull` in the project directory updates `qwe` immediately — no reinstall needed.

## Usage

```
qwe [question]         Ask a question (interactive prompt if omitted)
qwe light              Switch to light model  (~3 GB RAM, Gemma 4E4B)
qwe balanced           Switch to balanced     (~8 GB RAM, Gemma 4-12B)
qwe balanced+          Switch to balanced+    (~14 GB RAM, Gemma 4-12B Q8)
qwe smart              Switch to smart        (~28 GB RAM, Qwen3.6-35B Q6)
qwe setup              Run the interactive setup wizard
qwe status             Show current tier, endpoint, and server state
qwe stop               Kill llama-swap and llama-server (free RAM)
qwe --help             Show this help
```

### Examples

```bash
# Ask a question directly
qwe "how do I reverse a string in python"

# Interactive mode (prompts for input)
qwe

# Switch to a heavier model for harder questions
qwe smart
qwe "explain the tradeoffs between RAFT and Paxos"

# Free GPU memory when done
qwe stop

# Check what's running
qwe status
```

## Updating

```bash
cd /path/to/qwe   # wherever you cloned it
git pull
```

No reinstall needed — the symlinks already point to the updated files.

## Uninstall

```bash
bash uninstall.sh
```

Removes `qwe`, its config, and the PATH entry from your shell rc. You will be prompted separately for:
- llama-swap config (`~/.config/llama-swap/`)
- llama-swap binary
- llama.cpp / llama-server binary
- HuggingFace model cache (`~/.cache/huggingface/hub/`) — can be tens of GB

## How it works

`qwe` is a bash script that talks to [llama-swap](https://github.com/mostlygeek/llama-swap), a lightweight Go proxy that manages `llama-server` processes. llama-swap hot-swaps models on demand: when you switch tiers, the old model unloads and the new one starts — you never touch config files or restart anything.

The spinner polls llama-swap's `/running` endpoint every ~2 seconds and shows what's actually happening: downloading a model for the first time, loading it from disk, or generating a response.

The smart tier (Qwen3.6 35B) uses a [custom froggeric Qwen3 chat template](https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates) to disable chain-of-thought thinking for faster, more direct responses. The Gemma tiers disable thinking via `--chat-template-kwargs` directly.
