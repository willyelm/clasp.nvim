![NVIM](https://img.shields.io/badge/Neovim-57A143?style=flat-square&logo=neovim&logoColor=white)

# clasp.nvim

Pairs and tags: closed as you type, added, removed and replaced.

## What is clasp

Small editing utilities for the things that come in pairs: brackets, quotes and
markup tags. Each keystroke makes at most one buffer edit, so LSP servers with
incremental sync stay in step with the buffer.

clasp leans on what Neovim already does: surround finds pairs with the native
`a(`, `a"` and `at` text objects, and adds them with a `g@` operator that takes
any motion. Everything repeats with `.`.

### Pairs (every filetype)

| You type          | You get                        |
| ----------------- | ------------------------------ |
| `(`, `[`, `{`     | `(\|)`, `[\|]`, `{\|}`         |
| `"`, `'`, `` ` `` | `"\|"`, `'\|'`, `` `\|` ``     |
| `)` before `)`    | steps over it                  |
| `<BS>` in `(\|)`  | deletes both                   |
| `<CR>` in `{\|}`  | opens an indented line between |

A pair is not inserted before a word (`(|foo` stays `(foo`), and a quote is not
paired after a letter (`don't`) or after the same quote (`"""`, ` ``` `).

In JS/TS, `${` typed in a `"…"` or `'…'` string turns it into a template
literal: `"hi $` + `{` → `` `hi ${|}` ``.

### Tags (HTML, JSX/TSX, Vue, Svelte, Astro, XML)

| You type                      | You get                                         |
| ----------------------------- | ----------------------------------------------- |
| `<div>`                       | `<div>\|</div>`                                 |
| `<img>` (HTML)                | `<img>\|` (void elements are never closed)      |
| `<div><span>hi</`             | `<div><span>hi</span>\|`                        |
| `<Foo bar="x" /`              | `<Foo bar="x" />\|`                             |
| `<Foo /` before `></Foo>`     | `<Foo />\|`                                     |
| `/` in `<Foo>\|</Foo>`        | `<Foo />\|` (empty elements only)               |
| `<BS>` in `<Foo />\|`         | `<Foo>\|</Foo>` (deleting the slash reopens it) |
| `<CR>` in `<div>\|</div>`     | opens an indented line between                  |
| cursor on `<div>` or `</div>` | both tag names highlight (`MatchParen`)         |

Strings, comments, arrow functions (`=>`) and generics (`<T,>`, `a<b`) are left
alone. Plain HTML never gets `<div />`: only its void elements self-close there.

### Split / join (every filetype with a treesitter parser)

| Keys  | Before                | After                                  |
| ----- | --------------------- | -------------------------------------- |
| `gss` | `foo(a, b, c)`        | `foo(` / `  a,` / `  b,` / `  c` / `)` |
| `gsj` | the split form        | `foo(a, b, c)`                         |
| `gss` | `<Foo a="1" b={2}>`   | `<Foo` / `  a="1"` / `  b={2}` / `>`   |
| `gsj` | `{` / `  a: 1,` / `}` | `{ a: 1 }`                             |

It works on the smallest `()`, `[]`, `{}` or tag around the cursor, or the first
one after it on the line. Join drops a trailing comma and refuses when a comment
or a multi-line item would end up on one line; split adds the comma Go requires.

### Surround (every filetype)

| Keys                | Before        | After                               |
| ------------------- | ------------- | ----------------------------------- |
| `gsaiw"`            | `word`        | `"word"`                            |
| `gsa$)`             | `a b c`       | `(a b c)`                           |
| `v…gsa]` (visual)   | selection     | `[selection]`                       |
| `gsaiwt` + `div`    | `word`        | `<div>word</div>`                   |
| `gsd(`              | `(a, (b))`    | `(a, b)` (innermost)                |
| `gsdt`              | `<b>hi</b>`   | `hi`                                |
| `gsr"'`             | `"word"`      | `'word'`                            |
| `gsrtt` + `section` | `<div a="1">` | `<section a="1">` (attributes kept) |

Either half of a pair picks it: `(` and `)` both mean `(…)`. `t` is a tag, asked
for by name, and may include attributes (`div class="a"`). The new pair flashes
briefly; when there is nothing to delete or replace, clasp says so instead of
guessing.

## Native features

clasp only covers what Neovim lacks. These work without it:

| Feature                          | How                                                                                    |
| -------------------------------- | -------------------------------------------------------------------------------------- |
| Rename the paired tag            | `vim.lsp.linked_editing_range.enable(true)` with an LSP that supports it (vtsls, html) |
| JSX comments (`{/* */}`)         | `gc` / `gcc`                                                                           |
| Tag text objects                 | `it` / `at`                                                                            |
| Jump between open and close tags | `%` (matchit)                                                                          |
| Highlight the matching bracket   | matchparen (built in); clasp uses the same `MatchParen` group for tags                 |

## Requirements

- Neovim `>= 0.12`
- Treesitter parsers for the languages you edit (`html`, `tsx`, `javascript`,
  `xml`, `vue`, `svelte`, `astro`)

## Install (vim pack)

```lua
vim.pack.add({ "https://github.com/willyelm/clasp.nvim" })
require("clasp").setup()
```

## Install (lazy.nvim)

```lua
{
  "willyelm/clasp.nvim",
  config = function()
    require("clasp").setup()
  end,
}
```

## Setup

Defaults:

```lua
require("clasp").setup({
  tags = {
    -- Buffers tag closing attaches to. Embedded markup (html in vue/svelte,
    -- jsx in tsx) is found through treesitter injections.
    filetypes = {
      "html",
      "xml",
      "javascriptreact",
      "typescriptreact",
      "vue",
      "svelte",
      "astro",
    },
    on_gt = true, -- `<div>` inserts `</div>` after the cursor
    on_slash = true, -- `</` completes the innermost open tag
    self_close = true, -- `/` finishes `<Foo /` and collapses `<Foo></Foo>`; <BS> on `/>` reopens it
    highlight = true, -- highlight the tag under the cursor and its pair with `MatchParen`
  },
  pairs = {
    enabled = true,
    disable_filetypes = {}, -- every filetype except these
    chars = {
      ["("] = ")",
      ["["] = "]",
      ["{"] = "}",
      ['"'] = '"',
      ["'"] = "'",
      ["`"] = "`",
    },
    bs = true, -- <BS> inside an empty pair deletes both
    cr = true, -- <CR> between a pair (or tags) opens an indented line
    template = true, -- JS/TS: `${` in a quoted string makes it a template literal
  },
  surround = {
    enabled = true,
    -- false leaves a key unmapped
    keys = {
      add = "gsa", -- operator (normal) and visual
      delete = "gsd",
      replace = "gsr",
    },
  },
  split = {
    enabled = true,
    keys = {
      split = "gss", -- one item per line
      join = "gsj", -- back onto one line
    },
  },
})
```

## Keymaps

clasp maps only what it does, and never a native command:

- Pairs (insert, global): the keys in `pairs.chars`, their closers, `<BS>` and
  `<CR>`. Prompt buffers are left alone.
- Tags (insert, buffer-local, in `tags.filetypes`): `>`, `/` and `<BS>` (which
  falls back to the pairs `<BS>`).
- Surround and split (normal; `gsa` also visual): `gsa`, `gsd`, `gsr`, `gss`,
  `gsj`. Bare `s` keeps its native meaning; `gs` (`:sleep`) is the only native
  key the prefix covers.

Completion plugins that map `<CR>` with a fallback (blink.cmp's
`{ "accept", "fallback" }`) fall back to clasp's `<CR>`.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## Changelog

See [CHANGELOG.md](./CHANGELOG.md).
