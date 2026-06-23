#!/bin/bash
# install.sh — install qwe to ~/.local/bin and configure shell PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.local/bin"

BOLD=$'\e[1m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
CYAN=$'\e[36m'
RESET=$'\e[0m'

info() { printf "${CYAN}→${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}!${RESET} %s\n" "$*"; }

echo ""
printf "${BOLD}qwe installer${RESET}\n\n"

# 1. Create ~/.local/bin if needed
mkdir -p "$INSTALL_DIR"

# 2. Remove old ai2 symlinks if upgrading from the old name
for old in ai2 ai2-setup; do
    if [[ -L "$INSTALL_DIR/$old" ]]; then
        rm -f "$INSTALL_DIR/$old"
        ok "Removed old symlink: $old"
    fi
done

# 3. Symlink qwe and qwe-setup
info "Installing qwe → $SCRIPT_DIR/qwe"
ln -sf "$SCRIPT_DIR/qwe"       "$INSTALL_DIR/qwe"
ln -sf "$SCRIPT_DIR/qwe-setup" "$INSTALL_DIR/qwe-setup"
chmod +x "$SCRIPT_DIR/qwe" "$SCRIPT_DIR/qwe-setup"
ok "Symlinks created in $INSTALL_DIR"

# 4. Migrate old ~/.config/ai2 config if present and no qwe config exists yet
OLD_CONFIG="${HOME}/.config/ai2/config"
NEW_CONFIG_DIR="${HOME}/.config/qwe"
if [[ -f "$OLD_CONFIG" ]] && [[ ! -d "$NEW_CONFIG_DIR" ]]; then
    printf "\nFound old ai2 config. Migrate to qwe? [Y/n]: "
    read -r migrate
    if [[ "$migrate" != "n" && "$migrate" != "N" ]]; then
        mkdir -p "$NEW_CONFIG_DIR"
        cp "$OLD_CONFIG" "$NEW_CONFIG_DIR/config"
        ok "Migrated config to $NEW_CONFIG_DIR/config"
    fi
fi

# 5. Add ~/.local/bin to PATH in shell rc files
PATH_MARKER="# added by qwe installer"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

add_to_shell_rc() {
    local rc="$1"
    [[ ! -f "$rc" ]] && return
    if grep -qF "$PATH_MARKER" "$rc" 2>/dev/null; then
        ok "PATH already configured in $rc"
    elif grep -qF '$HOME/.local/bin' "$rc" 2>/dev/null || \
         grep -qF "${HOME}/.local/bin" "$rc" 2>/dev/null; then
        ok "~/.local/bin already in $rc"
    else
        printf '\n%s\n%s\n' "$PATH_MARKER" "$PATH_LINE" >> "$rc"
        ok "Added ~/.local/bin to PATH in $rc"
    fi
}

echo ""
info "Configuring shell PATH..."
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
add_to_shell_rc "$ZSHRC"
[[ -f "${HOME}/.bashrc" ]]       && add_to_shell_rc "${HOME}/.bashrc"
[[ -f "${HOME}/.bash_profile" ]] && add_to_shell_rc "${HOME}/.bash_profile"

# 6. Check if qwe is reachable in current session
echo ""
if command -v qwe &>/dev/null || [[ -x "$INSTALL_DIR/qwe" ]]; then
    printf "${GREEN}${BOLD}Ready.${RESET} Running setup wizard...\n\n"
    # Use full path in case PATH hasn't been reloaded yet
    "$INSTALL_DIR/qwe-setup" wizard
else
    warn "qwe installed but not yet in PATH for this session."
    printf "Run: ${BOLD}source ~/.zshrc${RESET}  then: ${BOLD}qwe setup${RESET}\n\n"
fi
