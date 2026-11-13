-- Cell navigation, editing and execution actions (the public Lua API builds on these).
local cells_mod = require("notebook_cells.cells")
local state = require("notebook_cells.state")
local ui = require("notebook_cells.ui")
local kernel = require("notebook_cells.kernel")

local M = {}

local function cur_buf() return vim.api.nvim_get_current_buf() end
local function cur_row() return vim.api.nvim_win_get_cursor(0)[1] end
local function notify(msg, level) vim.notify("notebook-cells: " .. msg, level or vim.log.levels.INFO) end

---Last line (inclusive) that belongs to cell `i`, including its trailing blank lines.
local function full_end(cells, i, total)
  return cells[i + 1] and (cells[i + 1].s - 1) or total
end

---Make sure the buffer ends with a blank line so every cell block is followed by one.
local function ensure_trailing_blank(buf)
  local n = vim.api.nvim_buf_line_count(buf)
  local last = vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1]
  if last ~= "" then vim.api.nvim_buf_set_lines(buf, n, n, false, { "" }) end
end

---Keep at least one cell in the buffer (like Jupyter): add an empty code cell if there is none.
function M.ensure_cell(buf)
  buf = (buf == nil or buf == 0) and cur_buf() or buf
  if #cells_mod.parse(buf) > 0 then return false end
  local n = vim.api.nvim_buf_line_count(buf)
  local last = vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1]
  local new = (last == "") and { "# %%", "" } or { "", "# %%", "" }
  vim.api.nvim_buf_set_lines(buf, n, n, false, new)
  return true
end

-- ── navigation and modes ──────────────────────────────────────────────────

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

-- ── structure: add / delete / copy / paste / move / merge / split ─────────

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

---Lines of the current cell (header included, trailing blanks removed).
local function cell_lines(buf, cells, lines, i)
  local out = {}
  for r = cells[i].s, cells[i].e do out[#out + 1] = lines[r] end
  return out
end

function M.copy_cell()
  local buf = cur_buf()
  local cells, lines = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, cur_row())
  if not i then return end
  state.clipboard = cell_lines(buf, cells, lines, i)
  notify("cell copied")
end

function M.delete_cell()
  local buf = cur_buf()
  local cells, lines = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, cur_row())
  if not i then return end
  state.clipboard = cell_lines(buf, cells, lines, i)
  local total = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, cells[i].s - 1, full_end(cells, i, total), false, {})
  M.ensure_cell(buf)
  local remaining = cells_mod.parse(buf)
  local j = math.min(i, #remaining)
  if j >= 1 then vim.api.nvim_win_set_cursor(0, { remaining[j].s, 0 }) end
  ui.render(buf)
end

M.cut_cell = M.delete_cell

function M.paste_cell(above)
  local clip = state.clipboard
  if not clip or #clip == 0 then return notify("no cell to paste", vim.log.levels.WARN) end
  local buf = cur_buf()
  local cells = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, cur_row())
  if not i then
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, vim.list_extend({ "" }, clip))
    return ui.render(buf)
  end
  if above then
    local block = vim.list_extend(vim.deepcopy(clip), { "" })
    vim.api.nvim_buf_set_lines(buf, cells[i].s - 1, cells[i].s - 1, false, block)
    vim.api.nvim_win_set_cursor(0, { cells[i].s, 0 })
  else
    local block = vim.list_extend({ "" }, clip)
    vim.api.nvim_buf_set_lines(buf, cells[i].e, cells[i].e, false, block)
    vim.api.nvim_win_set_cursor(0, { cells[i].e + 2, 0 })
  end
  state.mode[buf] = "command"
  ui.render(buf)
end

---Move the current cell up (dir = -1) or down (dir = 1). Uses :move so that
---extmarks (and therefore molten outputs) travel with the cell.
function M.move_cell(dir)
  local buf = cur_buf()
  ensure_trailing_blank(buf)
  local cells = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, cur_row())
  local j = i and (i + dir)
  if not i or j < 1 or j > #cells then return end
  local total = vim.api.nvim_buf_line_count(buf)
  local rel = cur_row() - cells[i].s -- keep the cursor at the same offset inside the cell
  local new_start
  if dir < 0 then
    vim.cmd(("silent keepjumps %d,%dmove %d"):format(cells[i].s, full_end(cells, i, total), cells[j].s - 1))
    new_start = cells[j].s
  else
    vim.cmd(("silent keepjumps %d,%dmove %d"):format(cells[i].s, full_end(cells, i, total), full_end(cells, j, total)))
    new_start = cells[i].s + (full_end(cells, j, total) - cells[j].s + 1)
  end
  vim.api.nvim_win_set_cursor(0, { new_start + rel, 0 })
  ui.render(buf)
end

---Merge the current cell with the one below it (both must be the same type).
function M.merge_below()
  local buf = cur_buf()
  local cells = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, cur_row())
  if not i or not cells[i + 1] then return end
  if cells[i].md ~= cells[i + 1].md then
    return notify("can only merge cells of the same type", vim.log.levels.WARN)
  end
  -- replace the blank lines + the next marker with a single blank line
  vim.api.nvim_buf_set_lines(buf, cells[i].e, cells[i + 1].s, false, { "" })
  ui.render(buf)
end

