-- Add, delete and replace the pair around text. Finding the pair is left to Neovim's own text objects
-- (`a(`, `a"`, `at`), which already handle nesting; adding is a `g@` operator, so it takes any motion or
-- text object. All three go through 'operatorfunc', so `.` repeats them with the same characters.
local M = {}

local ns = vim.api.nvim_create_namespace("clasp_surround")

-- Both halves of a pair select it: `gsa(` and `gsa)` both wrap in `(…)`.
local PAIRS = {
	["("] = { "(", ")" },
	[")"] = { "(", ")" },
	["["] = { "[", "]" },
	["]"] = { "[", "]" },
	["{"] = { "{", "}" },
	["}"] = { "{", "}" },
	["<"] = { "<", ">" },
	[">"] = { "<", ">" },
	['"'] = { '"', '"' },
	["'"] = { "'", "'" },
	["`"] = { "`", "`" },
}
local QUOTES = { ['"'] = true, ["'"] = true, ["`"] = true }

-- What the last operation used, so `.` repeats it without asking again.
local last = {}

local function read_char()
	local ok, char = pcall(vim.fn.getcharstr)
	if not ok or char == "\27" then
		return nil
	end
	return char
end

-- The open and close strings for `char`, asking for a tag when it is `t`. Calls back with nil to cancel.
local function resolve(char, tag, done)
	if char == "t" then
		if tag then
			return done(tag)
		end
		vim.ui.input({ prompt = "Tag" }, function(input)
			input = input and vim.trim(input)
			if not input or input == "" then
				return done(nil)
			end
			done(input)
		end)
		return
	end
	done(nil)
end

local function tag_pair(spec)
	local name = spec:match("^[^%s>]+")
	return { "<" .. spec .. ">", "</" .. name .. ">" }
end

local function no_pair(char)
	local name = char == "t" and "tag" or (PAIRS[char] and PAIRS[char][1] .. PAIRS[char][2]) or char
	vim.api.nvim_echo({ { "clasp: no " .. name .. " around the cursor", "WarningMsg" } }, false, {})
end

local function flash(buf, start, finish)
	vim.hl.range(buf, ns, "IncSearch", start, finish, { timeout = 150 })
end

-- Byte index just past the character starting at `col` (0-based) on `line`.
local function char_end(line, col)
	local byte = line:byte(col + 1)
	if not byte then
		return col
	end
	local len = byte >= 0xF0 and 4 or byte >= 0xE0 and 3 or byte >= 0xC0 and 2 or 1
	return col + len
end

