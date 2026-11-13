local M = {}

---@class NotebookCellsKeymaps
---Command-mode keys (act on cells; in edit mode they behave like normal Vim).
---Each value is a key, a list of keys, or `false` to disable.
M.defaults = {
  -- Buffers to attach to (autocmd patterns).
  patterns = { "*.ipynb" },

  -- Text shown in the cell header.
  labels = { code = "Python", markdown = "Markdown" },

  -- Characters used to draw the cells.
  border = { top = "╭─", rule = "─", bottom = "╰", bar = "▎" },

  -- Hide jupytext's `# ---` YAML front matter at the top of the buffer
  -- (needs Neovim 0.11+; the lines are still saved with the notebook).
  hide_header = true,

  -- Jupyter-style command/edit modes (j/k move between cells until you press
  -- <CR>/i to edit). Set to false to always behave like a normal buffer.
  modal = true,

  -- Override highlight groups, e.g. { Active = { fg = "#ff0000" } }.
  -- Group names are NotebookCells<Name>: CodeBody, MarkdownBody, Idle,
  -- IdleMarkdown, Active, ActiveMarkdown, Edit, CodeLabel, MarkdownLabel.
  highlights = {},

  -- Buffer-local keymaps. Use `false` to disable one, or `keymaps = false`
  -- to disable all of them and call the Lua API yourself.
  keymaps = {
    -- command mode
    next_cell = "j",
    prev_cell = "k",
    edit = { "<CR>", "i" },
    add_above = "a",
    add_below = "b",
    delete_cell = "dd",
    toggle_markdown = "m",
    -- mode switching (modal = true)
    exit_edit = "<Esc>",
    click_to_edit = "<LeftMouse>",
    -- always available
    jump_next = "]c",
    jump_prev = "[c",
    run_cell = "<leader>mc",
    run_and_next = { "<leader>mn", "<S-CR>" },
    new_code_below = "<leader>ma",
    new_markdown_below = "<leader>mA",
    start_kernel = "<leader>mi",
    pick_kernel = "<leader>mI",
  },

  -- Kernel handling (requires molten-nvim).
  kernel = {
    enabled = true,
    -- Directory names searched upward from the notebook for a virtualenv.
    venv_dirs = { ".venv", "venv" },
    -- Also fall back to $VIRTUAL_ENV when no venv dir is found.
    use_virtual_env = true,
    -- "ask" | true | false: install ipykernel into the venv when missing.
    install_ipykernel = "ask",
    -- Open molten's kernel picker when no venv is found.
    fallback_picker = true,
    -- How long to wait for the kernel to come up (ms).
    startup_timeout = 10000,
  },

  -- Keep `git diff` small: after each save, restore every unchanged cell
  -- byte-for-byte (needs a python3 on PATH; the helper uses only the stdlib).
  minimal_diff = {
    enabled = true,
    python = nil, -- default: first of python3 / python on PATH
    snapshot_dir = vim.fn.stdpath("cache") .. "/notebook-cells",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  -- tbl_deep_extend merges lists by index; let users replace them wholesale.
  if opts and opts.patterns then M.options.patterns = opts.patterns end
  if opts and opts.kernel and opts.kernel.venv_dirs then
    M.options.kernel.venv_dirs = opts.kernel.venv_dirs
  end
  return M.options
end

return M
