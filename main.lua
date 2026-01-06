--- @since 25.5.31

local shell = os.getenv("SHELL") or ""
---@enum FUSE_ARCHIVE_RETURN_CODE
local FUSE_ARCHIVE_RETURN_CODE = {
	SUCCESS = 0, -- Success.
	ERROR_GENERIC = 1, -- Generic error code for: missing command line argument, \
	-- too many command line arguments, unknown option, mount point is not empty, etc.
	CREATE_MOUNT_POINT_FAILED = 10, -- Cannot create the mount point.
	OPEN_THE_ACHIVE_FILE_FAILED = 11, -- Cannot open the archive file.
	CREATE_CACHE_FILE_FAILED = 12, -- Cannot create the cache file.
	NOT_ENOUGH_TEMP_SPACE = 13, -- Cannot write to the cache file. This is most likely the indication that there is not enough temp space.
	ENCRYPTED_FILE_BUT_NOT_PASSWORD = 20, -- The archive contains an encrypted file, but no password was provided.
	ENCRYPTED_FILE_BUT_WRONG_PASSWORD = 21, -- The archive contains an encrypted file, and the provided password does not decrypt it.
	ENCRYPTED_METHOD_UNSUPPORTED = 22, -- The archive contains an encrypted file, and the encryption method is not supported.
	ARCHIVE_FORMAT_UNSUPPORTED = 30, -- Cannot recognize the archive format.
	ARCHIVE_HEADER_INVALID = 31, -- Invalid archive header.
	ARCHIVE_READ_PERMISSION_INVALID = 32, -- Cannot read and extract the archive.
}

---@enum FUSE_ARCHIVE_MOUNT_ERROR_MSG
local FUSE_ARCHIVE_MOUNT_ERROR_MSG = {
	[FUSE_ARCHIVE_RETURN_CODE.ERROR_GENERIC] = "Fuse-archive exited with error: %s", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.CREATE_MOUNT_POINT_FAILED] = "Can't create mount point %s, maybe you don't have permission", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.OPEN_THE_ACHIVE_FILE_FAILED] = "Can't open archive file, maybe you don't have permission", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.CREATE_CACHE_FILE_FAILED] = "Can't not create cache point or not enough space for cache, trying to disable cache opt, this would make thing much slower", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.NOT_ENOUGH_TEMP_SPACE] = "Can't not create cache point or not enough space for cache, trying to disable cache opt, this would make thing much slower", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_METHOD_UNSUPPORTED] = "Encrypted method is unsupported", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_FILE_BUT_WRONG_PASSWORD] = "Incorrect password, %s attempts remaining.", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_FILE_BUT_NOT_PASSWORD] = "Please enter password to unlock file,%s attempts remaining.", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ARCHIVE_FORMAT_UNSUPPORTED] = "Unsupported this format file", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ARCHIVE_HEADER_INVALID] = "Archive file is corrupted", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ARCHIVE_READ_PERMISSION_INVALID] = "Can't open archive file, maybe you don't have permission",
}
---@enum YA_INPUT_EVENT
local YA_INPUT_EVENT = {
	ERROR = 0,
	CONFIRMED = 1,
	CANCELLED = 2,
	VALUE_CHANGED = 3,
}

local function error(s, ...)
	ya.notify({ title = "fuse-archive", content = string.format(s, ...), timeout = 3, level = "error" })
end

local function info(s, ...)
	ya.notify({ title = "fuse-archive", content = string.format(s, ...), timeout = 3, level = "info" })
end

local set_state = ya.sync(function(state, archive, key, value)
	if state[archive] then
		state[archive][key] = value
	else
		state[archive] = {}
		state[archive][key] = value
	end
end)

local get_state = ya.sync(function(state, archive, key)
	if state[archive] then
		return state[archive][key]
	else
		return nil
	end
end)

local function is_literal_string(str)
	return str and str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

local function path_quote(path)
	if not path or path == "" then
		return path
	end
	local result = "'" .. string.gsub(tostring(path), "'", "'\\''") .. "'"
	return result
