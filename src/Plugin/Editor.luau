--!strict
-- No-code Player Data editor. Lists open like folders and can hold the same four kinds again, nested as deep
-- as you like. Top-level renames/removals are major changes that bump the schema version; anything inside a
-- list only changes starting contents, so it never deletes or moves a player's saved data.

local SchemaFile = require(script.Parent.SchemaFile)

type Schema = SchemaFile.Schema

export type Context = {
	ui: any,
	path: { any },
	schemaModule: () -> ModuleScript?,
	setStatus: (text: string) -> (),
	refresh: () -> (),
}

local Editor = {}

local KINDS = {
	{ name = "Number", hint = "Coins, level, XP, wins: any amount", default = 0 },
	{ name = "Text", hint = "A chosen class, a nickname, a code", default = "" },
	{ name = "Yes/No", hint = "Tutorial done, VIP reward claimed", default = false },
	{ name = "List", hint = "Inventory, pets, settings: holds more data inside", default = {} },
}

local function trim(s: string): string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function keyLabel(key: any): string
	return if typeof(key) == "number" then `Item {key}` else tostring(key)
end

local function pathLabel(path: { any }): string
	local parts = { "Player data" }
	for _, key in path do
		table.insert(parts, keyLabel(key))
	end
	return table.concat(parts, " > ")
end

-- The table the editor is looking at; resets the path if it no longer leads to a list.
local function container(ctx: Context, schema: Schema): { [any]: any }
	local node: any = schema.Template
	for _, key in ctx.path do
		local child = node[key]
		if typeof(child) ~= "table" then
			table.clear(ctx.path)
			return schema.Template
		end
		node = child
	end
	return node
end

local function shape(t: { [any]: any }): (boolean, boolean)
	local named, numbered = false, false
	for k in t do
		if typeof(k) == "number" then
			numbered = true
		else
			named = true
		end
	end
	return named, numbered
end

local function sortedKeys(t: { [any]: any }): { any }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		if typeof(a) == typeof(b) then
			return a < b
		end
		return typeof(a) == "number"
	end)
	return keys
end

local function checkName(schema: Schema, node: { [any]: any }, top: boolean, raw: any, current: any): string?
	local name = trim(tostring(raw or ""))
	if name == "" then
		return "Give it a name."
	end
	if not name:match("^[%a][%w_]*$") then
		return "Use letters, numbers and _ only, starting with a letter (like Coins or BestTime)."
	end
	if name ~= current and node[name] ~= nil then
		return `There is already something called {name} here.`
	end
	if top then
		for _, r in schema.Removed do
			if r.key == name then
				return `{name} was removed in version {r.since}, and some old saves may still hold it. Pick a different name.`
			end
		end
		for _, r in schema.Renames do
			if r.from == name and name ~= current then
				return `{name} was renamed to {r.to} in version {r.since}. Pick a different name.`
			end
		end
	end
	return nil
end

-- Returns (value, problem).
local function parseValue(kind: string, raw: any): (any, string?)
	if kind == "Number" then
		local n = tonumber(trim(tostring(raw)))
		if n == nil then
			return nil, "The starting value must be a number, like 0 or 100."
		end
		return n, nil
	elseif kind == "Text" then
		return tostring(raw or ""), nil
	elseif kind == "Yes/No" then
		return raw == true, nil
	end
	return {}, nil
end

local function valueField(kind: string, value: any)
	if kind == "Yes/No" then
		return { key = "value", label = "Starts as", kind = "toggle", value = value == true }
	elseif kind == "Number" then
		return { key = "value", label = "Starting value", kind = "text", value = tostring(value) }
	elseif kind == "Text" then
		return { key = "value", label = "Starting text", kind = "text", value = value, placeholder = "empty" }
	end
	return nil
end

