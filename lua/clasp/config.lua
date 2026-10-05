local M = {
	defaults = {
		tags = {
			-- Buffers tag closing attaches to. Embedded markup (html in vue/svelte, jsx in tsx) is found through
			-- treesitter injections, so the host filetype is what goes here.
			filetypes = {
				"html",
				"xml",
				"javascriptreact",
				"typescriptreact",
				"vue",
				"svelte",
				"astro",
			},
			-- `<div>` inserts `</div>` after the cursor.
			on_gt = true,
			-- `</` completes the innermost open tag.
			on_slash = true,
			-- `/` inside an unfinished opening tag finishes it as `<Foo />`.
			self_close = true,
			-- With the cursor on a tag, highlight it and its pair with `MatchParen`.
			highlight = true,
		},
		pairs = {
			enabled = true,
			-- Every filetype except these.
			disable_filetypes = {},
			-- Typing the key inserts both; typing the closer next to an existing one steps over it.
			chars = {
				["("] = ")",
				["["] = "]",
				["{"] = "}",
				['"'] = '"',
				["'"] = "'",
				["`"] = "`",
			},
			-- <BS> inside an empty pair deletes both.
			bs = true,
			-- <CR> between a pair (or `<div>|</div>`) opens an indented line between them.
			cr = true,
			-- JS/TS: `${` typed in a "…" or '…' string turns it into a template literal.
			template = true,
		},
		surround = {
			enabled = true,
			-- add takes a motion (`gsaiw"`) or a visual selection; delete and replace take the pair's
			-- character (`gsd(`, `gsr"'`). `t` is a tag, asked for by name. false leaves a key unmapped.
			keys = {
				add = "gsa",
				delete = "gsd",
				replace = "gsr",
			},
		},
		split = {
			enabled = true,
			-- Split the pair around the cursor onto one item per line, or join it onto one line.
			keys = {
				split = "gss",
				join = "gsj",
			},
		},
	},
}
M.options = M.defaults

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
	return M.options
end

return M
