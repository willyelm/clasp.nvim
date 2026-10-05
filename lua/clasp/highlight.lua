-- Highlight the matching tag, like the built-in matchparen does for brackets: with the cursor in `<div …>`
-- or `</div>`, both tag names get `MatchParen`.
local lang = require("clasp.lang")

local M = {}

local ns = vim.api.nvim_create_namespace("clasp_match_tag")

local function mark(buf, node)
	local sr, sc, er, ec = node:range()
	vim.api.nvim_buf_set_extmark(buf, ns, sr, sc, { end_row = er, end_col = ec, hl_group = "MatchParen" })
end

-- The opening and closing tag of the element whose tag the cursor is in, or nil.
local function pair_at(buf, row, col)
	local root, kind = lang.tree_at(buf, row, col)
	if not root then
		return nil
	end
	local node = lang.node_at(root, row, col)
	-- Stop at the element itself: the cursor is in its content, not on one of its tags.
	while node and node:type() ~= kind.open and node:type() ~= kind.close do
		if node:type() == kind.element then
			return nil
		end
		node = node:parent()
	end
	local element = node and node:parent()
	if not element or element:type() ~= kind.element then
		return nil
	end
	local open, close
	for child in element:iter_children() do
		if child:type() == kind.open then
			open = child
		elseif child:type() == kind.close then
			close = child
		end
	end
	if open and close then
		return open, close, kind
	end
end

function M.update(buf)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local pos = vim.api.nvim_win_get_cursor(0)
	local open, close, kind = pair_at(buf, pos[1] - 1, pos[2])
	if not open then
		return
	end
	-- Fragments (`<>`) have no name; highlight the whole tags.
	mark(buf, kind.name_node(open) or open)
	mark(buf, kind.name_node(close) or close)
end

function M.attach(buf)
	local group = vim.api.nvim_create_augroup("clasp_highlight_" .. buf, { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "BufEnter" }, {
		group = group,
		buffer = buf,
		callback = function()
			M.update(buf)
		end,
	})
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = group,
		buffer = buf,
		callback = function()
			vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		end,
	})
end

function M.detach(buf)
	pcall(vim.api.nvim_del_augroup_by_name, "clasp_highlight_" .. buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	end
end

return M
