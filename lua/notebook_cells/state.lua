-- Per-buffer runtime state shared between modules.
return {
  mode = {}, -- buf -> "command" | "edit"
  active = {}, -- buf -> index of the highlighted cell
  clipboard = nil, -- lines of the last copied/cut cell
  starting = {}, -- buf -> true while a kernel is being set up
}
