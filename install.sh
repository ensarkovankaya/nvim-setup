#!/usr/bin/env bash
#
# Neovim setup installer — platform agnostic (macOS / Linux / Raspberry Pi).
#
# Yaptıkları:
#   1. Platform/dağıtım/mimari tespiti
#   2. Sistem bağımlılıkları (git, curl, ripgrep, fd, derleyici, pano araçları)
#   3. Neovim >= 0.11 (native vim.lsp API gerekli)
#   4. lazygit
#   5. Node.js + npm  (yaml-language-server için)
#   6. Go            (gopls için)
#   7. LSP sunucuları: gopls, yaml-language-server
#   8. Nerd Font (JetBrainsMono) — ikonlar için
#   9. Config'i ~/.config/nvim altına yerleştirme (symlink, eskisini yedekler)
#  10. Plugin bootstrap (lazy.nvim restore + treesitter parser)
#
# Kullanım:  ./install.sh [--copy] [--no-font] [--skip-deps] [--help]
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Ayarlar / bayraklar
# ---------------------------------------------------------------------------
DEPLOY_MODE="symlink"   # --copy ile "copy"
INSTALL_FONT="auto"     # --no-font ile "no"
SKIP_DEPS="no"          # --skip-deps ile "yes" (yalnız config + LSP)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/nvim"
CONFIG_DST="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
NVIM_MIN="0.11"

# ---------------------------------------------------------------------------
# Loglama
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
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------------------
# Argüman ayrıştırma
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --copy)      DEPLOY_MODE="copy" ;;
    --no-font)   INSTALL_FONT="no" ;;
    --skip-deps) SKIP_DEPS="yes" ;;
    -h|--help)   usage ;;
    *) die "Bilinmeyen argüman: $1  (--help için bak)" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Yardımcılar
# ---------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# sürüm karşılaştırma: ver_ge A B  -> A >= B mı?
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

# sudo soyutlaması
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
# Platform tespiti
# ---------------------------------------------------------------------------
OS="" ; DISTRO="" ; PKG="" ; ARCH_RAW="" ; IS_PI="no"
detect_platform() {
  step "Platform tespiti"
  ARCH_RAW="$(uname -m)"
  case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux)  OS="linux" ;;
    *) die "Desteklenmeyen işletim sistemi: $(uname -s)" ;;
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
    # Raspberry Pi donanım tespiti (Ubuntu/Debian Pi üzerinde de)
    if grep -qi 'raspberry pi' /proc/cpuinfo 2>/dev/null || grep -qi 'raspberry pi' /sys/firmware/devicetree/base/model 2>/dev/null; then
      IS_PI="yes"
    fi
    if have apt-get;  then PKG="apt"
    elif have dnf;    then PKG="dnf"
    elif have pacman; then PKG="pacman"
    elif have zypper; then PKG="zypper"
    else die "Desteklenen paket yöneticisi bulunamadı (apt/dnf/pacman/zypper)"; fi
  fi

  ok "OS=$OS  distro=$DISTRO  arch=$ARCH_RAW  pkg=$PKG  raspberry_pi=$IS_PI"
}

# Mimari -> Go / nvim / lazygit isimlendirmesi
go_arch()      { case "$ARCH_RAW" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; armv7l|armv6l) echo armv6l;; *) echo "";; esac; }
nvim_arch()    { case "$ARCH_RAW" in x86_64|amd64) echo x86_64;; aarch64|arm64) echo arm64;; *) echo "";; esac; }
lazygit_arch() { case "$ARCH_RAW" in x86_64|amd64) echo x86_64;; aarch64|arm64) echo arm64;; armv7l|armv6l) echo armv6;; *) echo "";; esac; }

# ---------------------------------------------------------------------------
# Homebrew (macOS)
# ---------------------------------------------------------------------------
ensure_homebrew() {
  have brew && { ok "Homebrew kurulu"; return; }
  step "Homebrew kuruluyor"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # PATH'e ekle (Apple Silicon / Intel)
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
  have brew || die "Homebrew kurulamadı"
}

