--!strict
-- Finds the PFS module. Easy scan = names only; deep scan = reads every script's Source.

local Scanner = {}

local EASY_ROOTS = { "ServerScriptService", "ServerStorage", "ReplicatedStorage" }
local DEEP_ROOTS = { "Workspace", "ServerScriptService", "ServerStorage", "ReplicatedStorage", "ReplicatedFirst", "StarterPlayer", "StarterGui", "StarterPack" }

local NAME_PATTERNS = { "profilestore", "profileservice" }

local OWNER_PATTERNS = { "ProfileStore%.New%s*%(", "%.GetProfileStore%s*%(", ":StartSessionAsync%s*%(", ":LoadProfileAsync%s*%(" }
local REQUIRE_PATTERNS = { "require%s*%(.-ProfileStore.-%)", "require%s*%(.-ProfileService.-%)" }
local RAW_DS_PATTERNS = { "DataStoreService", ":GetDataStore%s*%(", ":GetOrderedDataStore%s*%(" }

export type Result = {
	module: ModuleScript?,
	flavor: string?,
	users: { LuaSourceContainer },
	rawDataStore: { LuaSourceContainer },
}

function Scanner.flavorOf(module: ModuleScript): string?
	local ok, source = pcall(function()
		return module.Source
	end)
	if not ok then
		return nil
	end
	if source:find("StartSessionAsync", 1, true) and source:find("function ProfileStore.New", 1, true) then
		return "ProfileStore"
	elseif source:find("LoadProfileAsync", 1, true) and source:find("GetProfileStore", 1, true) then
		return "ProfileService"
	end
	return nil
end

local function anyMatch(source: string, patterns: { string }): boolean
	for _, pattern in patterns do
		if source:find(pattern) then
			return true
		end
	end
	return false
end

local function isDataGuard(inst: Instance): boolean
	local node: Instance? = inst
	while node do
		if node.Name == "DataGuard" and node:IsA("ModuleScript") then
			return true
		end
		node = node.Parent
	end
	return false
end

function Scanner.easy(): Result
	local result: Result = { users = {}, rawDataStore = {} }
	for _, rootName in EASY_ROOTS do
		local root = game:FindFirstChild(rootName)
		if not root then
			continue
		end
		for _, inst in root:GetDescendants() do
			if inst:IsA("ModuleScript") and not isDataGuard(inst) then
				local lower = inst.Name:lower()
				for _, pattern in NAME_PATTERNS do
					if lower:find(pattern, 1, true) then
						local flavor = Scanner.flavorOf(inst)
						if flavor then
							result.module, result.flavor = inst, flavor
							return result
						end
					end
				end
			end
		end
	end
	return result
end

function Scanner.deep(onProgress: ((number) -> ())?): Result
	local result: Result = { users = {}, rawDataStore = {} }
	local count = 0
	for _, rootName in DEEP_ROOTS do
		local root = game:FindFirstChild(rootName)
		if not root then
			continue
		end
		for _, inst in root:GetDescendants() do
			if not inst:IsA("LuaSourceContainer") or isDataGuard(inst) then
				continue
			end
			count += 1
			if count % 200 == 0 then
				if onProgress then
					onProgress(count)
				end
				task.wait()
			end

			local ok, source = pcall(function()
				return (inst :: any).Source
			end)
			if not ok or typeof(source) ~= "string" then
				continue
			end

			if result.module == nil and inst:IsA("ModuleScript") then
				local flavor = Scanner.flavorOf(inst)
				if flavor then
					result.module, result.flavor = inst, flavor
					continue
				end
			end
			if anyMatch(source, OWNER_PATTERNS) or anyMatch(source, REQUIRE_PATTERNS) then
				table.insert(result.users, inst)
			end
			if anyMatch(source, RAW_DS_PATTERNS) then
				table.insert(result.rawDataStore, inst)
			end
		end
	end
	return result
end

-- Resolve a GetFullName() path back to an instance.
function Scanner.resolve(path: string): Instance?
	local node: Instance? = game
	for segment in path:gmatch("[^%.]+") do
		node = node and node:FindFirstChild(segment)
		if not node then
			return nil
		end
	end
	return if node == game then nil else node
end

return Scanner
