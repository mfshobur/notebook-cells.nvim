-- Per-project Jupyter kernel: nearest virtualenv -> registered kernelspec -> molten.
local config = require("notebook_cells.config")
local state = require("notebook_cells.state")

local M = {}
local is_win = vim.fn.has("win32") == 1

local function notify(msg, level) vim.notify("notebook-cells: " .. msg, level or vim.log.levels.INFO) end

local function sys(cmd, cb)
  vim.system(cmd, { text = true }, function(r) vim.schedule(function() cb(r) end) end)
end

local ready = {} -- kernel id -> true once molten reported MoltenKernelReady

---Ids of the molten kernels attached to `buf` (default: current buffer).
function M.attached(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local ok, ids = pcall(vim.api.nvim_buf_call, buf, function() return vim.fn.MoltenRunningKernels(true) end)
  return (ok and type(ids) == "table") and ids or {}
end

---Is a molten kernel attached to the buffer (it may still be starting)?
function M.is_running(buf) return #M.attached(buf) > 0 end

---Is an attached kernel up and able to execute code?
function M.is_ready(buf)
  for _, id in ipairs(M.attached(buf)) do
    if ready[id] then return true end
  end
  return false
end

---Track molten's lifecycle events. Called from setup().
function M.setup()
  local group = vim.api.nvim_create_augroup("NotebookCellsKernel", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MoltenKernelReady",
    callback = function(a)
      local id = a.data and a.data.kernel_id
      if id then ready[id] = true end
    end,
  })
  -- a (re)initialised kernel with a reused id is not ready yet
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MoltenInitPost",
    callback = function()
      for _, id in ipairs(M.attached(0)) do ready[id] = nil end
    end,
  })
end

local function venv_python(venv)
  local candidates = is_win and { "/Scripts/python.exe" } or { "/bin/python", "/bin/python3" }
  for _, rel in ipairs(candidates) do
    if vim.fn.executable(venv .. rel) == 1 then return venv .. rel end
  end
end

---Nearest virtualenv above the buffer's file; returns venv dir, python executable.
function M.find_venv(buf)
  local o = config.options.kernel
  local file = vim.api.nvim_buf_get_name(buf)
  local dir = file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
  for _, name in ipairs(o.venv_dirs) do
    local found = vim.fs.find(name, { path = dir, upward = true, type = "directory" })[1]
    local py = found and venv_python(found)
    if py then return found, py end
  end
  if o.use_virtual_env and vim.env.VIRTUAL_ENV then
    local py = venv_python(vim.env.VIRTUAL_ENV)
    if py then return vim.env.VIRTUAL_ENV, py end
  end
end

local function project_name(venv) return vim.fs.basename(vim.fs.dirname(venv)) end

function M.kernel_name(venv)
  local safe = project_name(venv):gsub("[^%w%._%-]", "-")
  return ("venv-%s-%s"):format(safe, vim.fn.sha256(venv):sub(1, 6))
end

local PROBE = "import ipykernel; from jupyter_core.paths import jupyter_data_dir as d; print(d())"

---Make sure a kernelspec for the buffer's venv exists. cb(name) or cb(nil).
function M.ensure(buf, cb)
  local venv, py = M.find_venv(buf)
  if not venv then return cb(nil) end
  local name = M.kernel_name(venv)
  local pretty = ("%s (%s)"):format(project_name(venv), vim.fs.basename(venv))

  local function register(data_dir)
    local kjson = data_dir .. "/kernels/" .. name .. "/kernel.json"
    local ok, spec = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(kjson), "\n")) end)
    if ok and spec and spec.argv and vim.fs.dirname(spec.argv[1]) == vim.fs.dirname(py) then
      return cb(name)
    end
    sys({ py, "-m", "ipykernel", "install", "--user", "--name", name, "--display-name", pretty }, function(r)
      if r.code ~= 0 then
        notify("kernel registration failed:\n" .. (r.stderr or ""), vim.log.levels.ERROR)
        return cb(nil)
      end
      cb(name)
    end)
  end

  local function probe(after_install)
    sys({ py, "-c", PROBE }, function(r)
      if r.code == 0 then return register(vim.trim(r.stdout)) end
      if after_install then
        notify("ipykernel is still not importable in " .. venv, vim.log.levels.ERROR)
        return cb(nil)
      end
      local policy = config.options.kernel.install_ipykernel
      local ok = policy == true
        or (policy == "ask" and vim.fn.confirm("ipykernel is missing in " .. venv .. ". Install it?", "&Yes\n&No", 1) == 1)
      if not ok then return cb(nil) end
      notify("installing ipykernel into " .. venv .. " ...")
      local cmd = vim.fn.executable("uv") == 1 and { "uv", "pip", "install", "--python", py, "ipykernel" }
        or { py, "-m", "pip", "install", "ipykernel" }
      sys(cmd, function(r2)
        if r2.code ~= 0 then
          notify("ipykernel install failed:\n" .. (r2.stderr or ""), vim.log.levels.ERROR)
          return cb(nil)
        end
        probe(true)
      end)
    end)
  end

  probe(false)
