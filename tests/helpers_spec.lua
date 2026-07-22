local eq = assert.are.same
local helpers = require("ollama.helpers")

describe("ollama helpers", function()
  local original_selection

  local function set_lines(lines)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.modified = false
  end

  local function normal(keys)
    vim.cmd.normal({
      args = { vim.api.nvim_replace_termcodes(keys, true, false, true) },
      bang = true,
    })
  end

  before_each(function()
    original_selection = vim.o.selection
    vim.o.selection = "inclusive"
    vim.cmd("enew!")
  end)

  after_each(function()
    vim.o.selection = original_selection
    vim.cmd("enew!")
  end)

  it("returns a reversed multiline characterwise selection", function()
    set_lines({ "alpha one", "beta two", "gamma three" })
    normal("G$vgg04l")

    eq("a one\nbeta two\ngamma three", helpers.get_visual_selection())
  end)

  it("returns complete lines for a linewise selection", function()
    set_lines({ "alpha one", "beta two", "gamma three" })
    normal("ggVj")

    eq("alpha one\nbeta two", helpers.get_visual_selection())
  end)

  it("returns rectangular text for a blockwise selection", function()
    set_lines({ "abcdef", "uvwxyz" })
    normal("gg01l<C-v>j2l")

    eq("bcd\nvwx", helpers.get_visual_selection())
  end)

  it("requires an active Visual selection", function()
    set_lines({ "alpha" })
    normal("gg0")

    local ok, err = pcall(helpers.get_visual_selection)

    eq(false, ok)
    eq("ollama.nvim: get_visual_selection() requires an active Visual selection", err)
  end)
end)
