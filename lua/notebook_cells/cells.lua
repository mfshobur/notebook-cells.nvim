-- Parsing of jupytext "percent" buffers (`# %%` cell markers).
local M = {}

function M.is_marker(line) return line:match("^# %%%%") ~= nil end
function M.is_markdown(line) return line:match("^# %%%%%s*%[markdown%]") ~= nil end

---@class NotebookCell
---@field s integer  1-based line of the `# %%` marker
---@field e integer  1-based last body line (trailing blank lines trimmed, but at least one body line)
---@field md boolean markdown cell

---@return NotebookCell[] cells, string[] lines
function M.parse(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cells = {}
  for i, l in ipairs(lines) do
    if M.is_marker(l) then
      if #cells > 0 then cells[#cells].e = i - 1 end
      cells[#cells + 1] = { s = i, md = M.is_markdown(l) }
    end
  end
  if #cells > 0 then cells[#cells].e = #lines end
  for _, c in ipairs(cells) do
    while c.e > c.s + 1 and lines[c.e]:match("^%s*$") do c.e = c.e - 1 end
  end
  return cells, lines
end

---Line range (1-based, inclusive) of jupytext's `# ---` YAML front matter, or nil.
function M.header_range(lines)
  if lines[1] ~= "# ---" then return nil end
  for i = 2, math.min(#lines, 200) do
    if lines[i] == "# ---" then return 1, i end
    if M.is_marker(lines[i]) then return nil end
  end
  return nil
end

---Index of the cell containing `row` (1-based), or nil before the first cell.
function M.cell_at(cells, row)
  local found
  for i, c in ipairs(cells) do
    if c.s <= row then found = i else break end
  end
  return found
end

---Body line range (first, last) of the cell containing `row`.
function M.body_range(buf, row)
  local cells = M.parse(buf)
  local i = M.cell_at(cells, row)
  if not i then return nil end
  return cells[i].s + 1, cells[i].e
end

return M
