-- Per-buffer runtime state shared between modules.
return {
  mode = {}, -- buf -> "command" | "edit"
  active = {}, -- buf -> index of the highlighted cell
  clipboard = nil, -- lines of the last copied/cut cell
  run_gen = {}, -- buf -> counter, bumped to cancel a running "run all" sequence
  starting = {}, -- buf -> true while a kernel is being set up
}
