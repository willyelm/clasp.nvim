-- Run from the repo root: nvim --headless -u NONE -l tests/highlight.lua
-- `|` marks the cursor; the expected result is the highlighted text, in order.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd("filetype on")
vim.treesitter.language.register("tsx", "typescriptreact")
require("clasp").setup()
local highlight = require("clasp.highlight")
local ns = vim.api.nvim_get_namespaces().clasp_match_tag

local pass, fail = 0, 0
local function case(ft, text, expect)
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(buf)
	vim.bo[buf].filetype = ft
	local lines = vim.split(text, "\n")
	local row, col
	for i, l in ipairs(lines) do
		local at = l:find("|", 1, true)
		if at then
			row, col = i, at - 1
			lines[i] = l:sub(1, at - 1) .. l:sub(at + 1)
		end
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, { row, col })
	highlight.update(buf)
	local got = {}
	for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
		local text_hl = vim.api.nvim_buf_get_text(buf, m[2], m[3], m[4].end_row, m[4].end_col, {})
		got[#got + 1] = table.concat(text_hl, "\n")
	end
	local ok = vim.deep_equal(got, expect)
	if ok then
		pass = pass + 1
	else
		fail = fail + 1
	end
	io.stdout:write(
		("%s [%s] %q\n%s"):format(
			ok and "ok  " or "FAIL",
			ft,
			text,
			ok and "" or ("     got:    %s\n     expect: %s\n"):format(vim.inspect(got), vim.inspect(expect))
		)
	)
	vim.api.nvim_buf_delete(buf, { force = true })
end

case("typescriptreact", "const a = <d|iv><span>hi</span></div>;", { "div", "div" })
case("typescriptreact", "const a = <div><span>hi</span></d|iv>;", { "div", "div" })
case("typescriptreact", "const a = <div><sp|an>hi</span></div>;", { "span", "span" })
case("typescriptreact", 'const a = <div className="|a">x</div>;', { "div", "div" })
-- in an element's content, not on a tag
case("typescriptreact", "const a = <div><span>h|i</span></div>;", {})
case("typescriptreact", "const a = <div>|x</div>;", {})
-- self-closing tags have no pair
case("typescriptreact", "const a = <div><Fo|o /></div>;", {})
-- fragments have no name: the whole tags light up
case("typescriptreact", "const a = <|>x</>;", { "<>", "</>" })
-- multi-line, and member-expression names
case("typescriptreact", "const a = (\n  <Foo.B|ar>\n    x\n  </Foo.Bar>\n);", { "Foo.Bar", "Foo.Bar" })
case("html", "<ul><l|i>a</li></ul>", { "li", "li" })
case("html", "<ul><li>a</li></u|l>", { "ul", "ul" })
case("html", "<p>t|ext</p>", {})
-- outside markup
case("typescriptreact", "const a = 1 |+ 2;", {})

io.stdout:write(("\n%d passed, %d failed\n"):format(pass, fail))
os.exit(fail > 0 and 1 or 0)
