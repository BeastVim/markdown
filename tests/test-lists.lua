-- =========================================================================
-- Test: markdown list parsing and Enter continuation
-- =========================================================================
-- Run from the plugin root as: nvim --clean --headless -l tests/test-lists.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- BeastVim globals the plugin expects.
_G.Key = {
	safe_set = function(mode, lhs, rhs, opts)
		local o = vim.deepcopy(opts)
		o.group = nil -- consumed by the real Key lib, not a vim.keymap option
		vim.keymap.set(mode, lhs, rhs, o)
	end,
}
_G.Treesitter = { ensure_parser = function() end }

local passed, failed = 0, 0

local function assert_eq(name, got, expected)
	if vim.deep_equal(got, expected) then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " - expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got) .. "\n")
	end
end

local list = require("markdown.list")
local markdown = require("markdown")

io.write("\n--- list.parse ---\n")
local function marker_end(line)
	local it = list.parse(line)
	return it and it.marker_end
end
assert_eq("dash bullet", list.parse("- a").bullet, "-")
assert_eq("star bullet", list.parse("* a").bullet, "*")
assert_eq("plus bullet", list.parse("+ a").bullet, "+")
assert_eq("ordered dot", list.parse("12. a").number, 12)
assert_eq("ordered paren", list.parse("3) a").delim, ")")
assert_eq("task unchecked", list.parse("- [ ] a").checkbox, "[ ]")
assert_eq("task checked", list.parse("- [x] a").checkbox, "[x]")
assert_eq("task content", list.parse("- [x] a b").content, "a b")
assert_eq("not a task without space", list.parse("- [x]a").content, "[x]a")
assert_eq("empty item", list.parse("- ").content, "")
assert_eq("empty task", list.parse("- [ ] ").content, "")
assert_eq("indent kept", list.parse("    - a").indent, "    ")
assert_eq("quote prefix", list.parse("> - a").quote, "> ")
assert_eq("nested quote prefix", list.parse("> > 1. a").quote, "> > ")
assert_eq("marker_end", marker_end("  - a"), 4)
assert_eq("marker_end ordered", marker_end("10. a"), 4)
assert_eq("paragraph", list.parse("hello"), nil)
assert_eq("dash without space", list.parse("-a"), nil)
assert_eq("thematic break dashes", list.parse("- - -"), nil)
assert_eq("thematic break stars", list.parse("* * *"), nil)
assert_eq("year is not a list", list.parse("2024 was good"), nil)
assert_eq("next bullet", list.next_prefix(list.parse("  * a")), "  * ")
assert_eq("next ordered", list.next_prefix(list.parse("9. a")), "10. ")
assert_eq("next task resets box", list.next_prefix(list.parse("- [x] a")), "- [ ] ")
assert_eq("next quote kept", list.next_prefix(list.parse("> - a")), "> - ")

io.write("\n--- Enter mapping ---\n")
vim.o.autoindent = true
vim.bo.filetype = "markdown"
markdown.setup()

local function keys(s)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(s, true, true, true), "xt", false)
end

--- Load `lines` into a fresh markdown buffer, put the cursor at (row, col) and
--- feed `typed`. Returns the resulting lines.
local function run(lines, cursor, typed)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	vim.bo[buf].filetype = "markdown"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, cursor)
	keys(typed)
	return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

assert_eq("bullet continues", run({ "- apples" }, { 1, 0 }, "A<CR>oranges<Esc>"), { "- apples", "- oranges" })
assert_eq("star continues", run({ "* a" }, { 1, 0 }, "A<CR>b<Esc>"), { "* a", "* b" })
assert_eq("plus continues", run({ "+ a" }, { 1, 0 }, "A<CR>b<Esc>"), { "+ a", "+ b" })
assert_eq("ordered counts up", run({ "1. one" }, { 1, 0 }, "A<CR>two<CR>three<Esc>"), { "1. one", "2. two", "3. three" })
assert_eq("paren style kept", run({ "1) a" }, { 1, 0 }, "A<CR>b<Esc>"), { "1) a", "2) b" })
assert_eq("task gets empty box", run({ "- [x] write spec" }, { 1, 0 }, "A<CR>next<Esc>"), { "- [x] write spec", "- [ ] next" })
assert_eq("nested indent kept", run({ "- parent", "  - child" }, { 2, 0 }, "A<CR>x<Esc>"), { "- parent", "  - child", "  - x" })
assert_eq("quote prefix kept", run({ "> - item" }, { 1, 0 }, "A<CR>x<Esc>"), { "> - item", "> - x" })
assert_eq("empty item exits", run({ "- last", "- " }, { 2, 0 }, "A<CR>"), { "- last", "" })
assert_eq("empty task exits", run({ "- [ ] " }, { 1, 0 }, "A<CR>"), { "" })
assert_eq("mid-item split", run({ "- buy milk and eggs" }, { 1, 6 }, "i<CR><Esc>"), { "- buy", "- milk and eggs" })
-- Plain Enter inside the indent: same result as a buffer without the plugin.
local plain_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(plain_buf)
vim.api.nvim_buf_set_lines(plain_buf, 0, -1, false, { "  - item" })
vim.api.nvim_win_set_cursor(0, { 1, 1 })
keys("i<CR><Esc>")
assert_eq("cursor inside indent is plain", run({ "  - item" }, { 1, 1 }, "i<CR><Esc>"), vim.api.nvim_buf_get_lines(plain_buf, 0, -1, false))
assert_eq("paragraph is plain", run({ "hello" }, { 1, 0 }, "A<CR>x<Esc>"), { "hello", "x" })
assert_eq("fence is plain", run({ "```", "- x" }, { 2, 0 }, "A<CR>y<Esc>"), { "```", "- x", "y" })
assert_eq("after closed fence continues", run({ "```", "code", "```", "- x" }, { 4, 0 }, "A<CR>y<Esc>"), { "```", "code", "```", "- x", "- y" })
assert_eq("one undo reverts Enter", run({ "- a" }, { 1, 0 }, "A<CR>b<Esc>u"), { "- a" })

io.write("\n--- fallback to the global <CR> ---\n")
vim.keymap.set("i", "<CR>", function()
	return vim.api.nvim_replace_termcodes("<CR>#", true, true, true)
end, { expr = true, replace_keycodes = false })
assert_eq("non-list uses previous mapping", run({ "hello" }, { 1, 0 }, "A<CR><Esc>"), { "hello", "#" })
assert_eq("list ignores previous mapping", run({ "- a" }, { 1, 0 }, "A<CR>b<Esc>"), { "- a", "- b" })

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
