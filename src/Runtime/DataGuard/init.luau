--!strict
--[[
	DataGuard: middleman between game code and ProfileStore / ProfileService.

	local DataGuard = require(ServerStorage.DataGuard)
	local store = DataGuard.new("PlayerData")
	local session = store:Load(player)   -- nil if kicked or failed
	session.Data.Coins += 10             -- guarded writes
	store:Release(player)

	The PFS module is set by the plugin through the `PFSModule` ObjectValue child.
	Rules live in the sibling `Schema` ModuleScript.
]]

local Players = game:GetService("Players")

local Adapters = require(script.Adapters)
local Migrate = require(script.Migrate)
local Guard = require(script.Guard)

local DataGuard = {}
DataGuard.__index = DataGuard

local function resolveLibrary()
	local pointer = script:FindFirstChild("PFSModule")
	if not pointer or not pointer:IsA("ObjectValue") or not pointer.Value then
		error("DataGuard[E_NO_PFS]: PFSModule pointer missing; run the DataGuard plugin to locate or install PFS", 3)
	end
	local lib = require(pointer.Value :: ModuleScript)
	return lib, Adapters.detect(lib)
end

local function resolveSchema()
	local module = script:FindFirstChild("Schema") or (script.Parent and script.Parent:FindFirstChild("DataGuardSchema"))
	if not module then
		error("DataGuard[E_NO_SCHEMA]: Schema module missing", 3)
	end
	return require(module :: ModuleScript)
end

-- A bad schema could delete or move data, so it fails before any profile is opened.
local function validateSchema(schema: any)
	local function bad(message: string): never
		error(`DataGuard[E_BAD_SCHEMA]: {message}`, 4)
	end
	if typeof(schema.Version) ~= "number" or schema.Version < 1 or schema.Version % 1 ~= 0 then
		bad("Version must be a positive integer")
	end
	if typeof(schema.Template) ~= "table" then
		bad("Template must be a table")
	end
	local removed = {}
	for i, rule in schema.Removed or {} do
		if typeof(rule.key) ~= "string" or typeof(rule.since) ~= "number" then
			bad(`Removed[{i}] needs key (string) and since (number)`)
		end
		if rule.since > schema.Version then
			bad(`Removed[{i}].since ({rule.since}) is above Version ({schema.Version}); bump Version`)
		end
		if schema.Template[rule.key] ~= nil then
			bad(`'{rule.key}' is both in Template and Removed`)
		end
		removed[rule.key] = true
	end
	for i, rule in schema.Renames or {} do
		if typeof(rule.from) ~= "string" or typeof(rule.to) ~= "string" or typeof(rule.since) ~= "number" then
			bad(`Renames[{i}] needs from, to (strings) and since (number)`)
		end
		if rule.from == rule.to or rule.from == "_v" or rule.to == "_v" then
			bad(`Renames[{i}] is invalid`)
		end
		if rule.since > schema.Version then
			bad(`Renames[{i}].since ({rule.since}) is above Version ({schema.Version}); bump Version`)
		end
		if removed[rule.to] then
			bad(`Renames[{i}] targets removed key '{rule.to}'`)
		end
	end
end

export type Session ={ Data: any, Handle: Adapters.Handle }

function DataGuard.new(storeName: string, options: { key: ((Player) -> string)? }?)
	local lib, flavor = resolveLibrary()
	local schema = resolveSchema()
	validateSchema(schema)
	local _, load = Adapters.create(lib, flavor, storeName, schema.Template)

	local defaultKey = if flavor == "ProfileStore"
		then function(player: Player) return tostring(player.UserId) end
		else function(player: Player) return `Player_{player.UserId}` end

	return setmetatable({
		Flavor = flavor,
		Schema = schema,
		_load = load,
		_key = (options and options.key) or defaultKey,
		_sessions = {} :: { [Player]: Session & { _tracker: any } },
		_loading = {} :: { [Player]: boolean },
	}, DataGuard)
end

function DataGuard:Load(player: Player): Session?
	-- One session per player per server: a second Load would open a second copy of the same data.
	if self._sessions[player] or self._loading[player] then
		warn(`[DataGuard] {player.Name}({player.UserId}): duplicate Load ignored`)
		return self._sessions[player]
	end
	self._loading[player] = true
	local ok, handle = pcall(self._load, player, self._key(player))
	self._loading[player] = nil
	if not ok then
		warn(`[DataGuard] {player.Name}({player.UserId}): load error: {handle}`)
		handle = nil
	end
	if handle == nil then
		player:Kick("Your data could not be loaded. Please rejoin.")
		return nil
	end

	local raw = handle.Data
	local owner = `{player.Name}({player.UserId})`
	local stored = raw[Migrate.VERSION_KEY] or 0

	-- Version gate: a newer server already migrated this profile. Touch nothing, release, kick.
	if stored > self.Schema.Version then
		warn(`[DataGuard] {owner}: data v{stored} is newer than server v{self.Schema.Version}; kicking`)
		handle.Release()
		player:Kick("This server is out of date. Please rejoin to get a newer server.")
		return nil
	end

	for _, line in Migrate.run(raw, self.Schema) do
		print(`[DataGuard] {owner}: {line}`)
	end

	handle.AddUserId(player.UserId)

	local proxy, tracker = Guard.wrap(raw, self.Schema, owner, handle.IsActive)
	local session = {
		Handle = handle,
		Data = proxy,
		_tracker = tracker,
	}
	self._sessions[player] = session

	handle.OnRelease(function()
		tracker.closed = true
		if self._sessions[player] == session then
			self._sessions[player] = nil
		end
		if player.Parent == Players then
			player:Kick("Your data session ended (loaded on another server).")
		end
	end)

	if player.Parent ~= Players then
		self:Release(player)
		return nil
	end
	return session
end

function DataGuard:Get(player: Player): Session?
	return self._sessions[player]
end

function DataGuard:Release(player: Player)
	local session = self._sessions[player]
	if not session then
		return
	end
	self._sessions[player] = nil
	Guard.restore(session.Handle.Data, session._tracker, self.Schema, `{player.Name}({player.UserId})`)
	session._tracker.closed = true
	session.Handle.Release()
end

-- Convenience: load on join, release on leave.
function DataGuard:Bind(onLoaded: ((Player, Session) -> ())?)
	local function join(player: Player)
		local session = self:Load(player)
		if session and onLoaded then
			onLoaded(player, session)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(join, player)
	end
	Players.PlayerAdded:Connect(join)
	Players.PlayerRemoving:Connect(function(player)
		self:Release(player)
	end)
end

return DataGuard
