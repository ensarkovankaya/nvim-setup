# Neovim Setup

A portable, minimal, **Go + YAML/OpenAPI**-focused Neovim configuration.
Managed with `lazy.nvim`, using Neovim's **native LSP API** (0.11+).
Installs on **macOS / Linux / Raspberry Pi** with a single command.

**Supported architectures:** macOS (Intel + Apple Silicon), Linux x86_64 and
arm64 — **including 64-bit Raspberry Pi OS (arm64)**, with no extra steps. For
32-bit Pi (armv7l) there is no official Neovim binary, so a source build is
required (64-bit OS recommended).

```bash
git clone https://github.com/ensarkovankaya/nvim-setup.git ~/nvim-setup
cd ~/nvim-setup
./install.sh
```

______________________________________________________________________

## Table of contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick install](#quick-install)
- [What does install.sh do? (step by step)](#what-does-installsh-do-step-by-step)
- [Manual install (without the script)](#manual-install-without-the-script)
- [Plugins — what does each do?](#plugins--what-does-each-do)
- [LSP servers](#lsp-servers)
- [Keymaps](#keymaps)
- [Updating](#updating)
- [Troubleshooting](#troubleshooting)

______________________________________________________________________

## Architecture

```
nvim/
├── init.lua                 # entry point: requires the 3 modules
├── lazy-lock.json           # plugin version lock (reproducible installs)
└── lua/config/
    ├── options.lua          # editor settings (numbers, tabs, clipboard…)
    ├── keymaps.lua          # key mappings (leader = <Space>)
    └── plugins.lua          # plugin list + plugin/LSP setup
```

The structure is intentionally small: a single `plugins.lua` file holds both the
plugin declarations and the `setup` calls plus the LSP configuration.

______________________________________________________________________

## Prerequisites

`install.sh` installs all of these automatically. If installing manually:

| Dependency                 | Why it's needed                                      |
| -------------------------- | ---------------------------------------------------- |
| **Neovim ≥ 0.11**          | `vim.lsp.config` / `vim.lsp.enable` native API       |
| **git**                    | Cloning lazy.nvim and plugins, fugitive/diffview     |
| **ripgrep (`rg`)**         | Telescope `live_grep` (text search)                  |
| **fd**                     | Telescope `find_files` (fast file finding)           |
| **C compiler** (gcc/clang) | Building treesitter parsers                          |
| **lazygit**                | `lazygit.nvim` git UI                                |
| **Node.js + npm**          | Installing `yaml-language-server`                    |
| **Go**                     | Installing `gopls` (Go LSP)                          |
| **Nerd Font**              | nvim-tree / lualine icon glyphs                      |
| Clipboard (Linux)          | `xclip`/`wl-clipboard` — for `clipboard=unnamedplus` |

______________________________________________________________________

## Quick install

```bash
./install.sh                 # install everything (recommended)
./install.sh --copy          # copy the config instead of symlinking
./install.sh --no-font       # skip the Nerd Font
./install.sh --skip-deps     # skip system packages, config + LSP only
./install.sh --help
```

> **Symlink vs copy:** Default is **symlink** — `~/.config/nvim` links to the
> `nvim/` folder in this repo. This makes the repo the single source of truth;
> `git pull` applies changes instantly. Use `--copy` if you want a
> device-local/persistent copy instead.

______________________________________________________________________

## What does install.sh do? (step by step)

The script is idempotent (safe to re-run — it skips what's already installed).

01. **Platform detection** — OS (macOS/Linux) via `uname`, distro + Raspberry Pi
    via `/etc/os-release` and `/proc/cpuinfo`, architecture (x86_64/arm64/armv7l)
    via `uname -m`, and the package manager (brew/apt/dnf/pacman/zypper).

02. **Homebrew** (macOS only) — installs it if missing.

03. **System dependencies** — `git curl ripgrep fd` + a compiler (build-essential
    / base-devel / gcc) + on Linux the clipboard tools (`xclip`, `wl-clipboard`)
    and `fontconfig`. On Debian/Ubuntu the package is `fd-find` and the binary is
    `fdfind`; the script creates a `~/.local/bin/fd` symlink.

04. **Neovim ≥ 0.11** —

    - macOS: `brew install neovim`
    - Linux x86_64 / arm64: official tarball from GitHub (`/opt/nvim`, symlinked to
      `/usr/local/bin/nvim`). **64-bit Raspberry Pi OS (arm64) lands here and is
      first-class supported.**
    - 32-bit Pi (armv7l): no official binary → the distro package is tried; if the
      version is too old it warns to build from source.
      If the version is < 0.11 the install stops (native LSP API won't work).

05. **lazygit** — from the package manager on macOS/Arch; on other Linux a GitHub
    release binary (x86_64/arm64/armv6 by architecture).

06. **Node.js + npm** — from the package manager if not present. Needed for
    `yaml-language-server`.

07. **Go** — official tarball on Linux (`/usr/local/go`), brew on macOS. Needed
    for `gopls`; `/usr/local/go/bin` is added to PATH.

08. **LSP servers** —

    - `gopls`: `go install golang.org/x/tools/gopls@latest` → `~/go/bin`
    - `yaml-language-server`: `npm install -g`
      PATH lines are added idempotently to `~/.zshrc` / `~/.bashrc`.

09. **Nerd Font** — JetBrainsMono. Cask on macOS, `~/.local/share/fonts` +
    `fc-cache` on Linux. **Auto-skipped on SSH/headless sessions** (install it on
    the machine running the terminal).

10. **Config deployment** — any existing `~/.config/nvim` is moved to a
    timestamped backup, then symlinked (or copied with `--copy`).

11. **Plugin bootstrap** — `nvim --headless +Lazy! restore` installs the pinned
    commits from `lazy-lock.json`; the `go`/`lua` treesitter parsers are loaded.

12. **Doctor** — summarizes all binaries and versions.

______________________________________________________________________

## Manual install (without the script)

```bash
# 1) Prerequisites (example: macOS)
brew install neovim git ripgrep fd lazygit node go
brew install --cask font-jetbrains-mono-nerd-font

# 2) LSP servers
go install golang.org/x/tools/gopls@latest      # ~/go/bin must be on PATH
npm install -g yaml-language-server

# 3) Deploy the config
ln -s "$PWD/nvim" ~/.config/nvim                 # or: cp -R nvim ~/.config/nvim

# 4) Open Neovim — lazy.nvim installs the plugins automatically
nvim
```

On Debian/Ubuntu/Raspberry Pi OS use `apt` instead of `brew`; since the `apt`
Neovim is usually older than 0.11, install Neovim from the
[official tarball](https://github.com/neovim/neovim/releases).

______________________________________________________________________

## Plugins — what does each do?

| Plugin                                  | Purpose                                                                                                              |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| **lazy.nvim**                           | Plugin manager. `init.lua` bootstraps it on first launch; `lazy-lock.json` pins versions.                            |
| **catppuccin/nvim**                     | Color theme (`colorscheme catppuccin`). Loaded before others with `priority=1000`.                                   |
| **nvim-tree.lua**                       | File explorer on the left. Width 35, shows dotfiles, marks git status, follows the open file / working directory.    |
| **telescope.nvim** (+ **plenary.nvim**) | Fuzzy finder: find files, search text (`rg`), search within a buffer. LSP references are also listed via Telescope.  |
| **nvim-treesitter**                     | Accurate syntax highlighting and code parsing. `build=:TSUpdate`. The config registers the `go` and `lua` languages. |
| **lualine.nvim**                        | Bottom status line (mode, file, git, position).                                                                      |
| **gitsigns.nvim**                       | Inline git signs (added/changed/removed) + **current line blame** (author + time at end of line).                    |
| **vim-fugitive**                        | Classic git command interface (`:Git …`); also the foundation for diffview and other tools.                          |
| **lazygit.nvim**                        | Full-screen `lazygit` TUI from inside Neovim. Lazy-loaded via `cmd`.                                                 |
| **diffview.nvim**                       | Advanced diff and file-history views (`:DiffviewOpen`, file history).                                                |
| **nvim-cmp**                            | Autocompletion engine. Sources: LSP, snippets, buffer, path.                                                         |
| ↳ **cmp-nvim-lsp**                      | LSP completion source + advertises LSP capabilities to cmp.                                                          |
| ↳ **cmp-buffer / cmp-path**             | Completion from open-buffer words and file paths.                                                                    |
| ↳ **LuaSnip** + **cmp_luasnip**         | Snippet engine and its cmp integration.                                                                              |
| **which-key.nvim**                      | Popup showing keybinding hints when you press `<leader>`. `git`/`rename` groups defined.                             |
| **SchemaStore.nvim**                    | Provides ready-made JSON/YAML schemas (k8s, GitHub Actions, OpenAPI…) to yaml-language-server.                       |
| **csvview.nvim**                        | Renders CSV/TSV files as an aligned table; auto-enabled on open, disables line wrap.                                 |

______________________________________________________________________

## LSP servers

Configured with the native API (`vim.lsp.config` + `vim.lsp.enable`, Neovim
0.11+).

- **gopls** (Go) — `go`, `gomod`, `gowork`, `gotmpl`. Enabled: `unusedparams`
  and `shadow` analyses, `staticcheck`, `gofumpt` formatting. Root markers:
  `go.mod` / `go.work` / `.git`.
- **yaml-language-server** (YAML/OpenAPI) — schemas come from `SchemaStore.nvim`
  (`schemaStore` disabled, external `schemas()` used). RedHat telemetry disabled.
  Since yamlls doesn't support `references`, `gr` falls back to in-buffer grep.

When LSP attaches to a buffer (`LspAttach`), these mappings become active:
`gd` definition, `gr` references, `K` hover, `<leader>rn` rename, `<leader>ca`
code action, `<leader>d` diagnostic float, `[d`/`]d` diagnostic navigation.

______________________________________________________________________

## Keymaps

Leader key: **`<Space>`**

| Keymap                                                        | Description                                      |
| ------------------------------------------------------------- | ------------------------------------------------ |
| `<leader>w` / `<leader>q`                                     | Save / quit                                      |
| `<C-h/j/k/l>`                                                 | Move between windows                             |
| `jk` (insert)                                                 | Exit insert mode (ESC)                           |
| `<leader>e` / `<leader>f`                                     | Toggle / focus file tree                         |
| `<leader>cd`                                                  | Change cwd to the directory selected in the tree |
| `<leader>ff`                                                  | Find files (Telescope)                           |
| `<leader>fg`                                                  | Search text — live grep                          |
| `<leader>/`                                                   | Search within the open buffer                    |
| `<leader>gg` / `<leader>gf`                                   | LazyGit / current file's repo                    |
| `<leader>gd` / `<leader>gc`                                   | Diffview open / close                            |
| `<leader>gh`                                                  | Current file's git history                       |
| `<leader>gb`                                                  | Toggle line blame                                |
| `<leader>y` (visual, tmux)                                    | Copy selection to the tmux buffer                |
| `gd` `gr` `K` `<leader>rn` `<leader>ca` `<leader>d` `[d` `]d` | LSP (see above)                                  |

______________________________________________________________________

## Updating

```bash
# Update plugins and refresh the lock
nvim "+Lazy sync" +qa
# Commit the lazy-lock.json changes
git add nvim/lazy-lock.json && git commit -m "chore: plugin update"

# Apply the same versions on another device
git pull && nvim "+Lazy! restore" +qa
```

To update the LSP servers:
`go install golang.org/x/tools/gopls@latest` and
`npm update -g yaml-language-server`.

______________________________________________________________________

## Troubleshooting

- **`vim.lsp.config` error / LSP not working** → Neovim < 0.11. Check with
  `nvim --version`; update from the official tarball.
- **Icons show as boxes/question marks** → the terminal font isn't a Nerd Font.
  Select **JetBrainsMono Nerd Font** in your terminal profile.
- **Telescope `live_grep` empty** → ripgrep (`rg`) is not installed.
- **`find_files` slow / not working** → `fd` is missing; on Debian it may be
  installed as `fdfind`, and `~/.local/bin/fd` must be on PATH.
- **treesitter parser missing** → inside Neovim run `:TSInstall go lua`.
- **gopls not found** → `~/go/bin` is not on PATH. Add
  `export PATH="$HOME/go/bin:$PATH"` (the script adds it to `.zshrc`/`.bashrc`).
- **Clipboard (yank) not synced with the system (Linux)** → install `xclip`
  (X11) or `wl-clipboard` (Wayland). On headless/SSH use Neovim's OSC52 support:
  configure `vim.g.clipboard` for OSC52.
- **Neovim is old on 32-bit Raspberry Pi** → no official armv7 binary; build from
  source: <https://github.com/neovim/neovim/blob/master/BUILD.md>. **Recommended:
  use 64-bit Raspberry Pi OS (arm64)** — an official binary exists there, with no
  extra steps.
- **Wrong config loaded** → the old setup is backed up to
  `~/.config/nvim.bak.<date>`; restore it if needed.
