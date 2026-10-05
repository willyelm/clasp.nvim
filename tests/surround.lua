-- Run from the repo root: nvim --headless -u NONE -l tests/surround.lua
io.stdout:setvbuf("line")
-- Keys are typed in normal mode into an embedded Neovim. `|` marks the cursor, before and after.
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

-- add
case("lua", "x = |word", 'gsaiw"', 'x = |"word"')
case("lua", "x = |word", "gsaiw)", "x = |(word)")
case("lua", "x = |a b c", "gsa$]", "x = |[a b c]")
case("lua", "local |a = 1", "veegsa{", "local |{a = 1}")
case("lua", "x = |word", "gsaiwtdiv<CR>", "x = |<div>word</div>")
case("lua", 'x = |word', 'gsaiwtdiv class="a"<CR>', 'x = |<div class="a">word</div>')
case("lua", "x = |a\ny = b", "gsaiw'j.", "x = 'a'\ny = |'b'")
case("lua", "x = |word", "gsaiw<Esc>", "x = |word")
-- delete
case("lua", 'x = "wo|rd"', 'gsd"', "x = |word")
case("lua", "x = (a, (b|))", "gsd(", "x = (a, |b)")
case("lua", "x = (a, |b)", "gsd)", "x = |a, b")
-- Normal mode clamps the cursor onto the last character.
case("lua", "x = [|]", "gsd[", "x =| ")
case("lua", "x = wo|rd", "gsd(", "x = wo|rd")
case("typescriptreact", "const a = <div className=\"a\"><span>h|i</span></div>", "gsdt", "const a = <div className=\"a\">|hi</div>")
case("typescriptreact", "const a = <Foo onClick={() => go()}>|x</Foo>", "gsdt", "const a = |x")
case("lua", 'x = "a" .. "|b"', 'gsd".', "x = \"a\" .. |b")
-- replace
case("lua", 'x = "wo|rd"', "gsr\"'", "x = |'word'")
case("lua", "x = (wo|rd)", "gsr([", "x = |[word]")
case("typescriptreact", 'const a = <div className="a">h|i</div>', "gsrttsection<CR>", 'const a = |<section className="a">hi</section>')
case("lua", "x = (wo|rd)", "gsr(tb<CR>", "x = |<b>word</b>")
case("lua", "x = wo|rd", "gsr([", "x = wo|rd")
-- the next key after a missed replace is a fresh normal-mode key, not left pending
case("lua", "x = wo|rd", "gsr([0", "|x = word")

-- 'selection' exclusive moves the `>` mark one past the selection
lua([[vim.o.selection = "exclusive"]])
case("lua", "x = foo(\"|a\");", "gsd(", "x = foo|\"a\";")
case("lua", "x = (wo|rd);", "gsr([", "x = |[word];")
case("lua", "local |a = 1", "veegsa{", "local |{a = 1}")
case("lua", "x = <div>h|i</div>;", "gsdt", "x = |hi;")
lua([[vim.o.selection = "inclusive"]])

io.stdout:write(("\n%d passed, %d failed\n"):format(pass, fail))
vim.fn.jobstop(child)
os.exit(fail > 0 and 1 or 0)
