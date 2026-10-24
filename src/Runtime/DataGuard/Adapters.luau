--!strict
-- Maps ProfileStore and ProfileService onto one interface, validating the API before anything is called.

local Players = game:GetService("Players")

local Adapters = {}

export type Handle = {
	Raw: any,
	Data: any,
	Release: () -> (),
	OnRelease: (callback: () -> ()) -> (),
	AddUserId: (userId: number) -> (),
	IsActive: () -> boolean,
}

local REQUIRED = {
	ProfileStore = {
		module = { "New" },
		store = { "StartSessionAsync", "GetAsync", "RemoveAsync", "MessageAsync" },
		profile = { "EndSession", "IsActive", "AddUserId", "Save" },
	},
	ProfileService = {
		module = { "GetProfileStore" },
		store = { "LoadProfileAsync", "ViewProfileAsync", "WipeProfileAsync" },
		profile = { "Release", "IsActive", "AddUserId", "ListenToRelease" },
	},
}

local function fail(code: string, message: string): never
	error(`DataGuard[{code}]: {message}`, 3)
end

local function check(target: any, names: { string }, flavor: string, where: string)
	for _, name in names do
		if typeof(target[name]) ~= "function" then
			fail("E_MISSING_API", `{where}:{name} not found (flavor={flavor})`)
		end
	end
end

function Adapters.detect(lib: any): string
	if typeof(lib) ~= "table" then
		fail("E_BAD_MODULE", "PFS module did not return a table")
	end
	if typeof(lib.New) == "function" then
		return "ProfileStore"
	elseif typeof(lib.GetProfileStore) == "function" then
		return "ProfileService"
	end
	return fail("E_UNKNOWN_FLAVOR", "module is neither ProfileStore nor ProfileService")
end

function Adapters.validateModule(lib: any, flavor: string)
	check(lib, REQUIRED[flavor].module, flavor, flavor)
end

function Adapters.validateStore(store: any, flavor: string)
	check(store, REQUIRED[flavor].store, flavor, "Store")
end

function Adapters.validateProfile(profile: any, flavor: string)
	check(profile, REQUIRED[flavor].profile, flavor, "Profile")
end

-- Returns store, load(player, key) -> Handle?
function Adapters.create(lib: any, flavor: string, storeName: string, template: any)
	Adapters.validateModule(lib, flavor)
	local profileChecked = false

	if flavor == "ProfileStore" then
		local store = lib.New(storeName, template)
		Adapters.validateStore(store, flavor)

		local function load(player: Player, key: string): Handle?
			local profile = store:StartSessionAsync(key, {
				Cancel = function()
					return player.Parent ~= Players
				end,
			})
			if profile == nil then
				return nil
			end
			if not profileChecked then
				Adapters.validateProfile(profile, flavor)
				profileChecked = true
			end
			return {
				Raw = profile,
				Data = profile.Data,
				Release = function()
					profile:EndSession()
				end,
				OnRelease = function(callback)
					profile.OnSessionEnd:Connect(callback)
				end,
				AddUserId = function(userId)
					profile:AddUserId(userId)
				end,
				IsActive = function()
					return profile:IsActive()
				end,
			}
		end
		return store, load
	end

	local store = lib.GetProfileStore(storeName, template)
	Adapters.validateStore(store, flavor)

	local function load(_player: Player, key: string): Handle?
		local profile = store:LoadProfileAsync(key, "ForceLoad")
		if profile == nil then
			return nil
		end
		if not profileChecked then
			Adapters.validateProfile(profile, flavor)
			profileChecked = true
		end
		return {
			Raw = profile,
			Data = profile.Data,
			Release = function()
				profile:Release()
			end,
			OnRelease = function(callback)
				profile:ListenToRelease(callback)
			end,
			AddUserId = function(userId)
				profile:AddUserId(userId)
			end,
			IsActive = function()
				return profile:IsActive()
			end,
		}
	end
	return store, load
end

return Adapters
