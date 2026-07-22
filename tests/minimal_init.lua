vim.opt.runtimepath:append(vim.fn.getcwd())

local plenary_path = os.getenv("PLENARY_PATH") or (vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
vim.opt.runtimepath:append(plenary_path)
