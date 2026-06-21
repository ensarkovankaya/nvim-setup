#!/usr/bin/env bash
#
# Neovim setup installer — platform agnostic (macOS / Linux / Raspberry Pi).
#
# What it does:
#   1. Platform/distro/architecture detection
#   2. System dependencies (git, curl, ripgrep, fd, compiler, clipboard tools)
#   3. Neovim >= 0.11 (native vim.lsp API required)
#   4. lazygit
#   5. Node.js + npm  (for yaml-language-server)
#   6. Go            (for gopls)
#   7. LSP servers: gopls, yaml-language-server
#   8. Nerd Font (JetBrainsMono) — for icons
#   9. Deploy the config to ~/.config/nvim (symlink, backs up the old one)
#  10. Plugin bootstrap (lazy.nvim restore + treesitter parsers)
#
# Usage:  ./install.sh [--copy] [--no-font] [--skip-deps] [--help]
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Settings / flags
# ---------------------------------------------------------------------------
DEPLOY_MODE="symlink"   # "copy" with --copy
INSTALL_FONT="auto"     # "no" with --no-font
SKIP_DEPS="no"          # "yes" with --skip-deps (config + LSP only)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/nvim"
CONFIG_DST="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
NVIM_MIN="0.11"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'
else
  C_RESET=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BOLD=''
fi
step() { printf '\n%s==> %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '    %s! %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
die()  { printf '\n%s✗ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --copy)      DEPLOY_MODE="copy" ;;
    --no-font)   INSTALL_FONT="no" ;;
    --skip-deps) SKIP_DEPS="yes" ;;
    -h|--help)   usage ;;
    *) die "Unknown argument: $1  (see --help)" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# version compare: ver_ge A B  -> is A >= B ?
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

# sudo abstraction
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
elif have sudo; then
  SUDO="sudo"
else
  SUDO=""
fi
as_root() {
  if [ -n "$SUDO" ]; then "$SUDO" "$@"; else "$@"; fi
}

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
OS="" ; DISTRO="" ; PKG="" ; ARCH_RAW="" ; IS_PI="no"
detect_platform() {
  step "Platform detection"
  ARCH_RAW="$(uname -m)"
  case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux)  OS="linux" ;;
    *) die "Unsupported operating system: $(uname -s)" ;;
  esac

  if [ "$OS" = "macos" ]; then
    DISTRO="macos"; PKG="brew"
  else
    if [ -r /etc/os-release ]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      DISTRO="${ID:-linux}"
      case " ${ID:-} ${ID_LIKE:-} " in
        *" raspbian "*|*" rpi "*) IS_PI="yes" ;;
      esac
    fi
    # Raspberry Pi hardware detection (also on Ubuntu/Debian for Pi)
    if grep -qi 'raspberry pi' /proc/cpuinfo 2>/dev/null || grep -qi 'raspberry pi' /sys/firmware/devicetree/base/model 2>/dev/null; then
      IS_PI="yes"
    fi
    if have apt-get;  then PKG="apt"
    elif have dnf;    then PKG="dnf"
    elif have pacman; then PKG="pacman"
    elif have zypper; then PKG="zypper"
    else die "No supported package manager found (apt/dnf/pacman/zypper)"; fi
  fi

  ok "OS=$OS  distro=$DISTRO  arch=$ARCH_RAW  pkg=$PKG  raspberry_pi=$IS_PI"
}

# Architecture -> Go / nvim / lazygit naming
go_arch()      { case "$ARCH_RAW" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; armv7l|armv6l) echo armv6l;; *) echo "";; esac; }
nvim_arch()    { case "$ARCH_RAW" in x86_64|amd64) echo x86_64;; aarch64|arm64) echo arm64;; *) echo "";; esac; }
lazygit_arch() { case "$ARCH_RAW" in x86_64|amd64) echo x86_64;; aarch64|arm64) echo arm64;; armv7l|armv6l) echo armv6;; *) echo "";; esac; }

# ---------------------------------------------------------------------------
# Homebrew (macOS)
# ---------------------------------------------------------------------------
ensure_homebrew() {
  have brew && { ok "Homebrew installed"; return; }
  step "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # add to PATH (Apple Silicon / Intel)
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
  have brew || die "Homebrew installation failed"
}

