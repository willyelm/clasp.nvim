-- Split the pair around the cursor onto one item per line, or join it back onto one line:
--
--   foo(a, b, c)          foo(
--                           a,
--                           b,
--                           c
--                         )
--
-- Treesitter finds the smallest bracketed list (`()`, `[]`, `{}`) or tag (`<Foo a b>`) around the cursor, or
-- the first one after it on the line. Items are its named children, so this works in any language with a
-- parser.
local lang = require("clasp.lang")

local M = {}

local CLOSE = { ["("] = ")", ["["] = "]", ["{"] = "}" }

local function message(text)
	vim.api.nvim_echo({ { "clasp: " .. text, "WarningMsg" } }, false, {})
end

local function is_list(node)
	local count = node:child_count()
	if count < 2 then
		return false
	end
	local first, last = node:child(0), node:child(count - 1)
	return not first:named() and CLOSE[first:type()] == last:type()
end

local function tag_kind(buf, node)
	local ok, parser = pcall(vim.treesitter.get_parser, buf)
	if not ok or not parser then
		return nil
	end
	local sr, sc = node:start()
	local kind = lang.kinds[parser:language_for_range({ sr, sc, sr, sc }):lang()]
	if kind and (node:type() == kind.open or node:type() == kind.self) then
		return kind
	end
end

-- The list or tag node around (row, col), or nil.
local function container_at(buf, row, col)
	local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col } })
	if not ok then
		return nil
	end
	while node do
		if is_list(node) or tag_kind(buf, node) then
			return node
		end
		node = node:parent()
	end
end

-- The container around the cursor, or the first one that starts after it on the same line.
local function find(buf)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	row = row - 1
	local found = container_at(buf, row, col)
	if found then
		return found
	end
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	local at = line:find("[%(%[{<]", col + 1)
	while at do
		local node = container_at(buf, row, at - 1)
		if node then
			local sr, sc = node:start()
			if sr == row and sc == at - 1 then
				return node
			end
		end
		at = line:find("[%(%[{<]", at + 1)
	end
end

local function text(buf, node)
	return vim.treesitter.get_node_text(node, buf)
end

-- The list's items, each as { text, sep } where sep is the separator that followed it (`,`, `;` or "").
local function list_items(buf, node)
	local items = {}
	for i = 1, node:child_count() - 2 do
		local child = node:child(i)
		if child:named() then
			items[#items + 1] = { text = text(buf, child), sep = "", comment = child:type():find("comment") ~= nil }
		elseif #items > 0 then
			items[#items].sep = items[#items].sep .. text(buf, child)
		end
	end
	return items
end

-- A tag's name, attributes and closing (`>` or `/>`).
local function tag_parts(buf, node, kind)
	local name_node = kind.name_node(node)
	local attrs = {}
	for child in node:iter_children() do
		if child:named() and not (name_node and child:equal(name_node)) then
			attrs[#attrs + 1] = { text = text(buf, child), comment = child:type():find("comment") ~= nil }
		end
	end
	local tail = node:type() == kind.self and "/>" or ">"
	return name_node and text(buf, name_node) or "", attrs, tail
end

local function indent_unit()
	return vim.bo.expandtab and string.rep(" ", vim.fn.shiftwidth()) or "\t"
end

local function replace(buf, node, lines)
	local sr, sc, er, ec = node:range()
	vim.api.nvim_buf_set_text(buf, sr, sc, er, ec, lines)
	vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
end

-- `item` may span lines; only its first line gets the new indent, the rest keep theirs.
local function push_item(lines, prefix, item_text, suffix)
	local parts = vim.split(item_text, "\n", { plain = true })
	parts[1] = prefix .. parts[1]
	parts[#parts] = parts[#parts] .. suffix
	vim.list_extend(lines, parts)
end

function M._split()
	local buf = vim.api.nvim_get_current_buf()
	local node = find(buf)
	if not node then
		return message("nothing to split here")
	end
	local sr = node:start()
	local base = vim.api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1]:match("^%s*")
	local inner = base .. indent_unit()

	local kind = tag_kind(buf, node)
	local lines
	if kind then
		local name, attrs, tail = tag_parts(buf, node, kind)
		if #attrs == 0 then
			return message("no attributes to split")
		end
		lines = { "<" .. name }
		for _, attr in ipairs(attrs) do
			push_item(lines, inner, attr.text, "")
		end
		lines[#lines + 1] = base .. tail
	else
		local items = list_items(buf, node)
		if #items == 0 then
			return message("nothing to split here")
		end
		local open, close = text(buf, node:child(0)), text(buf, node:child(node:child_count() - 1))
		-- Go requires the trailing comma once the closer is on its own line.
		if vim.bo.filetype == "go" and items[#items].sep == "" and open ~= "{" then
			items[#items].sep = ","
		end
		lines = { open }
		for _, item in ipairs(items) do
			push_item(lines, inner, item.text, item.sep)
		end
		lines[#lines + 1] = base .. close
	end
	replace(buf, node, lines)
end

function M._join()
	local buf = vim.api.nvim_get_current_buf()
	local node = find(buf)
	if not node then
		return message("nothing to join here")
	end

	local kind = tag_kind(buf, node)
	local items = kind and select(2, tag_parts(buf, node, kind)) or list_items(buf, node)
	for _, item in ipairs(items) do
		if item.comment then
			return message("a comment would swallow the rest of the line")
		elseif item.text:find("\n", 1, true) then
			return message("join the multi-line item inside first")
		end
	end

	local joined
	if kind then
		local name, attrs, tail = tag_parts(buf, node, kind)
		local words = { "<" .. name }
		for _, attr in ipairs(attrs) do
			words[#words + 1] = attr.text
		end
		joined = table.concat(words, " ") .. (tail == "/>" and " />" or ">")
	else
		local open, close = text(buf, node:child(0)), text(buf, node:child(node:child_count() - 1))
		local parts = {}
		for i, item in ipairs(items) do
			-- A trailing comma only belongs on the multi-line form.
			local sep = (i == #items and item.sep == ",") and "" or item.sep
			parts[#parts + 1] = item.text .. sep
		end
		local pad = (open == "{" and #parts > 0) and " " or ""
		joined = open .. pad .. table.concat(parts, " ") .. pad .. close
	end
	replace(buf, node, { joined })
end

local function operator(fn)
	return function()
		vim.o.operatorfunc = "v:lua.require'clasp.split'." .. fn
		return "g@l"
	end
end

function M.setup(keys)
	local opts = { expr = true, silent = true }
	if keys.split then
		vim.keymap.set("n", keys.split, operator("_split"), vim.tbl_extend("force", opts, { desc = "clasp: split pair onto lines" }))
	end
	if keys.join then
		vim.keymap.set("n", keys.join, operator("_join"), vim.tbl_extend("force", opts, { desc = "clasp: join pair onto one line" }))
	end
end

return M
