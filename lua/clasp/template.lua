-- `${` typed in a "…" or '…' string turns it into a template literal: `…${|}…`. Elsewhere `{` behaves as
-- the usual pair.
local M = {}

local LANGS = { javascript = true, typescript = true, tsx = true }

-- The quoted string node around (row, col) in a JS/TS buffer, or nil.
local function string_at(buf, row, col)
	local ok, parser = pcall(vim.treesitter.get_parser, buf)
	if not ok or not parser then
		return nil
	end
	parser:parse({ row, row + 1 })
	local ltree = parser:language_for_range({ row, col, row, col })
	if not LANGS[ltree:lang()] then
		return nil
	end
	local node = ltree:named_node_for_range({ row, col, row, col }, { ignore_injections = true })
	while node and node:type() ~= "string" do
		node = node:parent()
	end
	return node
end

-- Whether `{` in this buffer may complete a `${`.
function M.applies()
	local ft = vim.bo.filetype
	return (ft:match("^javascript") or ft:match("^typescript")) ~= nil
end

-- `{` typed in a JS/TS buffer: after `$` in a quoted string, convert the string; otherwise the usual pair.
function M.brace()
	local buf = vim.api.nvim_get_current_buf()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	row = row - 1
	local line = vim.api.nvim_get_current_line()
	local node = line:sub(col, col) == "$" and string_at(buf, row, col - 1)
	if node then
		local sr, sc, er, ec = node:range()
		local text = vim.treesitter.get_node_text(node, buf)
		local quote = text:sub(1, 1)
		-- Single-line strings without backticks only: anything else would need escaping to stay the same.
		if sr == er and (quote == '"' or quote == "'") and not text:find("`", 1, true) then
			vim.api.nvim_buf_set_text(buf, er, ec - 1, er, ec, { "`" })
			vim.api.nvim_buf_set_text(buf, sr, sc, sr, sc + 1, { "`" })
			line = vim.api.nvim_get_current_line()
		else
			node = nil
		end
	end
	-- `${` always starts a substitution, so it is always paired.
	local paired = line:sub(col, col) == "$" or require("clasp.pairs").pairs_before(line:sub(col + 1, col + 1))
	vim.api.nvim_buf_set_text(buf, row, col, row, col, { paired and "{}" or "{" })
	vim.api.nvim_win_set_cursor(0, { row + 1, col + 1 })
end

return M