# ---------------------------------------------------------------------------
# Package install abstraction
# ---------------------------------------------------------------------------
pkg_update_done="no"
pkg_update() {
  [ "$pkg_update_done" = "yes" ] && return
  case "$PKG" in
    apt)    as_root apt-get update -y ;;
    dnf)    : ;;
    pacman) as_root pacman -Sy --noconfirm ;;
    zypper) as_root zypper --non-interactive refresh ;;
    brew)   brew update >/dev/null 2>&1 || true ;;
  esac
  pkg_update_done="yes"
}
pkg_install() {
  pkg_update
  case "$PKG" in
    apt)    as_root apt-get install -y "$@" ;;
    dnf)    as_root dnf install -y "$@" ;;
    pacman) as_root pacman -S --needed --noconfirm "$@" ;;
    zypper) as_root zypper --non-interactive install "$@" ;;
    brew)   brew install "$@" ;;
  esac
}

# ---------------------------------------------------------------------------
# System dependencies
# ---------------------------------------------------------------------------
install_base_deps() {
  step "System dependencies (git, curl, ripgrep, fd, compiler, clipboard)"
  case "$PKG" in
    brew)
      pkg_install git curl ripgrep fd ;;
    apt)
      pkg_install git curl unzip ripgrep fd-find build-essential \
                  xclip wl-clipboard fontconfig
      # Debian/Ubuntu: the binary is named fdfind -> create an fd alias
      if have fdfind && ! have fd; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        ok "fd -> fdfind symlink (~/.local/bin)"
      fi ;;
    dnf)
      pkg_install git curl unzip ripgrep fd-find gcc gcc-c++ make \
                  xclip wl-clipboard fontconfig ;;
    pacman)
      pkg_install git curl unzip ripgrep fd base-devel \
                  xclip wl-clipboard fontconfig ;;
    zypper)
      pkg_install git curl unzip ripgrep fd gcc gcc-c++ make \
                  xclip wl-clipboard fontconfig ;;
  esac
  ok "Base packages done"
}

# ---------------------------------------------------------------------------
# Neovim >= 0.11
# ---------------------------------------------------------------------------
nvim_version() { nvim --version 2>/dev/null | head -1 | sed -E 's/^NVIM v?//'; }

install_neovim() {
  step "Neovim (>= $NVIM_MIN required)"
  if have nvim && ver_ge "$(nvim_version)" "$NVIM_MIN"; then
    ok "Neovim $(nvim_version) is sufficient"
    return
  fi

  if [ "$OS" = "macos" ]; then
    pkg_install neovim
  else
    local arch tarball url dest
    arch="$(nvim_arch)"
    if [ -z "$arch" ]; then
      # 32-bit Pi (armv7l/armv6l): no official binary -> distro package + warning
      warn "No official Neovim binary for this arch ($ARCH_RAW); trying the distro package"
      pkg_install neovim || true
    else
      tarball="nvim-linux-${arch}.tar.gz"
      url="https://github.com/neovim/neovim/releases/latest/download/${tarball}"
      dest="/opt/nvim"
      info "Downloading: $url"
      curl -fsSL "$url" -o /tmp/nvim.tar.gz || die "Failed to download Neovim"
      as_root rm -rf "$dest"
      as_root mkdir -p "$dest"
      as_root tar -xzf /tmp/nvim.tar.gz -C "$dest" --strip-components=1
      as_root ln -sf "$dest/bin/nvim" /usr/local/bin/nvim
      rm -f /tmp/nvim.tar.gz
    fi
  fi

  have nvim || die "Neovim installation failed"
  ver_ge "$(nvim_version)" "$NVIM_MIN" \
    || die "Neovim version $(nvim_version) < $NVIM_MIN. A source build may be needed (especially on 32-bit Pi). https://github.com/neovim/neovim/blob/master/BUILD.md"
  ok "Neovim $(nvim_version) ready"
}

# ---------------------------------------------------------------------------
# lazygit
# ---------------------------------------------------------------------------
install_lazygit() {
  step "lazygit"
  have lazygit && { ok "lazygit installed"; return; }
  if [ "$OS" = "macos" ]; then
    pkg_install lazygit; ok "lazygit ready"; return
  fi
  if [ "$PKG" = "pacman" ]; then
    pkg_install lazygit; ok "lazygit ready"; return
  fi
  local arch ver url
  arch="$(lazygit_arch)"
  [ -z "$arch" ] && { warn "lazygit: no binary for $ARCH_RAW, skipping"; return; }
  ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
        | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')"
  [ -z "$ver" ] && { warn "Could not get lazygit version, skipping"; return; }
  url="https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_${arch}.tar.gz"
  info "Downloading: lazygit v$ver ($arch)"
  curl -fsSL "$url" -o /tmp/lazygit.tar.gz || { warn "Failed to download lazygit"; return; }
  tar -xzf /tmp/lazygit.tar.gz -C /tmp lazygit
  as_root install /tmp/lazygit /usr/local/bin/lazygit
  rm -f /tmp/lazygit.tar.gz /tmp/lazygit
  ok "lazygit ready"
}

