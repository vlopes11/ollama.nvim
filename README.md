# ollama.nvim

A minimalist Ollama wrapper for Neovim

## Requirements

- Neovim 0.10 or newer
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "vlopes11/ollama.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    endpoint = "http://localhost:11434/api/generate",
    actions = {
      copyedit = function()
        ---@type OllamaRequest
        local request = {
          model = "gemma4:31b",
          system =
          [[You are a strict, minimalist copyeditor. Your ONLY job is to fix objective errors in grammar, syntax, spelling, and punctuation. Do NOT alter the authors voice, tone, vocabulary, or sentence structure unless it is grammatically broken. If a sentence is already correct, leave it completely untouched. Output ONLY the corrected text and absolutely nothing else. No explanations, no markdown formatting, no conversation.]],
          prompt = require("ollama.helpers").get_visual_selection(),
        }

        return request
      end,
    },
    keymaps = {
      {
        mode = "x",
        lhs = "<leader>og",
        action = "copyedit",
        desc = "Copyedit selection",
      },
    },
  },
}
```
