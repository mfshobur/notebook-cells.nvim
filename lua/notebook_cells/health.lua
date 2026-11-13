local M = {}

function M.check()
  local h = vim.health
  h.start("notebook-cells.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim >= 0.10")
  else
    h.error("Neovim 0.10+ is required (vim.system, vim.uv)")
  end

  if pcall(require, "jupytext") then
    h.ok("jupytext.nvim found (opens .ipynb as percent-format scripts)")
  else
    h.error("jupytext.nvim not found", "Install GCBallesteros/jupytext.nvim and set style = 'percent'")
  end
  if vim.fn.executable("jupytext") == 1 then
    h.ok("`jupytext` CLI found")
  else
    h.error("`jupytext` CLI not found", "uv tool install jupytext   (or: pipx install jupytext)")
  end

  if vim.fn.exists(":MoltenInit") == 2 then
    h.ok("molten-nvim loaded")
  else
    h.warn("molten-nvim not available", "Running cells needs benlubas/molten-nvim (and :UpdateRemotePlugins)")
  end

  local md = require("notebook_cells.minimal_diff")
  if md.python() then
    h.ok("python for minimal-diff saves: " .. md.python())
  else
    h.warn("no python3 on PATH; minimal-diff saves are disabled")
  end

  if vim.fn.executable("uv") == 1 then
    h.ok("`uv` found (used to install ipykernel into project venvs)")
  else
    h.info("`uv` not found; pip is used to install ipykernel instead")
  end
end

return M
