# CLAUDE.md — qwe project guide

This file gives an LLM working in this repo the context needed to make good decisions without asking unnecessary questions.

## What this project is

`qwe` is a two-file bash CLI that lets a user ask questions to a local LLM from the terminal. It manages the full stack: installing dependencies, generating llama-swap config, starting the server daemon, and sending queries — all through a single command.

The two scripts are:
- `qwe` — the user-facing CLI (query, tier switch, status, stop)
- `qwe-setup` — the install/config companion (wizard, ensure-profile, start daemon)

`qwe` calls `qwe-setup` for setup tasks; they are always installed side by side in `~/.local/bin/` as symlinks back to the cloned repo.

## Stack

| Component | Role |
|-----------|------|
| **llama-server** (llama.cpp) | Runs inference; downloads models from HuggingFace on first use |
| **llama-swap** | Hot-swap proxy — manages llama-server processes, serves OpenAI-compatible API on `localhost:8080` |
| `qwe` | Talks to llama-swap via `/v1/chat/completions`; manages config and daemon lifecycle |

## File layout

```
qwe             — main CLI script
qwe-setup       — install/configure/start helper
install.sh      — one-shot installer: symlinks, PATH, runs wizard
uninstall.sh    — full removal with optional dependency cleanup
README.md       — user-facing docs
CLAUDE.md       — this file
```

Runtime files (not in repo):

```
~/.config/qwe/config              — active tier (MODEL_TIER) + endpoint (ENDPOINT)
~/.config/qwe/llama-swap.pid      — PID of the running llama-swap process
~/.config/qwe/llama-swap.log      — llama-swap stdout/stderr
~/.config/llama-swap/config.yaml  — llama-swap model profiles (managed by qwe-setup)
~/.config/llama-swap/qwen3.6-froggeric.jinja  — Qwen3 chat template (smart tier)
~/.cache/huggingface/hub/         — model files downloaded by llama-server
```

## Model tiers

| Tier | llama-swap profile | HuggingFace repo | RAM |
|------|--------------------|-----------------|-----|
| `light` | `qwe-light` | google/gemma-4-E4B-it-qat-q4_0-gguf | ~3 GB |
| `balanced` | `qwe-balanced` | google/gemma-4-12B-it-qat-q4_0-gguf | ~8 GB |
| `balanced+` | `qwe-balanced-plus` | unsloth/gemma-4-12b-it-GGUF:UD-Q8_K_XL | ~14 GB |
| `smart` | `qwe-smart` | unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q6_K | ~28 GB |

Profile names are prefixed `qwe-` to avoid collisions with any other llama-swap profiles on the user's machine.

## Key design decisions

### Bash 3.2 compatibility
macOS ships bash 3.2 as the default shell. `declare -A` (associative arrays) was added in bash 4 — using it silently breaks on macOS without Homebrew bash. All tier lookups use `case`-based functions (`tier_profile`, `tier_hf`, `tier_ram`, `tier_ctx`, `tier_name`, `tier_description`) instead. Both `qwe` and `qwe-setup` maintain identical copies of these functions.

### Two-script architecture
The installer/daemon logic lives in `qwe-setup` rather than `qwe` so that `qwe` stays fast and minimal. `qwe` calls `qwe-setup` by looking for it alongside itself (`dirname $(realpath $0)/qwe-setup`) and falls back to `qwe-setup` on PATH. This means both symlinks must be installed together.

### llama-swap as the server layer
llama-swap was chosen over running llama-server directly because it hot-swaps models on demand — switching tiers does not require a restart. `qwe` sends a 1-token warmup request immediately after a tier switch (eager hot-swap) so the model is ready by the time the user asks a real question.

### Config reload via SIGHUP
When `qwe-setup ensure-profile` adds a new profile to `config.yaml`, it sends `SIGHUP` to the running llama-swap process. llama-swap reloads its config on SIGHUP without restarting, so the new profile becomes available immediately with no downtime.