# ---------------------------------------------------------------------------
# Paket kurulum soyutlaması
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
# Sistem bağımlılıkları
# ---------------------------------------------------------------------------
install_base_deps() {
  step "Sistem bağımlılıkları (git, curl, ripgrep, fd, derleyici, pano)"
  case "$PKG" in
    brew)
      pkg_install git curl ripgrep fd ;;
    apt)
      pkg_install git curl unzip ripgrep fd-find build-essential \
                  xclip wl-clipboard fontconfig
      # Debian/Ubuntu: ikili adı fdfind -> fd alias'ı oluştur
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
  ok "Temel paketler tamam"
}

# ---------------------------------------------------------------------------
# Neovim >= 0.11
# ---------------------------------------------------------------------------
nvim_version() { nvim --version 2>/dev/null | head -1 | sed -E 's/^NVIM v?//'; }

install_neovim() {
  step "Neovim (>= $NVIM_MIN gerekli)"
  if have nvim && ver_ge "$(nvim_version)" "$NVIM_MIN"; then
    ok "Neovim $(nvim_version) yeterli"
    return
  fi

  if [ "$OS" = "macos" ]; then
    pkg_install neovim
  else
    local arch tarball url dest
    arch="$(nvim_arch)"
    if [ -z "$arch" ]; then
      # 32-bit Pi (armv7l/armv6l): resmi ikili yok -> dağıtım paketi + uyarı
      warn "Bu mimaride ($ARCH_RAW) resmi Neovim ikilisi yok; dağıtım paketi denenecek"
      pkg_install neovim || true
    else
      tarball="nvim-linux-${arch}.tar.gz"
      url="https://github.com/neovim/neovim/releases/latest/download/${tarball}"
      dest="/opt/nvim"
      info "İndiriliyor: $url"
      curl -fsSL "$url" -o /tmp/nvim.tar.gz || die "Neovim indirilemedi"
      as_root rm -rf "$dest"
      as_root mkdir -p "$dest"
      as_root tar -xzf /tmp/nvim.tar.gz -C "$dest" --strip-components=1
      as_root ln -sf "$dest/bin/nvim" /usr/local/bin/nvim
      rm -f /tmp/nvim.tar.gz
    fi
  fi

  have nvim || die "Neovim kurulumu başarısız"
  ver_ge "$(nvim_version)" "$NVIM_MIN" \
    || die "Neovim sürümü $(nvim_version) < $NVIM_MIN. Kaynaktan derleme gerekebilir (özellikle 32-bit Pi). https://github.com/neovim/neovim/blob/master/BUILD.md"
  ok "Neovim $(nvim_version) hazır"
}

# ---------------------------------------------------------------------------
# lazygit
# ---------------------------------------------------------------------------
install_lazygit() {
  step "lazygit"
  have lazygit && { ok "lazygit kurulu"; return; }
  if [ "$OS" = "macos" ]; then
    pkg_install lazygit; ok "lazygit hazır"; return
  fi
  if [ "$PKG" = "pacman" ]; then
    pkg_install lazygit; ok "lazygit hazır"; return
  fi
  local arch ver url
  arch="$(lazygit_arch)"
  [ -z "$arch" ] && { warn "lazygit: $ARCH_RAW için ikili yok, atlanıyor"; return; }
  ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
        | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')"
  [ -z "$ver" ] && { warn "lazygit sürümü alınamadı, atlanıyor"; return; }
  url="https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_${arch}.tar.gz"
  info "İndiriliyor: lazygit v$ver ($arch)"
  curl -fsSL "$url" -o /tmp/lazygit.tar.gz || { warn "lazygit indirilemedi"; return; }
  tar -xzf /tmp/lazygit.tar.gz -C /tmp lazygit
  as_root install /tmp/lazygit /usr/local/bin/lazygit
  rm -f /tmp/lazygit.tar.gz /tmp/lazygit
  ok "lazygit hazır"
}

