--!strict
-- DataGuard plugin. No-code first: Start DataGuard sets everything up, then Player Data edits the Schema.
-- Developer tools (scans, installs, raw Schema, code usage) sit in a separate section.

local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")

local Scanner = require(script.Scanner)
local Installer = require(script.Installer)
local Ui = require(script.Ui)
local Setup = require(script.Setup)
local Editor = require(script.Editor)
local RuntimeTemplate = script:WaitForChild("DataGuard") :: ModuleScript

local SETTING_KEY = `pfs:{game.GameId}:{game.PlaceId}`
local GREEN, AMBER, RED = "#6cc26c", "#e0b46c", "#e06c6c"

-- Static API check (plugin side). Requiring PFS in edit mode would start its loops, so we read Source instead;
-- the runtime does the real typeof() check before anything is called.
local STATIC_API = {
	ProfileStore = { "New", "StartSessionAsync", "GetAsync", "RemoveAsync", "MessageAsync", "EndSession", "IsActive", "AddUserId", "Save" },
	ProfileService = { "GetProfileStore", "LoadProfileAsync", "ViewProfileAsync", "WipeProfileAsync", "Release", "IsActive", "AddUserId", "ListenToRelease" },
}

local USAGE = [[local DataGuard = require(game.ServerStorage.DataGuard)
local store = DataGuard.new("PlayerData")

store:Bind(function(player, session)
	-- session.Data is guarded: deletes and type changes are blocked
	session.Data.Coins += 10
end)]]

---------------------------------------------------------------- Widget

local toolbar = plugin:CreateToolbar("DataGuard")
local toggle = toolbar:CreateButton("DataGuard", "Protect and edit player data", "rbxassetid://76654367927427")
toggle.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"DataGuardWidget",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 340, 560, 280, 320)
)
widget.Title = "DataGuard"
toggle.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggle:SetActive(widget.Enabled)
end)

local ui = Ui.new(widget)

---------------------------------------------------------------- State

local state = {
	module = nil :: ModuleScript?,
	flavor = nil :: string?,
	status = "",
	devOpen = false,
	busy = false,
}

local render: () -> ()

local function setStatus(text: string)
	state.status = text
	render()
end

local function validate(): { [string]: boolean }
	local report = {}
	local module, flavor = state.module, state.flavor
	if not module or not flavor then
		return report
	end
	local source = (module :: any).Source :: string
	for _, name in STATIC_API[flavor] do
		report[name] = source:find(`function%s+[%w_]+[%.:]{name}%s*%(`) ~= nil
	end
	return report
end

local function missingApi(): { string }
	local module, flavor = state.module, state.flavor
	if not module or not flavor then
		return { "(no ProfileStore)" }
	end
	local missing = {}
	local report = validate()
	for _, name in STATIC_API[flavor] do
		if not report[name] then
			table.insert(missing, name)
		end
	end
	return missing
end

local function setFound(module: ModuleScript?, flavor: string?)
	state.module, state.flavor = module, flavor
	plugin:SetSetting(SETTING_KEY, if module then module:GetFullName() else nil)
end

local function runtime(): ModuleScript?
	local r = ServerStorage:FindFirstChild("DataGuard")
	return if r and r:IsA("ModuleScript") then r else nil
end

local function schemaModule(): ModuleScript?
	local r = runtime()
	local s = r and r:FindFirstChild("Schema")
	return if s and s:IsA("ModuleScript") then s else nil
end

local function loadCached()
	local path = plugin:GetSetting(SETTING_KEY)
	if typeof(path) == "string" then
		local inst = Scanner.resolve(path)
		if inst and inst:IsA("ModuleScript") then
			local flavor = Scanner.flavorOf(inst)
			if flavor then
				state.module, state.flavor = inst, flavor
				return
			end
		end
		plugin:SetSetting(SETTING_KEY, nil)
	end
	-- The runtime remembers which PFS it was linked to.
	local r = runtime()
	local pointer = r and r:FindFirstChild("PFSModule")
	local linked = pointer and (pointer :: ObjectValue).Value
	if linked and linked:IsA("ModuleScript") then
		local flavor = Scanner.flavorOf(linked)
		if flavor then
			setFound(linked, flavor)
		end
	end
end

local function isSetUp(): boolean
	local r = runtime()
	local pointer = r and r:FindFirstChild("PFSModule")
	return state.module ~= nil and pointer ~= nil and (pointer :: ObjectValue).Value == state.module and schemaModule() ~= nil
end

-- One action at a time, so double clicks can't overlap installs.
local function action(fn: () -> ()): () -> ()
	return function()
		if state.busy then
			return
		end
		state.busy = true
		local ok, err = pcall(fn)
		state.busy = false
		if not ok then
			state.status = `Something went wrong: {err}`
		end
		render()
	end
end

local editorContext = {
	ui = ui,
	path = {},
	schemaModule = schemaModule,
	setStatus = setStatus,
	refresh = function()
		render()
	end,
}