end

---Wait (polling) until the buffer's kernel is ready, then call cb.
local function wait_ready(buf, cb)
  local interval = 100
  local function poll(left)
    if M.is_ready(buf) then
      state.starting[buf] = nil
      if config.options.outputs.load_on_start and not vim.b[buf].notebook_cells_loaded then
        vim.b[buf].notebook_cells_loaded = true
        require("notebook_cells.outputs").load(buf)
      end
      if cb then cb() end
    elseif left > 0 then
      vim.defer_fn(function() poll(left - 1) end, interval)
    else
      state.starting[buf] = nil
      notify("kernel did not become ready in time", vim.log.levels.WARN)
    end
  end
  poll(math.ceil(config.options.kernel.startup_timeout / interval))
end

---Make sure a kernel is attached and ready (starting the project's kernel, or
---molten's picker when there is no venv), then call cb.
function M.start(cb)
  local buf = vim.api.nvim_get_current_buf()
  if M.is_ready(buf) then return cb and cb() end
  if state.starting[buf] then return notify("kernel is already starting, please wait...") end
  state.starting[buf] = true
  if M.is_running(buf) then return wait_ready(buf, cb) end

  M.ensure(buf, function(name)
    if not name then
      state.starting[buf] = nil
      if config.options.kernel.fallback_picker then
        notify("no usable virtualenv kernel found; pick one manually")
        vim.cmd("MoltenInit")
      end
      return
    end
    notify("starting kernel '" .. name .. "'...")
    vim.cmd("MoltenInit " .. name)
    wait_ready(buf, cb)
  end)
end

M.ensure_ready = M.start

---Interrupt the running execution.
function M.interrupt(buf)
  local ids = M.attached(buf)
  if #ids == 0 then return notify("no kernel is running for this notebook", vim.log.levels.WARN) end
  vim.cmd("MoltenInterrupt " .. ids[1])
  notify("interrupted")
end

---Restart the kernel. With clear = true the outputs are removed too.
---Calls cb once the new kernel is ready.
function M.restart(clear, cb)
  local buf = vim.api.nvim_get_current_buf()
  local ids = M.attached(buf)
  if #ids == 0 then return M.start(cb) end
  ready[ids[1]] = nil
  vim.cmd("MoltenRestart" .. (clear and "!" or "") .. " " .. ids[1])
  notify("restarting kernel...")
  state.starting[buf] = true
  wait_ready(buf, cb)
end

---Pick any installed kernel and attach it to the notebook (replacing the current one).
function M.select()
  local buf = vim.api.nvim_get_current_buf()
  local ok, available = pcall(vim.fn.MoltenAvailableKernels)
  if not ok or type(available) ~= "table" or #available == 0 then
    return notify("no Jupyter kernels found", vim.log.levels.WARN)
  end
  vim.ui.select(available, { prompt = "Select kernel" }, function(choice)
    if not choice then return end
    local ids = M.attached(buf)
    if #ids > 0 then pcall(vim.cmd, "MoltenDeinit " .. ids[1]) end
    state.starting[buf] = true
    vim.cmd("MoltenInit " .. choice)
    wait_ready(buf, nil)
  end)
end

M.pick = M.select

---Short kernel description for a statusline, e.g. "● play" (ready) or "○ play" (starting).
---Empty when no kernel is attached.
function M.status(buf)
  local ids = M.attached(buf)
  if #ids == 0 then return "" end
  local name = ids[1]:gsub("^venv%-", ""):gsub("%-%x%x%x%x%x%x$", "")
  return (M.is_ready(buf) and "● " or "○ ") .. name
end

return M
