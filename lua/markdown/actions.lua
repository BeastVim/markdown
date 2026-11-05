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
		local prev = vim.api.nvim_buf_get_lines(0, row - 2, row - 1, false)[1]
		local trimmed = prev:gsub("%s+$", "")
		if #trimmed < #prev then
			vim.api.nvim_buf_set_text(0, row - 2, #trimmed, row - 2, #prev, { "" })
		end
	end
end

--- Empty item + Enter: drop the marker and leave the list.
function M.exit()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local item = list.parse(vim.api.nvim_get_current_line())
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
		return termcodes("<Cmd>lua require('markdown.actions').exit()<CR>")
	end
	pending = list.next_prefix(item)
	return termcodes("<C-g>u<CR><Cmd>lua require('markdown.actions').fill()<CR>")
end

return M
