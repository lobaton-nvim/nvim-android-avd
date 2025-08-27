local M = {}

function M.input(prompt, callback)
	vim.ui.input({ prompt = prompt }, callback)
end

function M.select(opts, prompt, format_item, callback)
	vim.ui.select(opts, {
		prompt = prompt,
		format_item = format_item or tostring,
	}, callback)
end

return M
