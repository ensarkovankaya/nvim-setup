local opt = vim.opt

opt.number = true          -- line numbers
opt.relativenumber = true  -- relative line numbers
opt.tabstop = 2            -- tab width
opt.shiftwidth = 2
opt.expandtab = true       -- use spaces instead of tabs
opt.smartindent = true
opt.wrap = true            -- enable line wrapping
opt.termguicolors = true   -- enable 24-bit colors
opt.clipboard = "unnamedplus"  -- sync with system clipboard
opt.scrolloff = 8          -- keep 8 lines above/below cursor
opt.signcolumn = "yes"     -- always show sign column (LSP diagnostics)
opt.timeoutlen = 300       -- which-key popup delay

-- Go: use tabs, width 4
vim.api.nvim_create_autocmd("FileType", {
  pattern = "go",
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.expandtab = false
  end,
})
