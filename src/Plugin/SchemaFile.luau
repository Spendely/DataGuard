--!strict
-- Reads the Schema ModuleScript as data and writes it back as clean, hand-editable Luau.

local ScriptEditorService = game:GetService("ScriptEditorService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local SchemaFile = {}

local LUA_KEYWORDS = {}
for _, word in { "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "continue", "type", "export" } do
	LUA_KEYWORDS[word] = true
end

export type Schema = {
	Version: number,
	Template: { [string]: any },
	Renames: { { from: string, to: string, since: number } },
	Removed: { { key: string, since: number } },
}

-- Plugins cache require(), so a clone is required to see the current source.
function SchemaFile.read(module: ModuleScript): (Schema?, string?)
	local copy = module:Clone()
	local ok, result = pcall(require, copy)
	copy:Destroy()
	if not ok then
		return nil, tostring(result)
	end
	if typeof(result) ~= "table" or typeof(result.Template) ~= "table" or typeof(result.Version) ~= "number" then
		return nil, "the Schema must return a table with Version and Template"
	end
	return {
		Version = result.Version,
		Template = result.Template,
		Renames = result.Renames or {},
		Removed = result.Removed or {},
	}, nil
end

local function isArray(t: { [any]: any }): boolean
	local n = 0
	for _ in t do
		n += 1
	end
	return n == #t
end

function SchemaFile.kindOf(value: any): string
	local t = typeof(value)
	if t == "number" then
		return "Number"
	elseif t == "string" then
		return "Text"
	elseif t == "boolean" then
		return "Yes/No"
	elseif t == "table" then
		return "List"
	end
	return t
end

function SchemaFile.describe(value: any): string
	local t = typeof(value)
	if t == "string" then
		return if value == "" then "empty text" else `"{value}"`
	elseif t == "boolean" then
		return if value then "Yes" else "No"
	elseif t == "table" then
		local n = 0
		for _ in value do
			n += 1
		end
		return if n == 0 then "an empty list" elseif n == 1 then "a list of 1 item" else `a list of {n} items`
	end
	return tostring(value)
end

local function quote(s: string): string
	return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r") .. '"'
end

local function key(k: any): string
	if typeof(k) == "string" and k:match("^[%a_][%w_]*$") and not LUA_KEYWORDS[k] then
		return k
	end
	return "[" .. (if typeof(k) == "string" then quote(k) else tostring(k)) .. "]"
end

local function sortedKeys(t: { [any]: any }): { any }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

SchemaFile.isArray = isArray

function SchemaFile.serialize(value: any, indent: string): string
	local t = typeof(value)
	if t == "string" then
		return quote(value)
	elseif t == "number" or t == "boolean" then
		return tostring(value)
	elseif t ~= "table" then
		error(`DataGuard: cannot save a {t} in the Schema`)
	end
	if next(value) == nil then
		return "{}"
	end
	local inner = indent .. "\t"
	local lines = {}
	if isArray(value) then
		for _, v in ipairs(value) do
			table.insert(lines, inner .. SchemaFile.serialize(v, inner) .. ",")
		end
	else
		for _, k in sortedKeys(value) do
			table.insert(lines, `{inner}{key(k)} = {SchemaFile.serialize(value[k], inner)},`)
		end
	end
	return "{\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "}"
end

function SchemaFile.source(schema: Schema): string
	local renames, removed = {}, {}
	for _, r in schema.Renames do
		table.insert(renames, `\t\t\{ from = {quote(r.from)}, to = {quote(r.to)}, since = {r.since} },`)
	end
	for _, r in schema.Removed do
		table.insert(removed, `\t\t\{ key = {quote(r.key)}, since = {r.since} },`)
	end
	local function list(lines: { string }): string
		return if #lines == 0 then "{}" else "{\n" .. table.concat(lines, "\n") .. "\n\t}"
	end
	return table.concat({
		"-- DataGuard schema. Managed by the DataGuard plugin (Player Data panel); hand edits are fine too.",
		"-- Bump Version whenever Renames or Removed change.",
		"-- Keys not in Template and not in Removed are kept as-is.",
		"return {",
		`\tVersion = {schema.Version},`,
		"",
		`\tTemplate = {SchemaFile.serialize(schema.Template, "\t")},`,
		"",
		"\t-- Renamed fields: saved values move from the old name to the new one when a player joins.",
		`\tRenames = {list(renames)},`,
		"",
		"\t-- Removed fields: deleted from saves when a player joins. The only way data is deleted.",
		`\tRemoved = {list(removed)},`,
		"}",
		"",
	}, "\n")
end

function SchemaFile.write(module: ModuleScript, schema: Schema, label: string)
	local source = SchemaFile.source(schema)
	local id = ChangeHistoryService:TryBeginRecording(`DataGuard: {label}`)
	local ok, err = pcall(function()
		ScriptEditorService:UpdateSourceAsync(module, function()
			return source
		end)
	end)
	if not ok then
		ok, err = pcall(function()
			(module :: any).Source = source
		end)
	end
	if id then
		ChangeHistoryService:FinishRecording(id, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	end
	if not ok then
		error(`DataGuard: could not save the Schema ({err})`, 0)
	end
end

return SchemaFile
