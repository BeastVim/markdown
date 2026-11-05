-- Buffer-level list actions. Insert-mode actions inspect the line and return
-- the keystrokes to run (the mapping feeds them to the front of the typeahead),
-- so the edit stays inside the normal typing flow (one undo step via <C-g>u,
-- autoindent honoured). Edits that cannot be expressed as keys run through
-- `<Cmd>` calls embedded in the returned keys.

local list = require("markdown.list")

local M = {}

-- Prefix for the item the pending `fill()` call will start.
local pending

local function termcodes(keys)
	return vim.api.nvim_replace_termcodes(keys, true, true, true)
end

--- Keys for `lhs` as if this plugin had no mapping: the global mapping when one
--- exists (autopairs' <CR>), otherwise the plain key.
---@param lhs string  e.g. "<CR>"
---@return string keys  raw bytes
local function fallback(lhs)
	for _, map in ipairs(vim.api.nvim_get_keymap("i")) do
		-- Only expr callbacks hand back keys; any other mapping is skipped.
		if map.lhs == lhs and map.callback and map.expr == 1 then
			local keys = map.callback()
			return map.replace_keycodes == 1 and termcodes(keys) or keys
		end
	end
	return termcodes(lhs)
end

--- Is `row` (1-based) inside a fenced code block, judged by the fence openers
--- and closers above it?
---@param buf integer
---@param row integer
---@return boolean
function M.in_fence(buf, row)
	local open
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, row - 1, false)) do
		local fence, info = line:match("^%s*[>%s]*([`~][`~][`~]+)(.*)$")
		if fence then
			if not open then
				-- A backtick fence's info string cannot contain backticks
				-- (that would be inline code such as ```x```).
				if not (fence:sub(1, 1) == "`" and info:find("`", 1, true)) then
					open = fence
				end
			elseif fence:sub(1, 1) == open:sub(1, 1) and #fence >= #open and info:match("^%s*$") then
				open = nil
			end
		end
	end
	return open ~= nil
end

local function get_line(buf, row)
	return vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
end

--- Nearest list item above `row` in the same quote whose indent width is at
--- most `max_width`, skipping deeper items, blank lines and indented
--- continuation text. nil when unindented text or the file start comes first.
---@param buf integer
---@param row integer
---@param quote string
---@param max_width integer
---@return Markdown.Item|nil
local function item_above(buf, row, quote, max_width)
	for r = row - 1, 1, -1 do
		local line = get_line(buf, r)
		if line:match("%S") then
			local item = list.parse(line)
			if item then
				if item.quote ~= quote then
					return nil
				end
				if list.width(item.indent) <= max_width then
					return item
				end
			elseif list.width(line:match("^%s*")) <= max_width then
				return nil
			end
		end
	end
end

