local M = {}

M.config = {
	sdkmanager_cmd = "sdkmanager",
	avdmanager_cmd = "avdmanager",
	emulator_cmd = "emulator",
	nohup_launch = true,
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
