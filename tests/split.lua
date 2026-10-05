-- Run from the repo root: nvim --headless -u NONE -l tests/split.lua
-- Keys are typed in normal mode into an embedded Neovim. `|` marks the cursor, before and after.
io.stdout:setvbuf("line")
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
	vim.o.expandtab = true
	vim.o.shiftwidth = 2
	require("clasp").setup()
]],
	root
)

local pass, fail = 0, 0
local function case(ft, before, keys, expect)
	lua(
		[[
		local ft, before = ...
		vim.cmd("enew!")
		vim.bo.filetype = ft
		vim.bo.expandtab = true
		vim.bo.shiftwidth = 2
		local lines = vim.split(before, "\n")
		local row, col
		for i, l in ipairs(lines) do
			local at = l:find("|", 1, true)
			if at then
				row, col = i, at - 1
				lines[i] = l:sub(1, at - 1) .. l:sub(at + 1)
			end
		end
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		pcall(vim.treesitter.start)
		vim.api.nvim_win_set_cursor(0, { row, col })
	]],
		ft,
		before
	)
	vim.rpcrequest(child, "nvim_input", keys)
	vim.wait(80)
	local got = lua([[
		local r, c = unpack(vim.api.nvim_win_get_cursor(0))
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		lines[r] = lines[r]:sub(1, c) .. "|" .. lines[r]:sub(c + 1)
		return table.concat(lines, "\n")
	]])
	local ok = got == expect
	if ok then
		pass = pass + 1
	else
		fail = fail + 1
	end
	io.stdout:write(
		("%s [%s] %q + %q\n%s"):format(
			ok and "ok  " or "FAIL",
			ft,
			before,
			keys,
			ok and "" or ("     got:    %q\n     expect: %q\n"):format(got, expect)
		)
	)
end

-- lists
case("typescript", "foo(a, |b, c);", "gss", "foo|(\n  a,\n  b,\n  c\n);")
case("typescript", "foo|(\n  a,\n  b,\n  c\n);", "gsj", "foo|(a, b, c);")
case("typescript", "const o = { a: 1, |b: 2 };", "gss", "const o = |{\n  a: 1,\n  b: 2\n};")
case("typescript", "const o = |{\n  a: 1,\n  b: 2,\n};", "gsj", "const o = |{ a: 1, b: 2 };")
case("lua", "  local t = { 1, |2 }", "gss", "  local t = |{\n    1,\n    2\n  }")
-- the cursor before the list on the same line still finds it
case("typescript", "fo|o(a, b);", "gss", "foo|(\n  a,\n  b\n);")
-- the innermost list wins
case("typescript", "foo(a, [1, |2]);", "gss", "foo(a, |[\n  1,\n  2\n]);")
-- tags: one attribute per line, closer on its own line
case("typescriptreact", 'const a = <Foo a="1" |b={2}>x</Foo>;', "gss", 'const a = |<Foo\n  a="1"\n  b={2}\n>x</Foo>;')
case("typescriptreact", 'const a = |<Foo\n  a="1"\n  b={2}\n/>;', "gsj", 'const a = |<Foo a="1" b={2} />;')
case("html", '<input type="text" |name="q">', "gss", '|<input\n  type="text"\n  name="q"\n>')
-- `.` repeats
case("typescript", "foo(a, |b);\nbar(c, d);", "gssG.", "foo(\n  a,\n  b\n);\nbar|(\n  c,\n  d\n);")
-- refuses to join over comments or multi-line items
case("typescript", "foo|(\n  a, // note\n  b\n);", "gsj", "foo|(\n  a, // note\n  b\n);")
case("typescript", "foo|(\n  {\n    x: 1,\n  },\n  b\n);", "gsj", "foo|(\n  {\n    x: 1,\n  },\n  b\n);")
-- nothing to do
case("typescript", "const |x = 1;", "gss", "const |x = 1;")

io.stdout:write(("\n%d passed, %d failed\n"):format(pass, fail))
vim.fn.jobstop(child)
os.exit(fail > 0 and 1 or 0)
