local config = require("avd.config")
local ui = require("avd.ui")

local M = {}

-- === Detectar ANDROID_HOME (portable) ===
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
		local windows_path = local_app_data .. "\\Android\\Sdk"
		windows_path = windows_path:gsub("\\", "/")
		if vim.uv.fs_stat(windows_path) then
			return windows_path
		end
	end

	return nil
end

-- === Instalar skin desde repo si no existe ===
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
		local ok = os.execute("mkdir -p " .. skins_dir)
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

	local clone_cmd =
		string.format("git clone --depth=1 https://github.com/lobaton-nvim/android-skins.git %s", temp_dir)
	local success = os.execute(clone_cmd)
	if not success then
		print("❌ Failed to clone https://github.com/lobaton-nvim/android-skins.git")
		os.execute("rm -rf " .. temp_dir)
		return false
	end

	local src_skin = temp_dir .. "/" .. skin_name
	if not vim.uv.fs_stat(src_skin) then
		print("❌ Skin not found in repo: " .. skin_name)
		os.execute("rm -rf " .. temp_dir)
		return false
	end

	local copy_cmd = string.format("cp -r %s %s/", src_skin, skins_dir)
	success = os.execute(copy_cmd)
	if not success then
		print("❌ Failed to copy skin.")
		os.execute("rm -rf " .. temp_dir)
		return false
	end

	local git_dir = skin_path .. "/.git"
	if vim.uv.fs_stat(git_dir) then
		os.execute("rm -rf " .. git_dir)
	end

	os.execute("rm -rf " .. temp_dir)

	print("✅ Skin '" .. skin_name .. "' installed in " .. skin_path)
	return true
end

-- === Listar AVDs ===
function M.list_avds()
	local handle = io.popen(config.avdmanager_cmd .. " list avd")
	if not handle then
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

	return avds
end

-- === Listar imágenes instaladas ===
function M.list_images()
	local handle = io.popen(config.sdkmanager_cmd .. " --list_installed 2>/dev/null")
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

	return images, display_options
end

-- === Listar dispositivos ===
function M.list_devices()
	local handle = io.popen(config.avdmanager_cmd .. " list device")
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

	return devices, device_ids
end

-- === Crear AVD ===
function M.create_avd()
	ui.input("AVD Name: ", function(name)
		if not name or name == "" then
			print("Cancelled.")
			return
		end

		local images, display_options = M.list_images()
		if not images or #images == 0 then
			print("❌ No system images found. Install with sdkmanager.")
			return
		end

		ui.select(display_options, "Select System Image:", nil, function(_, idx)
			if not idx then
				return
			end
			local image = images[idx]

			local devices, device_ids = M.list_devices()
			if not devices or #devices == 0 then
				print("❌ No device definitions found.")
				return
			end

			ui.select(devices, "Select Device:", nil, function(_, dev_idx)
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
					config.avdmanager_cmd,
					name,
					image,
					device_id,
					skin_name
				)

				print("🔧 " .. cmd)
				local success = os.execute(cmd)
				if success == 0 then
					print(string.format("✅ AVD '%s' created!", name))
					print("▶️  Launch with :AVDLaunch")
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

	ui.select(avds, "Launch AVD:", function(item)
		return "📱 " .. item
	end, function(chosen)
		if not chosen then
			return
		end

		local cmd
		if config.nohup_launch then
			cmd = string.format("nohup %s -avd '%s' > /dev/null 2>&1 &", config.emulator_cmd, chosen)
		else
			cmd = string.format("%s -avd '%s'", config.emulator_cmd, chosen)
		end

		print("🚀 Launching " .. chosen)
		os.execute(cmd)
	end)
end

-- === Comandos de usuario ===
vim.api.nvim_create_user_command("AVDCreate", function()
	M.create_avd()
end, { desc = "Create a new Android Virtual Device" })

vim.api.nvim_create_user_command("AVDLaunch", function()
	M.launch_avd()
end, { desc = "Launch an existing Android Virtual Device" })

return M
