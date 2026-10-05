-- Run from the repo root: nvim --headless -u NONE -l tests/pairs.lua
-- Pairs are expression mappings, so keys are typed for real into an embedded Neovim; `|` marks where the
-- cursor ends up.
local root = vim.fn.getcwd()
local child = vim.fn.jobstart({ "nvim", "--embed", "--headless", "-u", "NONE" }, { rpc = true })
local function lua(code, ...)
	return vim.rpcrequest(child, "nvim_exec_lua", code, { ... })
end
lua(
	[[
	vim.opt.rtp:prepend(...)
	vim.o.swapfile = false
	vim.cmd("filetype plugin indent on")
	vim.treesitter.language.register("tsx", "typescriptreact")
	vim.o.autoindent = true
	vim.o.expandtab = true
	vim.o.shiftwidth = 2
	require("clasp").setup()
]],
	root
)

local pass, fail = 0, 0
local function case(ft, before, keys, expect, after)
	lua(
		[[
		local ft, before, after = ...
		vim.cmd("enew!")
		vim.bo.filetype = ft
		local lines = vim.split(before, "\n")
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		local row, col = #lines, #lines[#lines]
		if after ~= "" then
			vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { after })
		end
		pcall(vim.treesitter.start)
		vim.api.nvim_win_set_cursor(0, { row, col })
	]],
		ft,
		before,
		after or ""
	)
	-- `a` from normal mode appends after the cursor; with the cursor clamped onto the last character that
	-- would skip one, so insert starts with `i` and the cursor is moved right first when text follows.
	local start = (after and after ~= "") and "i" or "a"
	if before == "" or before:sub(-1) == "\n" then
		start = "i"
	end
	vim.rpcrequest(child, "nvim_input", start .. keys .. "|<Esc>")
	vim.wait(50)
	local got = lua([[return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")]])
	local ok = got == expect
	if ok then
		pass = pass + 1
	else
		fail = fail + 1
	end
	io.stdout:write(
		("%s [%s] %q + %q\n     got:    %q\n%s"):format(
			ok and "ok  " or "FAIL",
			ft,
			before,
			keys,
			got,
			ok and "" or ("     expect: %q\n"):format(expect)
		)
	)
end

-- brackets
case("lua", "x = ", "(", "x = (|)")
case("lua", "x = ", "{", "x = {|}")
case("lua", "x = ", "foo(a", "x = foo(a|)")
case("lua", "x = ", "foo(a)", "x = foo(a)|")
case("lua", "x = ", "(", "x = (|foo", "foo")
-- quotes
case("lua", "x = ", '"', 'x = "|"')
case("lua", "x = ", '"ab"', 'x = "ab"|')
case("lua", "-- don", "'t", "-- don't|")
case("lua", 'x = "it', "'", 'x = "it\'|"', '"')
case("typescriptreact", "const s = ", "`", "const s = `|`")
-- a quote right after the same quote is not paired: `"""` docstrings, ``` fences
case("python", "", '"""', '"""|')
case("markdown", "", "```", "```|")
-- <BS> deletes an empty pair
case("lua", "x = ", "(<BS>", "x = |")
case("lua", "x = ", '"<BS>', "x = |")
case("lua", "x = ", "(a<BS><BS>", "x = |")
-- <CR> opens a pair or a tag
case("lua", "local t = ", "{<CR>a", "local t = {\n  a|\n}")
-- Indentation is the filetype's own indentexpr (here Neovim's built-in one aligns with the `(`).
case("typescriptreact", "const a = (", "<lt>div><CR>x", "const a = (<div>\n           x|\n           </div>)", ")")
case("lua", "x = 1", "<CR>y", "x = 1\ny|")
-- self-closing: `/` in an empty element collapses it, <BS> on that `/` reopens it
case("typescriptreact", "const a = (", "<lt>Foo>/", "const a = (<Foo />|)", ")")
case("typescriptreact", "const a = (", '<lt>Foo a="1">/', 'const a = (<Foo a="1" />|)', ")")
case("typescriptreact", "const a = (<Foo /", "<BS>", "const a = (<Foo>|</Foo>)", ">)")
case("typescriptreact", "const a = (<Foo a={1} /", "<BS>x", "const a = (<Foo a={1}>x|</Foo>)", ">)")
-- <BS> right after the collapse undoes it
case("typescriptreact", "const a = (", "<lt>Foo>/<BS>", "const a = (<Foo>|</Foo>)", ")")
case("typescriptreact", "const a = (<Foo />", "<BS>", "const a = (<Foo>|</Foo>)", ")")
case("typescriptreact", "const a = (<div>a /", "<BS>", "const a = (<div>a |</div>)", "</div>)")
-- plain HTML only self-closes void elements, so it is left alone
case("html", "", "<lt>div>/", "<div>/|</div>")
case("html", "<br /", "<BS>", "<br |>", ">")
-- <BS> still deletes an empty pair in tag buffers
case("typescriptreact", "const a = ", "(<BS>", "const a = |")

-- `${` in a quoted JS/TS string turns it into a template literal
case("typescriptreact", 'const s = "hi ', "${name", "const s = `hi ${name|}`", '"')
case("typescriptreact", "const s = 'a ", "${", "const s = `a ${|}b`", "b'")
case("typescript", "const s = `a ", "${", "const s = `a ${|}`", "`")
case("typescriptreact", "const o = ", "${", "const o = ${|}")
-- other languages keep the usual rule: no pair right before a quote
case("lua", 'x = "', "${", 'x = "${|"', '"')
-- JS/TS `{` outside strings is still the usual pair
case("typescript", "const o = ", "{", "const o = {|}")
case("typescript", "const o = ", "{", "const o = {|x", "x")

-- visual-block insert types the same text on every line, so it is never paired
lua([[vim.cmd("enew!") vim.api.nvim_buf_set_lines(0, 0, -1, false, { " aa", " bb" })]])
vim.rpcrequest(child, "nvim_input", "gg0<C-v>jI(<Esc>")
vim.wait(50)
local block = table.concat(lua([[return vim.api.nvim_buf_get_lines(0, 0, -1, false)]]), "/")
local block_ok = block == "( aa/( bb"
pass, fail = pass + (block_ok and 1 or 0), fail + (block_ok and 0 or 1)
io.stdout:write(("%s [block insert] %q\n"):format(block_ok and "ok  " or "FAIL", block))
-- pairing is back after the block insert
case("lua", "x = ", "(", "x = (|)")

-- prompt buffers are left alone
lua([[vim.cmd("enew!") vim.bo.buftype = "prompt"]])
vim.rpcrequest(child, "nvim_input", "i(|<Esc>")
vim.wait(50)
local prompt = lua([[return vim.api.nvim_get_current_line()]])
-- The prompt buffer shows its own "% " prefix.
local prompt_ok = prompt == "% (|"
pass, fail = pass + (prompt_ok and 1 or 0), fail + (prompt_ok and 0 or 1)
io.stdout:write(("%s [prompt] %q\n"):format(prompt_ok and "ok  " or "FAIL", prompt))

io.stdout:write(("\n%d passed, %d failed\n"):format(pass, fail))
vim.fn.jobstop(child)
os.exit(fail > 0 and 1 or 0)