--- Renumber the ordered items below `row` that sit at indent `width`, counting
--- on from `last`. Stops at a shallower item, unindented text, a bullet or an
--- item with another delimiter ("1)" after "1." starts a new list).
---@param buf integer
---@param row integer
---@param width integer
---@param quote string
---@param delim string
---@param last integer
local function renumber_below(buf, row, width, quote, delim, last)
	for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, row, -1, false)) do
		if line:match("%S") then
			local item = list.parse(line)
			if item then
				if item.quote ~= quote then
					return
				end
				local w = list.width(item.indent)
				if w < width then
					return
				end
				if w == width then
					if item.kind ~= "ordered" or item.delim ~= delim then
						return
					end
					last = last + 1
					if item.number ~= last then
						local start = #item.quote + #item.indent
						local digits = line:match("^%d+", start + 1)
						local r0 = row + i - 1
						vim.api.nvim_buf_set_text(buf, r0, start, r0, start + #digits, { tostring(last) })
					end
				end
			elseif list.width(line:match("^%s*")) <= width then
				return
			end
		end
	end
end

--- Is `sibling` the previous item of the same ordered list as `item` once `item`
--- sits at indent width `width`?
---@param sibling Markdown.Item|nil
---@param item Markdown.Item
---@param width integer
---@return boolean
local function same_list(sibling, item, width)
	return sibling ~= nil and sibling.kind == "ordered" and sibling.delim == item.delim and list.width(sibling.indent) == width
end

--- Give the item on `row` a new indent and (ordered items) number. Returns the
--- change in byte length so the caller can move the cursor.
---@param row integer
---@param item Markdown.Item
---@param indent string
---@param number integer|nil
---@return integer delta
local function reindent(row, item, indent, number)
	local line = get_line(0, row)
	local start = #item.quote
	local old_len = #item.indent + (item.kind == "ordered" and #line:match("^%d+", start + #item.indent + 1) + 1 or 1)
	local marker = item.kind == "ordered" and number .. item.delim or item.bullet
	vim.api.nvim_buf_set_text(0, row - 1, start, row - 1, start + old_len, { indent .. marker })
	return #indent + #marker - old_len
end

--- Replace the new line's leading whitespace with the pending item prefix and
--- put the cursor after it. Runs right after the <CR> of `enter()`.
function M.fill()
	local prefix = pending
	pending = nil
	if not prefix then
		return
	end
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_get_current_line()
	local ws = line:match("^%s*")
	vim.api.nvim_buf_set_text(0, row - 1, 0, row - 1, #ws, { prefix })
	vim.api.nvim_win_set_cursor(0, { row, #prefix })

	-- A mid-sentence split ("buy |milk") leaves trailing whitespace on the line
	-- above. Only then: at the end of a line, trailing spaces are the user's own
	-- (two of them are a markdown hard line break).
	if #ws < #line then
		local prev = get_line(0, row - 1)
		local trimmed = prev:gsub("%s+$", "")
		if #trimmed < #prev then
			vim.api.nvim_buf_set_text(0, row - 2, #trimmed, row - 2, #prev, { "" })
		end
	end

	local item = list.parse(prefix)
	if item and item.kind == "ordered" then
		renumber_below(0, row, list.width(item.indent), item.quote, item.delim, item.number)
	end
end

--- Nest the current item under the item above it, renumbering both levels.
function M.nest()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local item = list.parse(get_line(0, row))
	if not item then
		return
	end
	local old_width = list.width(item.indent)
	local parent = item_above(0, row, item.quote, old_width)
	if not parent or list.width(parent.indent) ~= old_width then
		return
	end

	local indent = list.child_indent(parent)
	local width = list.width(indent)
	local sibling = item_above(0, row, item.quote, width)
	local number = same_list(sibling, item, width) and sibling.number + 1 or 1
	local delta = reindent(row, item, indent, number)
	vim.api.nvim_win_set_cursor(0, { row, math.max(col + delta, 0) })

	if item.kind == "ordered" then
		renumber_below(0, row, width, item.quote, item.delim, number)
	end
	if parent.kind == "ordered" then
		renumber_below(0, row, old_width, item.quote, parent.delim, parent.number)
	end
end

--- Move the current item out one level, to the indent of its parent item.
function M.dedent()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local item = list.parse(get_line(0, row))
	if not item then
		return
	end
	local old_width = list.width(item.indent)
	if old_width == 0 then
		return
	end

	local parent = item_above(0, row, item.quote, old_width - 1)
	local indent = parent and parent.indent or ""
	local width = list.width(indent)
	local sibling = item_above(0, row, item.quote, width)
	local number = same_list(sibling, item, width) and sibling.number + 1 or 1
	local delta = reindent(row, item, indent, number)
	vim.api.nvim_win_set_cursor(0, { row, math.max(col + delta, 0) })

	if item.kind == "ordered" then
		renumber_below(0, row, width, item.quote, item.delim, number)
		-- Deeper items that followed now belong to this item and start over.
		renumber_below(0, row, old_width, item.quote, item.delim, 0)
	end
end

--- Empty item + Enter: un-nest one level, or drop the marker at the top level.
function M.exit()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local item = list.parse(vim.api.nvim_get_current_line())
	if item and item.indent ~= "" then
		return M.dedent()
	end
	local line = item and item.quote or ""
	vim.api.nvim_set_current_line(line)
	vim.api.nvim_win_set_cursor(0, { row, #line })
end

--- Insert-mode <CR>: decide what Enter does on the current line.
---@return string keys  raw bytes to feed
function M.enter()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local item = list.parse(vim.api.nvim_get_current_line())
	-- Inside the marker, indent or checkbox Enter stays a plain newline.
	if vim.fn.pumvisible() == 1 or not item or col < (item.checkbox and item.content_start or item.marker_end) or M.in_fence(0, row) then
		return fallback("<CR>")
	end
	if item.content == "" then
		return termcodes("<C-g>u<Cmd>lua require('markdown.actions').exit()<CR>")
	end
	pending = list.next_prefix(item)
	return termcodes("<C-g>u<CR><Cmd>lua require('markdown.actions').fill()<CR>")
end

--- Keys for Tab / Shift-Tab: `action` ("nest" | "dedent") on a list item, the
--- plain key anywhere else (completion menu, snippet jumps, paragraphs, code).
---@param lhs string
---@param action string
---@return string keys
local function indent_keys(lhs, action)
	local row = vim.api.nvim_win_get_cursor(0)[1]
	if vim.fn.pumvisible() == 1 or vim.snippet.active() or not list.parse(vim.api.nvim_get_current_line()) or M.in_fence(0, row) then
		return fallback(lhs)
	end
	return termcodes("<C-g>u<Cmd>lua require('markdown.actions')." .. action .. "()<CR>")
end

---@return string keys
function M.tab()
	return indent_keys("<Tab>", "nest")
end

---@return string keys
function M.shift_tab()
	return indent_keys("<S-Tab>", "dedent")
end

--- Run the action called `name` ("enter", "tab" or "shift_tab") and feed the keys
--- it decides on to the front of the typeahead. Reached through the `<Cmd>` that
--- `M.keys` returns, so it runs when the key is consumed, in order.
---@param name string
function M.press(name)
	vim.api.nvim_feedkeys(M[name](), "ni", false)
end

--- The rhs of the insert mappings (use with `expr`): a constant `<Cmd>` that
--- defers every decision to `press`. It must not look at the buffer itself:
--- Neovim evaluates `expr` mappings while peeking at queued keys, before the
--- characters typed ahead of the key are in the buffer.
---@param name string
---@return string keys  raw bytes
function M.keys(name)
	return termcodes("<Cmd>lua require('markdown.actions').press('" .. name .. "')<CR>")
end

return M
