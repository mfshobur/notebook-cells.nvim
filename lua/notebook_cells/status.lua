-- Execution status of cells, read from the text molten draws under each cell.
-- Molten has no API for this, but it always starts its output with a line such as
-- "Out[3]: ✓ Done 0.1s", anchored to the last line of the evaluated range.
local M = {}

local STATES = {
  { "On Hold", "hold" },
  { "Running", "running" },
  { "Done", "done" },
  { "Failed", "failed" },
  { "Never Run", "never" },
}

local function molten_namespaces()
  local list = {}
  for name, id in pairs(vim.api.nvim_get_namespaces()) do
    if name:lower():find("molten", 1, true) then list[#list + 1] = id end
  end
  return list
end

local function parse(header)
  local inner, rest = header:match("Out%[(.-)%]:%s*(.*)$")
  if not inner then return nil end
  local state
  for _, s in ipairs(STATES) do
    if rest:find(s[1], 1, true) then state = s[2] end
  end
  if not state then return nil end
  return { state = state, count = tonumber(inner), header = header, old = header:find("[OLD]", 1, true) ~= nil }
end

---Status entries keyed by the (0-based) row they are anchored to.
function M.by_row(buf)
  local found = {}
  for _, ns in ipairs(molten_namespaces()) do
    local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, buf, ns, 0, -1, { details = true })
    if ok then
      for _, m in ipairs(marks) do
        local lines = m[4].virt_lines
        if lines and lines[1] then
          local text = ""
          for _, chunk in ipairs(lines[1]) do text = text .. chunk[1] end
          local st = parse(text)
          if st then found[m[2]] = st end
        end
      end
    end
  end
  return found
end

---Status of the cell whose body spans the 1-based lines first..last.
function M.in_range(buf, first, last, rows)
  rows = rows or M.by_row(buf)
  for r = last - 1, first - 1, -1 do
    if rows[r] then return rows[r] end
  end
end

---True while at least one cell is waiting for or running on the kernel.
function M.busy(buf)
  for _, st in pairs(M.by_row(buf)) do
    if st.state == "hold" or st.state == "running" then return true end
  end
  return false
end

---A string that changes whenever any status text changes (used to redraw headers).
function M.signature(buf)
  local parts = {}
  for r, st in pairs(M.by_row(buf)) do parts[#parts + 1] = r .. st.header end
  table.sort(parts)
  return table.concat(parts, "|")
end

return M
