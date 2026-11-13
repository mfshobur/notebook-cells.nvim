-- Run: nvim --headless -u NONE -l tests/smoke.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local failures = 0
local function check(name, cond, extra)
  if cond then
    print("ok   " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name .. (extra and (" -> " .. tostring(extra)) or ""))
  end
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local nb = tmp .. "/test.ipynb"

require("notebook_cells").setup({ minimal_diff = { enabled = false } })
vim.cmd("edit " .. nb)
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "# %%",
  "import os",
  "x = 1",
  "",
  "# %% [markdown]",
  "# # Title",
  "# some text",
  "",
  "# %%",
  "print(x)",
})
vim.cmd("doautocmd BufEnter")

local row = function() return vim.api.nvim_win_get_cursor(0)[1] end
local line = function() return vim.api.nvim_get_current_line() end
local cells = require("notebook_cells.cells")
local ns = vim.api.nvim_get_namespaces().notebook_cells

check("parses 3 cells", #cells.parse(0) == 3, #cells.parse(0))
check("markdown cell detected", cells.parse(0)[2].md == true)
check("renders extmarks", #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) > 0)
check("starts in command mode on first header", row() == 1 and require("notebook_cells.state").mode[vim.api.nvim_get_current_buf()] == "command", row())

vim.cmd("normal j")
check("command mode: j jumps to next cell header", row() == 5, row())
vim.cmd("normal k")
check("command mode: k jumps back", row() == 1, row())

vim.cmd("normal j")
vim.cmd("lua require('notebook_cells.actions').enter_edit(false)")
check("enter edit lands on first body line", row() == 6, row())
vim.cmd("normal j")
check("edit mode: j moves by row", row() == 7, row())
vim.cmd("normal kk")
vim.cmd("doautocmd CursorMoved")
check("edit mode: header is not enterable", not cells.is_marker(line()), line())

require("notebook_cells.actions").exit_edit()
check("exit edit returns to header", cells.is_marker(line()), line())

-- add / toggle / delete
local before = #cells.parse(0)
require("notebook_cells.actions").add_cell(false)
check("add cell below", #cells.parse(0) == before + 1)
check("new cell body line exists", (function()
  local cs = cells.parse(0)
  local i = cells.cell_at(cs, row())
  return cs[i].e > cs[i].s
end)())

require("notebook_cells.actions").delete_cell()
check("delete cell", #cells.parse(0) == before)

vim.api.nvim_win_set_cursor(0, { 1, 0 })
require("notebook_cells.actions").toggle_markdown()
check("toggle code -> markdown", cells.parse(0)[1].md and vim.api.nvim_buf_get_lines(0, 1, 2, false)[1] == "# import os")
require("notebook_cells.actions").toggle_markdown()
check("toggle markdown -> code", not cells.parse(0)[1].md and vim.api.nvim_buf_get_lines(0, 1, 2, false)[1] == "import os")

-- jupytext front matter
vim.api.nvim_buf_set_lines(0, 0, 0, false, { "# ---", "# jupyter:", "#   kernelspec:", "# ---", "" })
require("notebook_cells.ui").render(0)
local h1, h2 = cells.header_range(vim.api.nvim_buf_get_lines(0, 0, -1, false))
check("detects jupytext front matter", h1 == 1 and h2 == 4, tostring(h2))
if vim.fn.has("nvim-0.11") == 1 then
  local hidden = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
  local n = 0
  for _, m in ipairs(hidden) do if m[4].conceal_lines then n = n + 1 end end
  check("front matter lines are concealed", n == 4, n)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("doautocmd CursorMoved")
  check("cursor skips hidden front matter", row() == 6, row())
end

-- kernel naming / venv detection
local kernel = require("notebook_cells.kernel")
check("kernel name is a valid kernelspec name", kernel.kernel_name("/a/b c/.venv"):match("^[%w%._%-]+$") ~= nil)
check("no venv found in empty dir", kernel.find_venv(0) == nil)

vim.fn.delete(tmp, "rf")
if failures > 0 then
  print(failures .. " check(s) failed")
  os.exit(1)
end
print("all checks passed")
vim.cmd("qa!")
