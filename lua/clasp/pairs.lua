-- Bracket and quote pairs while typing. Every key is an expression mapping that returns plain keys, using
-- <C-g>U so moving the cursor inside the pair does not break undo or `.` repeat.
local config = require("clasp.config")

local M = {}

-- A pair is not inserted when the next character would end up inside it: `(|foo` stays `(foo`.
local NO_PAIR_BEFORE = "[%w%%'%[\"%.`%$]"

local LEFT = "<C-g>U<Left>"
local RIGHT = "<C-g>U<Right>"

local STRING_NODES = {
	string = true,
	string_fragment = true,
	string_content = true,
	template_string = true,
	raw_string_literal = true,
	interpreted_string_literal = true,
	quoted_attribute_value = true,
	attribute_value = true,
	comment = true,
}

-- Set while inserting from visual-block mode (`<C-v>I`), where one typed pair would land on every line.
local block_insert = false

local function enabled()
	local opts = config.options.pairs
	return not block_insert
		and vim.bo.buftype ~= "prompt"
		and not vim.tbl_contains(opts.disable_filetypes, vim.bo.filetype)
end

-- The characters either side of the cursor.
local function around()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	local line = vim.api.nvim_get_current_line()
	return line:sub(col, col), line:sub(col + 1, col + 1), line, col
end

local function in_string(col)
	local row = vim.api.nvim_win_get_cursor(0)[1] - 1
	local ok, node = pcall(vim.treesitter.get_node, { pos = { row, math.max(col - 1, 0) } })
	return ok and node ~= nil and STRING_NODES[node:type()] == true
end

-- Unescaped `quote`s before the cursor; an odd count means the cursor is inside a string they opened.
local function count_before(line, col, quote)
	local n, i = 0, 1
	while i <= col do
		local c = line:sub(i, i)
		if c == "\\" then
			i = i + 1
		elseif c == quote then
			n = n + 1
		end
		i = i + 1
	end
	return n
end

local function open_bracket(open, close)
	if not enabled() then
		return open
	end
	-- In JS/TS, `{` may complete a `${`. A `$` typed just before can still be on its way into the buffer, so
	-- the check runs from <Cmd>, after it has landed.
	if open == "{" and config.options.pairs.template and require("clasp.template").applies() then
		return "<Cmd>lua require('clasp.template').brace()<CR>"
	end
	local _, next = around()
	return M.pairs_before(next) and open .. close .. LEFT or open
end

-- Whether an opening bracket is paired when `next` is the character after the cursor.
function M.pairs_before(next)
	return not next:match(NO_PAIR_BEFORE)
end

local function close_bracket(close)
	if not enabled() then
		return close
	end
	local _, next = around()
	return next == close and RIGHT or close
end

local function quote(char)
	if not enabled() then
		return char
	end
	local prev, next, line, col = around()
	if next == char then
		return RIGHT
	end
	-- `don't`, `it's`, a third quote (`"""`, ```` ``` ````), and closing a string the cursor is already in.
	if prev:match("[%w\\]") or prev == char or next:match(NO_PAIR_BEFORE) then
		return char
	end
	if count_before(line, col, char) % 2 == 1 or in_string(col) then
		return char
	end
	return char .. char .. LEFT
end

-- Also called from the tag buffers' own <BS>, so it checks its options itself.
function M.backspace()
	local opts = config.options.pairs
	if not opts.enabled or not opts.bs or not enabled() then
		return "<BS>"
	end
	local prev, next = around()
	local close = config.options.pairs.chars[prev]
	if close and close == next then
		return "<BS><Del>"
	end
	return "<BS>"
end

-- Split `(|)` or `<div>|</div>` onto three lines with the cursor on the indented middle one.
local function enter()
	if not enabled() then
		return "<CR>"
	end
	local prev, next, line, col = around()
	local close = config.options.pairs.chars[prev]
	local between = (close and close == next and close ~= prev)
		or (prev == ">" and line:sub(col + 1, col + 2) == "</")
	return between and "<CR><C-o>O" or "<CR>"
end

local function map(lhs, fn, desc)
	vim.keymap.set("i", lhs, fn, { expr = true, replace_keycodes = true, desc = desc })
end

function M.setup()
	local opts = config.options.pairs
	if not opts.enabled then
		return
	end
	local closers = {}
	for open, close in pairs(opts.chars) do
		if open == close then
			map(open, function()
				return quote(open)
			end, "clasp: pair " .. open)
		else
			map(open, function()
				return open_bracket(open, close)
			end, "clasp: pair " .. open .. close)
			closers[close] = true
		end
	end
	for close in pairs(closers) do
		map(close, function()
			return close_bracket(close)
		end, "clasp: step over " .. close)
	end
	local group = vim.api.nvim_create_augroup("clasp_pairs", { clear = true })
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		pattern = "\22:i",
		callback = function()
			block_insert = true
		end,
	})
	vim.api.nvim_create_autocmd("InsertLeave", {
		group = group,
		callback = function()
			block_insert = false
		end,
	})
	if opts.bs then
		map("<BS>", M.backspace, "clasp: delete empty pair")
	end
	if opts.cr then
		map("<CR>", enter, "clasp: open pair")
	end
end

return M