end

local function path_remove_trailing_slash(path)
	if path == "/" then
		return path
	end
	return (path:gsub("/$", ""))
end

local is_mount_point = ya.sync(function(state)
	local dir = cx.active.current.cwd.name
	local cwd = tostring(cx.active.current.cwd.path or cx.active.current.cwd)
	local mount_root_dir = get_state("global", "mount_root_dir")
	local match_pattern = "^" .. is_literal_string(mount_root_dir .. "/yazi/fuse-archive") .. "/[^/]+%.tmp%.[^/]+$"

	for archive, _ in pairs(state) do
		if archive == dir and string.match(cwd, match_pattern) then
			return true
		end
	end
	return false
end)

---@return Url|nil, boolean|nil
local current_file = ya.sync(function()
	local h = cx.active.current.hovered
	if not h then
		return
	end
	return h.url, h.cha.is_dir
end)

local current_dir = ya.sync(function()
	return cx.active.current.cwd
end)

local current_dir_name = ya.sync(function()
	return cx.active.current.cwd.name
end)

local enter = function(hovered_url, is_dir)
	if hovered_url and is_dir then
		ya.emit("enter", {})
	else
		if get_state("global", "smart_enter") then
			ya.emit("open", { hovered = true })
		else
			ya.emit("enter", {})
		end
	end
end

---run any command
---@param cmd string
---@param args string[]
---@param _stdin? STD_STREAM|nil
---@return integer|nil, Output|nil
local function run_command(cmd, args, _stdin)
	local cwd = current_dir()
	cwd = tostring(
		cwd.scheme and cwd.scheme.is_virtual and Url(cwd.scheme.cache .. tostring(cwd.path)).parent or cwd.path or cwd
	)

	local stdin = _stdin or Command.PIPED
	local child, cmd_err =
		Command(cmd):arg(args):cwd(cwd):stdin(stdin):stdout(Command.PIPED):stderr(Command.PIPED):spawn()

	if not child then
		error("Failed to start `%s` failed with error: %s", cmd, cmd_err)
		return cmd_err, nil
	end

	local output, out_err = child:wait_with_output()
	if not output then
		error("Cannot read `%s` output, error: %s", cmd, out_err)
		return out_err, nil
	else
		return nil, output
	end
end

local is_mounted = function(dir_path)
	local cmd_err_code, res = run_command(shell, { "-c", "mountpoint -q " .. path_quote(dir_path) })
	if cmd_err_code or res == nil or res.status.code ~= 0 then
		-- case error, or mountpoint command not found
		return false
	end
	return res and res.status.success
end

---Get the fuse mount point
---@return string|nil
local fuse_dir = function()
	local mount_root_dir = get_state("global", "mount_root_dir")
	local fuse_mount_point = mount_root_dir .. "/yazi/fuse-archive"
	local _, _, exit_code = os.execute("mkdir -p " .. ya.quote(fuse_mount_point))
	if exit_code ~= 0 then
		error("Cannot create mount point %s", fuse_mount_point)
		return
	end
	return fuse_mount_point
end

local function split_by_space_or_comma(input)
	local result = {}
	for word in string.gmatch(input, "[^%s,]+") do
		table.insert(result, word)
	end
	return result
end

--- return a string array with unique value
---@param tbl string[]
---@return string[] table with only unique strings
local function tbl_unique_strings(tbl)
	local unique_table = {}
	local seen = {}

	for _, str in ipairs(tbl) do
		if not seen[str] then
			seen[str] = true
			table.insert(unique_table, str)
		end
	end

	return unique_table
end

local function tbl_to_set(t1)
	local set = {}

	for _, v in ipairs(t1) do
		set[v] = true
	end

	return set
end

local function remove_from_set(set, t2)
	if not set then
		set = {}
	end
	for _, v in ipairs(t2) do
		set[v] = nil
	end
	return set
end

