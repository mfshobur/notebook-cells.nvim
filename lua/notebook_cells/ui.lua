-- Highlights, cell rendering (extmarks) and window options.
local cells_mod = require("notebook_cells.cells")
local config = require("notebook_cells.config")
local state = require("notebook_cells.state")

local M = {}
local ns = vim.api.nvim_create_namespace("notebook_cells")
M.ns = ns

-- ── highlights ────────────────────────────────────────────────────────────

local function get_hl(name)
  local ok, h = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and h or {}
end

local function fg_of(names, fallback)
  for _, n in ipairs(names) do
    local h = get_hl(n)
    if h.fg then return h.fg end
  end
  return fallback
end

local function channel(c, shift) return math.floor(c / shift) % 256 end

local function blend(a, b, t)
  local function mix(shift)
    return math.floor(channel(a, shift) * (1 - t) + channel(b, shift) * t + 0.5)
  end
  return mix(65536) * 65536 + mix(256) * 256 + mix(1)
end

---Derive the palette from the current colorscheme so it adapts to any theme.
function M.setup_highlights()
  local set = function(name, spec) vim.api.nvim_set_hl(0, "NotebookCells" .. name, spec) end
  local bg = get_hl("Normal").bg
  local blue = fg_of({ "Function", "DiagnosticInfo" }, 0x7aa2f7)
  local purple = fg_of({ "Keyword", "Special" }, 0xbb9af7)
  local green = fg_of({ "DiagnosticOk", "String" }, 0x9ece6a)
  local dim = fg_of({ "NonText", "Comment" }, 0x565f89)

  set("CodeBody", bg and { bg = blend(bg, blue, 0.06) } or {})
  set("MarkdownBody", bg and { bg = blend(bg, purple, 0.07) } or {})
  set("Idle", { fg = blend(bg or 0x1a1b26, dim, 0.6) })
  set("IdleMarkdown", { fg = blend(bg or 0x1a1b26, purple, 0.35) })
  set("Active", { fg = blue, bold = true })
  set("ActiveMarkdown", { fg = purple, bold = true })
  set("Edit", { fg = green, bold = true })
  set("CodeLabel", { fg = blue, bold = true })
  set("MarkdownLabel", { fg = purple, bold = true })

  for name, spec in pairs(config.options.highlights or {}) do
    set(name, spec)
  end
end

-- ── rendering ─────────────────────────────────────────────────────────────

local function text_width(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then return 100 end
  local info = vim.fn.getwininfo(win)[1]
  return math.max(20, info.width - info.textoff - 1)
end

function M.render(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local o = config.options
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local cells, lines = cells_mod.parse(buf)
  local w = text_width(buf)
  local win = vim.fn.bufwinid(buf)
  local row = win ~= -1 and vim.api.nvim_win_get_cursor(win)[1] or 1
  local act = cells_mod.cell_at(cells, row)
  state.active[buf] = act

  if o.hide_header and vim.fn.has("nvim-0.11") == 1 then
    local h1, h2 = cells_mod.header_range(lines)
    if h1 then
      for r = h1, h2 do
        vim.api.nvim_buf_set_extmark(buf, ns, r - 1, 0, { conceal_lines = "" })
      end
    end
  end

  for idx, c in ipairs(cells) do
    local is_active = idx == act
    local edit = is_active and state.mode[buf] == "edit"
    local md = c.md
    local group = edit and "Edit"
      or (is_active and (md and "ActiveMarkdown" or "Active") or (md and "IdleMarkdown" or "Idle"))
    group = "NotebookCells" .. group
    local label = "NotebookCells" .. (md and "MarkdownLabel" or "CodeLabel")
    local body = "NotebookCells" .. (md and "MarkdownBody" or "CodeBody")

    -- header: ╭─ [n] Python ──────
    local title = (" [%d] %s "):format(idx, md and o.labels.markdown or o.labels.code)
    local used = vim.fn.strdisplaywidth(o.border.top) + vim.fn.strdisplaywidth(title)
    vim.api.nvim_buf_set_extmark(buf, ns, c.s - 1, 0, {
      virt_text = {
        { o.border.top, group },
        { title, label },
        { o.border.rule:rep(math.max(0, w - used)), group },
      },
      virt_text_pos = "overlay",
    })

    for r = c.s + 1, c.e do
      vim.api.nvim_buf_set_extmark(buf, ns, r - 1, 0, {
        line_hl_group = body,
        sign_text = o.border.bar,
        sign_hl_group = group,
        priority = 20,
      })
      -- hide the "# " comment prefix in markdown cells
      if md and lines[r]:match("^# ") then
        vim.api.nvim_buf_set_extmark(buf, ns, r - 1, 0, { end_col = 2, conceal = "" })
      elseif md and lines[r] == "#" then
        vim.api.nvim_buf_set_extmark(buf, ns, r - 1, 0, { end_col = 1, conceal = "" })
      end
    end

    -- footer: ╰──────
    vim.api.nvim_buf_set_extmark(buf, ns, c.e - 1, 0, {
      virt_lines = { { { o.border.bottom .. o.border.rule:rep(math.max(0, w - vim.fn.strdisplaywidth(o.border.bottom))), group } } },
    })
  end
end

-- ── window options (saved on enter, restored on leave) ────────────────────

local WO = { conceallevel = 2, concealcursor = "nvic", signcolumn = "yes", cursorline = false }

function M.apply_window_options(win)
  win = (win == nil or win == 0) and vim.api.nvim_get_current_win() or win
  if vim.w[win].notebook_cells_saved then return end
  local saved = {}
  for k, v in pairs(WO) do
    saved[k] = vim.api.nvim_get_option_value(k, { win = win })
    vim.api.nvim_set_option_value(k, v, { scope = "local", win = win })
  end
  vim.w[win].notebook_cells_saved = saved
end

function M.restore_window_options(win)
  win = (win == nil or win == 0) and vim.api.nvim_get_current_win() or win
  local saved = vim.w[win].notebook_cells_saved
  if not saved then return end
  for k, v in pairs(saved) do
    vim.api.nvim_set_option_value(k, v, { scope = "local", win = win })
  end
  vim.w[win].notebook_cells_saved = nil
end

return M
