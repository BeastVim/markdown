local M = {}

--- Install the buffer-local list mappings.
---@param buf integer
local function attach(buf)
	local actions = require("markdown.actions")
	-- Not `expr` mappings: Neovim evaluates those while peeking at queued keys
	-- (macros, fast typing), when the line does not yet hold the characters typed
	-- before the key. A callback runs when the key is consumed, in order.
	local function map(lhs, action, desc)
		Key.safe_set("i", lhs, function()
			vim.api.nvim_feedkeys(action(), "ni", false)
		end, { buffer = buf, noremap = true, desc = desc, group = "Markdown" })
	end
	map("<CR>", actions.enter, "Markdown: continue list")
	map("<Tab>", actions.tab, "Markdown: nest list item")
	map("<S-Tab>", actions.shift_tab, "Markdown: un-nest list item")
end

function M.setup()
	local missing = {}
	if not Key then
		table.insert(missing, "Key")
	end
	if not Treesitter then
		table.insert(missing, "Treesitter")
	end
	if #missing > 0 then
		vim.notify(
			"markdown requires BeastVim's global " .. table.concat(missing, ", ") .. " (this plugin only works inside the BeastVim ecosystem)",
			vim.log.levels.ERROR,
			{ title = "markdown" }
		)
		return
	end

	Treesitter.ensure_parser("markdown")
	Treesitter.ensure_parser("markdown_inline")

	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("BeastMarkdown", { clear = true }),
		pattern = "markdown",
		callback = function(args)
			attach(args.buf)
		end,
	})

	-- setup() runs on the FileType event that lazy-loaded this plugin, after
	-- which the autocmd above would be too late for the buffers already open.
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].filetype == "markdown" then
			attach(buf)
		end
	end
end

return M
