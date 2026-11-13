-- Keep `git diff` small: jupytext rewrites the whole .ipynb on save. We keep a
-- snapshot of the file as opened and, after each save, restore every unchanged
-- cell byte-for-byte (see scripts/nb_minimal_diff.py).
local config = require("notebook_cells.config")

local M = {}

local function script_path()
  local src = debug.getinfo(1, "S").source:sub(2)
  local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(src)))
  return root .. "/scripts/nb_minimal_diff.py"
end

local function python()
  local o = config.options.minimal_diff
  if o.python then return o.python end
  for _, exe in ipairs({ "python3", "python" }) do
    if vim.fn.executable(exe) == 1 then return exe end
  end
end

M.python = python
M.script_path = script_path

local function snap_path(file)
  return config.options.minimal_diff.snapshot_dir .. "/" .. vim.fn.sha256(vim.fn.resolve(file)) .. ".ipynb"
end

function M.snapshot(file)
  vim.fn.mkdir(config.options.minimal_diff.snapshot_dir, "p")
  vim.uv.fs_copyfile(file, snap_path(file), function() end)
end

function M.minimise(file)
  local snap = snap_path(file)
  local py = python()
  if not py or vim.fn.filereadable(snap) == 0 then return end
  local out = vim.fn.system({ py, script_path(), snap, file })
  if vim.v.shell_error ~= 0 then
    vim.notify("notebook-cells: minimal-diff failed: " .. out, vim.log.levels.WARN)
    return
  end
  vim.uv.fs_copyfile(file, snap, function() end)
end

return M
