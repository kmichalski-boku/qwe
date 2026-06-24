#!/bin/bash
# install.sh — install qwe to ~/.local/bin, install dependencies, and configure
#
# Options:
#   --force-brew   Force Homebrew for all components (where available)
#   --force-git    Force GitHub binary download for all components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.local/bin"
QWE_CONFIG_DIR="${HOME}/.config/qwe"
INSTALL_STATE_FILE="${QWE_CONFIG_DIR}/install-state"

FORCE_METHOD=""  # brew | git | "" (auto)

for arg in "$@"; do
    case "$arg" in
        --force-brew) FORCE_METHOD="brew" ;;
        --force-git)  FORCE_METHOD="git"  ;;
        *)
            printf "Unknown option: %s\n" "$arg" >&2
            printf "Usage: %s [--force-brew|--force-git]\n" "$0" >&2
            exit 1
            ;;
    esac
done

BOLD=$'\e[1m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
RED=$'\e[31m'
CYAN=$'\e[36m'
RESET=$'\e[0m'

info()  { printf "${CYAN}→${RESET} %s\n" "$*"; }
ok()    { printf "${GREEN}✓${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}!${RESET} %s\n" "$*" >&2; }
err()   { printf "${RED}✗${RESET} %s\n" "$*" >&2; }
step()  { printf "\n${BOLD}%s${RESET}\n" "$*"; }

echo ""
printf "${BOLD}qwe installer${RESET}"
[[ -n "$FORCE_METHOD" ]] && printf "  ${CYAN}(forcing: %s)${RESET}" "$FORCE_METHOD"
printf "\n\n"

# 1. Create ~/.local/bin if needed
mkdir -p "$INSTALL_DIR"

# 2. Symlink qwe and qwe-setup
info "Installing qwe → $SCRIPT_DIR/qwe"
ln -sf "$SCRIPT_DIR/qwe"       "$INSTALL_DIR/qwe"
ln -sf "$SCRIPT_DIR/qwe-setup" "$INSTALL_DIR/qwe-setup"
chmod +x "$SCRIPT_DIR/qwe" "$SCRIPT_DIR/qwe-setup"
ok "Symlinks created in $INSTALL_DIR"

# 3. Add ~/.local/bin to PATH in shell rc files
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

# --- OS / arch detection -------------------------------------------------------
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)   echo "x86_64" ;;
        aarch64|arm64)  echo "arm64" ;;
        *)              echo "$(uname -m)" ;;
    esac
}

# --- install helpers -----------------------------------------------------------
install_with_brew() {
    local pkg="$1"
    command -v brew &>/dev/null || return 1
    info "Installing $pkg via Homebrew..."
    brew install "$pkg"
}

install_llama_swap_brew() {
    command -v brew &>/dev/null || return 1
    info "Tapping mostlygeek/llama-swap..."
    brew tap mostlygeek/llama-swap
    # Homebrew 4.4+ requires explicit trust for third-party taps
    brew trust mostlygeek/llama-swap 2>/dev/null || true
    info "Installing llama-swap via Homebrew..."
    brew install mostlygeek/llama-swap/llama-swap
}

download_llama_server_linux() {
    local arch
    arch=$(detect_arch)
    mkdir -p "$INSTALL_DIR"

    info "Fetching latest llama.cpp release for linux-$arch..."
    local release_url
    release_url=$(curl -sf "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*linux[^"]*'"$arch"'[^"]*"' \
        | grep -v 'rpc\|mpi\|sycl' \
        | head -1 \
        | grep -o 'https://[^"]*')

    if [[ -z "$release_url" ]]; then
        err "Could not find a linux-$arch llama.cpp binary. Please install manually."
        return 1
    fi

    local tmp_zip
    tmp_zip=$(mktemp -d)
    info "Downloading $release_url..."
    curl -L --progress-bar -o "$tmp_zip/llama.zip" "$release_url"
    unzip -q "$tmp_zip/llama.zip" -d "$tmp_zip/llama"
    local server_bin
    server_bin=$(find "$tmp_zip/llama" -name "llama-server" -type f | head -1)
    if [[ -z "$server_bin" ]]; then
        err "llama-server binary not found in archive."
        rm -rf "$tmp_zip"
        return 1
    fi
    cp "$server_bin" "$INSTALL_DIR/llama-server"
    chmod +x "$INSTALL_DIR/llama-server"
    rm -rf "$tmp_zip"
    ok "llama-server installed to $INSTALL_DIR/llama-server"
}

download_llama_swap_binary() {
    local arch
    arch=$(detect_arch)
    local os
    os=$(detect_os)
    mkdir -p "$INSTALL_DIR"

    local go_os="linux"
    [[ "$os" == "macos" ]] && go_os="darwin"
    local go_arch="amd64"
    [[ "$arch" == "arm64" ]] && go_arch="arm64"

    info "Fetching latest llama-swap release..."
    local release_url
    release_url=$(curl -sf "https://api.github.com/repos/mostlygeek/llama-swap/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*'"${go_os}_${go_arch}"'[^"]*"' \
        | head -1 \
        | grep -o 'https://[^"]*')

    if [[ -z "$release_url" ]]; then
        err "Could not find a llama-swap binary for ${go_os}_${go_arch}."
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local filename
    filename=$(basename "$release_url")

    info "Downloading $release_url..."
    curl -L --progress-bar -o "$tmp_dir/$filename" "$release_url"

    if [[ "$filename" == *.tar.gz ]]; then
        tar xzf "$tmp_dir/$filename" -C "$tmp_dir"
        local binary
        binary=$(find "$tmp_dir" -name "llama-swap" -not -name "*.tar.gz" -type f | head -1)
        if [[ -z "$binary" ]]; then
            err "llama-swap binary not found in archive."
            rm -rf "$tmp_dir"
            return 1
        fi
        cp "$binary" "$INSTALL_DIR/llama-swap"
    else
        cp "$tmp_dir/$filename" "$INSTALL_DIR/llama-swap"
    fi

    chmod +x "$INSTALL_DIR/llama-swap"
    rm -rf "$tmp_dir"
    ok "llama-swap installed to $INSTALL_DIR/llama-swap"
}

