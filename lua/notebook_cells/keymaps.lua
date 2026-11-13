-- Buffer-local keymaps (all configurable / disable-able via `keymaps`).
local config = require("notebook_cells.config")
local state = require("notebook_cells.state")

local M = {}

local function as_list(v)
  if not v then return {} end
  if type(v) == "string" then return { v } end
  return v
end

local ACTIONS = "require('notebook_cells.actions')"

function M.attach(buf)
  local o = config.options
  local km = o.keymaps
  if not km then return end
  local map = vim.keymap.set
  local function plain(key, rhs, desc)
    for _, lhs in ipairs(as_list(km[key])) do
      map("n", lhs, rhs, { buffer = buf, desc = "Notebook: " .. desc })
    end
  end

  -- Keys that act on cells in command mode and fall through to normal Vim
  -- behaviour while editing a cell.
  local function modal(key, call, desc, edit_rhs)
    for _, lhs in ipairs(as_list(km[key])) do
      map("n", lhs, function()
        if state.mode[buf] == "command" then
          return ("<Cmd>lua %s.%s<CR>"):format(ACTIONS, call)
        end
        if type(edit_rhs) == "function" then return edit_rhs() end
        return edit_rhs or lhs
      end, { buffer = buf, expr = true, desc = "Notebook: " .. desc })
    end
  end
  local function counted(key, alt)
    return function()
      if vim.v.count > 0 then return vim.v.count .. key end
      return alt or key
    end
  end

  local actions = require("notebook_cells.actions")
  local kernel = require("notebook_cells.kernel")

  if o.modal then
    modal("next_cell", "goto_cell(1)", "next cell / row", counted("j", "gj"))
    modal("prev_cell", "goto_cell(-1)", "previous cell / row", counted("k", "gk"))
    modal("edit", "enter_edit(true)", "edit cell")
    modal("add_above", "add_cell(true)", "add cell above")
    modal("add_below", "add_cell(false)", "add cell below")
    modal("delete_cell", "delete_cell()", "delete cell")
    modal("toggle_markdown", "toggle_markdown()", "toggle markdown/code")
    for _, lhs in ipairs(as_list(km.exit_edit)) do
      map("n", lhs, function()
        if state.mode[buf] == "edit" then
          return ("<Cmd>nohlsearch<CR><Cmd>lua %s.exit_edit()<CR>"):format(ACTIONS)
        end
        return lhs
      end, { buffer = buf, expr = true, desc = "Notebook: command mode" })
    end
    for _, lhs in ipairs(as_list(km.click_to_edit)) do
      map("n", lhs, lhs .. ("<Cmd>lua %s.click()<CR>"):format(ACTIONS), { buffer = buf, desc = "Notebook: click to edit" })
    end
  end

  plain("jump_next", function() actions.goto_cell(1) end, "next cell")
  plain("jump_prev", function() actions.goto_cell(-1) end, "previous cell")
  plain("run_cell", function() actions.run_cell(false) end, "run cell")
  plain("run_and_next", function() actions.run_cell(true) end, "run cell and go to next")
  plain("new_code_below", function() actions.new_cell(false) end, "new code cell below")
  plain("new_markdown_below", function() actions.new_cell(true) end, "new markdown cell below")
  if o.kernel.enabled then
    plain("start_kernel", function() kernel.start() end, "start project kernel")
    plain("pick_kernel", function() kernel.pick() end, "pick kernel")
  end
end

return M
