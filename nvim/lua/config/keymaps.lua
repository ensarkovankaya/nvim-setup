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
map("n", "<leader>fs", ":Telescope lsp_dynamic_workspace_symbols<CR>", { desc = "Find symbols (workspace, LSP)" })
map("n", "<leader>fo", ":Telescope lsp_document_symbols<CR>",          { desc = "Symbols in current file (LSP)" })
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

-- Pick a branch via Telescope, then run on_choice(branch) instead of checking out
local function diff_pick_branch(on_choice)
  local actions = require("telescope.actions")
  local astate = require("telescope.actions.state")
  require("telescope.builtin").git_branches({
    attach_mappings = function(bufnr)
      actions.select_default:replace(function()
        local entry = astate.get_selected_entry()
        actions.close(bufnr)
        if entry then on_choice(entry.value) end
      end)
      return true
    end,
  })
end

-- Git
map("n", "<leader>gg", ":LazyGit<CR>",               { desc = "LazyGit" })
map("n", "<leader>gf", ":LazyGitCurrentFile<CR>",    { desc = "LazyGit current file repo" })
map("n", "<leader>gd", ":DiffviewOpen<CR>",          { desc = "Diffview open" })
map("n", "<leader>gh", ":DiffviewFileHistory %<CR>", { desc = "Current file history" })
map("n", "<leader>gc", ":DiffviewClose<CR>",         { desc = "Diffview close" })

-- Compare against a branch (Telescope branch picker, no checkout)
-- Normal: whole file, native side-by-side split (gitsigns)
map("n", "<leader>gB", function()
  diff_pick_branch(function(branch)
    require("gitsigns").diffthis(branch)
  end)
end, { desc = "Diff file vs branch" })

-- Visual: only the selected line range, isolated side-by-side in a scratch tab
map("x", "<leader>gB", function()
  -- leave visual so '< and '> mark the selection
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
  local file = vim.fn.expand("%:p")
  if file == "" then return vim.notify("No file in buffer", vim.log.levels.WARN) end
  local dir = vim.fn.fnamemodify(file, ":h")
  local ft = vim.bo.filetype
  local cur = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
  diff_pick_branch(function(branch)
    local rel = vim.fn.systemlist({ "git", "-C", dir, "ls-files", "--full-name", "--", file })[1]
    if not rel or rel == "" then return vim.notify("File not tracked by git", vim.log.levels.WARN) end
    local all = vim.fn.systemlist({ "git", "-C", dir, "show", branch .. ":" .. rel })
    if vim.v.shell_error ~= 0 then
      return vim.notify("git show failed: " .. branch .. ":" .. rel, vim.log.levels.ERROR)
    end
    local other = {}
    for i = l1, math.min(l2, #all) do other[#other + 1] = all[i] end
    local function scratch(name, lines)
      local b = vim.api.nvim_get_current_buf()
      vim.bo[b].buftype, vim.bo[b].bufhidden, vim.bo[b].swapfile = "nofile", "wipe", false
      vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
      vim.bo[b].filetype = ft
      pcall(vim.api.nvim_buf_set_name, b, name)
      vim.cmd("diffthis")
    end
    vim.cmd("tabnew")
    scratch(branch .. " [" .. l1 .. "-" .. l2 .. "]", other)
    vim.cmd("rightbelow vsplit | enew")
    scratch("CURRENT [" .. l1 .. "-" .. l2 .. "]", cur)
  end)
end, { desc = "Diff selection vs branch" })

-- Tmux
if vim.env.TMUX then
  map("v", "<leader>y", function()
    vim.cmd('normal! "+y')
    vim.fn.system("tmux load-buffer -", vim.fn.getreg("+"))
  end, { desc = "Yank to tmux buffer" })
end

-- Insert mode
map("i", "jk", "<ESC>", { desc = "Exit insert mode" })
