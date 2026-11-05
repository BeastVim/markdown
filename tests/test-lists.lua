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
--- Wrap this buffer's insert mapping the way blink.cmp does: its own `expr`
--- mapping on top, falling back to ours (non-expr callbacks are `vim.schedule`d).
local function blinkify(lhs)
	local m = vim.fn.maparg(lhs, "i", false, true)
	vim.keymap.set("i", lhs, function()
		if m.expr ~= 1 then
			vim.schedule(m.callback)
			return
		end
		local expr = m.callback()
		return m.replace_keycodes == 1 and vim.api.nvim_replace_termcodes(expr, true, true, true) or expr
	end, { buffer = true, expr = true, noremap = true, replace_keycodes = false })
end

local function run(lines, cursor, typed, blink)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	vim.bo[buf].filetype = "markdown"
	if blink then
		for _, lhs in ipairs({ "<CR>", "<Tab>", "<S-Tab>" }) do
			blinkify(lhs)
		end
	end
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

assert_eq("multibyte split", run({ "- héllo wörld" }, { 1, 10 }, "i<CR><Esc>"), { "- héllo w", "- örld" })
assert_eq("tilde fence is plain", run({ "~~~", "- x" }, { 2, 0 }, "A<CR>y<Esc>"), { "~~~", "- x", "y" })
assert_eq("tab indent kept", run({ "\t- a" }, { 1, 0 }, "A<CR>b<Esc>"), { "\t- a", "\t- b" })
local boxed = run({ "- [ ] a" }, { 1, 3 }, "i<CR><Esc>")
assert_eq("cursor inside checkbox is plain", #boxed == 2 and boxed[1] == "- [" and not boxed[2]:match("^%s*[-*+] "), true)
assert_eq("mid-sentence split trims trailing space", run({ "- buy milk" }, { 1, 6 }, "i<CR><Esc>")[1], "- buy")
assert_eq("end of line keeps hard-break spaces", run({ "- a  " }, { 1, 0 }, "A<CR>b<Esc>"), { "- a  ", "- b" })
vim.o.autoindent = false
assert_eq("noautoindent nested", run({ "  - a" }, { 1, 0 }, "A<CR>b<Esc>"), { "  - a", "  - b" })
assert_eq("noautoindent mid-split", run({ "  - ab" }, { 1, 5 }, "i<CR><Esc>"), { "  - a", "  - b" })
vim.o.autoindent = true

io.write("\n--- renumbering, Tab and Shift-Tab ---\n")
assert_eq(
	"insert mid-list renumbers",
	run({ "1. one", "2. two", "3. three" }, { 1, 0 }, "A<CR>inserted<Esc>"),
	{ "1. one", "2. inserted", "3. two", "4. three" }
)
local others = run({ "1. a", "2. b", "", "- x", "", "1. z" }, { 1, 0 }, "A<CR><Esc>")
assert_eq("other list untouched", others[#others], "1. z")
assert_eq("tab nests bullet", run({ "- a", "- b" }, { 2, 0 }, "A<Tab><Esc>"), { "- a", "  - b" })
assert_eq("tab nests ordered, restarts at 1", run({ "1. a", "2. b", "3. " }, { 3, 0 }, "A<Tab><Esc>"), { "1. a", "2. b", "   1. " })
assert_eq("shift-tab un-nests ordered", run({ "1. a", "2. b", "3. " }, { 3, 0 }, "A<Tab><S-Tab><Esc>"), { "1. a", "2. b", "3. " })
assert_eq("tab keeps cursor on text", run({ "- a", "- b" }, { 2, 0 }, "A<Tab>x<Esc>"), { "- a", "  - bx" })
assert_eq("tab renumbers both levels", run({ "1. a", "2. b", "3. c", "4. d" }, { 3, 0 }, "A<Tab><Esc>"), { "1. a", "2. b", "   1. c", "3. d" })
assert_eq("tab joins existing child list", run({ "1. a", "   1. b", "2. c" }, { 3, 0 }, "A<Tab><Esc>"), { "1. a", "   1. b", "   2. c" })
assert_eq(
	"shift-tab renumbers both levels",
	run({ "1. a", "2. b", "   1. c", "   2. d", "3. e" }, { 3, 0 }, "A<S-Tab><Esc>"),
	{ "1. a", "2. b", "3. c", "   1. d", "4. e" }
)
assert_eq("tab on first item is a no-op", run({ "- a" }, { 1, 0 }, "A<Tab>x<Esc>"), { "- ax" })
assert_eq("shift-tab at top level is a no-op", run({ "- a" }, { 1, 0 }, "A<S-Tab>x<Esc>"), { "- ax" })
-- Plain Tab only adds whitespace (spaces or a tab, per the buffer's 'expandtab').
local para = run({ "hello" }, { 1, 0 }, "A<Tab><Esc>")
assert_eq("tab in a paragraph is plain", #para == 1 and para[1]:match("^hello%s+$") ~= nil, true)
local fenced = run({ "```", "- a", "- b" }, { 3, 0 }, "A<Tab><Esc>")
assert_eq("tab in a fence is plain", fenced[2] == "- a" and fenced[3]:match("^%- b%s+$") ~= nil, true)
assert_eq("empty nested bullet un-nests", run({ "- parent", "    - " }, { 2, 0 }, "A<CR>"), { "- parent", "- " })
assert_eq("empty nested ordered un-nests", run({ "1. a", "2. b", "   1. " }, { 3, 0 }, "A<CR>"), { "1. a", "2. b", "3. " })
assert_eq("un-nest leaves the cursor on the item", run({ "- parent", "    - " }, { 2, 0 }, "A<CR>x<Esc>"), { "- parent", "- x" })
assert_eq("one undo reverts Enter and renumbering", run({ "1. a", "2. b" }, { 1, 0 }, "A<CR>x<Esc>u"), { "1. a", "2. b" })
assert_eq("one undo reverts Tab", run({ "1. a", "2. b", "3. c" }, { 2, 0 }, "A<Tab><Esc>u"), { "1. a", "2. b", "3. c" })

io.write("\n--- edge cases ---\n")
assert_eq("9 to 10 renumbers", run({ "9. a", "10. b", "11. c" }, { 1, 0 }, "A<CR>x<Esc>"), { "9. a", "10. x", "11. b", "12. c" })
assert_eq("nest into 10+ digits", run({ "1. a", "10. b" }, { 2, 0 }, "A<Tab><Esc>"), { "1. a", "   1. b" })
assert_eq("other delimiter is a separate list", run({ "1. a", "2. b", "1) c" }, { 1, 0 }, "A<CR>x<Esc>"), { "1. a", "2. x", "3. b", "1) c" })
assert_eq("bullet ends the ordered run", run({ "1. a", "- x", "2. b" }, { 1, 0 }, "A<CR>y<Esc>"), { "1. a", "2. y", "- x", "2. b" })
assert_eq("loose list renumbers", run({ "1. a", "", "2. b", "", "3. c" }, { 1, 0 }, "A<CR>x<Esc>"), { "1. a", "2. x", "", "3. b", "", "4. c" })
assert_eq("quoted list renumbers", run({ "> 1. a", "> 2. b" }, { 1, 0 }, "A<CR>x<Esc>"), { "> 1. a", "> 2. x", "> 3. b" })
assert_eq("quoted tab nests", run({ "> - a", "> - b" }, { 2, 0 }, "A<Tab><Esc>"), { "> - a", ">   - b" })
assert_eq("tab-indented list nests", run({ "\t1. a", "\t2. b" }, { 2, 0 }, "A<Tab><Esc>"), { "\t1. a", "\t   1. b" })
assert_eq("tab on a task item", run({ "- [ ] a", "- [x] b" }, { 2, 0 }, "A<Tab><Esc>"), { "- [ ] a", "  - [x] b" })

io.write("\n--- o / O ---\n")
assert_eq("o continues a bullet", run({ "- item" }, { 1, 0 }, "ox<Esc>"), { "- item", "- x" })
assert_eq("o continues an ordered item and renumbers", run({ "1. a", "2. b" }, { 1, 0 }, "ox<Esc>"), { "1. a", "2. x", "3. b" })
assert_eq("o continues a task", run({ "- [x] a" }, { 1, 0 }, "ox<Esc>"), { "- [x] a", "- [ ] x" })
assert_eq("o in a quote", run({ "> - item" }, { 1, 0 }, "ox<Esc>"), { "> - item", "> - x" })
assert_eq("o from mid-line opens below", run({ "- item" }, { 1, 2 }, "ox<Esc>"), { "- item", "- x" })
assert_eq("O opens a bullet above", run({ "- item" }, { 1, 0 }, "Ox<Esc>"), { "- x", "- item" })
assert_eq("O ordered takes the number and renumbers", run({ "1. a", "2. b" }, { 2, 0 }, "Ox<Esc>"), { "1. a", "2. x", "3. b" })
assert_eq("O on the first item", run({ "1. a", "2. b" }, { 1, 0 }, "Ox<Esc>"), { "1. x", "2. a", "3. b" })
assert_eq("O task is unchecked", run({ "- [x] a" }, { 1, 0 }, "Ox<Esc>"), { "- [ ] x", "- [x] a" })
assert_eq("o on a paragraph is plain", run({ "hello" }, { 1, 0 }, "ox<Esc>"), { "hello", "x" })
assert_eq("O on a paragraph is plain", run({ "hello" }, { 1, 0 }, "Ox<Esc>"), { "x", "hello" })
assert_eq("o on an empty item is plain", run({ "- " }, { 1, 0 }, "ox<Esc>"), { "- ", "x" })
assert_eq("o in a fence is plain", run({ "```", "- a" }, { 2, 0 }, "ox<Esc>"), { "```", "- a", "x" })
assert_eq("count keeps plain o", #run({ "- a" }, { 1, 0 }, "2ox<Esc>"), 3)
assert_eq("quoted ordered Enter", run({ "> 1. a", "> 2. b" }, { 2, 0 }, "A<CR>x<Esc>"), { "> 1. a", "> 2. b", "> 3. x" })
assert_eq("one undo reverts o", run({ "- a" }, { 1, 0 }, "ox<Esc>u"), { "- a" })
assert_eq("one undo reverts O and renumbering", run({ "1. a", "2. b" }, { 2, 0 }, "Ox<Esc>u"), { "1. a", "2. b" })
assert_eq("O in a quote", run({ "> - a" }, { 1, 0 }, "Ox<Esc>"), { "> - x", "> - a" })
assert_eq("o in a nested list", run({ "- p", "  - c" }, { 2, 0 }, "ox<Esc>"), { "- p", "  - c", "  - x" })
assert_eq("O in a nested ordered list", run({ "1. p", "   1. c", "   2. d" }, { 3, 0 }, "Ox<Esc>"), { "1. p", "   1. c", "   2. x", "   3. d" })
assert_eq("count keeps plain O", #run({ "- a" }, { 1, 0 }, "3Ox<Esc>"), 4)
local repeated = run({ "- a", "- b", "- c" }, { 1, 0 }, "ox<Esc>jj.")
assert_eq("dot-repeat never splits an item", #repeated == 5 and vim.tbl_contains(repeated, "- b") and vim.tbl_contains(repeated, "- c"), true)
local repeated_above = run({ "- a", "- b" }, { 1, 0 }, "Ox<Esc>jj.")
assert_eq("dot-repeat of O never splits an item", vim.tbl_contains(repeated_above, "- a") and vim.tbl_contains(repeated_above, "- b"), true)

io.write("\n--- behind blink.cmp's mappings ---\n")
assert_eq("blink: o continues", run({ "1. a", "2. b" }, { 1, 0 }, "ox<Esc>", true), { "1. a", "2. x", "3. b" })
assert_eq("blink: enter continues", run({ "- a" }, { 1, 0 }, "A<CR>b<Esc>", true), { "- a", "- b" })
assert_eq("blink: queued enters", run({ "1. one" }, { 1, 0 }, "A<CR>two<CR>three<Esc>", true), { "1. one", "2. two", "3. three" })
assert_eq("blink: enter mid-item", run({ "1. one", "2. two" }, { 1, 0 }, "A<CR>x<Esc>", true), { "1. one", "2. x", "3. two" })
assert_eq("blink: tab nests", run({ "1. a", "2. b", "3. c", "4. d" }, { 3, 0 }, "A<Tab><Esc>", true), { "1. a", "2. b", "   1. c", "3. d" })
assert_eq("blink: shift-tab un-nests", run({ "1. a", "2. b", "   1. c" }, { 3, 0 }, "A<S-Tab><Esc>", true), { "1. a", "2. b", "3. c" })
assert_eq("blink: empty nested un-nests", run({ "- p", "    - " }, { 2, 0 }, "A<CR>", true), { "- p", "- " })
assert_eq("blink: paragraph is plain", run({ "hello" }, { 1, 0 }, "A<CR>x<Esc>", true), { "hello", "x" })

io.write("\n--- fallback to the global <CR> ---\n")
vim.keymap.set("i", "<CR>", function()
	return vim.api.nvim_replace_termcodes("<CR>#", true, true, true)
end, { expr = true, replace_keycodes = false })
assert_eq("non-list uses previous mapping", run({ "hello" }, { 1, 0 }, "A<CR><Esc>"), { "hello", "#" })
assert_eq("list ignores previous mapping", run({ "- a" }, { 1, 0 }, "A<CR>b<Esc>"), { "- a", "- b" })

vim.keymap.set("i", "<CR>", function() end, {})
assert_eq("non-expr global callback is ignored", run({ "hello" }, { 1, 0 }, "A<CR>x<Esc>"), { "hello", "x" })

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
