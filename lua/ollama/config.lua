---@alias OllamaOptions table<string, any>

---@class OllamaRequest
---@field model string
---@field system string
---@field prompt string
---@field options? OllamaOptions
---@field stream? boolean

---@alias OllamaAction fun(): OllamaRequest

---@class OllamaKeymap
---@field mode string
---@field lhs string
---@field action string
---@field desc? string
---@field options? OllamaOptions

---@class OllamaConfig
---@field message? string
---@field endpoint? string
---@field actions? table<string, OllamaAction>
---@field keymaps? OllamaKeymap[]

local M = {}

M.defaults = {
  message = "Hello from ollama.nvim!",
  endpoint = "http://localhost:11434/api/generate",
  actions = {},
  keymaps = {},
}

M.options = vim.deepcopy(M.defaults)

---@param opts? OllamaConfig
---@return OllamaConfig
function M.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then
    error("ollama.nvim: setup options must be a table", 0)
  end

  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  return M.options
end

return M
