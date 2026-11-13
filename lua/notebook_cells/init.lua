local M = {}

local function is_notebook(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  for _, pat in ipairs(require("notebook_cells.config").options.patterns) do
    if vim.regex(vim.fn.glob2regpat(pat)):match_str(name) then return true end
  end
  return false
end

---@param opts? table  see `lua/notebook_cells/config.lua` for all options
function M.setup(opts)
  local config = require("notebook_cells.config")
  local ui = require("notebook_cells.ui")
  local cells = require("notebook_cells.cells")
  local state = require("notebook_cells.state")
  local actions = require("notebook_cells.actions")
  local o = config.setup(opts)

  ui.setup_highlights()
  require("notebook_cells.kernel").setup()
  local group = vim.api.nvim_create_augroup("NotebookCells", { clear = true })
  local patterns = o.patterns

  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = ui.setup_highlights })

  -- attach: window options, initial mode, keymaps
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = group,
    pattern = patterns,
    callback = function(a)
      ui.apply_window_options(0)
      if state.mode[a.buf] == nil then
        state.mode[a.buf] = o.modal and "command" or "edit"
        local was_modified = vim.bo[a.buf].modified
        if actions.ensure_cell(a.buf) then vim.bo[a.buf].modified = was_modified end
        local cs = cells.parse(a.buf)
        if o.modal and cs[1] then vim.api.nvim_win_set_cursor(0, { cs[1].s, 0 }) end
      end
      if not vim.b[a.buf].notebook_cells_attached then
        vim.b[a.buf].notebook_cells_attached = true
        require("notebook_cells.keymaps").attach(a.buf)
      end
      ui.render(a.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    pattern = patterns,
    callback = function() ui.restore_window_options(0) end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    pattern = patterns,
    callback = function(a) ui.render(a.buf) end,
  })

  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(win)
        if is_notebook(b) then ui.render(b) end
      end
    end,
  })

  -- re-render only when the active cell changes
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    pattern = patterns,
    callback = function(a)
      local cs, lines = cells.parse(a.buf)
      local row = vim.api.nvim_win_get_cursor(0)[1]
      -- hidden front matter: never leave the cursor inside it
      if o.hide_header and vim.fn.has("nvim-0.11") == 1 and cs[1] then
        local _, h2 = cells.hidden_range(lines)
        if h2 and row <= h2 then
          row = cs[1].s
          vim.api.nvim_win_set_cursor(0, { row, 0 })
        end
      end
      -- edit mode: the header line is not editable, bounce into the body
      if state.mode[a.buf] == "edit" and lines[row] and cells.is_marker(lines[row]) then
        if row == #lines then vim.api.nvim_buf_set_lines(a.buf, -1, -1, false, { "" }) end
        row = row + 1
        vim.api.nvim_win_set_cursor(0, { row, 0 })
      end
      if cells.cell_at(cs, row) ~= state.active[a.buf] then ui.render(a.buf) end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    pattern = patterns,
    callback = function(a)
      state.mode[a.buf], state.active[a.buf], state.starting[a.buf] = nil, nil, nil
    end,
  })

  if o.minimal_diff.enabled then
    local md = require("notebook_cells.minimal_diff")
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      pattern = patterns,
      callback = function(a)
        if not vim.b[a.buf].notebook_cells_snapshot then
          vim.b[a.buf].notebook_cells_snapshot = true
          md.snapshot(a.file)
        end
      end,
    })
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      pattern = patterns,
      callback = function(a)
        md.minimise(a.file)
        require("notebook_cells.outputs").after_write(a.buf, a.file)
      end,
    })
  end

  local commands = {
    NotebookCellsRun = function() actions.run_cell(false) end,
    NotebookCellsRunNext = function() actions.run_cell(true) end,
    NotebookCellsRunAll = function() actions.run_all() end,
    NotebookCellsRunAbove = function() actions.run_above() end,
    NotebookCellsRunBelow = function() actions.run_below() end,
    NotebookCellsInterrupt = function() actions.interrupt() end,
    NotebookCellsRestart = function(c) actions.restart(c.bang) end,
    NotebookCellsRestartRunAll = function(c) actions.restart_and_run_all(c.bang) end,
    NotebookCellsClearOutput = function() actions.clear_cell_output() end,
    NotebookCellsClearAllOutputs = function() actions.clear_all_outputs() end,
    NotebookCellsSaveOutputs = function() require("notebook_cells.outputs").save() end,
    NotebookCellsLoadOutputs = function() require("notebook_cells.outputs").load() end,
    NotebookCellsKernel = function() require("notebook_cells.kernel").start() end,
    NotebookCellsSelectKernel = function() require("notebook_cells.kernel").select() end,
  }
  for name, fn in pairs(commands) do
    vim.api.nvim_create_user_command(name, fn, { bang = name:find("Restart") ~= nil })
  end
end

-- Lua API -------------------------------------------------------------------
local function lazy(mod, fn)
  return function(...) return require("notebook_cells." .. mod)[fn](...) end
end
M.run_cell = lazy("actions", "run_cell")
M.run_all = lazy("actions", "run_all")
M.run_above = lazy("actions", "run_above")
M.run_below = lazy("actions", "run_below")
M.interrupt = lazy("actions", "interrupt")
M.restart = lazy("actions", "restart")
M.restart_and_run_all = lazy("actions", "restart_and_run_all")
M.clear_cell_output = lazy("actions", "clear_cell_output")
M.clear_all_outputs = lazy("actions", "clear_all_outputs")
M.goto_cell = lazy("actions", "goto_cell")
M.new_cell = lazy("actions", "new_cell")
M.move_cell = lazy("actions", "move_cell")
M.merge_below = lazy("actions", "merge_below")
M.split_cell = lazy("actions", "split_cell")
M.start_kernel = lazy("kernel", "start")
M.select_kernel = lazy("kernel", "select")
M.status = lazy("kernel", "status")
M.save_outputs = lazy("outputs", "save")
M.load_outputs = lazy("outputs", "load")
M.render = lazy("ui", "render")

return M