local function add_to_set(set, t2)
	if not set then
		set = {}
	end
	for _, v in ipairs(t2) do
		set[v] = true
	end
	return set
end

---
---@param tmp_file_name string tmp file name
---@return Url|nil
local function get_mount_url(tmp_file_name)
	local fuse_mount_point = get_state("global", "fuse_dir")
	if not fuse_mount_point then
		return
	end
	return Url(fuse_mount_point):join(tmp_file_name)
end

---Show password input dialog
---@return boolean cancelled, string password
local function show_ask_pw_dialog()
	local passphrase = ""
	local cancelled = false
	-- Asking user to input the password
	local input_pw = ya.input({
		title = "Enter password to unlock:",
		obscure = true,
		pos = { "center", x = 0, y = 0, w = 50, h = 3 },
		position = { "center", x = 0, y = 0, w = 50, h = 3 },
		realtime = true,
	})

	while true and input_pw do
		---@type string, YA_INPUT_EVENT
		local value, ev = input_pw:recv()
		if ev == YA_INPUT_EVENT.CONFIRMED then
			passphrase = value or ""
			break
		elseif ev == YA_INPUT_EVENT.CANCELLED then
			passphrase = ""
			cancelled = true
			break
		end
	end
	return cancelled, passphrase
end

local redirect_mounted_tab_to_home = ya.sync(function(state, _)
	local mount_root_dir = get_state("global", "mount_root_dir")
	local match_pattern = "^" .. is_literal_string(mount_root_dir .. "/yazi/fuse-archive") .. "/[^/]+%.tmp%.[^/]+$"
	local HOME = os.getenv("HOME")

	for _, tab in ipairs(cx.tabs) do
		local dir = tab.current.cwd.name
		local cwd = tostring(tab.current.cwd)

		for archive, _ in pairs(state) do
			if archive == dir and string.match(cwd, match_pattern) then
				ya.emit("cd", {
					HOME,
					tab = (type(tab.id) == "number" or type(tab.id) == "string") and tab.id or tab.id.value,
					raw = true,
				})
				goto continue
			end
		end
		::continue::
	end
end)

---mount fuse
---@param opts {archive_path: Url, fuse_mount_point: Url, mount_options: string[], passphrase?: string, max_retry?: integer, retries?: integer}
---@return boolean
local function mount_fuse(opts)
	local archive_path = opts.archive_path
	local fuse_mount_point = opts.fuse_mount_point
	local mount_options = opts.mount_options or {}
	local passphrase = opts.passphrase
	local max_retry = opts.max_retry or 3
	local retries = opts.retries or 0
	local ignore_global_error_notify = false
	local payload_error_notify = {}

	if is_mounted(opts.fuse_mount_point) then
		return true
	end
	local _mount_opts = tbl_unique_strings({ "auto_unmount", table.unpack(mount_options) })

	local res, _ = Command(shell)
		:arg({
			"-c",
			(passphrase and "printf '%s\n' " .. path_quote(passphrase) .. " | " or "")
				.. " fuse-archive -o "
				.. table.concat(_mount_opts, ",")
				.. " "
				.. path_quote(archive_path)
				.. " "
				.. path_quote(fuse_mount_point),
		})
		-- :stdin(passpharase_stdin)
		:stderr(Command.PIPED)
		:stdout(Command.PIPED)
		:output()

	local fuse_mount_res_code, fuse_mount_res_msg

	-- already mounted, so stop re-mount
	if res then
		if res.stderr and res.stderr:find("mountpoint is not empty") then
			return true
		end
		fuse_mount_res_code = res.status.code
		fuse_mount_res_msg = res.stderr
	end

	if fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.SUCCESS then
		return true
	elseif fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.ERROR_GENERIC then
		payload_error_notify = { fuse_mount_res_code }
	elseif fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.CREATE_MOUNT_POINT_FAILED then
		payload_error_notify = { fuse_mount_point }
	elseif
		fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.NOT_ENOUGH_TEMP_SPACE
		or fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.CREATE_CACHE_FILE_FAILED
	then
		-- disable cache
		table.insert(mount_options, "nocache")
	elseif
		fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_FILE_BUT_NOT_PASSWORD
		or fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_FILE_BUT_WRONG_PASSWORD
	then
		ignore_global_error_notify = true
		-- Too many attempts
		if retries == max_retry then
			return false
		end
		if retries == 0 then
			-- First time ask for password dialog shown up
			info(FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code], max_retry - retries)
		else
			error(FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code], max_retry - retries)
		end
		local cancelled, pw = show_ask_pw_dialog()
		if not cancelled then
			passphrase = pw
		else
			return false
		end
	end

	--show retry notification
	if retries >= max_retry or not ignore_global_error_notify then
		if FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code] then
			if fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.ARCHIVE_READ_PERMISSION_INVALID then
				if
					archive_path.ext == "rar"
					and fuse_mount_res_msg
					and fuse_mount_res_msg:find("encrypted data is not currently supported", 1, true)
				then
					error("Password-protected RAR file is not supported yet!")
					return false
				elseif fuse_mount_res_msg and fuse_mount_res_msg:find("Unspecified error", 1, true) then
					error("Cannot mount archive file, error: Unspecified error")
					return false
				end
			end
			error(FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code], table.unpack(payload_error_notify))
		end
		return false
	end
	-- Increase retries every run
	retries = retries + 1
	return mount_fuse({
		archive_path = archive_path,
		fuse_mount_point = fuse_mount_point,
		mount_options = mount_options,
		passphrase = passphrase,
		retries = retries,
		max_retry = max_retry,
	})
