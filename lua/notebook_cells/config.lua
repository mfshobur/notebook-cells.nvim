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
    -- command mode (act on cells; in edit mode these keys keep their normal Vim meaning)
    next_cell = "j",
    prev_cell = "k",
    edit = { "<CR>", "i" },
    add_above = "a",
    add_below = "b",
    delete_cell = "dd",
    cut_cell = "x",
    copy_cell = "c",
    paste_below = "v",
    paste_above = "V",
    merge_below = "M",
    to_markdown = "m",
    to_code = "y",
    -- mode switching (modal = true)
    exit_edit = "<Esc>",
    click_to_edit = "<LeftMouse>",
    -- always available
    jump_next = "]c",
    jump_prev = "[c",
    run_cell = { "<leader>mc", "<C-CR>" },
    run_and_next = { "<leader>mn", "<S-CR>" },
    run_and_insert = { "<leader>mO", "<A-CR>" },
    run_all = "<leader>mR",
    run_above = "<leader>mU",
    run_below = "<leader>mB",
    interrupt = "<leader>mx",
    restart = "<leader>mK",
    restart_and_run_all = "<leader>mZ",
    clear_cell_output = "<leader>mC",
    clear_all_outputs = "<leader>mX",
    move_up = "<leader>m[",
    move_down = "<leader>m]",
    split_cell = "<leader>ms",
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

  -- Keeping cell outputs in the .ipynb file. Off by default.
  outputs = {
    -- After each save, write molten's outputs of the executed cells into the file.
    save_on_write = false,
    -- When the kernel first becomes ready, show the outputs stored in the file.
    load_on_start = false,
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
