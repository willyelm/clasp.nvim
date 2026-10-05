local config = require("clasp.config")
local close = require("clasp.close")
local pair = require("clasp.pairs")
local surround = require("clasp.surround")
local highlight = require("clasp.highlight")
local split = require("clasp.split")

local M = {}

-- Called from the `>` and `/` mappings right after the character is inserted, before the next key is
-- read, so a fast typist, a macro or `.` never gets ahead of it.
function M._typed(char)
	local buf = vim.api.nvim_get_current_buf()
	local opts = config.options.tags
	if char == ">" then
		close.on_gt(buf)
	else
		close.on_slash(buf, opts)
	end
end

function M.attach(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if vim.b[buf].clasp_attached then
		return
	end
	vim.b[buf].clasp_attached = true
	local opts = config.options.tags
	local function map(char, desc)
		local rhs = char .. "<Cmd>lua require('clasp')._typed('" .. char .. "')<CR>"
		vim.keymap.set("i", char, rhs, { buffer = buf, desc = desc })
	end
	if opts.on_gt then
		map(">", "clasp: close tag")
	end
	if opts.on_slash or opts.self_close then
		map("/", "clasp: close or self-close tag")
	end
	if opts.self_close then
		-- Deleting the `/` of `<Foo />` reopens it; every other <BS> is the usual one (pairs included).
		vim.keymap.set("i", "<BS>", function()
			if close.at_self_closing_slash() then
				return "<Cmd>lua require('clasp.close').expand(0)<CR>"
			end
			return pair.backspace()
		end, { buffer = buf, expr = true, replace_keycodes = true, desc = "clasp: reopen self-closing tag" })
	end
	if opts.highlight then
		highlight.attach(buf)
	end
end

function M.detach(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not vim.b[buf].clasp_attached then
		return
	end
	vim.b[buf].clasp_attached = nil
	pcall(vim.keymap.del, "i", ">", { buffer = buf })
	pcall(vim.keymap.del, "i", "/", { buffer = buf })
	pcall(vim.keymap.del, "i", "<BS>", { buffer = buf })
	highlight.detach(buf)
end

function M.setup(opts)
	config.setup(opts)
	pair.setup()
	if config.options.surround.enabled then
		surround.setup(config.options.surround.keys)
	end
	if config.options.split.enabled then
		split.setup(config.options.split.keys)
	end
	local group = vim.api.nvim_create_augroup("clasp", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = config.options.tags.filetypes,
		callback = function(args)
			M.attach(args.buf)
		end,
	})
	-- Buffers opened before setup ran.
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains(config.options.tags.filetypes, vim.bo[buf].filetype) then
			M.attach(buf)
		end
	end
end

return M