# ---------------------------------------------------------------------------
# Node.js + npm  (yaml-language-server)
# ---------------------------------------------------------------------------
install_node() {
  step "Node.js + npm"
  if have node && have npm; then ok "Node $(node -v) kurulu"; return; fi
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
  have npm || warn "npm kurulamadı; yaml-language-server atlanabilir"
}

# ---------------------------------------------------------------------------
# Go  (gopls)
# ---------------------------------------------------------------------------
GO_MIN="1.21"
install_go() {
  step "Go"
  if have go && ver_ge "$(go version | sed -E 's/.*go([0-9.]+).*/\1/')" "$GO_MIN"; then
    ok "Go $(go version | sed -E 's/.*go([0-9.]+).*/\1/') kurulu"; return
  fi
  if [ "$OS" = "macos" ]; then
    pkg_install go
  else
    local arch ver url
    arch="$(go_arch)"
    [ -z "$arch" ] && { warn "Go: $ARCH_RAW desteklenmiyor, dağıtım paketi deneniyor"; pkg_install golang || pkg_install go || true; return; }
    ver="$(curl -fsSL https://go.dev/VERSION?m=text | head -1)"   # ör: go1.22.5
    [ -z "$ver" ] && { warn "Go sürümü alınamadı, dağıtım paketi"; pkg_install golang || true; return; }
    url="https://go.dev/dl/${ver}.linux-${arch}.tar.gz"
    info "İndiriliyor: $ver ($arch)"
    curl -fsSL "$url" -o /tmp/go.tar.gz || { warn "Go indirilemedi"; return; }
    as_root rm -rf /usr/local/go
    as_root tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
    export PATH="/usr/local/go/bin:$PATH"
    add_path_line '/usr/local/go/bin'
  fi
  have go && ok "Go $(go version | sed -E 's/.*go([0-9.]+).*/\1/') hazır" || warn "Go kurulamadı"
}

# ---------------------------------------------------------------------------
# PATH yardımcı: shell rc'ye satır ekle (idempotent)
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
# LSP sunucuları
# ---------------------------------------------------------------------------
install_lsp_servers() {
  step "LSP sunucuları: gopls, yaml-language-server"

  # gopls
  export PATH="${PATH}:/usr/local/go/bin:$HOME/go/bin"
  if have go; then
    if have gopls; then
      ok "gopls kurulu"
    else
      info "gopls kuruluyor (go install)…"
      GOBIN="$HOME/go/bin" go install golang.org/x/tools/gopls@latest \
        && { add_path_line "$HOME/go/bin"; ok "gopls hazır (~/go/bin)"; } \
        || warn "gopls kurulamadı"
    fi
  else
    warn "Go yok → gopls atlandı"
  fi

  # yaml-language-server
  if have yaml-language-server; then
    ok "yaml-language-server kurulu"
  elif have npm; then
    info "yaml-language-server kuruluyor (npm -g)…"
    if npm install -g yaml-language-server >/dev/null 2>&1; then
      ok "yaml-language-server hazır"
    elif as_root env PATH="$PATH" npm install -g yaml-language-server >/dev/null 2>&1; then
      ok "yaml-language-server hazır (sudo)"
    else
      warn "yaml-language-server kurulamadı"
    fi
  else
    warn "npm yok → yaml-language-server atlandı"
  fi
}