### Profile insertion before `startPort:` / `hooks:`
llama-swap's YAML structure requires all model profiles to appear inside the `models:` block, which ends at the first top-level key (`startPort:`, `hooks:`, or `groups:`). Appending to EOF would place profiles after that key and they would be silently ignored. `cmd_ensure_profile` finds the first such key with `grep -n` and uses `head`/`tail` to insert before it.

### Smart spinner with contextual labels
The spinner polls `GET /running` on the llama-swap endpoint every ~2 seconds (every 25 animation frames × 80ms). It maps llama-swap's `state` field to user-friendly labels:
- `starting` + model not cached → "Downloading model (first run, may take a few minutes)"
- `starting` + model cached → "Loading model into memory"
- `ready` → "Generating response"

Each redraw uses `\r\e[K` (carriage return + erase-to-end-of-line) so switching from a long label to a short one doesn't leave trailing characters on screen. The correct endpoint is `/running` (not `/api/models` or `/v1/models`) — only `/running` exposes per-model `state`.

### HuggingFace cache detection with `find -L`
llama-server caches models under `~/.cache/huggingface/hub/models--{org}--{repo}/`. The actual `.gguf` files live in `blobs/` and are referenced via symlinks in `snapshots/`. A plain `find` won't follow those symlinks and reports 0 results even when files are present — `find -L` is required.

### Thinking suppression per model family
- **Gemma tiers**: `--chat-template-kwargs '{"enable_thinking":false}'` passed directly to llama-server disables chain-of-thought at the server level.
- **Smart tier (Qwen3.6)**: Uses a custom [froggeric chat template](https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates) that responds to a `<|think_off|>` token in the system prompt. The template is downloaded to `~/.config/llama-swap/qwen3.6-froggeric.jinja` and referenced via the `${template}` macro in `config.yaml`. The `--chat-template-kwargs` approach does not work reliably for Qwen3 with llama-server.

### install.sh uses symlinks, not copies
`install.sh` creates symlinks from `~/.local/bin/qwe` → the cloned repo rather than copying the scripts. This means `git pull` in the project directory updates both scripts immediately with no reinstall step.

### PATH marker for clean uninstall
The installer appends a two-line block to `~/.zshrc` (and `~/.bashrc`/`~/.bash_profile` if present):
```
# added by qwe installer
export PATH="$HOME/.local/bin:$PATH"
```
The marker line lets `uninstall.sh` find and remove exactly these two lines with `awk`, without touching any other PATH configuration the user may have.

## Things to keep in sync

When modifying tier definitions (models, context sizes, HuggingFace repos):
- Update `tier_profile`, `tier_hf`, `tier_ram`, `tier_ctx`, `tier_name`, `tier_description` in **both** `qwe` and `qwe-setup` — they are independent scripts and share no state.
- Update the model tier table in `README.md`.

When adding a new subcommand to `qwe`:
- Add it to the `case` dispatch at the bottom of `qwe`.
- Add it to `cmd_help()`.
- Add it to the usage table in `README.md`.

## llama-swap config structure

Generated configs follow this structure:
```yaml
macros:          # named substitutions expanded by llama-swap (${macro-name})
  llama-server: "/path/to/llama-server"
  common-flags: >  # multiline YAML scalar — used only by qwe-smart
    ...

models:          # one entry per tier; must come before startPort/hooks/groups
  qwe-light:
    name: "..."         # shown in llama-swap dashboard
    description: "..."  # shown in llama-swap dashboard
    cmd: |
      ${llama-server}
      ...
    ttl: 7200           # seconds before idle model is unloaded (2 hours)

startPort: 9999  # llama-server processes get ports counting down from here

hooks:
  on_startup:
    preload:
      - "qwe-light"    # profile to load immediately when llama-swap starts
```

`qwe-setup ensure-profile` only adds profiles — it never rewrites or removes existing ones, so user customisations to `config.yaml` are preserved.
