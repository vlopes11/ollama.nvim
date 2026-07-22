local M = {}

local visual_modes = {
  v = true,
  V = true,
  [string.char(22)] = true,
}

---Return the text in the active Visual selection.
---@return string
function M.get_visual_selection()
  local mode = vim.fn.mode()
  if not visual_modes[mode] then
    error("ollama.nvim: get_visual_selection() requires an active Visual selection", 0)
  end

  local selection = vim.fn.getregion(
    vim.fn.getpos("v"),
    vim.fn.getpos("."),
    { type = mode }
  )

  return table.concat(selection, "\n")
end

return M
