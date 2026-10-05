-- Run from the repo root: nvim --headless -u NONE -l tests/close.lua
-- Characters are inserted directly and the handlers called the way the InsertCharPre callback calls them;
-- `|` marks where the cursor ends up.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd("filetype on")
vim.o.virtualedit = "onemore"
vim.treesitter.language.register("tsx", "typescriptreact")
require("clasp").setup()
local pass, fail = 0, 0

local function case(ft, before, keys, expect, after)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = ft
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(before, "\n"))
  local last = vim.api.nvim_buf_line_count(buf)
  local col = #vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1]
  if after then vim.api.nvim_buf_set_text(buf, last - 1, col, last - 1, col, { after }) end
  vim.api.nvim_win_set_cursor(0, { last, col })
  local close = require("clasp.close")
  local function put(ch)
    local r, c = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_text(buf, r - 1, c, r - 1, c, { ch })
    vim.api.nvim_win_set_cursor(0, { r, c + #ch })
  end
  for _, ch in ipairs(vim.split(keys, "")) do
    put(ch)
    if ch == ">" then close.on_gt(buf) elseif ch == "/" then close.on_slash(buf, require("clasp.config").options.tags) end
  end
  put("|") -- mark the cursor
  local got = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local ok = got == expect
  if ok then pass = pass + 1 else fail = fail + 1 end
  io.stdout:write(("%s [%s] %q + %q\n     got:    %q\n%s"):format(ok and "ok  " or "FAIL", ft, before, keys, got, ok and "" or ("     expect: %q\n"):format(expect)))
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- `>` auto-close
case("typescriptreact", "const a = (", "<div>", "const a = (<div>|</div>")
case("typescriptreact", "const a = (", "<Foo.Bar>", "const a = (<Foo.Bar>|</Foo.Bar>")
case("typescriptreact", "const a = (", "<>", "const a = (<>|</>")
case("typescriptreact", "const a = (", '<div className="a">', 'const a = (<div className="a">|</div>')
case("typescriptreact", "const a = (", "<Foo onClick={() => go()}>", "const a = (<Foo onClick={() => go()}>|</Foo>")
case("typescriptreact", "const f = ", "<T,>", "const f = <T,>|")
case("typescriptreact", "const f = (x) =", ">", "const f = (x) =>|")
case("typescriptreact", 'const s = "', "<div>", 'const s = "<div>|')
case("typescriptreact", "// ", "<div>", "// <div>|")
case("typescriptreact", "const a = (<div>", "<span>", "const a = (<div><span>|</span>")
case("html", "", "<div>", "<div>|</div>")
case("html", "", "<img>", "<img>|")
case("html", "<!-- ", "<div>", "<!-- <div>| -->", " -->")
-- `</` completes the innermost open tag
case("typescriptreact", "const a = (<div><span>hi", "</", "const a = (<div><span>hi</span>|")
case("typescriptreact", "const a = (<div><span>hi</span>", "</", "const a = (<div><span>hi</span></div>|")
case("html", "<ul><li>a", "</", "<ul><li>a</li>|")
case("html", "<div><br>", "</", "<div><br></div>|")
-- `/` self-closes an unfinished opening tag
case("typescriptreact", "const a = (<Foo bar=\"x\" ", "/", "const a = (<Foo bar=\"x\" />|")
case("typescriptreact", "const a = (<Foo onClick={() => a / b} ", "/", "const a = (<Foo onClick={() => a / b} />|")
case("typescriptreact", "const a = (<a href=\"", "/", "const a = (<a href=\"/|")
case("typescriptreact", "const a = 1 ", "/", "const a = 1 /|")
case("typescriptreact", "const a = (<div>a ", "/", "const a = (<div>a /|")
case("html", '<img src="x" ', "/", '<img src="x" />|')
-- an existing closing tag right after the cursor is not duplicated
case("typescriptreact", "const a = (", "<div>", "const a = (<div>|</div>)", "</div>)")
-- `/` before `>` of an empty element drops the closing tag
case("typescriptreact", "const a = (<Foo ", "/", "const a = (<Foo />|", "></Foo>")
-- multi-line: `</` closes across lines, nested component inside an attribute stays balanced
case("typescriptreact", "return (\n  <ul>\n    <li icon={<Icon />}>\n      a\n    ", "</", "return (\n  <ul>\n    <li icon={<Icon />}>\n      a\n    </li>|")
case("typescriptreact", "return (\n  <Foo\n    a=\"1\"\n    ", "/", "return (\n  <Foo\n    a=\"1\"\n    />|")
-- tag right after element text, and  right before an existing closing tag
case("typescriptreact", "const a = (<div>x<br ", "/", "const a = (<div>x<br />|</div>)", "</div>)")
case("typescriptreact", "const a = (<div>x", "</", "const a = (<div>x</|</div>)", "</div>)")
case("typescriptreact", "const ok = a<b ", "/", "const ok = a<b /|")
io.stdout:write(("\n%d passed, %d failed\n"):format(pass, fail))
os.exit(fail > 0 and 1 or 0)
