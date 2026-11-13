-- Cell navigation / editing actions (the public Lua API builds on these).
local cells_mod = require("notebook_cells.cells")
local config = require("notebook_cells.config")
local state = require("notebook_cells.state")
local ui = require("notebook_cells.ui")

local M = {}

local function cur_buf() return vim.api.nvim_get_current_buf() end
local function cur_row() return vim.api.nvim_win_get_cursor(0)[1] end

---Move to the next (dir = 1) or previous (dir = -1) cell.
---In command mode the cursor lands on the header, in edit mode on the first body line.
function M.goto_cell(dir)
  local buf = cur_buf()
  local cells = cells_mod.parse(buf)
  local cur = cells_mod.cell_at(cells, cur_row()) or 0
  local tgt = cur + dir
  if tgt < 1 or tgt > #cells then return end
  local c = cells[tgt]
  local line = (state.mode[buf] == "edit") and math.min(c.s + 1, c.e) or c.s
  vim.api.nvim_win_set_cursor(0, { line, 0 })
end

---Switch between "command" (cell selected) and "edit" mode.
function M.set_mode(buf, m)
  buf = (buf == nil or buf == 0) and cur_buf() or buf
  state.mode[buf] = m
  if m == "edit" then
    local cs = cells_mod.parse(buf)
    local ci = cells_mod.cell_at(cs, cur_row())
    -- an empty last cell may have no body line yet
    if ci and cs[ci].s == vim.api.nvim_buf_line_count(buf) then
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
    end
  end
  local cells = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, cur_row())
  if i then
    local c = cells[i]
    if m == "command" then
      vim.api.nvim_win_set_cursor(0, { c.s, 0 })
    elseif cur_row() == c.s then
      vim.api.nvim_win_set_cursor(0, { math.min(c.s + 1, c.e), 0 })
    end
  end
  ui.render(buf)
end

function M.enter_edit(insert)
  M.set_mode(0, "edit")
  if insert then vim.cmd("startinsert!") end
end

function M.exit_edit() M.set_mode(0, "command") end

function M.click()
  local buf = cur_buf()
  state.mode[buf] = "edit"
  ui.render(buf)
end

---Add a cell above/below the current one (command mode).
function M.add_cell(above)
  local buf = cur_buf()
  local cells = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, cur_row())
  if not i then return end
  local c = cells[i]
  if above then
    vim.api.nvim_buf_set_lines(buf, c.s - 1, c.s - 1, false, { "# %%", "", "" })
    vim.api.nvim_win_set_cursor(0, { c.s, 0 })
  else
    vim.api.nvim_buf_set_lines(buf, c.e, c.e, false, { "", "# %%", "" })
    vim.api.nvim_win_set_cursor(0, { c.e + 2, 0 })
  end
  ui.render(buf)
end

function M.delete_cell()
  local buf = cur_buf()
  local cells = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, cur_row())
  if not i then return end
  local from = cells[i].s - 1
  local to = cells[i + 1] and (cells[i + 1].s - 1) or vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, from, to, false, {})
  local remaining = cells_mod.parse(buf)
  local j = math.min(i, #remaining)
  if j >= 1 then vim.api.nvim_win_set_cursor(0, { remaining[j].s, 0 }) end
  ui.render(buf)
end

function M.toggle_markdown()
  local buf = cur_buf()
  local cells, lines = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, cur_row())
  if not i then return end
  local c = cells[i]
  local new = {}
  if c.md then
    new[1] = "# %%"
    for r = c.s + 1, c.e do new[#new + 1] = (lines[r]:gsub("^# ?", "", 1)) end
  else
    new[1] = "# %% [markdown]"
    for r = c.s + 1, c.e do new[#new + 1] = "# " .. lines[r] end
  end
  vim.api.nvim_buf_set_lines(buf, c.s - 1, c.e, false, new)
  ui.render(buf)
end

---Append a new cell after the current one and start typing in it.
function M.new_cell(markdown)
  local buf = cur_buf()
  local _, e = cells_mod.body_range(buf, cur_row())
  e = e or cur_row()
  vim.api.nvim_buf_set_lines(buf, e, e, false, { "", markdown and "# %% [markdown]" or "# %%", markdown and "# " or "" })
  vim.api.nvim_win_set_cursor(0, { e + 3, 0 })
  state.mode[buf] = "edit"
  ui.render(buf)
  vim.cmd("startinsert!")
end

---Evaluate the current cell with molten (starting the project's kernel if needed).
function M.run_cell(advance)
  local kernel = require("notebook_cells.kernel")
  if config.options.kernel.enabled and not kernel.is_running() then
    kernel.start(function() M.run_cell(advance) end)
    return
  end
  local buf = cur_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local s, e = cells_mod.body_range(buf, pos[1])
  if not s or s > e then return vim.notify("notebook-cells: no cell here", vim.log.levels.WARN) end
  vim.api.nvim_win_set_cursor(0, { s, 0 })
  vim.cmd("normal! V")
  vim.api.nvim_win_set_cursor(0, { e, 0 })
  vim.cmd("normal! \27")
  vim.cmd("MoltenEvaluateVisual")
  vim.api.nvim_win_set_cursor(0, pos)
  if advance then M.goto_cell(1) end
end

return M
