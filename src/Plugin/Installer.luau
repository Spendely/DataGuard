--!strict
-- Pulls PFS from GitHub on request, and installs the DataGuard runtime into ServerStorage.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local ScriptEditorService = game:GetService("ScriptEditorService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Installer = {}

local SOURCES = {
	ProfileStore = {
		repo = "MadStudioRoblox/ProfileStore",
		paths = { "src/ProfileStore.luau", "ProfileStore.luau", "src/init.luau" },
	},
	ProfileService = {
		repo = "MadStudioRoblox/ProfileService",
		paths = { "src/ProfileService.lua", "ProfileService.lua" },
	},
}

local function stripBom(source: string): string
	if source:sub(1, 3) == "\239\187\191" then
		return source:sub(4)
	end
	return source
end

local function setSource(module: ModuleScript, source: string)
	local ok = pcall(function()
		ScriptEditorService:UpdateSourceAsync(module, function()
			return source
		end)
	end)
	if not ok then
		(module :: any).Source = source
	end
end

local function withHistory<T>(name: string, fn: () -> T): T
	local id = ChangeHistoryService:TryBeginRecording(name)
	local ok, result = pcall(fn)
	if id then
		ChangeHistoryService:FinishRecording(id, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	end
	if not ok then
		error(result, 0)
	end
	return result
end

local function latestSha(repo: string): string?
	local ok, body = pcall(HttpService.GetAsync, HttpService, `https://api.github.com/repos/{repo}/commits?per_page=1`)
	if not ok then
		return nil
	end
	local decoded = HttpService:JSONDecode(body)
	return decoded[1] and decoded[1].sha
end

function Installer.fetchPFS(flavor: string): ModuleScript
	local info = SOURCES[flavor]
	-- Download from an exact commit, so the pinned SHA is the code that was actually installed.
	local sha = latestSha(info.repo)
	if not sha then
		error(`DataGuard[E_FETCH]: could not read latest commit of github.com/{info.repo} (HTTP allowed for the plugin?)`, 0)
	end
	local source, usedPath
	for _, path in info.paths do
		local ok, body = pcall(HttpService.GetAsync, HttpService, `https://raw.githubusercontent.com/{info.repo}/{sha}/{path}`)
		if ok and #body > 1000 then
			source, usedPath = stripBom(body), path
			break
		end
	end
	if not source or not source:find(if flavor == "ProfileStore" then "StartSessionAsync" else "LoadProfileAsync", 1, true) then
		error(`DataGuard[E_FETCH]: could not download a valid {flavor} from github.com/{info.repo}@{sha:sub(1, 10)}`, 0)
	end

	return withHistory(`DataGuard: install {flavor}`, function()
		local existing = ServerStorage:FindFirstChild(flavor)
		if existing then
			existing:Destroy()
		end
		local module = Instance.new("ModuleScript")
		module.Name = flavor
		setSource(module, source)
		module:SetAttribute("DataGuardSource", `{info.repo}/{usedPath}`)
		module:SetAttribute("DataGuardSha", sha)
		module.Parent = ServerStorage
		return module
	end)
end

-- Clones the runtime bundled inside the plugin; keeps an existing Schema so user rules survive updates.
function Installer.installRuntime(runtimeTemplate: ModuleScript, pfs: ModuleScript): ModuleScript
	return withHistory("DataGuard: install runtime", function()
		local existing = ServerStorage:FindFirstChild("DataGuard")
		local keptSchema = existing and existing:FindFirstChild("Schema")
		if keptSchema then
			keptSchema.Parent = nil
		end
		if existing then
			existing:Destroy()
		end

		local runtime = runtimeTemplate:Clone()
		if keptSchema then
			local fresh = runtime:FindFirstChild("Schema")
			if fresh then
				fresh:Destroy()
			end
			keptSchema.Parent = runtime
		end

		local pointer = Instance.new("ObjectValue")
		pointer.Name = "PFSModule"
		pointer.Value = pfs
		pointer.Parent = runtime

		runtime.Parent = ServerStorage
		return runtime
	end)
end

function Installer.bumpVersion(schema: ModuleScript): number?
	local source = (schema :: any).Source :: string
	local current = tonumber(source:match("Version%s*=%s*(%d+)"))
	if not current then
		return nil
	end
	local updated = source:gsub("Version%s*=%s*%d+", `Version = {current + 1}`, 1)
	withHistory("DataGuard: bump schema version", function()
		setSource(schema, updated)
	end)
	return current + 1
end

return Installer