-- Wrap the region from (sr, sc) to the character at (er, ec), all 0-based and inclusive.
local function wrap(buf, sr, sc, er, ec, pair)
	local end_line = vim.api.nvim_buf_get_lines(buf, er, er + 1, false)[1] or ""
	local stop = math.min(char_end(end_line, ec), #end_line)
	vim.api.nvim_buf_set_text(buf, er, stop, er, stop, { pair[2] })
	vim.api.nvim_buf_set_text(buf, sr, sc, sr, sc, { pair[1] })
	vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
	local last_col = stop + #pair[2] + (sr == er and #pair[1] or 0)
	flash(buf, { sr, sc }, { er, last_col })
end

local function region(kind)
	local start, finish = vim.api.nvim_buf_get_mark(0, "["), vim.api.nvim_buf_get_mark(0, "]")
	local sr, sc, er, ec = start[1] - 1, start[2], finish[1] - 1, finish[2]
	if kind == "line" then
		-- Linewise: from the first non-blank of the first line to the end of the last.
		local first = vim.api.nvim_buf_get_lines(0, sr, sr + 1, false)[1]
		local final = vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1]
		sc = (first:find("%S") or 1) - 1
		ec = math.max(#final - 1, 0)
	end
	return sr, sc, er, ec
end

function M._add(kind)
	local buf = vim.api.nvim_get_current_buf()
	local sr, sc, er, ec = region(kind)
	local char = last.add_char or read_char()
	if not char then
		return
	end
	if not PAIRS[char] and char ~= "t" then
		return
	end
	resolve(char, last.add_tag, function(tag)
		if char == "t" and not tag then
			return
		end
		last.add_char, last.add_tag = char, tag
		wrap(buf, sr, sc, er, ec, tag and tag_pair(tag) or PAIRS[char])
	end)
end

-- The outer range of the pair `char` around the cursor, from Neovim's `a` text object. Returns 0-based
-- start (row, col) and end (row, col) exclusive, or nil when there is no such pair.
local function find(char)
	local object = char == "t" and "t" or (PAIRS[char] and PAIRS[char][1])
	if not object then
		return nil
	end
	-- With 'selection' exclusive the `>` mark lands one past the pair; select inclusively, then restore.
	local view, selection = vim.fn.winsaveview(), vim.o.selection
	vim.o.selection = "inclusive"
	vim.cmd("silent! normal! v" .. "a" .. object .. "\27")
	vim.o.selection = selection
	local start, finish = vim.api.nvim_buf_get_mark(0, "<"), vim.api.nvim_buf_get_mark(0, ">")
	vim.fn.winrestview(view)
	local sr, sc, er, ec = start[1] - 1, start[2], finish[1] - 1, finish[2]
	local lines = vim.api.nvim_buf_get_lines(0, sr, er + 1, false)
	if #lines == 0 then
		return nil
	end
	ec = math.min(char_end(lines[#lines], ec), #lines[#lines])

	if QUOTES[char] then
		-- `a"` takes surrounding whitespace too; trim back to the quotes themselves.
		while sc < #lines[1] and lines[1]:sub(sc + 1, sc + 1) ~= char do
			sc = sc + 1
		end
		while ec > 0 and lines[#lines]:sub(ec, ec) ~= char do
			ec = ec - 1
		end
	end

	-- A text object that found nothing leaves a one-character selection; check the ends are the pair.
	local open = lines[1]:sub(sc + 1, sc + 1)
	local close = lines[#lines]:sub(ec, ec)
	if char == "t" then
		if open ~= "<" or close ~= ">" then
			return nil
		end
	elseif open ~= PAIRS[char][1] or close ~= PAIRS[char][2] or (sr == er and ec - sc < 2) then
		return nil
	end
	return sr, sc, er, ec
end

-- End (0-based, exclusive) of the opening tag that starts at (row, col): the first `>` outside quotes
-- and `{}`, so `<Foo onClick={() => go()}>` ends at the last `>`.
local function open_tag_end(buf, row, col)
	local lines = vim.api.nvim_buf_get_lines(buf, row, -1, false)
	local quote, depth = nil, 0
	for i, line in ipairs(lines) do
		for j = (i == 1 and col + 2 or 1), #line do
			local c = line:sub(j, j)
			if quote then
				if c == quote then
					quote = nil
				end
			elseif c == '"' or c == "'" or c == "`" then
				quote = c
			elseif c == "{" then
				depth = depth + 1
			elseif c == "}" then
				depth = depth - 1
			elseif c == ">" and depth == 0 then
				return row + i - 1, j
			end
		end
	end
end

-- The open and close halves of the pair found at the outer range, each as { start_row, start_col,
-- end_row, end_col }.
local function halves(buf, char, sr, sc, er, ec)
	if char ~= "t" then
		return { sr, sc, sr, sc + 1 }, { er, ec - 1, er, ec }
	end
	local open_row, open_col = open_tag_end(buf, sr, sc)
	local last_line = vim.api.nvim_buf_get_lines(buf, er, er + 1, false)[1]
	local close_col = last_line:sub(1, ec):match(".*()</") - 1
	return { sr, sc, open_row, open_col }, { er, close_col, er, ec }
end

local function apply(buf, open, close, new)
	vim.api.nvim_buf_set_text(buf, close[1], close[2], close[3], close[4], { new[2] })
	vim.api.nvim_buf_set_text(buf, open[1], open[2], open[3], open[4], { new[1] })
	vim.api.nvim_win_set_cursor(0, { open[1] + 1, open[2] })
end

function M._delete()
	local buf = vim.api.nvim_get_current_buf()
	local char = last.delete_char or read_char()
	if not char then
		return
	end
	local sr, sc, er, ec = find(char)
	if not sr then
		return no_pair(char)
	end
	last.delete_char = char
	local open, close = halves(buf, char, sr, sc, er, ec)
	apply(buf, open, close, { "", "" })
end

function M._replace()
	local buf = vim.api.nvim_get_current_buf()
	-- Both characters are read before looking, so a missing pair never leaves the second one to run as a
	-- normal-mode command.
	local old = last.replace_old or read_char()
	local new = old and (last.replace_new or read_char())
	if not new or (not PAIRS[new] and new ~= "t") then
		return
	end
	local sr, sc, er, ec = find(old)
	if not sr then
		return no_pair(old)
	end
	resolve(new, last.replace_tag, function(tag)
		if new == "t" and not tag then
			return
		end
		last.replace_old, last.replace_new, last.replace_tag = old, new, tag
		local open, close = halves(buf, old, sr, sc, er, ec)
		local pair = tag and tag_pair(tag) or PAIRS[new]
		if old == "t" and tag then
			-- Tag to tag keeps the attributes: only the names change.
			local open_text = table.concat(vim.api.nvim_buf_get_text(buf, open[1], open[2], open[3], open[4], {}), "\n")
			local name = tag:match("^[^%s>]+")
			pair = { (open_text:gsub("^<[^%s>/]*", "<" .. name, 1)), "</" .. name .. ">" }
		end
		apply(buf, open, close, pair)
		flash(buf, { open[1], open[2] }, { open[1], open[2] + #pair[1] })
	end)
end

-- Expression mappings: clear what `.` would reuse, then hand off to `g@`.
local function operator(fn, motion)
	return function()
		last = {}
		vim.o.operatorfunc = "v:lua.require'clasp.surround'." .. fn
		return "g@" .. (motion or "")
	end
end

function M._visual()
	local mode = vim.fn.visualmode()
	-- getregionpos() honours 'selection', so an exclusive selection ends on its last selected character.
	local region = vim.fn.getregionpos(vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = mode })
	if #region == 0 then
		return
	end
	local first, final = region[1][1], region[#region][2]
	vim.api.nvim_buf_set_mark(0, "[", first[2], first[3] - 1, {})
	vim.api.nvim_buf_set_mark(0, "]", final[2], final[3] - 1, {})
	last = {}
	M._add(mode == "V" and "line" or "char")
end

function M.setup(keys)
	local opts = { expr = true, silent = true }
	if keys.add then
		vim.keymap.set("n", keys.add, operator("_add"), vim.tbl_extend("force", opts, { desc = "clasp: add surround" }))
		vim.keymap.set("x", keys.add, "<Esc><Cmd>lua require('clasp.surround')._visual()<CR>", {
			silent = true,
			desc = "clasp: surround selection",
		})
	end
	if keys.delete then
		vim.keymap.set("n", keys.delete, operator("_delete", "l"), vim.tbl_extend("force", opts, { desc = "clasp: delete surround" }))
	end
	if keys.replace then
		vim.keymap.set("n", keys.replace, operator("_replace", "l"), vim.tbl_extend("force", opts, { desc = "clasp: replace surround" }))
	end
end

return M