end

---Mount path using inode (unique for each files)
---@param file_url Url
---@return string|nil
local function tmp_file_name(file_url)
	local fname = file_url.name
	local cmd_err_code, res = run_command(shell, { "-c", "xxh128sum -q " .. path_quote(file_url) })
	if cmd_err_code or res == nil or res.status.code ~= 0 then
		error("Cannot create unique path of file %s", fname)
		return nil
	end
	local hashed_name = res.stdout:match("^(%S+)")
	return fname .. ".tmp." .. hashed_name
end

local function unmount_on_quit()
	redirect_mounted_tab_to_home()
	local mount_root_dir = get_state("global", "mount_root_dir")
	local unmount_script =
		path_quote(os.getenv("HOME") .. "/.config/yazi/plugins/fuse-archive.yazi/assets/unmount_on_quit.sh")
	os.execute("chmod +x " .. unmount_script)
	os.execute(unmount_script .. " " .. path_quote(mount_root_dir))
end

local function setup(_, opts)
	set_state(
		"global",
		"mount_root_dir",
		opts
				and opts.mount_root_dir
				and type(opts.mount_root_dir) == "string"
				and path_remove_trailing_slash(opts.mount_root_dir)
			or "/tmp"
	)
	local fuse = fuse_dir()
	set_state("global", "fuse_dir", fuse)
	set_state("global", "smart_enter", opts and opts.smart_enter)
	local mount_options = {}
	if opts and opts.mount_options then
		if type(opts.mount_options) == "string" then
			mount_options = split_by_space_or_comma(opts.mount_options)
		else
			error("mount_options option in setup() must be a string separated by space or comma")
		end
	end
	set_state("global", "mount_options", mount_options)

	-- stylua: ignore
	local ORIGINAL_SUPPORTED_EXTENSIONS = {
		"7z",       "7zip",     "a",        "aia",      "apk",
		"ar",       "b64",      "base64",   "br",       "brotli",
		"bz2",      "bzip2",    "cab",      "cpio",     "crx",
		"deb",      "docx",     "grz",      "grzip",    "gz",
		"gzip",     "iso",      "iso9660",  "jar",      "lha",
		"lrz",      "lrzip",    "lz",       "lz4",      "lzip",
		"lzma",     "lzo",      "lzop",     "mtree",    "odf",
		"odg",      "odp",      "ods",      "odt",      "ppsx",
		"pptx",     "rar",      "rpm",      "tar",      "tar.br",
		"tar.brotli","tar.bz2", "tar.bzip2","tar.grz",  "tar.grzip",
		"tar.gz",   "tar.gzip", "tar.lha",  "tar.lrz",  "tar.lrzip",
		"tar.lz",   "tar.lz4",  "tar.lzip", "tar.lzma", "tar.lzo",
		"tar.lzop", "tar.xz",   "tar.z",    "tar.zst",  "tar.zstd",
		"taz",      "tb2",      "tbr",      "tbz",      "tbz2",
		"tgz",      "tlz",      "tlz4",     "tlzip",    "tlzma",
		"txz",      "tz",       "tz2",      "tzs",      "tzst",
		"tzstd",    "uu",       "warc",     "xar",      "xlsx",
		"xz",       "z",        "zip",      "zipx",     "zst",
		"zstd",
	}

	local SET_ALLOWED_EXTENSIONS = tbl_to_set(ORIGINAL_SUPPORTED_EXTENSIONS)

	if opts and opts.extra_extensions then
		if type(opts.extra_extensions) == "table" then
			SET_ALLOWED_EXTENSIONS = add_to_set(SET_ALLOWED_EXTENSIONS, opts.extra_extensions)
		else
			error("extra_extensions option in setup() must be a table of string")
		end
	end

	if opts and opts.excluded_extensions then
		if type(opts.excluded_extensions) == "table" then
			SET_ALLOWED_EXTENSIONS = remove_from_set(SET_ALLOWED_EXTENSIONS, opts.excluded_extensions)
		else
			error("excluded_extensions option in setup() must be a table of string")
		end
	end
	set_state("global", "valid_extensions", SET_ALLOWED_EXTENSIONS)

	-- trigger unmount on quit
	ps.sub("key-quit", function(args)
		unmount_on_quit()
		return args
	end)
	ps.sub("emit-quit", function(args)
		unmount_on_quit()
		return args
	end)
	ps.sub("emit-ind-quit", function(args)
		unmount_on_quit()
		return args
	end)
