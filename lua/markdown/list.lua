-- Pure markdown list-item parsing. No buffer access, so it is unit-testable.

local M = {}

---@class Markdown.Item
---@field quote string          block quote prefix, e.g. "> " (may be "")
---@field indent string         whitespace between the quote and the marker
---@field kind "bullet"|"ordered"
---@field bullet? string        "-", "*" or "+"
---@field number? integer       ordered items only
---@field delim? string         "." or ")" (ordered items only)
---@field gap string            spaces between the marker and what follows
---@field checkbox? string      "[ ]", "[x]" or "[X]"
---@field content string        item text after the marker and checkbox
---@field marker_end integer    byte length of quote .. indent .. marker .. gap
---@field content_start integer byte length of everything before `content`

--- Split a leading run of block quote markers off `line`.
---@param line string
---@return string quote, string rest
local function split_quote(line)
	local pos = 1
	while true do
		local q = line:match("^%s*>%s?", pos)
		if not q then
			break
		end
		pos = pos + #q
	end
	return line:sub(1, pos - 1), line:sub(pos)
end

--- Parse `line` as a list item, or return nil when it is not one.
---@param line string
---@return Markdown.Item|nil
function M.parse(line)
	local quote, rest = split_quote(line)

	local item, indent, marker, gap, content
	local bullet
	indent, bullet, gap, content = rest:match("^(%s*)([-*+])( +)(.*)$")
	if bullet then
		-- "- - -" / "* * *" are thematic breaks, not nested bullets.
		local stripped = rest:gsub("%s", "")
		if #stripped >= 3 and stripped == bullet:rep(#stripped) then
			return nil
		end
		marker = bullet
		item = { kind = "bullet", bullet = bullet }
	else
		local digits, delim
		indent, digits, delim, gap, content = rest:match("^(%s*)(%d+)([.)])( +)(.*)$")
		if not digits or #digits > 9 then
			return nil
		end
		marker = digits .. delim
		item = { kind = "ordered", number = tonumber(digits), delim = delim }
	end

	item.quote, item.indent, item.gap = quote, indent, gap
	item.marker_end = #quote + #indent + #marker + #gap
	local head = item.marker_end

	local box, tail = content:match("^(%[[ xX]%])(.*)$")
	if box and (tail == "" or tail:sub(1, 1) == " ") then
		local spaces = tail:match("^ *")
		item.checkbox = box
		content = tail:sub(#spaces + 1)
		head = head + #box + #spaces
	end

	item.content = content
	item.content_start = head
	return item
end

--- Display width of leading whitespace (tabs count as 'tabstop').
---@param ws string
---@return integer
function M.width(ws)
	return vim.fn.strdisplaywidth(ws)
end

--- Whitespace that nests a child under `item`: aligned with the parent's content,
--- the smallest indent CommonMark accepts (2 for "- ", 3 for "1. ").
---@param item Markdown.Item
---@return string
function M.child_indent(item)
	local marker = item.kind == "ordered" and item.number .. item.delim or item.bullet
	return item.indent .. (" "):rep(#marker + #item.gap)
end

--- The text that starts the item following `item` (quote, indent, marker, gap
--- and an empty checkbox when `item` had one).
---@param item Markdown.Item
---@return string
function M.next_prefix(item)
	local marker = item.kind == "ordered" and (item.number + 1) .. item.delim or item.bullet
	return item.quote .. item.indent .. marker .. item.gap .. (item.checkbox and "[ ] " or "")
end

return M