# --- install dependencies ------------------------------------------------------
# Populated by install_dependencies(); written to INSTALL_STATE_FILE afterwards.
LLAMA_SERVER_METHOD=""
LLAMA_SWAP_METHOD=""
JQ_METHOD=""

install_dependencies() {
    local os
    os=$(detect_os)

    # ── llama-server ──────────────────────────────────────────────────────────
    step "Installing llama-server (llama.cpp)"
    if command -v llama-server &>/dev/null; then
        ok "llama-server already installed: $(command -v llama-server)"
        LLAMA_SERVER_METHOD="system"
    else
        case "$os" in
            macos)
                if [[ "$FORCE_METHOD" == "git" ]]; then
                    warn "Binary download not supported for macOS llama-server; using Homebrew."
                fi
                install_with_brew llama.cpp || { err "Homebrew install failed."; return 1; }
                ok "llama-server installed."
                LLAMA_SERVER_METHOD="brew"
                ;;
            linux)
                case "$FORCE_METHOD" in
                    git)
                        download_llama_server_linux || return 1
                        LLAMA_SERVER_METHOD="git"
                        ;;
                    brew)
                        install_with_brew llama.cpp || { err "Homebrew install failed."; return 1; }
                        LLAMA_SERVER_METHOD="brew"
                        ;;
                    *)
                        if command -v brew &>/dev/null && install_with_brew llama.cpp; then
                            LLAMA_SERVER_METHOD="brew"
                        elif download_llama_server_linux; then
                            LLAMA_SERVER_METHOD="git"
                        else
                            return 1
                        fi
                        ;;
                esac
                ;;
            *)
                err "Unsupported OS. Install llama.cpp manually."
                return 1
                ;;
        esac
    fi

    # ── llama-swap ────────────────────────────────────────────────────────────
    step "Installing llama-swap"
    if command -v llama-swap &>/dev/null; then
        ok "llama-swap already installed: $(command -v llama-swap)"
        LLAMA_SWAP_METHOD="system"
    else
        case "$FORCE_METHOD" in
            brew)
                install_llama_swap_brew || { err "Homebrew install failed."; return 1; }
                LLAMA_SWAP_METHOD="brew"
                ;;
            git)
                download_llama_swap_binary || return 1
                LLAMA_SWAP_METHOD="git"
                ;;
            *)
                # auto: brew preferred, git as fallback
                local brew_ok=0
                case "$os" in
                    macos)         install_llama_swap_brew && brew_ok=1 ;;
                    linux)
                        command -v brew &>/dev/null && install_llama_swap_brew && brew_ok=1 ;;
                esac
                if [[ "$brew_ok" -eq 1 ]]; then
                    LLAMA_SWAP_METHOD="brew"
                elif download_llama_swap_binary; then
                    LLAMA_SWAP_METHOD="git"
                else
                    err "Could not install llama-swap."
                    return 1
                fi
                ;;
        esac
        command -v llama-swap &>/dev/null && ok "llama-swap installed."
    fi

    # ── jq ────────────────────────────────────────────────────────────────────
    step "Installing jq"
    if command -v jq &>/dev/null; then
        ok "jq already installed."
        JQ_METHOD="system"
    else
        case "$os" in
            macos)
                install_with_brew jq && JQ_METHOD="brew"
                ;;
            linux)
                if command -v apt-get &>/dev/null; then
                    sudo apt-get install -y jq && JQ_METHOD="apt"
                elif command -v brew &>/dev/null; then
                    install_with_brew jq && JQ_METHOD="brew"
                else
                    err "Could not install jq. Install it manually."
                fi
                ;;
        esac
    fi
}

save_install_state() {
    mkdir -p "$QWE_CONFIG_DIR"
    cat > "$INSTALL_STATE_FILE" <<STATE
LLAMA_SERVER_METHOD=${LLAMA_SERVER_METHOD}
LLAMA_SWAP_METHOD=${LLAMA_SWAP_METHOD}
JQ_METHOD=${JQ_METHOD}
STATE
    ok "Install state saved to $INSTALL_STATE_FILE"
}

# 4. Install dependencies
echo ""
install_dependencies || { err "Dependency installation failed. Aborting."; exit 1; }

# 5. Save install state (used by uninstall.sh to know how to clean up)
save_install_state

# 6. Run qwe-setup wizard (configure llama-swap and qwe)
echo ""
if command -v qwe &>/dev/null || [[ -x "$INSTALL_DIR/qwe" ]]; then
    printf "${GREEN}${BOLD}Dependencies ready.${RESET} Running setup wizard...\n\n"
    "$INSTALL_DIR/qwe-setup" wizard
else
    printf "qwe installed but not yet in PATH for this session.\n"
    printf "Run: ${BOLD}source ~/.zshrc${RESET}  then: ${BOLD}qwe setup${RESET}\n\n"
fi
