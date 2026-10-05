-- Per-language tag shapes. Every grammar names its tags differently; the rest of clasp only asks this
-- module "is this an opening tag, what is it called, and where is its pair".
local M = {}

-- Elements HTML never closes; typing `<img>` must not insert `</img>`.
M.void = {
	area = true,
	base = true,
	br = true,
	col = true,
	embed = true,
	hr = true,
	img = true,
	input = true,
	link = true,
	meta = true,
	param = true,
	source = true,
	track = true,
	wbr = true,
}

-- The node holding a tag's name, or nil for a JSX fragment (`<>`), which has none.
local function html_name_node(node)
	for child in node:iter_children() do
		if child:type() == "tag_name" then
			return child
		end
	end
end

local function jsx_name_node(node)
	return node:field("name")[1]
end

local function xml_name_node(node)
	for child in node:iter_children() do
		if child:type() == "Name" then
			return child
		end
	end
end

-- `open`/`close` are the tag nodes, `element` the node pairing them and `self` a self-closing tag.
local function kind(open, close, element, self, name_node, void)
	return {
		open = open,
		close = close,
		element = element,
		self = self,
		name_node = name_node,
		void = void,
		name = function(node, buf)
			local name = name_node(node)
			return name and vim.treesitter.get_node_text(name, buf) or ""
		end,
	}
end

local html = kind("start_tag", "end_tag", "element", "self_closing_tag", html_name_node, true)
local jsx = kind("jsx_opening_element", "jsx_closing_element", "jsx_element", "jsx_self_closing_element", jsx_name_node, false)
local xml = kind("STag", "ETag", "element", "EmptyElemTag", xml_name_node, false)

M.kinds = {
	html = html,
	vue = html,
	svelte = html,
	astro = html,
	javascript = jsx,
	tsx = jsx,
	xml = xml,
}

-- Strings and comments, where a typed `<`, `>` or `/` is never markup. Element text is not here: `</`
-- is typed in text.
M.inert = {
	comment = true,
	string = true,
	string_fragment = true,
	template_string = true,
	attribute_value = true,
	quoted_attribute_value = true,
}

-- The tree root, tag shape and language name covering a position, after bringing the parse up to date with
-- what was just typed.
function M.tree_at(buf, row, col)
	local ok, parser = pcall(vim.treesitter.get_parser, buf)
	if not ok or not parser then
		return nil
	end
	parser:parse(true)
	local ltree = parser:language_for_range({ row, col, row, col })
	local kind = M.kinds[ltree:lang()]
	if not kind then
		return nil
	end
	local tree = ltree:tree_for_range({ row, col, row, col }, { ignore_injections = true })
	if not tree then
		return nil
	end
	return tree:root(), kind, ltree:lang()
end

function M.node_at(root, row, col)
	return root:named_descendant_for_range(row, col, row, col)
end

function M.is_inert(node)
	return node ~= nil and M.inert[node:type()] == true
end

return M
