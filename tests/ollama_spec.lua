local curl = require("plenary.curl")

local eq = assert.are.same
local mapping = "<Plug>(ollama-nvim-test)"

describe("ollama actions", function()
  local original_notify
  local original_post
  local notifications
  local post_call
  local modal_buf
  local modal_win

  local function start_action()
    require("ollama").setup({
      endpoint = "http://ollama.test/api/generate",
      actions = {
        generate = function()
          return {
            model = "test-model",
            system = "system instructions",
            prompt = "prompt\nwith a tab:\tand Unicode: λ",
          }
        end,
      },
      keymaps = {
        {
          mode = "n",
          lhs = mapping,
          action = "generate",
          options = {
            temperature = 0.25,
          },
        },
      },
    })

    local map = vim.fn.maparg(mapping, "n", false, true)
    assert.is_function(map.callback)
    map.callback()

    modal_buf = vim.api.nvim_get_current_buf()
    modal_win = vim.api.nvim_get_current_win()
  end

  local function wait_until(predicate)
    assert.is_true(vim.wait(1000, predicate, 10))
  end

  local function wait_for_scheduled_callbacks()
    local done = false
    vim.schedule(function()
      done = true
    end)
    wait_until(function()
      return done
    end)
  end

  before_each(function()
    notifications = {}
    post_call = nil
    modal_buf = nil
    modal_win = nil

    original_notify = vim.notify
    vim.notify = function(message, level, options)
      table.insert(notifications, {
        message = message,
        level = level,
        options = options,
      })
    end

    original_post = curl.post
    curl.post = function(endpoint, options)
      post_call = {
        endpoint = endpoint,
        options = options,
      }
      return { mocked_job = true }
    end
  end)

  after_each(function()
    curl.post = original_post
    vim.notify = original_notify
    pcall(vim.keymap.del, "n", mapping)

    if modal_win and vim.api.nvim_win_is_valid(modal_win) then
      vim.api.nvim_win_close(modal_win, true)
    elseif modal_buf and vim.api.nvim_buf_is_valid(modal_buf) then
      vim.api.nvim_buf_delete(modal_buf, { force = true })
    end
  end)

  it("posts the completed request asynchronously", function()
    start_action()

    eq("http://ollama.test/api/generate", post_call.endpoint)
    eq({
      content_type = "application/json",
      accept = "application/json",
    }, post_call.options.headers)

    local request = vim.json.decode(post_call.options.body)
    eq("test-model", request.model)
    eq("system instructions", request.system)
    eq("prompt\nwith a tab:\tand Unicode: λ", request.prompt)
    eq({ temperature = 0.25 }, request.options)
    eq(false, request.stream)

    assert.is_function(post_call.options.callback)
    assert.is_function(post_call.options.on_error)
    eq({ "Loading..." }, vim.api.nvim_buf_get_lines(modal_buf, 0, -1, false))
  end)

  it("replaces Loading with a multiline generated response", function()
    start_action()
    local generated = "first\tline\n\nUnicode: λ中\n"

    post_call.options.callback({
      status = 201,
      body = vim.json.encode({ response = generated }),
    })

    wait_until(function()
      return vim.api.nvim_buf_get_lines(modal_buf, 0, -1, false)[1] ~= "Loading..."
    end)
    eq({ "first\tline", "", "Unicode: λ中", "" }, vim.api.nvim_buf_get_lines(modal_buf, 0, -1, false))
    eq({}, notifications)
  end)

  it("closes the modal and reports transport errors", function()
    start_action()
    post_call.options.on_error({ message = "connection refused" })

    wait_until(function()
      return #notifications == 1
    end)
    assert.is_false(vim.api.nvim_buf_is_valid(modal_buf))
    assert.matches("transport error", notifications[1].message)
    eq(vim.log.levels.ERROR, notifications[1].level)
    eq("ollama.nvim", notifications[1].options.title)
  end)

  it("closes the modal and reports HTTP errors", function()
    start_action()
    post_call.options.callback({ status = 503, body = "unavailable" })

    wait_until(function()
      return #notifications == 1
    end)
    assert.is_false(vim.api.nvim_buf_is_valid(modal_buf))
    assert.matches("HTTP status 503", notifications[1].message)
    eq("ollama.nvim", notifications[1].options.title)
  end)

  it("closes the modal and reports malformed JSON", function()
    start_action()
    post_call.options.callback({ status = 200, body = "not-json" })

    wait_until(function()
      return #notifications == 1
    end)
    assert.is_false(vim.api.nvim_buf_is_valid(modal_buf))
    assert.matches("invalid JSON", notifications[1].message)
  end)

  it("closes the modal when the response field is missing", function()
    start_action()
    post_call.options.callback({
      status = 200,
      body = vim.json.encode({ model = "test-model" }),
    })

    wait_until(function()
      return #notifications == 1
    end)
    assert.is_false(vim.api.nvim_buf_is_valid(modal_buf))
    assert.matches('string "response" field', notifications[1].message)
  end)

  it("ignores a successful response after the modal is closed", function()
    start_action()
    vim.api.nvim_win_close(modal_win, true)
    assert.is_false(vim.api.nvim_buf_is_valid(modal_buf))

    post_call.options.callback({
      status = 200,
      body = vim.json.encode({ response = "too late" }),
    })
    wait_for_scheduled_callbacks()

    assert.is_false(vim.api.nvim_buf_is_valid(modal_buf))
    eq({}, notifications)
  end)
end)
