#!/bin/bash
# uninstall.sh — remove qwe and optionally its dependencies

INSTALL_DIR="${HOME}/.local/bin"
QWE_CONFIG_DIR="${HOME}/.config/qwe"
LLAMA_SWAP_CONFIG_DIR="${HOME}/.config/llama-swap"

BOLD=$'\e[1m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
RED=$'\e[31m'
CYAN=$'\e[36m'
RESET=$'\e[0m'

info()    { printf "${CYAN}→${RESET} %s\n" "$*"; }
ok()      { printf "${GREEN}✓${RESET} %s\n" "$*"; }
warn()    { printf "${YELLOW}!${RESET} %s\n" "$*"; }
err()     { printf "${RED}✗${RESET} %s\n" "$*"; }

ask() {
    local prompt="$1"
    printf "%s [y/N]: " "$prompt"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

echo ""
printf "${BOLD}qwe uninstaller${RESET}\n"
warn "This will remove qwe and its configuration."
echo ""

# ── 1. Stop running processes ────────────────────────────────────────────────
info "Stopping llama-swap and llama-server..."
swap_pid=$(pgrep -f "llama-swap --config" 2>/dev/null | head -1)
if [[ -n "$swap_pid" ]]; then
    kill "$swap_pid" 2>/dev/null \
        && ok "Stopped llama-swap (PID $swap_pid)" \
        || warn "Could not stop llama-swap (PID $swap_pid)"
else
    ok "llama-swap not running"
fi
while IFS= read -r server_pid; do
    [[ -z "$server_pid" ]] && continue
    kill "$server_pid" 2>/dev/null \
        && ok "Stopped llama-server (PID $server_pid)" \
        || warn "Could not stop llama-server (PID $server_pid)"
done < <(pgrep -f "llama-server" 2>/dev/null)

# ── 2. Remove qwe scripts from ~/.local/bin ──────────────────────────────────
echo ""
info "Removing qwe scripts from $INSTALL_DIR..."
for f in qwe qwe-setup; do
    if [[ -e "$INSTALL_DIR/$f" ]]; then
        rm -f "$INSTALL_DIR/$f"
        ok "Removed $INSTALL_DIR/$f"
    fi
done

# ── 3. Remove qwe config directory ──────────────────────────────────────────
if [[ -d "$QWE_CONFIG_DIR" ]]; then
    rm -rf "$QWE_CONFIG_DIR"
    ok "Removed $QWE_CONFIG_DIR"
fi

# ── 4. Remove PATH entry added by installer ──────────────────────────────────
remove_from_rc() {
    local rc="$1"
    [[ ! -f "$rc" ]] && return
    if grep -qF "# added by qwe installer" "$rc" 2>/dev/null; then
        awk '
            /^# added by qwe installer$/ { skip=1; next }
            skip { skip=0; next }
            { print }
        ' "$rc" > "${rc}.qwe_bak" && mv "${rc}.qwe_bak" "$rc"
        ok "Removed PATH entry from $rc"
    fi
}
remove_from_rc "${ZDOTDIR:-$HOME}/.zshrc"
remove_from_rc "${HOME}/.bashrc"
remove_from_rc "${HOME}/.bash_profile"

# ── Optional: llama-swap config ──────────────────────────────────────────────
echo ""
printf "${BOLD}Optional cleanups:${RESET}\n\n"

if [[ -d "$LLAMA_SWAP_CONFIG_DIR" ]]; then
    if ask "Remove llama-swap config directory ($LLAMA_SWAP_CONFIG_DIR)?"; then
        rm -rf "$LLAMA_SWAP_CONFIG_DIR"
        ok "Removed $LLAMA_SWAP_CONFIG_DIR"
    else
        ok "Kept $LLAMA_SWAP_CONFIG_DIR"
    fi
fi

# ── Optional: uninstall llama-swap binary ────────────────────────────────────
if command -v llama-swap &>/dev/null; then
    llama_swap_bin=$(command -v llama-swap)
    if ask "Uninstall llama-swap ($llama_swap_bin)?"; then
        if command -v brew &>/dev/null && brew list llama-swap &>/dev/null 2>&1; then
            brew uninstall llama-swap \
                && ok "Uninstalled llama-swap via Homebrew" \
                || warn "Homebrew uninstall failed — remove $llama_swap_bin manually"
        elif [[ "$llama_swap_bin" == "${HOME}/.local/bin/"* ]]; then
            rm -f "$llama_swap_bin" && ok "Removed $llama_swap_bin"
        else
            warn "Cannot auto-remove $llama_swap_bin — remove it manually"
        fi
    else
        ok "Kept llama-swap"
    fi
fi

# ── Optional: uninstall llama.cpp ────────────────────────────────────────────
if command -v llama-server &>/dev/null; then
    llama_server_bin=$(command -v llama-server)
    if ask "Uninstall llama.cpp / llama-server ($llama_server_bin)?"; then
        if command -v brew &>/dev/null && brew list llama.cpp &>/dev/null 2>&1; then
            brew uninstall llama.cpp \
                && ok "Uninstalled llama.cpp via Homebrew" \
                || warn "Homebrew uninstall failed — remove $llama_server_bin manually"
        elif [[ "$llama_server_bin" == "${HOME}/.local/bin/"* ]]; then
            rm -f "$llama_server_bin" && ok "Removed $llama_server_bin"
        else
            warn "Cannot auto-remove $llama_server_bin — remove it manually"
        fi
    else
        ok "Kept llama-server"
    fi
fi

# ── Optional: clear HuggingFace model cache ──────────────────────────────────
HF_CACHE_DIR="${HF_HOME:-${HOME}/.cache/huggingface}/hub"
if [[ -d "$HF_CACHE_DIR" ]]; then
    cache_size=$(du -sh "$HF_CACHE_DIR" 2>/dev/null | cut -f1)
    if ask "Clear HuggingFace model cache ($HF_CACHE_DIR, ~${cache_size} on disk)?"; then
        rm -rf "$HF_CACHE_DIR"
        ok "Cleared HuggingFace cache"
    else
        ok "Kept HuggingFace cache ($HF_CACHE_DIR)"
    fi
fi

echo ""
printf "${GREEN}${BOLD}Uninstall complete.${RESET}\n"
printf "Reload your shell to clear the PATH entry: ${BOLD}source ~/.zshrc${RESET}\n\n"
