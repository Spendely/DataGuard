--!strict
-- Shallow proxy over profile data. Top-level deletes and type changes are warned and ignored.
-- The library keeps saving the raw table; game code only ever sees the proxy.

local Guard = {}

local function log(message: string)
	warn(`[DataGuard] {message}`)
end

local function removableSet(schema: any): { [any]: boolean }
	local set = {}
	for _, removed in schema.Removed or {} do
		set[removed.key] = true
	end
	return set
end

export type Tracker = { latest: { [any]: any }, closed: boolean }

-- isActive: writes after the session ended would never save, so they are refused instead of silently lost.
function Guard.wrap(raw: any, schema: any, owner: string, isActive: () -> boolean)
	local removable = removableSet(schema)

	-- Last value written through the proxy (tables by reference, so nested edits stay current).
	-- Used by restore() so a bypass is repaired with the newest value, never a load-time copy.
	local tracker: Tracker = { latest = {}, closed = false }
	for key, value in raw do
		tracker.latest[key] = value
	end

	local proxy = setmetatable({}, {
		__index = raw,
		__newindex = function(_, key, value)
			if tracker.closed or not isActive() then
				log(`{owner}: blocked write to '{tostring(key)}' after session ended (would not save)`)
				return
			end
			local current = raw[key]
			if key == "_v" then
				log(`{owner}: blocked write to version key`)
				return
			end
			if value == nil and current ~= nil and not removable[key] then
				log(`{owner}: blocked delete of '{tostring(key)}' (not listed in Schema.Removed)`)
				return
			end
			if current ~= nil and value ~= nil and typeof(current) ~= typeof(value) then
				log(`{owner}: blocked type change on '{tostring(key)}' ({typeof(current)} -> {typeof(value)})`)
				return
			end
			raw[key] = value
			tracker.latest[key] = value
		end,
		__iter = function()
			return next, raw
		end,
		__len = function()
			return #raw
		end,
	})
	return proxy, tracker
end

-- Repairs top-level keys removed behind the proxy (rawset on Handle.Data). Only fills nil keys, with the
-- latest known value, so it can never roll a value back or bring back something legitimately removed.
function Guard.restore(raw: any, tracker: Tracker, schema: any, owner: string)
	local removable = removableSet(schema)
	for key, value in tracker.latest do
		if raw[key] == nil and not removable[key] then
			log(`{owner}: '{tostring(key)}' vanished outside the proxy; restored latest value`)
			raw[key] = value
		end
	end
end

return Guard