# ---------------------------------------------------------------------------
# Node.js + npm  (yaml-language-server)
# ---------------------------------------------------------------------------
install_node() {
  step "Node.js + npm"
  if have node && have npm; then ok "Node $(node -v) installed"; return; fi
  if [ "$OS" = "macos" ]; then
    pkg_install node
  else
    case "$PKG" in
      apt)    pkg_install nodejs npm ;;
      dnf)    pkg_install nodejs npm ;;
      pacman) pkg_install nodejs npm ;;
      zypper) pkg_install nodejs npm ;;
    esac
  fi
  have npm || warn "npm could not be installed; yaml-language-server may be skipped"
}

# ---------------------------------------------------------------------------
# Go  (gopls)
# ---------------------------------------------------------------------------
GO_MIN="1.21"
install_go() {
  step "Go"
  if have go && ver_ge "$(go version | sed -E 's/.*go([0-9.]+).*/\1/')" "$GO_MIN"; then
    ok "Go $(go version | sed -E 's/.*go([0-9.]+).*/\1/') installed"; return
  fi
  if [ "$OS" = "macos" ]; then
    pkg_install go
  else
    local arch ver url
    arch="$(go_arch)"
    [ -z "$arch" ] && { warn "Go: $ARCH_RAW unsupported, trying distro package"; pkg_install golang || pkg_install go || true; return; }
    ver="$(curl -fsSL https://go.dev/VERSION?m=text | head -1)"   # e.g. go1.22.5
    [ -z "$ver" ] && { warn "Could not get Go version, using distro package"; pkg_install golang || true; return; }
    url="https://go.dev/dl/${ver}.linux-${arch}.tar.gz"
    info "Downloading: $ver ($arch)"
    curl -fsSL "$url" -o /tmp/go.tar.gz || { warn "Failed to download Go"; return; }
    as_root rm -rf /usr/local/go
    as_root tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
    export PATH="/usr/local/go/bin:$PATH"
    add_path_line '/usr/local/go/bin'
  fi
  have go && ok "Go $(go version | sed -E 's/.*go([0-9.]+).*/\1/') ready" || warn "Go could not be installed"
}

# ---------------------------------------------------------------------------
# PATH helper: append a line to shell rc (idempotent)
# ---------------------------------------------------------------------------
add_path_line() {
  local dir="$1" line rc
  line="export PATH=\"$dir:\$PATH\""
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -e "$rc" ] || continue
    grep -qF "$dir" "$rc" 2>/dev/null || printf '\n# neovim-setup\n%s\n' "$line" >> "$rc"
  done
}

# ---------------------------------------------------------------------------
# LSP servers
# ---------------------------------------------------------------------------
install_lsp_servers() {
  step "LSP servers: gopls, yaml-language-server"

  # gopls
  export PATH="${PATH}:/usr/local/go/bin:$HOME/go/bin"
  if have go; then
    if have gopls; then
      ok "gopls installed"
    else
      info "Installing gopls (go install)…"
      GOBIN="$HOME/go/bin" go install golang.org/x/tools/gopls@latest \
        && { add_path_line "$HOME/go/bin"; ok "gopls ready (~/go/bin)"; } \
        || warn "gopls could not be installed"
    fi
  else
    warn "No Go → gopls skipped"
  fi

  # yaml-language-server
  if have yaml-language-server; then
    ok "yaml-language-server installed"
  elif have npm; then
    info "Installing yaml-language-server (npm -g)…"
    if npm install -g yaml-language-server >/dev/null 2>&1; then
      ok "yaml-language-server ready"
    elif as_root env PATH="$PATH" npm install -g yaml-language-server >/dev/null 2>&1; then
      ok "yaml-language-server ready (sudo)"
    else
      warn "yaml-language-server could not be installed"
    fi
  else
    warn "No npm → yaml-language-server skipped"
  fi
}

