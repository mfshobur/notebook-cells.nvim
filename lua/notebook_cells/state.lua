-- Per-buffer runtime state shared between modules.
return {
  mode = {}, -- buf -> "command" | "edit"
  active = {}, -- buf -> index of the highlighted cell
  starting = {}, -- buf -> true while a kernel is being set up
}
