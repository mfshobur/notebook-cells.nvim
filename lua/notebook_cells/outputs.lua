-- Keeping cell outputs in the .ipynb file (opt-in, see `outputs` in config.lua).
local config = require("notebook_cells.config")
local kernel = require("notebook_cells.kernel")
local minimal_diff = require("notebook_cells.minimal_diff")

local M = {}

local function notify(msg, level) vim.notify("notebook-cells: " .. msg, level or vim.log.levels.INFO) end

---Write molten's outputs into the notebook file (matching cells by their code).
function M.save(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local id = kernel.attached(buf)[1]
  if not id then return notify("no kernel for this notebook, nothing to save", vim.log.levels.WARN) end
  local file = vim.api.nvim_buf_get_name(buf)
  local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
    vim.cmd(("MoltenExportOutput! %s %s"):format(vim.fn.fnameescape(file), id))
  end)
  if not ok then return notify("saving outputs failed: " .. tostring(err), vim.log.levels.ERROR) end
  minimal_diff.snapshot(file)
end

---Show the outputs stored in the notebook file (needs a running kernel).
function M.load(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local id = kernel.attached(buf)[1]
  if not id then return notify("start the kernel first", vim.log.levels.WARN) end
  local file = vim.api.nvim_buf_get_name(buf)
  pcall(vim.api.nvim_buf_call, buf, function()
    vim.cmd(("MoltenImportOutput %s %s"):format(vim.fn.fnameescape(file), id))
  end)
end

---Called after every save of a notebook (after the minimal-diff step).
function M.after_write(buf, file)
  if vim.b[buf].notebook_cells_strip_outputs then
    vim.b[buf].notebook_cells_strip_outputs = nil
    local py = minimal_diff.python()
    if py then
      vim.fn.system({ py, minimal_diff.script_path(), "--clear-outputs", file })
      minimal_diff.snapshot(file)
    end
  end
  if config.options.outputs.save_on_write and kernel.is_running(buf) then M.save(buf) end
end

return M
