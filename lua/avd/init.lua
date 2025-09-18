-- nvim-android-avd: Caché persistente hasta cambio
-- ✅ Modificado solo para compatibilidad multiplataforma (Windows/macOS/Linux)
local M = {}

-- Detectar sistema operativo
local is_windows = vim.loop.os_uname().sysname:find("Windows")

-- === Configuración ===
M.config = {
	sdkmanager_cmd = is_windows and "sdkmanager.bat" or "sdkmanager",
	avdmanager_cmd = is_windows and "avdmanager.bat" or "avdmanager",
	emulator_cmd = is_windows and "emulator.exe" or "emulator",
	nohup_launch = not is_windows, -- nohup solo en Unix
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- === UI wrapper ===
local function input(prompt, callback)
	vim.ui.input({ prompt = prompt }, callback)
end

local function select(opts, prompt, format_item, callback)
	vim.ui.select(opts, {
		prompt = prompt,
		format_item = format_item or tostring,
	}, callback)
end

-- === Caché persistente (sin TTL) ===
local cache = {
	avds = nil,
	images = nil,
	devices = nil,
	display_options = nil,
	device_ids = nil,
}

-- === Invalidar caché específica ===
local function invalidate(key)
	cache[key] = nil
end

function M.clear_cache(which)
	if which == "avds" or not which then
		cache.avds = nil
		print("✅ Cache: AVDs cleared")
	end
	if which == "images" or not which then
		cache.images = nil
		cache.display_options = nil
		print("✅ Cache: Images cleared")
	end
	if which == "devices" or not which then
		cache.devices = nil
		cache.device_ids = nil
		print("✅ Cache: Devices cleared")
	end
	if not which then
		print("✅ All caches cleared.")
	end
end

-- === Detectar ANDROID_HOME ===
local function get_android_home()
	local home = os.getenv("ANDROID_HOME")
	if home and vim.uv.fs_stat(home) then
		return home
	end

	home = os.getenv("ANDROID_SDK_ROOT")
	if home and vim.uv.fs_stat(home) then
		return home
	end

	local user_home = vim.loop.os_homedir()
	local default_path = user_home .. "/Android/Sdk"
	if vim.uv.fs_stat(default_path) then
		return default_path
	end

	local local_app_data = os.getenv("LOCALAPPDATA")
	if local_app_data then
		local windows_path = vim.fn.fnamemodify(local_app_data .. "\\Android\\Sdk", ":p")
		if vim.uv.fs_stat(windows_path) then
			return windows_path
		end
	end

	return nil
end

-- === Instalar skin ===
local function install_skin(skin_name)
	local android_home = get_android_home()
	if not android_home then
		print("❌ ANDROID_HOME not found.")
		print("💡 Set ANDROID_HOME or ensure ~/Android/Sdk exists.")
		return false
	end

	local skins_dir = android_home .. "/skins"
	local skin_path = skins_dir .. "/" .. skin_name

	if not vim.uv.fs_stat(skins_dir) then
		print("📁 Creating skins directory: " .. skins_dir)
		local cmd
		if is_windows then
			cmd = 'cmd /c mkdir "' .. skins_dir:gsub("/", "\\") .. '"'
		else
			cmd = "mkdir -p " .. skins_dir
		end
		local ok = os.execute(cmd)
		if not ok then
			print("❌ Failed to create: " .. skins_dir)
			return false
		end
	end

	if vim.uv.fs_stat(skin_path) then
		print("✅ Skin '" .. skin_name .. "' already exists.")
		return true
	end

	print("📦 Installing skin: " .. skin_name)

	local temp_dir = vim.loop.os_tmpdir() .. "/android-skins-" .. vim.fn.strftime("%s")

	local clone_cmd
	if is_windows then
		clone_cmd = 'cmd /c git clone --depth=1 https://github.com/lobaton-nvim/android-skins.git   "'
			.. temp_dir:gsub("/", "\\")
			.. '"'
	else
		clone_cmd =
			string.format("git clone --depth=1 https://github.com/lobaton-nvim/android-skins.git   %s", temp_dir)
	end

	local success = os.execute(clone_cmd)
	if not success then
		print("❌ Failed to clone https://github.com/lobaton-nvim/android-skins.git  ")
		os.execute(is_windows and 'cmd /c rmdir /s /q "' .. temp_dir:gsub("/", "\\") .. '"' or "rm -rf " .. temp_dir)
		return false
	end

	local src_skin = temp_dir .. "/" .. skin_name
	if not vim.uv.fs_stat(src_skin) then
		print("❌ Skin not found in repo: " .. skin_name)
		os.execute(is_windows and 'cmd /c rmdir /s /q "' .. temp_dir:gsub("/", "\\") .. '"' or "rm -rf " .. temp_dir)
		return false
	end

	local copy_cmd
	if is_windows then
		copy_cmd =
			string.format('cmd /c xcopy /E /I /Y "%s" "%s\\"', src_skin:gsub("/", "\\"), skins_dir:gsub("/", "\\"))
	else
		copy_cmd = string.format("cp -r %s %s/", src_skin, skins_dir)
	end

	success = os.execute(copy_cmd)
	if not success then
		print("❌ Failed to copy skin.")
		os.execute(is_windows and 'cmd /c rmdir /s /q "' .. temp_dir:gsub("/", "\\") .. '"' or "rm -rf " .. temp_dir)
		return false
	end

	local git_dir = skin_path .. "/.git"
	if vim.uv.fs_stat(git_dir) then
		os.execute(is_windows and 'cmd /c rmdir /s /q "' .. git_dir:gsub("/", "\\") .. '"' or "rm -rf " .. git_dir)
	end

	os.execute(is_windows and 'cmd /c rmdir /s /q "' .. temp_dir:gsub("/", "\\") .. '"' or "rm -rf " .. temp_dir)

	print("✅ Skin '" .. skin_name .. "' installed in " .. skin_path)
	return true
end

-- === Listar AVDs (caché persistente) ===
function M.list_avds()
	if cache.avds then
		return cache.avds
	end

	local cmd = M.config.avdmanager_cmd .. " list avd"
	local handle = io.popen(cmd)
	if not handle then
		print("❌ Failed to run: " .. cmd)
		return {}
	end

	local output = handle:read("*a")
	handle:close()

	local avds = {}
	for line in output:gmatch("[^\r\n]+") do
		local name = line:match("Name:%s*(.+)")
		if name then
			table.insert(avds, vim.trim(name))
		end
	end

	cache.avds = avds
	return avds
end

-- === Listar imágenes (caché persistente) ===
function M.list_images()
	if cache.images then
		return cache.images, cache.display_options
	end

	local cmd = M.config.sdkmanager_cmd .. " --list_installed 2>/dev/null"
	local handle = io.popen(cmd)
	if not handle then
		return {}, {}
	end

	local output = handle:read("*a")
	handle:close()

	local images = {}
	local display_options = {}

	local vendor_names = {
		["google_apis"] = "Google APIs",
		["google_apis_playstore"] = "Google Play",
		["default"] = "AOSP (no GApps)",
	}

	for line in output:gmatch("[^\r\n]+") do
		local package = line:match("system%%-images;[^%s|]+")
		if not package then
			package = line:match("system%-images[^%s|]+")
		end

		if package then
			local parts = {}
			for part in package:gmatch("([^;]+)") do
				table.insert(parts, vim.trim(part))
			end

			if #parts >= 4 and parts[2]:match("android%-%d+") then
				local api = parts[2]:match("android%-(%d+)")
				local vendor = parts[3]
				local arch = parts[4]
				local vendor_name = vendor_names[vendor] or vendor
				local desc = string.format("API %s | %s | %s", api, vendor_name, arch)

				table.insert(images, package)
				table.insert(display_options, desc)
			end
		end
	end

	cache.images = images
	cache.display_options = display_options
	return images, display_options
end

-- === Listar dispositivos (caché persistente) ===
function M.list_devices()
	if cache.devices then
		return cache.devices, cache.device_ids
	end

	local cmd = M.config.avdmanager_cmd .. " list device"
	local handle = io.popen(cmd)
	if not handle then
		return {}, {}
	end

	local output = handle:read("*a")
	handle:close()

	local devices = {}
	local device_ids = {}

	local current_id, current_name = nil, nil
	for line in output:gmatch("[^\r\n]+") do
		local id = line:match("%s*id:%s*(%d+)")
		if id then
			current_id = id
		end

		local name = line:match("%s*Name:%s*(.+)")
		if name then
			current_name = name
		end

		if current_id and current_name and not current_name:match("Example") then
			table.insert(devices, current_name)
			table.insert(device_ids, current_id)
			current_id, current_name = nil, nil
		end
	end

	cache.devices = devices
	cache.device_ids = device_ids
	return devices, device_ids
end

-- === Crear AVD → invalida solo AVDs ===
function M.create_avd()
	input("AVD Name: ", function(name)
		if not name or name == "" then
			return
		end

		local images, display_options = M.list_images()
		if not images or #images == 0 then
			print("❌ No system images found.")
			return
		end

		local devices, device_ids = M.list_devices()
		if not devices or #devices == 0 then
			print("❌ No device definitions found.")
			return
		end

		select(display_options, "Select System Image:", nil, function(_, idx)
			if not idx then
				return
			end
			local image = images[idx]

			select(devices, "Select Device:", nil, function(_, dev_idx)
				if not dev_idx then
					return
				end
				local device_id = device_ids[dev_idx]
				local device_name = devices[dev_idx]
				local skin_name = device_name:lower():gsub("%s+", "_"):gsub("[^%w_]", "")

				if not install_skin(skin_name) then
					print("❌ Could not install skin. Aborting.")
					return
				end

				local cmd = string.format(
					"%s create avd -n '%s' -k '%s' -d '%s' --skin '%s'",
					M.config.avdmanager_cmd,
					name,
					image,
					device_id,
					skin_name
				)

				print("🔧 " .. cmd)
				local success = os.execute(cmd)
				if success == 0 then
					print(string.format("✅ AVD '%s' created!", name))
					invalidate("avds")
				else
					print("❌ Failed to create AVD.")
				end
			end)
		end)
	end)
end

-- === Lanzar AVD ===
function M.launch_avd()
	local avds = M.list_avds()
	if not avds or #avds == 0 then
		print("No AVDs found. Create one with :AVDCreate")
		return
	end

	select(avds, "Launch AVD:", function(item)
		return "📱 " .. item
	end, function(chosen)
		if not chosen then
			return
		end

		local cmd
		if M.config.nohup_launch then
			cmd = string.format("nohup %s -avd '%s' > /dev/null 2>&1 &", M.config.emulator_cmd, chosen)
		else
			-- Windows: usar start /B
			if is_windows then
				cmd = string.format('start /B %s -avd "%s"', M.config.emulator_cmd, chosen)
			else
				cmd = string.format("%s -avd '%s'", M.config.emulator_cmd, chosen)
			end
		end

		print("🚀 Launching " .. chosen)
		os.execute(cmd)
	end)
end

-- === Comandos ===
vim.api.nvim_create_user_command("AVDCreate", function()
	M.create_avd()
end, { desc = "Create Android AVD" })

vim.api.nvim_create_user_command("AVDLaunch", function()
	M.launch_avd()
end, { desc = "Launch Android AVD" })

vim.api.nvim_create_user_command("AVDClearCache", function(opts)
	local which = opts.args == "" and nil or opts.args
	M.clear_cache(which)
end, {
	desc = "Clear AVD cache: avds, images, devices, or all",
	nargs = "?",
	complete = function()
		return { "avds", "images", "devices", "all" }
	end,
})

return M
