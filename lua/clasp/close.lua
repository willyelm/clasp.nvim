-- Tag closing while typing: `>` closes the tag just opened, `</` completes the innermost open tag, `/`
-- inside an unfinished opening tag or an empty element self-closes it, and deleting that `/` opens it back
-- up. Each one is a single buffer edit.
local lang = require("clasp.lang")

local M = {}

-- How far back the self-close scanner looks for the `<` that opened the tag being typed.
local SCAN_LINES = 50

local function cursor()
	local pos = vim.api.nvim_win_get_cursor(0)
	return pos[1] - 1, pos[2]
end

-- Inserting at the cursor pushes it past the text, so it is always placed explicitly: after the text when
-- `move`, otherwise where it was.
local function insert(buf, row, col, text, move)
	vim.api.nvim_buf_set_text(buf, row, col, row, col, { text })
	vim.api.nvim_win_set_cursor(0, { row + 1, move and col + #text or col })
end

-- `<div>` just typed: insert the matching `</div>` after the cursor.
function M.on_gt(buf)
	local row, col = cursor()
	local line = vim.api.nvim_get_current_line()
	local prev = line:sub(col - 1, col - 1)
	-- `/>` already closes itself; `=>` and `->` are never tags.
	if line:sub(col, col) ~= ">" or prev == "/" or prev == "=" or prev == "-" then
		return
	end

	local root, kind = lang.tree_at(buf, row, col - 1)
	if not root then
		return
	end
	local node = lang.node_at(root, row, col - 1)
	if lang.is_inert(node) then
		return
	end
	while node and node:type() ~= kind.open do
		node = node:parent()
	end
	if not node then
		return
	end
	local _, _, end_row, end_col = node:range()
	if end_row ~= row or end_col ~= col then
		return
	end

	local name = kind.name(node, buf)
	if not name or (kind.void and lang.void[name:lower()]) then
		return
	end
	local closing = "</" .. name .. ">"
	if vim.startswith(line:sub(col + 1), closing) then
		return
	end
	insert(buf, row, col, closing, false)
end

-- Names of the tags still open before (row, col), innermost last.
local function open_tags(buf, root, kind, row, col)
	local stack = {}
	local function before(node)
		local start_row, start_col = node:start()
		return start_row < row or (start_row == row and start_col < col)
	end
	local function walk(node)
		for child in node:iter_children() do
			if not before(child) then
				return false
			end
			local kind_of = child:type()
			if kind_of == kind.open then
				local name = kind.name(child, buf)
				if name and not (kind.void and lang.void[name:lower()]) then
					stack[#stack + 1] = name
				end
			elseif kind_of == kind.close then
				local name = kind.name(child, buf)
				for i = #stack, 1, -1 do
					if stack[i] == name then
						for j = #stack, i, -1 do
							stack[j] = nil
						end
						break
					end
				end
			end
			if walk(child) == false then
				return false
			end
		end
	end
	walk(root)
	return stack
end

-- `</` just typed: complete the innermost tag that is still open.
local function close_open_tag(buf, row, col, line)
	local root, kind = lang.tree_at(buf, row, col - 2)
	if not root or lang.is_inert(lang.node_at(root, row, col - 2)) then
		return
	end
	local stack = open_tags(buf, root, kind, row, col - 2)
	local name = stack[#stack]
	if not name then
		return
	end
	-- Typed just before that tag's own closing tag: nothing is left to close.
	if vim.startswith(line:sub(col + 1), "</" .. name) or vim.startswith(line:sub(col + 1), name) then
		return
	end
	local text = line:sub(col + 1, col + 1) == ">" and name or name .. ">"
	insert(buf, row, col, text, true)
end

-- The tag name if `text` ends inside an opening tag that has not been finished with `>`. Quotes and `{}`
-- are tracked so `>` in a string or in `() => x` does not count as the end of the tag. `in_text(i)` says
-- whether the character at byte `i` is element text, where `x<br` starts a tag rather than comparing.
local function unfinished_tag(text, in_text)
	local name, quote, depth
	local i = 1
	while i <= #text do
		local c = text:sub(i, i)
		if not name then
			-- In code, `a<b` is a comparison or a generic, not a tag.
			local tag = c == "<" and text:match("^<([%a_$][%w_$%.:%-]*)", i)
			if tag and text:sub(i - 1, i - 1):match("[%w_$%)%]]") and not in_text(i - 1) then
				tag = nil
			end
			if tag then
				name, quote, depth = tag, nil, 0
				i = i + #tag
			end
		elseif quote then
			if c == "\\" then
				i = i + 1
			elseif c == quote then
				quote = nil
			end
		elseif c == '"' or c == "'" or c == "`" then
			quote = c
		elseif c == "{" then
			depth = depth + 1
		elseif c == "}" then
			depth = math.max(0, depth - 1)
		elseif depth == 0 and c == ">" then
			name = nil
		elseif depth == 0 and c == "<" then
			-- A new `<` outside braces: whatever came before was not a tag.
			name = nil
			i = i - 1
		end
		i = i + 1
	end
	return name and not quote and depth == 0 and name or nil
end

-- `/` typed inside an opening tag: finish it as `<Foo />`, dropping an empty `</Foo>` already after it.
local function self_close(buf, row, col, line)
	local prev = line:sub(col - 1, col - 1)
	if prev == "=" then
		return
	end
	local root = lang.tree_at(buf, row, col - 1)
	if not root or lang.is_inert(lang.node_at(root, row, col - 1)) then
		return
	end

	local first = math.max(0, row - SCAN_LINES)
	local lines = vim.api.nvim_buf_get_lines(buf, first, row, false)
	lines[#lines + 1] = line:sub(1, col - 1)
	-- Byte offset of each scanned line in the joined text, to map a byte back to a buffer position.
	local starts, offset = {}, 0
	for i, l in ipairs(lines) do
		starts[i] = offset
		offset = offset + #l + 1
	end
	local function in_text(i)
		local idx = #starts
		while idx > 1 and starts[idx] >= i do
			idx = idx - 1
		end
		local node = lang.node_at(root, first + idx - 1, i - starts[idx] - 1)
		return node ~= nil and (node:type() == "jsx_text" or node:type() == "text")
	end
	local name = unfinished_tag(table.concat(lines, "\n"), in_text)
	if not name then
		return
	end

	local rest = line:sub(col + 1)
	if rest:sub(1, 1) == ">" then
		local empty = rest:match("^>%s*</" .. vim.pesc(name) .. ">")
		if empty then
			vim.api.nvim_buf_set_text(buf, row, col + 1, row, col + #empty, {})
			vim.api.nvim_win_set_cursor(0, { row + 1, col + 1 })
		end
		return
	end
	insert(buf, row, col, ">", true)
end

-- Plain HTML only self-closes void elements (`<br />`), so `<div />` is never produced or expanded there.
local function self_closing_allowed(language, kind, name)
	return language ~= "html" and not (kind.void and lang.void[name:lower()])
end

-- `/` typed in an empty element, `<Foo>/|</Foo>`: collapse it to `<Foo />`.
local function collapse(buf, row, col, line)
	if line:sub(col - 1, col - 1) ~= ">" then
		return false
	end
	local root, kind, language = lang.tree_at(buf, row, col - 2)
	if not root then
		return false
	end
	local node = lang.node_at(root, row, col - 2)
	while node and node:type() ~= kind.open do
		node = node:parent()
	end
	if not node then
		return false
	end
	local _, _, end_row, end_col = node:range()
	local name = kind.name(node, buf)
	local closing = "</" .. name .. ">"
	if end_row ~= row or end_col ~= col - 1 or name == "" or not vim.startswith(line:sub(col + 1), closing) then
		return false
	end
	if not self_closing_allowed(language, kind, name) then
		return false
	end
	-- Replace `>/</Foo>` with ` />`, without doubling a space that is already there.
	local text = line:sub(col - 2, col - 2) == " " and "/>" or " />"
	vim.api.nvim_buf_set_text(buf, row, col - 2, row, col + #closing, { text })
	vim.api.nvim_win_set_cursor(0, { row + 1, col - 2 + #text })
	return true
end

function M.on_slash(buf, opts)
	local row, col = cursor()
	local line = vim.api.nvim_get_current_line()
	if line:sub(col, col) ~= "/" then
		return
	end
	if line:sub(col - 1, col - 1) == "<" then
		if opts.on_slash then
			close_open_tag(buf, row, col, line)
		end
	elseif opts.self_close and not collapse(buf, row, col, line) then
		self_close(buf, row, col, line)
	end
end

-- 0-based column of the `/` in a `/>` the cursor is on or just after (`<Foo /|>`, `<Foo />|`), or nil.
local function slash_col(line, col)
	if line:sub(col, col + 1) == "/>" then
		return col - 1
	elseif line:sub(col - 1, col) == "/>" then
		return col - 2
	end
end

-- Whether <BS> at the cursor would delete part of a `/>`.
function M.at_self_closing_slash()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	return slash_col(vim.api.nvim_get_current_line(), col) ~= nil
end

-- The name of the self-closing tag whose `/>` starts at (row, slash), or nil.
local function self_closing_at(buf, row, slash)
	local root, kind, language = lang.tree_at(buf, row, slash)
	local node = root and lang.node_at(root, row, slash)
	while node and node:type() ~= kind.self do
		node = node:parent()
	end
	if not node then
		return nil
	end
	local _, _, end_row, end_col = node:range()
	local name = kind.name(node, buf)
	if name == "" or end_row ~= row or end_col ~= slash + 2 or not self_closing_allowed(language, kind, name) then
		return nil
	end
	return name
end

-- <BS> on or just after the `/>` of `<Foo />`: open it back up as `<Foo>|</Foo>`. Anywhere else it is a
-- plain backspace.
function M.expand(buf)
	local row, col = cursor()
	local line = vim.api.nvim_get_current_line()
	local slash = slash_col(line, col)
	local name = slash and self_closing_at(buf, row, slash)
	if not name then
		vim.api.nvim_buf_set_text(buf, row, col - 1, row, col, {})
		vim.api.nvim_win_set_cursor(0, { row + 1, col - 1 })
		return
	end
	-- Drop the space before the slash too: `<Foo />` → `<Foo>|</Foo>`.
	local start = line:sub(slash, slash) == " " and slash - 1 or slash
	vim.api.nvim_buf_set_text(buf, row, start, row, slash + 2, { "></" .. name .. ">" })
	vim.api.nvim_win_set_cursor(0, { row + 1, start + 1 })
end

return M