local setupContext = { ui = ui, setStatus = setStatus, setFound = setFound, missingApi = missingApi, runtimeTemplate = RuntimeTemplate }

---------------------------------------------------------------- Views

local function listNames(list: { Instance }, max: number): string
	local out = {}
	for i, inst in list do
		if i > max then
			table.insert(out, `...and {#list - max} more`)
			break
		end
		table.insert(out, inst:GetFullName())
	end
	return table.concat(out, "\n")
end

local function devTools()
	ui:label("Status", { bold = true })
	local module, flavor = state.module, state.flavor
	if module and flavor then
		local sha = module:GetAttribute("DataGuardSha")
		ui:label(
			`<b>PFS:</b> {flavor}\n<b>Path:</b> {module:GetFullName()}`
				.. (if sha then `\n<b>Pinned:</b> {tostring(sha):sub(1, 10)}` else "")
				.. "\n<b>Runtime:</b> "
				.. (if isSetUp() then `<font color="{GREEN}">installed + linked</font>` else `<font color="{AMBER}">not installed</font>`),
			{ code = true, size = 13 }
		)
		local report = validate()
		local lines = {}
		for _, name in STATIC_API[flavor] do
			table.insert(lines, if report[name] then `<font color="{GREEN}">OK</font> {name}` else `<font color="{RED}">MISSING</font> {name}`)
		end
		ui:label(table.concat(lines, "   "), { code = true, size = 13 })
	else
		ui:label(`<b>PFS:</b> <font color="{RED}">not found</font>`, { code = true, size = 13 })
	end

	ui:button("Easy Scan", action(function()
		local result = Scanner.easy()
		setFound(result.module, result.flavor)
		state.status = if result.module then "Easy scan: found." else "Easy scan: nothing by name. Try Deep Scan."
	end))
	ui:button("Deep Scan", action(function()
		local result = Scanner.deep()
		if result.module then
			setFound(result.module, result.flavor)
		end
		local text = (if result.module then "Deep scan: PFS found." else "Deep scan: no PFS module found.")
			.. `\nScripts using PFS ({#result.users}):\n`
			.. listNames(result.users, 8)
		if #result.rawDataStore > 0 then
			text ..= `\nRaw DataStore use ({#result.rawDataStore}) bypasses DataGuard:\n` .. listNames(result.rawDataStore, 8)
		end
		state.status = text
	end))
	ui:button("Install ProfileStore from Git", action(function()
		setFound(Installer.fetchPFS("ProfileStore"), "ProfileStore")
		state.status = "ProfileStore installed in ServerStorage."
	end))
	ui:button("Install ProfileService from Git", action(function()
		setFound(Installer.fetchPFS("ProfileService"), "ProfileService")
		state.status = "ProfileService installed in ServerStorage."
	end))
	ui:button("Install / Update DataGuard Runtime", action(function()
		local missing = missingApi()
		if #missing > 0 then
			state.status = `Can't install: missing {table.concat(missing, ", ")}.`
			return
		end
		Selection:Set({ Installer.installRuntime(RuntimeTemplate, state.module :: ModuleScript) })
		state.status = "Runtime installed at ServerStorage.DataGuard (existing Schema kept)."
	end))
	ui:button("Open Schema (edit as code)", function()
		local s = schemaModule()
		if s then
			plugin:OpenScript(s)
		else
			setStatus("Install the runtime first.")
		end
	end)
	ui:button("Bump Schema Version", action(function()
		local s = schemaModule()
		if not s then
			state.status = "Install the runtime first."
			return
		end
		local v = Installer.bumpVersion(s)
		state.status = if v then `Schema Version is now {v}.` else "Could not find Version = N in Schema."
	end))
	ui:button("Re-validate", action(function()
		loadCached()
		state.status = if state.module then "Re-validated." else "No PFS found."
	end))

	ui:label("Use it in code", { bold = true })
	ui:codeBox(USAGE)
end

render = function()
	ui:clear()
	ui:retheme()
	if state.status ~= "" then
		ui:label(state.status, { dim = true, size = 14 })
	end

	if isSetUp() then
		Editor.render(editorContext)
	else
		local card = ui:card()
		ui:label("Protect your player data", { parent = card, bold = true, size = 18 })
		ui:label(
			"DataGuard sits between your game and ProfileStore. It stops saves from being wiped by mistake, handles renamed data, and keeps old servers from rolling anything back.\n\nOne click sets it all up.",
			{ parent = card, size = 14 }
		)
		ui:button("Start DataGuard", action(function()
			Setup.run(setupContext)
		end), { parent = card, style = "primary", height = 34 })
	end

	ui:button(if state.devOpen then "Developer tools (hide)" else "Developer tools (show)", function()
		state.devOpen = not state.devOpen
		render()
	end)
	if state.devOpen then
		devTools()
	end
end

settings().Studio.ThemeChanged:Connect(function()
	render()
end)

loadCached()
render()
