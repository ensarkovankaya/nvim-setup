# Neovim Setup

Taşınabilir, minimal ve **Go + YAML/OpenAPI** odaklı Neovim yapılandırması.
`lazy.nvim` ile yönetilir, Neovim'in **native LSP API**'sini (0.11+) kullanır.
Tek komutla **macOS / Linux / Raspberry Pi** üzerine kurulur.

**Desteklenen mimariler:** macOS (Intel + Apple Silicon), Linux x86_64 ve arm64
— **64-bit Raspberry Pi OS (arm64) dahil**, ekstra adım gerektirmez. 32-bit Pi
(armv7l) için resmi Neovim ikilisi olmadığından kaynaktan derleme gerekir
(64-bit OS önerilir).

```bash
git clone https://github.com/ensarkovankaya/nvim-setup.git ~/nvim-setup
cd ~/nvim-setup
./install.sh
```

______________________________________________________________________

## İçindekiler

- [Mimari](#mimari)
- [Önkoşullar](#%C3%B6nko%C5%9Fullar)
- [Hızlı kurulum](#h%C4%B1zl%C4%B1-kurulum)
- [install.sh ne yapıyor? (adım adım)](#installsh-ne-yap%C4%B1yor-ad%C4%B1m-ad%C4%B1m)
- [Elle kurulum](#elle-kurulum-script-kullanmadan)
- [Pluginler — ne işe yarıyor?](#pluginler--ne-i%C5%9Fe-yar%C4%B1yor)
- [LSP sunucuları](#lsp-sunucular%C4%B1)
- [Kısayollar (keymaps)](#k%C4%B1sayollar-keymaps)
- [Güncelleme](#g%C3%BCncelleme)
- [Sorun giderme](#sorun-giderme)

______________________________________________________________________

## Mimari

```
nvim/
├── init.lua                 # giriş noktası: 3 modülü require eder
├── lazy-lock.json           # plugin sürüm kilidi (tekrarlanabilir kurulum)
└── lua/config/
    ├── options.lua          # editör ayarları (numara, tab, clipboard…)
    ├── keymaps.lua          # tuş atamaları (leader = <Space>)
    └── plugins.lua          # plugin listesi + plugin/LSP kurulumları
```

Yapı bilinçli olarak küçük: tek bir `plugins.lua` dosyası hem plugin tanımlarını
hem de kurulum (`setup`) çağrılarını ve LSP yapılandırmasını içerir.

______________________________________________________________________

## Önkoşullar

Aşağıdakilerin tamamını `install.sh` otomatik kurar. Elle kuracaksanız:

| Bağımlılık                  | Neden gerekli                                            |
| --------------------------- | -------------------------------------------------------- |
| **Neovim ≥ 0.11**           | `vim.lsp.config` / `vim.lsp.enable` native API'si        |
| **git**                     | lazy.nvim ve eklentilerin klonlanması, fugitive/diffview |
| **ripgrep (`rg`)**          | Telescope `live_grep` (metin araması)                    |
| **fd**                      | Telescope `find_files` (hızlı dosya bulma)               |
| **C derleyici** (gcc/clang) | treesitter parser derlemesi                              |
| **lazygit**                 | `lazygit.nvim` git arayüzü                               |
| **Node.js + npm**           | `yaml-language-server` kurulumu                          |
| **Go**                      | `gopls` (Go LSP) kurulumu                                |
| **Nerd Font**               | nvim-tree / lualine ikon glifleri                        |
| Pano (Linux)                | `xclip`/`wl-clipboard` — `clipboard=unnamedplus` için    |

______________________________________________________________________

## Hızlı kurulum

```bash
./install.sh                 # her şeyi kur (önerilen)
./install.sh --copy          # config'i symlink yerine kopyala
./install.sh --no-font       # Nerd Font kurma
./install.sh --skip-deps     # sistem paketlerini atla, sadece config + LSP
./install.sh --help
```

> **Symlink vs copy:** Varsayılan **symlink** — `~/.config/nvim`, bu repodaki
> `nvim/` klasörüne bağlanır. Böylece repo "tek doğru kaynak" olur; `git pull`
> ile değişiklikler anında geçerli olur. Cihaza bağımlı/kalıcı bir kopya
> istiyorsanız `--copy` kullanın.

______________________________________________________________________

## install.sh ne yapıyor? (adım adım)

Script idempotent'tir (tekrar çalıştırmak güvenli — kurulu olanı atlar).

01. **Platform tespiti** — `uname` ile OS (macOS/Linux), `/etc/os-release` ve
    `/proc/cpuinfo` ile dağıtım + Raspberry Pi, `uname -m` ile mimari
    (x86_64/arm64/armv7l) ve paket yöneticisi (brew/apt/dnf/pacman/zypper).

02. **Homebrew** (yalnız macOS) — yoksa kurar.

03. **Sistem bağımlılıkları** — `git curl ripgrep fd` + derleyici (build-essential
    / base-devel / gcc) + Linux'ta pano araçları (`xclip`, `wl-clipboard`) ve
    `fontconfig`. Debian/Ubuntu'da paket `fd-find` olarak gelir, ikili adı
    `fdfind`'dir; script `~/.local/bin/fd` symlink'i oluşturur.

04. **Neovim ≥ 0.11** —

    - macOS: `brew install neovim`
    - Linux x86_64 / arm64: GitHub'dan resmi tarball (`/opt/nvim`, `/usr/local/bin/nvim` symlink).
      **64-bit Raspberry Pi OS (arm64) buraya girer ve birinci sınıf desteklenir.**
    - 32-bit Pi (armv7l): resmi ikili yok → dağıtım paketi denenir, sürüm
      yetersizse kaynaktan derleme uyarısı verir.
      Sürüm < 0.11 ise kurulum durur (native LSP API çalışmaz).

05. **lazygit** — macOS/Arch'ta paketten; diğer Linux'ta GitHub release ikilisi
    (mimariye göre x86_64/arm64/armv6).

06. **Node.js + npm** — mevcut değilse paket yöneticisinden. `yaml-language-server`
    için gerekli.

07. **Go** — Linux'ta resmi tarball (`/usr/local/go`), macOS'ta brew. `gopls`
    için gerekli; PATH'e `/usr/local/go/bin` eklenir.

08. **LSP sunucuları** —

    - `gopls`: `go install golang.org/x/tools/gopls@latest` → `~/go/bin`
    - `yaml-language-server`: `npm install -g`
      PATH satırları `~/.zshrc` / `~/.bashrc`'ye idempotent eklenir.

09. **Nerd Font** — JetBrainsMono. macOS'ta cask, Linux'ta
    `~/.local/share/fonts` + `fc-cache`. **SSH/headless oturumda otomatik
    atlanır** (terminalin çalıştığı makineye kurulmalı).

10. **Config dağıtımı** — varsa mevcut `~/.config/nvim` zaman damgalı yedeğe
    taşınır, sonra symlink (veya `--copy`).

11. **Plugin bootstrap** — `nvim --headless +Lazy! restore` ile
    `lazy-lock.json`'daki sabit commit'ler kurulur; treesitter `go`/`lua`
    parser'ları yüklenir.

12. **Doctor** — tüm ikilileri ve sürümleri özetler.

______________________________________________________________________

## Elle kurulum (script kullanmadan)

```bash
# 1) Önkoşullar (örnek: macOS)
brew install neovim git ripgrep fd lazygit node go
brew install --cask font-jetbrains-mono-nerd-font

# 2) LSP sunucuları
go install golang.org/x/tools/gopls@latest      # ~/go/bin PATH'te olmalı
npm install -g yaml-language-server

# 3) Config'i yerleştir
ln -s "$PWD/nvim" ~/.config/nvim                 # veya: cp -R nvim ~/.config/nvim

# 4) Neovim'i aç — lazy.nvim pluginleri otomatik kurar
nvim
```

Debian/Ubuntu/Raspberry Pi OS'te `brew` yerine `apt` kullanın; `apt`'taki
Neovim çoğu zaman 0.11'den eski olduğu için Neovim'i [resmi
tarball](https://github.com/neovim/neovim/releases)'dan kurun.

______________________________________________________________________

## Pluginler — ne işe yarıyor?

| Plugin                                  | İşlevi                                                                                                                       |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **lazy.nvim**                           | Plugin yöneticisi. `init.lua` ilk açılışta kendini bootstrap eder; `lazy-lock.json` ile sürümleri kilitler.                  |
| **catppuccin/nvim**                     | Renk teması (`colorscheme catppuccin`). `priority=1000` ile diğerlerinden önce yüklenir.                                     |
| **nvim-tree.lua**                       | Soldaki dosya gezgini. Genişlik 35, dotfile'ları gösterir, git durumunu işaretler, açık dosyayı/çalışma dizinini takip eder. |
| **telescope.nvim** (+ **plenary.nvim**) | Fuzzy finder: dosya bul, metin ara (`rg`), buffer içinde ara. LSP referansları da Telescope ile listelenir.                  |
| **nvim-treesitter**                     | Doğru sözdizimi vurgulama ve kod ayrıştırma. `build=:TSUpdate`. Config `go` ve `lua` dillerini kayıt eder.                   |
| **lualine.nvim**                        | Alt durum çubuğu (mod, dosya, git, konum).                                                                                   |
| **gitsigns.nvim**                       | Satır içi git işaretleri (eklendi/değişti/silindi) + **current line blame** (satır sonunda yazar + zaman).                   |
| **vim-fugitive**                        | Klasik git komut arayüzü (`:Git …`); diffview/diğer araçların da temeli.                                                     |
| **lazygit.nvim**                        | Neovim içinden tam ekran `lazygit` TUI'si. `cmd` ile tembel yüklenir.                                                        |
| **diffview.nvim**                       | Gelişmiş diff ve dosya geçmişi görünümü (`:DiffviewOpen`, dosya history).                                                    |
| **nvim-cmp**                            | Otomatik tamamlama motoru. Kaynaklar: LSP, snippet, buffer, path.                                                            |
| ↳ **cmp-nvim-lsp**                      | LSP tamamlama kaynağı + LSP yeteneklerini cmp'ye bildirir.                                                                   |
| ↳ **cmp-buffer / cmp-path**             | Açık buffer kelimeleri ve dosya yolu tamamlama.                                                                              |
| ↳ **LuaSnip** + **cmp_luasnip**         | Snippet motoru ve cmp entegrasyonu.                                                                                          |
| **which-key.nvim**                      | `<leader>` bastığınızda kısayol ipuçlarını gösteren popup. `git`/`rename` grupları tanımlı.                                  |
| **SchemaStore.nvim**                    | yaml-language-server'a hazır JSON/YAML şemaları (k8s, GitHub Actions, OpenAPI…) sağlar.                                      |
| **csvview.nvim**                        | CSV/TSV dosyalarını hizalı tablo olarak gösterir; açılışta otomatik etkinleşir, satır kaydırmayı kapatır.                    |

______________________________________________________________________

## LSP sunucuları

Native API (`vim.lsp.config` + `vim.lsp.enable`, Neovim 0.11+) ile yapılandırılır.

- **gopls** (Go) — `go`, `gomod`, `gowork`, `gotmpl`. Açık: `unusedparams` ve
  `shadow` analizleri, `staticcheck`, `gofumpt` formatlama. Kök işaretleri:
  `go.mod` / `go.work` / `.git`.
- **yaml-language-server** (YAML/OpenAPI) — şemalar `SchemaStore.nvim`'den
  beslenir (`schemaStore` kapalı, harici `schemas()` kullanılır). RedHat
  telemetrisi kapalı. yamlls `references` desteklemediğinden `gr` için buffer
  içi grep fallback'i vardır.

LSP bir tampona bağlanınca (`LspAttach`) şu kısayollar etkinleşir:
`gd` tanım, `gr` referanslar, `K` hover, `<leader>rn` rename, `<leader>ca` code
action, `<leader>d` diagnostic float, `[d`/`]d` diagnostic gezinme.

______________________________________________________________________

## Kısayollar (keymaps)

Leader tuşu: **`<Space>`**

| Kısayol                                                       | Açıklama                          |
| ------------------------------------------------------------- | --------------------------------- |
| `<leader>w` / `<leader>q`                                     | Kaydet / çık                      |
| `<C-h/j/k/l>`                                                 | Pencereler arası geçiş            |
| `jk` (insert)                                                 | Insert modundan çık (ESC)         |
| `<leader>e` / `<leader>f`                                     | Dosya ağacı aç-kapa / odakla      |
| `<leader>cd`                                                  | cwd'yi ağaçta seçili dizine taşı  |
| `<leader>ff`                                                  | Dosya bul (Telescope)             |
| `<leader>fg`                                                  | Metin ara — live grep             |
| `<leader>/`                                                   | Açık buffer içinde ara            |
| `<leader>gg` / `<leader>gf`                                   | LazyGit / mevcut dosyanın repo'su |
| `<leader>gd` / `<leader>gc`                                   | Diffview aç / kapat               |
| `<leader>gh`                                                  | Mevcut dosyanın git geçmişi       |
| `<leader>gb`                                                  | Satır blame aç-kapa               |
| `<leader>y` (visual, tmux)                                    | Seçimi tmux buffer'ına kopyala    |
| `gd` `gr` `K` `<leader>rn` `<leader>ca` `<leader>d` `[d` `]d` | LSP (yukarıya bakın)              |

______________________________________________________________________

## Güncelleme

```bash
# Pluginleri güncelle ve kilidi tazele
nvim "+Lazy sync" +qa
# lazy-lock.json değişikliklerini commit'le
git add nvim/lazy-lock.json && git commit -m "chore: plugin güncellemesi"

# Başka cihazda aynı sürümleri uygula
git pull && nvim "+Lazy! restore" +qa
```

LSP sunucularını güncellemek için:
`go install golang.org/x/tools/gopls@latest` ve
`npm update -g yaml-language-server`.

______________________________________________________________________

## Sorun giderme

- **`vim.lsp.config` hatası / LSP çalışmıyor** → Neovim < 0.11.
  `nvim --version` ile kontrol edin; resmi tarball'dan güncelleyin.
- **İkonlar kutucuk/soru işareti** → Terminal yazı tipi Nerd Font değil.
  Terminal profilinden **JetBrainsMono Nerd Font** seçin.
- **Telescope `live_grep` boş** → `rg` (ripgrep) kurulu değil.
- **`find_files` yavaş / çalışmıyor** → `fd` yok; Debian'da `fdfind` kurulu
  olabilir, `~/.local/bin/fd` symlink'i PATH'te olmalı.
- **treesitter parser eksik** → Neovim içinde `:TSInstall go lua`.
- **gopls bulunamadı** → `~/go/bin` PATH'te değil.
  `export PATH="$HOME/go/bin:$PATH"` ekleyin (script `.zshrc`/`.bashrc`'ye ekler).
- **Pano (yank) sistemle senkron değil (Linux)** → `xclip` (X11) veya
  `wl-clipboard` (Wayland) kurun. Headless/SSH'da Neovim'in OSC52
  desteğini kullanın: `vim.g.clipboard` için OSC52 ayarı.
- **32-bit Raspberry Pi'de Neovim eski** → resmi armv7 ikilisi yok; kaynaktan
  derleyin: <https://github.com/neovim/neovim/blob/master/BUILD.md>. **Öneri:
  64-bit Raspberry Pi OS (arm64) kullanın** — orada resmi ikili var, ekstra
  adım gerekmez.
- **Yanlış config yüklendi** → eski kurulum `~/.config/nvim.bak.<tarih>`'e
  yedeklenir; gerekirse geri alın.