---Split the current cell at the cursor (code cells split inside the line,
---markdown cells at the start of the line).
function M.split_cell()
  local buf = cur_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local cells, lines = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, pos[1])
  if not i or pos[1] == cells[i].s then return end
  local md = cells[i].md
  local line = lines[pos[1]]
  local marker = md and "# %% [markdown]" or "# %%"
  local new
  if md or pos[2] == 0 then
    new = { "", marker, line }
  else
    new = { line:sub(1, pos[2]), "", marker, line:sub(pos[2] + 1) }
    if md then new[#new] = "# " .. new[#new] end
  end
  vim.api.nvim_buf_set_lines(buf, pos[1] - 1, pos[1], false, new)
  vim.api.nvim_win_set_cursor(0, { pos[1] + #new - 1, 0 })
  ui.render(buf)
end

local function set_type(markdown)
  local buf = cur_buf()
  local cells, lines = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, cur_row())
  if not i then return end
  local c = cells[i]
  if c.md == markdown then return end
  local new = {}
  if markdown then
    new[1] = "# %% [markdown]"
    for r = c.s + 1, c.e do new[#new + 1] = "# " .. lines[r] end
  else
    new[1] = "# %%"
    for r = c.s + 1, c.e do new[#new + 1] = (lines[r]:gsub("^# ?", "", 1)) end
  end
  vim.api.nvim_buf_set_lines(buf, c.s - 1, c.e, false, new)
  ui.render(buf)
end

function M.to_markdown() set_type(true) end
function M.to_code() set_type(false) end

function M.toggle_markdown()
  local cells = cells_mod.parse(cur_buf())
  local i = cells_mod.cell_at(cells, cur_row())
  if i then set_type(not cells[i].md) end
end

-- ── execution ─────────────────────────────────────────────────────────────

---Body line ranges of the non-empty code cells selected by `pred(index, cell)`.
local function code_ranges(buf, pred)
  local cells, lines = cells_mod.parse(buf)
  local list = {}
  for i, c in ipairs(cells) do
    if not c.md and pred(i, c) then
      for r = c.s + 1, c.e do
        if lines[r]:match("%S") then
          list[#list + 1] = { c.s + 1, c.e }
          break
        end
      end
    end
  end
  return list
end

---Evaluate line ranges in order, starting the kernel first when needed.
function M.run_ranges(ranges, after)
  local buf = cur_buf()
  if #ranges == 0 then
    if after then after() end
    return
  end
  kernel.ensure_ready(function()
    vim.api.nvim_buf_call(buf, function()
      local id = kernel.attached(buf)[1]
      for _, r in ipairs(ranges) do
        vim.fn.MoltenEvaluateRange(id, r[1], r[2])
      end
    end)
    if after then after() end
  end)
end

---Run the current cell. With advance = true move to the next one, adding a
---new cell when you are on the last cell (like Shift+Enter in Jupyter).
function M.run_cell(advance, insert)
  local buf = cur_buf()
  local cells = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, cur_row())
  if not i then return notify("no cell here", vim.log.levels.WARN) end
  local c = cells[i]
  local function after()
    if insert or (advance and not cells[i + 1]) then
      -- cursor may have moved while the kernel started: go back to the cell first
      if cells_mod.cell_at(cells_mod.parse(buf), cur_row()) ~= i then return end
      M.add_cell(false)
      M.enter_edit(true)
    elseif advance then
      M.goto_cell(1)
    end
  end
  if c.md then return after() end
  M.run_ranges(code_ranges(buf, function(k) return k == i end), after)
end

function M.run_and_insert() M.run_cell(false, true) end

function M.run_all() M.run_ranges(code_ranges(cur_buf(), function() return true end)) end

function M.run_above()
  local buf = cur_buf()
  local cur = cells_mod.cell_at(cells_mod.parse(buf), cur_row()) or 1
  M.run_ranges(code_ranges(buf, function(k) return k < cur end))
end

---Run the current cell and all cells below it.
function M.run_below()
  local buf = cur_buf()
  local cur = cells_mod.cell_at(cells_mod.parse(buf), cur_row()) or 1
  M.run_ranges(code_ranges(buf, function(k) return k >= cur end))
end

function M.interrupt() kernel.interrupt() end

---Restart the kernel (clear = true also removes all outputs).
function M.restart(clear) kernel.restart(clear) end

function M.restart_and_run_all(clear)
  kernel.restart(clear, function() M.run_all() end)
end

-- ── outputs ───────────────────────────────────────────────────────────────

---Remove the output of the cell under the cursor.
function M.clear_cell_output()
  local buf = cur_buf()
  if not kernel.is_running(buf) then return end
  local pos = vim.api.nvim_win_get_cursor(0)
  local cells = cells_mod.parse(buf)
  local i = cells_mod.cell_at(cells, pos[1])
  if not i then return end
  -- in command mode the cursor is on the header, outside the evaluated range
  vim.api.nvim_win_set_cursor(0, { math.min(cells[i].s + 1, vim.api.nvim_buf_line_count(buf)), 0 })
  pcall(vim.fn.MoltenOnCursorMoved)
  pcall(vim.cmd, "MoltenDelete")
  vim.api.nvim_win_set_cursor(0, pos)
  ui.render(buf)
end

---Remove the outputs of every cell.
function M.clear_all_outputs()
  local buf = cur_buf()
  -- also drop the outputs stored in the file the next time the notebook is saved
  vim.b[buf].notebook_cells_strip_outputs = true
  if not kernel.is_running(buf) then return end
  local pos = vim.api.nvim_win_get_cursor(0)
  for _, c in ipairs(cells_mod.parse(buf)) do
    vim.api.nvim_win_set_cursor(0, { math.min(c.s + 1, vim.api.nvim_buf_line_count(buf)), 0 })
    -- molten only learns the selected cell from a cursor event
    pcall(vim.fn.MoltenOnCursorMoved)
    pcall(vim.cmd, "MoltenDelete")
  end
  vim.api.nvim_win_set_cursor(0, pos)
  ui.render(buf)
end

return M
