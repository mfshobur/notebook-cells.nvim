-- Per-project Jupyter kernel: nearest virtualenv -> registered kernelspec -> molten.
local config = require("notebook_cells.config")
local state = require("notebook_cells.state")

local M = {}
local is_win = vim.fn.has("win32") == 1

local function notify(msg, level) vim.notify("notebook-cells: " .. msg, level or vim.log.levels.INFO) end

local function sys(cmd, cb)
  vim.system(cmd, { text = true }, function(r) vim.schedule(function() cb(r) end) end)
end

---Is a molten kernel attached to the current buffer?
function M.is_running()
  local ok, kernels = pcall(vim.fn.MoltenRunningKernels, true)
  return ok and type(kernels) == "table" and #kernels > 0
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

---Start the project's kernel (or molten's picker if there is no venv), then call cb.
function M.start(cb)
  local buf = vim.api.nvim_get_current_buf()
  if M.is_running() then return cb and cb() end
  if state.starting[buf] then return notify("kernel is already starting, please wait...") end
  state.starting[buf] = true

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
    local interval = 200
    local function poll(left)
      if M.is_running() then
        state.starting[buf] = nil
        if cb then cb() end
      elseif left > 0 then
        vim.defer_fn(function() poll(left - 1) end, interval)
      else
        state.starting[buf] = nil
        notify("kernel did not start in time", vim.log.levels.WARN)
      end
    end
    poll(math.ceil(config.options.kernel.startup_timeout / interval))
  end)
end

---Always show molten's own kernel picker.
function M.pick() vim.cmd("MoltenInit") end

return M
