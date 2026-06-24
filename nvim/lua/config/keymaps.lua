vim.g.mapleader = " "   -- set Space as leader key

local map = vim.keymap.set

-- Normal mode
map("n", "<leader>w", ":w<CR>",  { desc = "Save" })
map("n", "<leader>q", ":q<CR>",  { desc = "Quit" })
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })

-- File explorer
map("n", "<leader>e", ":NvimTreeToggle<CR>", { desc = "Toggle file tree" })
map("n", "<leader>f", ":NvimTreeFocus<CR>",  { desc = "Focus file tree" })

-- Telescope (searches from cwd)
map("n", "<leader>ff", ":Telescope find_files<CR>", { desc = "Find files" })
map("n", "<leader>fg", ":Telescope live_grep<CR>",  { desc = "Live grep" })
map("n", "<leader>/",  ":Telescope current_buffer_fuzzy_find<CR>", { desc = "Search in buffer" })

-- Find & replace (Spectre)
map("n", "<leader>sr", function() require("spectre").open() end, { desc = "Find & replace (project)" })
map("n", "<leader>sf", function() require("spectre").open_file_search({ select_word = true }) end, { desc = "Find & replace (current file)" })
map("n", "<leader>sw", function() require("spectre").open_visual({ select_word = true }) end, { desc = "Replace word under cursor" })
map("v", "<leader>sw", function() require("spectre").open_visual() end, { desc = "Replace selection" })

-- Change cwd to nvim-tree's focused directory
map("n", "<leader>cd", function()
  local api = require("nvim-tree.api")
  local node = api.tree.get_node_under_cursor()
  if node then
    local path = node.type == "directory" and node.absolute_path or vim.fn.fnamemodify(node.absolute_path, ":h")
    vim.cmd("cd " .. path)
    vim.notify("cwd → " .. path)
  end
end, { desc = "cd to tree dir" })

-- Git
map("n", "<leader>gg", ":LazyGit<CR>",               { desc = "LazyGit" })
map("n", "<leader>gf", ":LazyGitCurrentFile<CR>",    { desc = "LazyGit current file repo" })
map("n", "<leader>gd", ":DiffviewOpen<CR>",          { desc = "Diffview open" })
map("n", "<leader>gh", ":DiffviewFileHistory %<CR>", { desc = "Current file history" })
map("n", "<leader>gc", ":DiffviewClose<CR>",         { desc = "Diffview close" })

-- Tmux
if vim.env.TMUX then
  map("v", "<leader>y", function()
    vim.cmd('normal! "+y')
    vim.fn.system("tmux load-buffer -", vim.fn.getreg("+"))
  end, { desc = "Yank to tmux buffer" })
end

-- Insert mode
map("i", "jk", "<ESC>", { desc = "Exit insert mode" })
