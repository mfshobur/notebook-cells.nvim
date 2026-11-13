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

-- Keys that act on cells in command mode. In edit mode they fall through to
-- their normal Vim meaning. { key name, action call, description }
local COMMAND_KEYS = {
  { "edit", "enter_edit(true)", "edit cell" },
  { "add_above", "add_cell(true)", "add cell above" },
  { "add_below", "add_cell(false)", "add cell below" },
  { "delete_cell", "delete_cell()", "delete cell" },
  { "cut_cell", "cut_cell()", "cut cell" },
  { "copy_cell", "copy_cell()", "copy cell" },
  { "paste_below", "paste_cell(false)", "paste cell below" },
  { "paste_above", "paste_cell(true)", "paste cell above" },
  { "merge_below", "merge_below()", "merge with cell below" },
  { "to_markdown", "to_markdown()", "change cell to markdown" },
  { "to_code", "to_code()", "change cell to code" },
}

-- Always-available keys. { key name, function name in actions.lua, argument, description }
local PLAIN_KEYS = {
  { "jump_next", "goto_cell", 1, "next cell" },
  { "jump_prev", "goto_cell", -1, "previous cell" },
  { "run_cell", "run_cell", false, "run cell" },
  { "run_and_next", "run_cell", true, "run cell and go to next" },
  { "run_and_insert", "run_and_insert", nil, "run cell and insert one below" },
  { "run_all", "run_all", nil, "run all cells" },
  { "run_above", "run_above", nil, "run all cells above" },
  { "run_below", "run_below", nil, "run this cell and all below" },
  { "interrupt", "interrupt", nil, "interrupt kernel" },
  { "restart", "restart", false, "restart kernel" },
  { "restart_and_run_all", "restart_and_run_all", false, "restart kernel and run all cells" },
  { "clear_cell_output", "clear_cell_output", nil, "clear cell output" },
  { "clear_all_outputs", "clear_all_outputs", nil, "clear all outputs" },
  { "move_up", "move_cell", -1, "move cell up" },
  { "move_down", "move_cell", 1, "move cell down" },
  { "split_cell", "split_cell", nil, "split cell at cursor" },
  { "new_code_below", "new_cell", false, "new code cell below" },
  { "new_markdown_below", "new_cell", true, "new markdown cell below" },
}

function M.attach(buf)
  local o = config.options
  local km = o.keymaps
  if not km then return end
  local map = vim.keymap.set
  local actions = require("notebook_cells.actions")
  local kernel = require("notebook_cells.kernel")

  local function counted(key, alt)
    return function()
      -- a count typed before the key stays in the typeahead; only pick gj/gk for plain presses
      if vim.v.count > 0 then return key end
      return alt or key
    end
  end

  local function modal(lhs, call, desc, edit_rhs)
    map("n", lhs, function()
      if state.mode[buf] == "command" then
        return ("<Cmd>lua %s.%s<CR>"):format(ACTIONS, call)
      end
      if type(edit_rhs) == "function" then return edit_rhs() end
      return edit_rhs or lhs
    end, { buffer = buf, expr = true, desc = "Notebook: " .. desc })
  end

  if o.modal then
    for _, lhs in ipairs(as_list(km.next_cell)) do modal(lhs, "goto_cell(1)", "next cell / row", counted("j", "gj")) end
    for _, lhs in ipairs(as_list(km.prev_cell)) do modal(lhs, "goto_cell(-1)", "previous cell / row", counted("k", "gk")) end
    for _, def in ipairs(COMMAND_KEYS) do
      for _, lhs in ipairs(as_list(km[def[1]])) do modal(lhs, def[2], def[3]) end
    end
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

  for _, def in ipairs(PLAIN_KEYS) do
    local fn, arg = actions[def[2]], def[3]
    for _, lhs in ipairs(as_list(km[def[1]])) do
      map("n", lhs, function() fn(arg) end, { buffer = buf, desc = "Notebook: " .. def[4] })
    end
  end

  if o.kernel.enabled then
    for _, lhs in ipairs(as_list(km.start_kernel)) do
      map("n", lhs, function() kernel.start() end, { buffer = buf, desc = "Notebook: start project kernel" })
    end
    for _, lhs in ipairs(as_list(km.pick_kernel)) do
      map("n", lhs, function() kernel.select() end, { buffer = buf, desc = "Notebook: select kernel" })
    end
  end
end

return M
