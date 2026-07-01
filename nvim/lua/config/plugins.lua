-- Bootstrap lazy.nvim if not installed
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath
  })
end
vim.opt.rtp:prepend(lazypath)

-- Define plugins
require("lazy").setup({
  -- Color theme
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },

  -- File explorer
  { "nvim-tree/nvim-tree.lua" },

  -- Fuzzy finder (file and text search)
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      -- C-compiled sorter; enables prompt filters: !exclude  'exact  ^prefix  suffix$
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
  },

  -- Find & replace UI (current file or project-wide; needs ripgrep + sed)
  {
    "nvim-pack/nvim-spectre",
    dependencies = { "nvim-lua/plenary.nvim" },
  },

  -- Syntax highlighting
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },

  -- Auto-highlight other uses of the symbol under the cursor
  { "RRethy/vim-illuminate" },

  -- Status bar
  { "nvim-lualine/lualine.nvim" },

  -- Git
  { "lewis6991/gitsigns.nvim" },
  { "tpope/vim-fugitive" },
  {
    "kdheepak/lazygit.nvim",
    cmd = { "LazyGit", "LazyGitConfig", "LazyGitCurrentFile", "LazyGitFilter", "LazyGitFilterCurrentFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
  },
  { "sindrets/diffview.nvim" },

  -- GitHub PR/issue review inside nvim (needs gh CLI; uses telescope picker + diffview)
  {
    "pwntester/octo.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    cmd = "Octo",
    opts = { picker = "telescope" },
  },

  -- Autocomplete
  { "hrsh7th/nvim-cmp", dependencies = {
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-path",
    "L3MON4D3/LuaSnip",
    "saadparwaiz1/cmp_luasnip",
  }},

  -- Keymap hints
  { "folke/which-key.nvim", event = "VeryLazy" },

  -- JSON/YAML schemas (OpenAPI, k8s, github actions, ...)
  { "b0o/SchemaStore.nvim", lazy = true },

  -- CSV/TSV table view (auto-enabled when a csv/tsv file is opened)
  {
    "hat0uma/csvview.nvim",
    cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle" },
    opts = {
      view = { display_mode = "border", header_lnum = 1 },
    },
    init = function()
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "csv", "tsv" },
        callback = function()
          vim.opt_local.wrap = false  -- wrap breaks table alignment and blocks horizontal scroll
          vim.cmd("CsvViewEnable")
        end,
      })
    end,
  },
})

-- Activate color theme
vim.cmd.colorscheme("catppuccin")

-- Setup nvim-tree
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
require("nvim-tree").setup({
  view = { width = 35 },
  filters = {
    dotfiles = false,
    git_ignored = false,
  },
  git = {
    enable = true,
    ignore = false,
  },
  sync_root_with_cwd = true,
  respect_buf_cwd = true,
  update_focused_file = {
    enable = true,
    update_root = true,
  },
})

-- Telescope setup
require("telescope").setup({
  extensions = {
    -- fzf syntax in any picker prompt: !pat = exclude, 'pat = exact, ^pat / pat$ = anchored
    fzf = {
      fuzzy = true,
      override_generic_sorter = true,
      override_file_sorter = true,
      case_mode = "smart_case",
    },
  },
})
require("telescope").load_extension("fzf")

-- Spectre (find & replace) setup
require("spectre").setup()

-- Status bar setup (lualine_b shows git branch automatically when in a repo)
require("lualine").setup({
  options = {
    theme = "catppuccin-nvim",  -- catppuccin doesn't ship a "catppuccin" theme; this tracks the active flavour
    globalstatus = true,  -- single statusline shared across splits
  },
})

-- Gitsigns setup
require("gitsigns").setup({
  current_line_blame = true,
  current_line_blame_opts = {
    virt_text = true,
    virt_text_pos = "eol",
    delay = 300,
    ignore_whitespace = false,
  },
  current_line_blame_formatter = "<author>, <author_time:%R> - <summary>",
})
vim.keymap.set("n", "<leader>gb", ":Gitsigns toggle_current_line_blame<CR>", { silent = true, desc = "Toggle line blame" })

-- Treesitter: ensure Go is installed
vim.treesitter.language.add("go")
vim.treesitter.language.add("lua")

-- Auto-highlight symbol under cursor (LSP → treesitter → regex fallback)
require("illuminate").configure({
  delay = 120,
  providers = { "lsp", "treesitter", "regex" },
})

-- Autocomplete setup
local cmp = require("cmp")
local luasnip = require("luasnip")
cmp.setup({
  snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
  mapping = cmp.mapping.preset.insert({
    ["<C-Space>"] = cmp.mapping.complete(),
    ["<CR>"] = cmp.mapping.confirm({ select = true }),
    ["<Tab>"] = cmp.mapping.select_next_item(),
    ["<S-Tab>"] = cmp.mapping.select_prev_item(),
  }),
  sources = cmp.config.sources({
    { name = "nvim_lsp" },
    { name = "luasnip" },
  }, {
    { name = "buffer" },
    { name = "path" },
  }),
})

-- which-key setup (groups; per-mapping descriptions are defined in keymaps.lua)
local wk = require("which-key")
wk.setup({ preset = "modern" })
wk.add({
  { "<leader>g", group = "git" },
  { "<leader>r", group = "rename" },
  { "<leader>s", group = "search/replace" },
})

-- LSP: gopls (nvim 0.11+ native API)
vim.lsp.config.gopls = {
  cmd = { "gopls" },
  filetypes = { "go", "gomod", "gowork", "gotmpl" },
  root_markers = { "go.mod", "go.work", ".git" },
  capabilities = require("cmp_nvim_lsp").default_capabilities(),
  settings = {
    gopls = {
      analyses = { unusedparams = true, shadow = true },
      staticcheck = true,
      gofumpt = true,
    },
  },
}
vim.lsp.enable("gopls")

-- LSP: yaml-language-server (OpenAPI/Swagger $ref support)
vim.lsp.config.yamlls = {
  cmd = { "yaml-language-server", "--stdio" },
  filetypes = { "yaml", "yaml.docker-compose", "yaml.gitlab" },
  root_markers = { ".git" },
  capabilities = require("cmp_nvim_lsp").default_capabilities(),
  settings = {
    yaml = {
      schemaStore = { enable = false, url = "" },  -- provided via SchemaStore.nvim
      schemas = require("schemastore").yaml.schemas(),
      validate = true,
      hover = true,
      completion = true,
    },
    redhat = { telemetry = { enabled = false } },
  },
}
vim.lsp.enable("yamlls")

-- LSP keymaps (active once LSP attaches)
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local function o(desc) return { buffer = ev.buf, desc = desc } end
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, o("Go to definition"))
    vim.keymap.set("n", "gr", function()
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      -- yamlls doesn't support references → in-buffer grep fallback
      if client and not client.server_capabilities.referencesProvider then
        require("telescope.builtin").current_buffer_fuzzy_find({
          default_text = vim.fn.expand("<cword>"),
        })
      else
        require("telescope.builtin").lsp_references({ include_declaration = false })
      end
    end, o("References"))
    vim.keymap.set("n", "K", vim.lsp.buf.hover, o("Hover"))
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, o("LSP rename"))
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, o("Code action"))
    vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, o("Diagnostics float"))
    vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, o("Prev diagnostic"))
    vim.keymap.set("n", "]d", vim.diagnostic.goto_next, o("Next diagnostic"))
  end,
})