# ---------------------------------------------------------------------------
# Nerd Font (icons)
# ---------------------------------------------------------------------------
install_nerd_font() {
  step "Nerd Font (JetBrainsMono)"
  if [ "$INSTALL_FONT" = "no" ]; then info "--no-font given, skipping"; return; fi
  if [ -n "${SSH_CONNECTION:-}" ] && [ "$INSTALL_FONT" = "auto" ]; then
    warn "SSH/headless session detected → skipping font (install it on the terminal machine). Re-run to force."
    return
  fi
  if [ "$OS" = "macos" ]; then
    brew install --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1 \
      && ok "JetBrainsMono Nerd Font installed" \
      || warn "Font install failed (remember to select 'JetBrainsMono Nerd Font' in your terminal)"
  else
    local dir="$HOME/.local/share/fonts"
    mkdir -p "$dir"
    if curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -o /tmp/JBM.zip; then
      unzip -oq /tmp/JBM.zip -d "$dir/JetBrainsMonoNerd" && rm -f /tmp/JBM.zip
      have fc-cache && fc-cache -f "$dir" >/dev/null 2>&1 || true
      ok "JetBrainsMono Nerd Font installed (~/.local/share/fonts)"
    else
      warn "Failed to download font"
    fi
  fi
  info "Select 'JetBrainsMono Nerd Font' as the font in your terminal profile."
}

# ---------------------------------------------------------------------------
# Config deployment
# ---------------------------------------------------------------------------
deploy_config() {
  step "Config deployment → $CONFIG_DST  (mode: $DEPLOY_MODE)"
  [ -d "$CONFIG_SRC" ] || die "Source config not found: $CONFIG_SRC"
  mkdir -p "$(dirname "$CONFIG_DST")"

  # Back up the existing config (unless it's already our symlink)
  if [ -e "$CONFIG_DST" ] || [ -L "$CONFIG_DST" ]; then
    if [ "$(readlink "$CONFIG_DST" 2>/dev/null)" = "$CONFIG_SRC" ]; then
      ok "Already the correct symlink"
      return
    fi
    local bak
    bak="$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
    mv "$CONFIG_DST" "$bak"
    warn "Old config backed up: $bak"
  fi

  if [ "$DEPLOY_MODE" = "symlink" ]; then
    ln -s "$CONFIG_SRC" "$CONFIG_DST"
    ok "Symlink: $CONFIG_DST → $CONFIG_SRC"
  else
    cp -R "$CONFIG_SRC" "$CONFIG_DST"
    ok "Copied: $CONFIG_DST"
  fi
}

# ---------------------------------------------------------------------------
# Plugin bootstrap
# ---------------------------------------------------------------------------
bootstrap_plugins() {
  step "Plugin bootstrap (lazy.nvim + treesitter)"
  export PATH="${PATH}:/usr/local/go/bin:$HOME/go/bin"
  info "lazy.nvim restore (pinned versions from lazy-lock.json)…"
  nvim --headless "+Lazy! restore" +qa 2>/dev/null || warn "Lazy restore warned (completes on first launch)"
  info "treesitter parsers (go, lua)…"
  nvim --headless -c "lua pcall(function() require('nvim-treesitter').install({'go','lua'}) end)" -c "qa" 2>/dev/null \
    || nvim --headless "+TSUpdate go lua" +qa 2>/dev/null \
    || warn "treesitter parser install skipped (try :TSInstall go lua inside nvim)"
  ok "Plugins installed"
}

# ---------------------------------------------------------------------------
# Doctor — final status summary
# ---------------------------------------------------------------------------
doctor() {
  step "Doctor — install summary"
  export PATH="${PATH}:/usr/local/go/bin:$HOME/go/bin:$HOME/.local/bin"
  local b ver
  for b in nvim git rg fd lazygit node npm go gopls yaml-language-server; do
    if have "$b"; then
      case "$b" in
        nvim) ver="$(nvim_version)" ;;
        go)   ver="$(go version | sed -E 's/.*go([0-9.]+).*/\1/')" ;;
        node) ver="$(node -v)" ;;
        *)    ver="" ;;
      esac
      ok "$(printf '%-22s %s' "$b" "$ver")"
    else
      warn "$(printf '%-22s missing' "$b")"
    fi
  done
  printf '\n%sDone.%s Open Neovim: %snvim%s  (plugins sync on first launch)\n' \
    "$C_BOLD$C_GREEN" "$C_RESET" "$C_BOLD" "$C_RESET"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  printf '%sNeovim setup installer%s\n' "$C_BOLD" "$C_RESET"
  detect_platform
  [ "$OS" = "macos" ] && ensure_homebrew

  if [ "$SKIP_DEPS" = "no" ]; then
    install_base_deps
    install_neovim
    install_lazygit
    install_node
    install_go
  else
    warn "--skip-deps: system dependencies skipped"
    have nvim && ver_ge "$(nvim_version)" "$NVIM_MIN" || die "Neovim >= $NVIM_MIN required (must already be present with --skip-deps)"
  fi

  install_lsp_servers
  install_nerd_font
  deploy_config
  bootstrap_plugins
  doctor
}

main "$@"