# ---------------------------------------------------------------------------
# Nerd Font (ikonlar)
# ---------------------------------------------------------------------------
install_nerd_font() {
  step "Nerd Font (JetBrainsMono)"
  if [ "$INSTALL_FONT" = "no" ]; then info "--no-font verildi, atlanıyor"; return; fi
  if [ -n "${SSH_CONNECTION:-}" ] && [ "$INSTALL_FONT" = "auto" ]; then
    warn "SSH/headless oturum tespit edildi → font atlanıyor (terminal makinesine kur). Zorlamak için tekrar çalıştırın."
    return
  fi
  if [ "$OS" = "macos" ]; then
    brew install --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1 \
      && ok "JetBrainsMono Nerd Font kuruldu" \
      || warn "Font kurulamadı (terminalde 'JetBrainsMono Nerd Font' seçmeyi unutmayın)"
  else
    local dir="$HOME/.local/share/fonts"
    mkdir -p "$dir"
    if curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -o /tmp/JBM.zip; then
      unzip -oq /tmp/JBM.zip -d "$dir/JetBrainsMonoNerd" && rm -f /tmp/JBM.zip
      have fc-cache && fc-cache -f "$dir" >/dev/null 2>&1 || true
      ok "JetBrainsMono Nerd Font kuruldu (~/.local/share/fonts)"
    else
      warn "Font indirilemedi"
    fi
  fi
  info "Terminal profilinizden yazı tipini 'JetBrainsMono Nerd Font' seçin."
}

# ---------------------------------------------------------------------------
# Config dağıtımı
# ---------------------------------------------------------------------------
deploy_config() {
  step "Config dağıtımı → $CONFIG_DST  (mod: $DEPLOY_MODE)"
  [ -d "$CONFIG_SRC" ] || die "Kaynak config yok: $CONFIG_SRC"
  mkdir -p "$(dirname "$CONFIG_DST")"

  # Mevcut config'i yedekle (kendi symlink'imiz değilse)
  if [ -e "$CONFIG_DST" ] || [ -L "$CONFIG_DST" ]; then
    if [ "$(readlink "$CONFIG_DST" 2>/dev/null)" = "$CONFIG_SRC" ]; then
      ok "Zaten doğru symlink"
      return
    fi
    local bak
    bak="$CONFIG_DST.bak.$(date +%Y%m%d%H%M%S)"
    mv "$CONFIG_DST" "$bak"
    warn "Eski config yedeklendi: $bak"
  fi

  if [ "$DEPLOY_MODE" = "symlink" ]; then
    ln -s "$CONFIG_SRC" "$CONFIG_DST"
    ok "Symlink: $CONFIG_DST → $CONFIG_SRC"
  else
    cp -R "$CONFIG_SRC" "$CONFIG_DST"
    ok "Kopyalandı: $CONFIG_DST"
  fi
}

# ---------------------------------------------------------------------------
# Plugin bootstrap
# ---------------------------------------------------------------------------
bootstrap_plugins() {
  step "Plugin bootstrap (lazy.nvim + treesitter)"
  export PATH="${PATH}:/usr/local/go/bin:$HOME/go/bin"
  info "lazy.nvim restore (lazy-lock.json'a göre sabit sürümler)…"
  nvim --headless "+Lazy! restore" +qa 2>/dev/null || warn "Lazy restore uyarı verdi (ilk açılışta tamamlanır)"
  info "treesitter parser (go, lua)…"
  nvim --headless -c "lua pcall(function() require('nvim-treesitter').install({'go','lua'}) end)" -c "qa" 2>/dev/null \
    || nvim --headless "+TSUpdate go lua" +qa 2>/dev/null \
    || warn "treesitter parser kurulumu atlandı (nvim içinde :TSInstall go lua deneyin)"
  ok "Pluginler kuruldu"
}

# ---------------------------------------------------------------------------
# Doctor — son durum özeti
# ---------------------------------------------------------------------------
doctor() {
  step "Doctor — kurulum özeti"
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
      warn "$(printf '%-22s eksik' "$b")"
    fi
  done
  printf '\n%sBitti.%s Neovim açın: %snvim%s  (ilk açılışta pluginler senkronlanır)\n' \
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
    warn "--skip-deps: sistem bağımlılıkları atlandı"
    have nvim && ver_ge "$(nvim_version)" "$NVIM_MIN" || die "Neovim >= $NVIM_MIN gerekli (--skip-deps ile mevcut olmalı)"
  fi

  install_lsp_servers
  install_nerd_font
  deploy_config
  bootstrap_plugins
  doctor
}

main "$@"
