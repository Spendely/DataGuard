--!strict
-- Load-time pipeline: renames -> explicit removals -> reconcile -> version stamp.
-- Keys that are neither in the template nor listed in Removed are kept untouched.

local Migrate = {}

Migrate.VERSION_KEY = "_v"

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Only named (string) keys are filled in. Numbered list items are a player's own contents: refilling
-- them would hand back starting items a player already spent or traded (a dupe).
local function reconcile(data: any, template: any)
	for key, default in template do
		if typeof(key) ~= "string" then
			continue
		end
		if data[key] == nil then
			data[key] = deepCopy(default)
		elseif typeof(default) == "table" and typeof(data[key]) == "table" then
			reconcile(data[key], default)
		end
	end
end

-- Returns a list of log lines describing what changed.
function Migrate.run(data: any, schema: any): { string }
	local log = {}
	local from = data[Migrate.VERSION_KEY] or 0

	for _, rename in schema.Renames or {} do
		if from < (rename.since or math.huge) and data[rename.from] ~= nil then
			if data[rename.to] == nil then
				data[rename.to] = data[rename.from]
				data[rename.from] = nil
				table.insert(log, `renamed {rename.from} -> {rename.to}`)
			else
				-- Never merge (dupe risk) and never drop (loss risk): leave both, flag it for review.
				warn(`[DataGuard] both {rename.from} and {rename.to} exist; kept both untouched, using {rename.to}`)
			end
		end
	end

	for _, removed in schema.Removed or {} do
		if from < (removed.since or math.huge) and data[removed.key] ~= nil then
			data[removed.key] = nil
			table.insert(log, `removed {removed.key}`)
		end
	end

	reconcile(data, schema.Template)
	data[Migrate.VERSION_KEY] = schema.Version
	return log
end

return Migrate