local function save(ctx: Context, schema: Schema, label: string, message: string)
	local module = ctx.schemaModule()
	if not module then
		ctx.setStatus("The Schema is missing. Run Start DataGuard again.")
		return
	end
	SchemaFile.write(module, schema, label)
	ctx.setStatus(message)
	ctx.refresh()
end

function Editor.add(ctx: Context, schema: Schema)
	local node = container(ctx, schema)
	local top = #ctx.path == 0
	local where = if top then "player data" else keyLabel(ctx.path[#ctx.path])

	local buttons, lines = {}, {}
	for _, kind in KINDS do
		table.insert(buttons, { text = kind.name })
		table.insert(lines, `<b>{kind.name}</b>: {kind.hint}`)
	end
	table.insert(buttons, { text = "Cancel" })
	local picked = ctx.ui:dialog({ title = `Add to {where}: what kind?`, body = table.concat(lines, "\n"), buttons = buttons })
	local kind
	for _, k in KINDS do
		if k.name == picked then
			kind = k
		end
	end
	if not kind then
		return
	end

	-- Inside a list, entries are either all named or all numbered.
	local named, numbered = shape(node)
	local mode = if top or named then "named" elseif numbered then "numbered" else "either"
	local fields = {}
	if mode ~= "numbered" then
		table.insert(fields, {
			key = "name",
			label = if mode == "either" then "Name (leave empty to make it a numbered item)" else "Name",
			kind = "text",
			placeholder = if top then "e.g. Coins" else "e.g. Sword",
		})
	end
	local vf = valueField(kind.name, kind.default)
	if vf then
		table.insert(fields, vf)
	end

	local body = if top
		then "Every player gets this the next time they join. Nothing existing changes."
		elseif mode == "numbered" then `This becomes item {#node + 1} of {where}'s starting contents.`
		else `Named entries are added inside {where} for every player. Numbered items are only starting contents.`
	if kind.name == "List" then
		body ..= "\n\nAfter adding it, tap Open to put things inside."
	end

	local pressed, values = ctx.ui:dialog({
		title = `New {kind.name}`,
		body = body,
		fields = fields,
		buttons = { { text = "Add", style = "primary", validate = true }, { text = "Cancel" } },
		validate = function(v)
			local _, problem = parseValue(kind.name, v.value)
			if problem then
				return problem
			end
			if mode == "numbered" or (mode == "either" and trim(tostring(v.name or "")) == "") then
				return nil
			end
			return checkName(schema, node, top, v.name)
		end,
	})
	if pressed ~= "Add" then
		return
	end
	local value = parseValue(kind.name, values.value)
	local name = trim(tostring(values.name or ""))
	local label
	if name == "" then
		table.insert(node, value)
		label = `Item {#node}`
	else
		node[name] = value
		label = name
	end

	local message
	if top then
		message = `Added {label}. Players get {SchemaFile.describe(value)} the next time they join.`
	elseif name == "" then
		message = `Added {label} to {where}'s starting contents. Players who already have it aren't given it again, so nothing is duplicated.`
	else
		message = `Added {label} inside {where}. Every player gets it the next time they join.`
	end
	save(ctx, schema, `add {label}`, message)
end

function Editor.edit(ctx: Context, schema: Schema, key: any)
	local node = container(ctx, schema)
	local top = #ctx.path == 0
	local current = node[key]
	local kind = SchemaFile.kindOf(current)
	local isNamed = typeof(key) == "string"

	local fields = {}
	if isNamed then
		table.insert(fields, { key = "name", label = "Name", kind = "text", value = key })
	end
	local vf = valueField(kind, current)
	if vf then
		table.insert(fields, vf)
	end
	if #fields == 0 then
		ctx.ui:dialog({ title = keyLabel(key), body = "Numbered list items have no name. Tap Open to change what's inside.", buttons = { { text = "OK" } } })
		return
	end

	local body = `Type: <b>{kind}</b>. The type can't change, because saves already store a {kind}. To switch types, add a new one and remove this one.`
	if vf then
		body ..= `\n\nChanging the starting value only affects players who don't have {keyLabel(key)} yet.`
	end
	local pressed, values = ctx.ui:dialog({
		title = `Edit {keyLabel(key)}`,
		body = body,
		fields = fields,
		buttons = { { text = "Save", style = "primary", validate = true }, { text = "Cancel" } },
		validate = function(v)
			local _, problem = parseValue(kind, v.value)
			if problem then
				return problem
			end
			return if isNamed then checkName(schema, node, top, v.name, key) else nil
		end,
	})
	if pressed ~= "Save" then
		return
	end
	local value = if kind == "List" then current else parseValue(kind, values.value)
	local newName = if isNamed then trim(values.name) else key

	if newName == key then
		node[key] = value
		save(ctx, schema, `edit {keyLabel(key)}`, `Saved {keyLabel(key)}.`)
		return
	end

	if not top then
		local confirm = ctx.ui:dialog({
			title = `Rename {key} to {newName}?`,
			body = `Players who already have {pathLabel(ctx.path)} keep their {key} as it is, and get {newName} with its starting value. Only top-level player data can be moved to a new name.`,
			buttons = { { text = "Rename", style = "primary" }, { text = "Cancel" } },
		})
		if confirm ~= "Rename" then
			return
		end
		node[key] = nil
		node[newName] = value
		save(ctx, schema, `rename {key} to {newName}`, `Renamed {key} to {newName} in the starting contents.`)
		return
	end

	local nextVersion = schema.Version + 1
	local confirm = ctx.ui:dialog({
		title = `Rename {key} to {newName}?`,
		body = `Each player's saved {key} moves to {newName} the next time they join. Nothing is lost.\n\nThis is a major change, so the schema goes to version {nextVersion}. Players still on older servers are asked to rejoin, so an old server can never write {key} back and roll anything back.`,
		buttons = { { text = "Rename", style = "primary" }, { text = "Cancel" } },
	})
	if confirm ~= "Rename" then
		return
	end
	schema.Version = nextVersion
	node[key] = nil
	node[newName] = value
	table.insert(schema.Renames, { from = key, to = newName, since = nextVersion })
	save(ctx, schema, `rename {key} to {newName}`, `Renamed {key} to {newName}. Schema is now version {nextVersion}.`)
end

function Editor.remove(ctx: Context, schema: Schema, key: any)
	local node = container(ctx, schema)
	local label = keyLabel(key)

	if #ctx.path > 0 then
		local choice = ctx.ui:dialog({
			title = `Remove {label}?`,
			body = `This only removes it from the starting contents of {pathLabel(ctx.path)}. Players who already have it keep theirs; it just stops being given out.`,
			buttons = { { text = "Remove", style = "danger" }, { text = "Cancel" } },
		})
		if choice ~= "Remove" then
			return
		end
		if typeof(key) == "number" then
			table.remove(node, key)
		else
			node[key] = nil
		end
		save(ctx, schema, `remove {label}`, `Removed {label} from the starting contents.`)
		return
	end

	local nextVersion = schema.Version + 1
	local choice = ctx.ui:dialog({
		title = `Remove {label}?`,
		body = `<b>Every player's saved {label} will be permanently deleted</b> the next time they join. This can't be undone, even by changing it back later.\n\nUsually you don't need to remove data:\n- To give it a better name, <b>Rename</b> it. Saved values are kept.\n- If the game just stopped using it, leaving it costs almost nothing.\n\nRemoving moves the schema to version {nextVersion}, and players on older servers are asked to rejoin.`,
		buttons = { { text = "Rename instead", style = "primary" }, { text = "Remove", style = "danger" }, { text = "Cancel" } },
	})
	if choice == "Rename instead" then
		Editor.edit(ctx, schema, key)
		return
	elseif choice ~= "Remove" then
		return
	end

	local confirm = ctx.ui:dialog({
		title = `Type {label} to confirm`,
		body = `This deletes {label} from every player's save.`,
		fields = { { key = "confirm", label = "Name", kind = "text", placeholder = label } },
		buttons = { { text = "Delete forever", style = "danger", validate = true }, { text = "Cancel" } },
		validate = function(v)
			return if trim(tostring(v.confirm)) == label then nil else `Type {label} exactly to confirm.`
		end,
	})
	if confirm ~= "Delete forever" then
		return
	end
	schema.Version = nextVersion
	node[key] = nil
	table.insert(schema.Removed, { key = key, since = nextVersion })
	save(ctx, schema, `remove {label}`, `Removed {label}. Schema is now version {nextVersion}.`)
end

function Editor.render(ctx: Context)
	local ui = ctx.ui
	local module = ctx.schemaModule()
	local schema, err = nil, "the Schema module is missing"
	if module then
		schema, err = SchemaFile.read(module)
	end
	if not schema then
		ui:label(`Couldn't read the Schema: {err}. Open Developer tools > Open Schema to fix it, or run Start DataGuard again.`, { color = Color3.fromRGB(240, 110, 110) })
		return
	end
	local s = schema :: Schema
	local node = container(ctx, s)
	local top = #ctx.path == 0

	if top then
		ui:label(`Player data   <font size="13">version {s.Version}</font>`, { size = 19, bold = true })
		ui:label("This is what every player's save contains. Open a List to put things inside it.", { dim = true, size = 14 })
	else
		local row = ui:row()
		ui:button("< Back", function()
			table.remove(ctx.path)
			ctx.refresh()
		end, { parent = row, width = 0.5, height = 26 })
		ui:button("Top", function()
			table.clear(ctx.path)
			ctx.refresh()
		end, { parent = row, width = 0.5, height = 26 })
		ui:label(pathLabel(ctx.path), { dim = true, size = 13 })
		ui:label(keyLabel(ctx.path[#ctx.path]), { size = 19, bold = true })
		ui:label("Starting contents of this list. Named entries are added for every player; numbered items only go to players who don't have this list yet.", { dim = true, size = 14 })
	end

	local keys = sortedKeys(node)
	if #keys == 0 then
		ui:label(if top then "No player data yet. Add your first one below." else "This list is empty.", { dim = true })
	end
	for _, key in keys do
		local value = node[key]
		local kind = SchemaFile.kindOf(value)
		local card = ui:card()
		ui:label(`<b>{keyLabel(key)}</b>`, { parent = card, size = 16 })
		ui:label(`{kind} - starts as {SchemaFile.describe(value)}`, { parent = card, dim = true, size = 14 })
		local row = ui:row(card)
		local width = if kind == "List" then 1 / 3 else 0.5
		if kind == "List" then
			ui:button("Open", function()
				table.insert(ctx.path, key)
				ctx.refresh()
			end, { parent = row, width = width, height = 24, style = "primary" })
		end
		ui:button("Edit", function()
			Editor.edit(ctx, s, key)
		end, { parent = row, width = width, height = 24 })
		ui:button("Remove", function()
			Editor.remove(ctx, s, key)
		end, { parent = row, width = width, height = 24 })
	end

	ui:button(if top then "+ Add player data" else `+ Add inside {keyLabel(ctx.path[#ctx.path])}`, function()
		Editor.add(ctx, s)
	end, { style = "primary", height = 32 })

	if top and #s.Renames + #s.Removed > 0 then
		ui:label("History", { bold = true, size = 15 })
		local lines = {}
		for _, r in s.Renames do
			table.insert(lines, { since = r.since, text = `v{r.since}: renamed {r.from} > {r.to}` })
		end
		for _, r in s.Removed do
			table.insert(lines, { since = r.since, text = `v{r.since}: removed {r.key}` })
		end
		table.sort(lines, function(a, b)
			return a.since > b.since
		end)
		for _, line in lines do
			ui:label(line.text, { dim = true, size = 14 })
		end
	end
end

return Editor
