local config = require("ollama.config")

local M = {
  config = config.options,
}

local function config_error(message)
  error("ollama.nvim: " .. message, 0)
end

---@param text string
---@return string[]
local function text_to_lines(text)
  return vim.split(text, "\n", { plain = true })
end

---@param text string
---@param title? string
---@return integer
local function open_text_modal(text, title)
  -- Create an unlisted scratch buffer (listed = false, scratch = true)
  local buf = vim.api.nvim_create_buf(false, true)

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text_to_lines(text))

  -- Calculate centered position
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = title or " Modal ",
    title_pos = "center",
  }

  -- Open and focus the window
  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Buffer options: make non-modifiable so user doesn't alter modal text
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- Map 'q' and '<Esc>' to close the modal
  local close_opts = { buffer = buf, silent = true }
  vim.keymap.set("n", "q", "<cmd>close<CR>", close_opts)
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", close_opts)

  return buf
end

---@param buf integer
local function close_modal(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      pcall(vim.api.nvim_win_close, win, true)
      return
    end
  end
end

---@param buf integer
---@param message string
local function report_request_error(buf, message)
  close_modal(buf)
  vim.notify(message, vim.log.levels.ERROR, { title = "ollama.nvim" })
end

---@param buf integer
---@param response table
local function handle_response(buf, response)
  local status = type(response) == "table" and response.status or nil
  if type(status) ~= "number" or status < 200 or status >= 300 then
    report_request_error(buf, ("Ollama request failed with HTTP status %s"):format(status or "unknown"))
    return
  end

  local ok, decoded = pcall(vim.json.decode, response.body)
  if not ok then
    report_request_error(buf, "Ollama returned invalid JSON")
    return
  end

  if type(decoded) ~= "table" or type(decoded.response) ~= "string" then
    report_request_error(buf, 'Ollama response is missing a string "response" field')
    return
  end

  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text_to_lines(decoded.response))
  vim.bo[buf].modifiable = false
end

---@param action_name string
---@param request unknown
local function validate_request(action_name, request)
  if type(request) ~= "table" then
    config_error(("action %q must return an OllamaRequest table"):format(action_name))
  end

  for _, field in ipairs({ "model", "system", "prompt" }) do
    if type(request[field]) ~= "string" then
      config_error(("action %q must return a string field %q"):format(action_name, field))
    end
  end
end

---@param action_name string
---@param action_options OllamaOptions
local function run_action(action_name, action_options)
  local action = M.config.actions[action_name]
  local request = action()

  validate_request(action_name, request)

  request.options = nil
  if next(action_options) ~= nil then
    request.options = vim.deepcopy(action_options)
  end

  request.stream = false

  local ok, encoded = pcall(vim.json.encode, request)
  if not ok then
    config_error(("action %q returned a request that cannot be encoded as JSON: %s"):format(action_name, encoded))
  end

  local buf = open_text_modal("Loading...", action_name)

  require("plenary.curl").post(M.config.endpoint, {
    body = encoded,
    headers = {
      content_type = "application/json",
      accept = "application/json",
    },
    callback = vim.schedule_wrap(function(response)
      handle_response(buf, response)
    end),
    on_error = vim.schedule_wrap(function()
      report_request_error(buf, "Ollama request failed due to a transport error")
    end),
  })
end

---@param options OllamaConfig
local function validate_config(options)
  if type(options.message) ~= "string" then
    config_error("message must be a string")
  end

  if type(options.endpoint) ~= "string" then
    config_error("endpoint must be a string")
  end

  if type(options.actions) ~= "table" then
    config_error("actions must be a table")
  end

  if type(options.keymaps) ~= "table" then
    config_error("keymaps must be a table")
  end

  for action_name, action in pairs(options.actions) do
    if type(action_name) ~= "string" then
      config_error("action names must be strings")
    end

    if type(action) ~= "function" then
      config_error(("action %q must be a function"):format(action_name))
    end
  end

  for index, keymap in ipairs(options.keymaps) do
    if type(keymap) ~= "table" then
      config_error(("keymap %d must be a table"):format(index))
    end

    if type(keymap.mode) ~= "string" then
      config_error(("keymap %d mode must be a string"):format(index))
    end

    if type(keymap.lhs) ~= "string" then
      config_error(("keymap %d lhs must be a string"):format(index))
    end

    if type(keymap.action) ~= "string" then
      config_error(("keymap %d action must be a string"):format(index))
    end

    if keymap.desc ~= nil and type(keymap.desc) ~= "string" then
      config_error(("keymap %d desc must be a string"):format(index))
    end

    if keymap.options ~= nil and type(keymap.options) ~= "table" then
      config_error(("keymap %d options must be a table"):format(index))
    end

    if options.actions[keymap.action] == nil then
      config_error(("keymap %d references unknown action %q"):format(index, keymap.action))
    end
  end
end

---@param options OllamaConfig
local function normalize_keymaps(options)
  for _, keymap in ipairs(options.keymaps) do
    keymap.options = vim.deepcopy(keymap.options or {})
  end
end

---@param options OllamaConfig
local function register_keymaps(options)
  for _, keymap in ipairs(options.keymaps) do
    local action_name = keymap.action
    local action_options = keymap.options

    vim.keymap.set(keymap.mode, keymap.lhs, function()
      run_action(action_name, action_options)
    end, {
      desc = keymap.desc,
    })
  end
end

---@param opts? OllamaConfig
function M.setup(opts)
  M.config = config.setup(opts)
  validate_config(M.config)
  normalize_keymaps(M.config)
  register_keymaps(M.config)
end

function M.hello()
  vim.notify(M.config.message, vim.log.levels.INFO, { title = "ollama.nvim" })
  return M.config.message
end

return M