end

return {
	entry = function(_, job)
		local action = job.args[1]
		if not action then
			return
		end

		if action == "mount" then
			local hovered_url, is_dir = current_file()
			if hovered_url == nil then
				return
			end
			local VALID_EXTENSIONS = get_state("global", "valid_extensions")
			if is_dir or is_dir == nil or (is_dir == false and not VALID_EXTENSIONS[hovered_url.ext]) then
				enter(hovered_url, is_dir)
				return
			end
			local is_virtual = hovered_url.scheme and hovered_url.scheme.is_virtual
			hovered_url = is_virtual and Url(hovered_url.scheme.cache .. tostring(hovered_url.path))
				or hovered_url.path
				or hovered_url
			if is_virtual and not fs.cha(hovered_url) then
				ya.emit("download", { tostring(hovered_url) })
				return
			end
			local tmp_fname = tmp_file_name(hovered_url)
			if not tmp_fname then
				return
			end
			local tmp_file_url = get_mount_url(tmp_fname)

			if tmp_file_url then
				local success = mount_fuse({
					archive_path = hovered_url,
					fuse_mount_point = tmp_file_url,
					mount_options = get_state("global", "mount_options"),
				})
				if success then
					local cwd = current_dir()
					set_state(tmp_fname, "cwd", tostring(cwd.path or cwd))
					set_state(tmp_fname, "tmp", tostring(tmp_file_url))
					ya.emit("cd", { tostring(tmp_file_url), raw = true })
				end
			end
			-- leave without unmount
		elseif action == "leave" then
			if not is_mount_point() then
				ya.emit("leave", {})
				return
			end
			local file = current_dir_name()
			ya.emit("cd", { get_state(file, "cwd"), raw = true })
			return
		elseif action == "unmount" then
			unmount_on_quit()
		end
	end,
	setup = setup,
}
