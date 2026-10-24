--!strict
-- One-click setup: find ProfileStore (easy, then deep scan), offer to install it if missing (No = cancel),
-- check its API, then install the DataGuard runtime.

local Scanner = require(script.Parent.Scanner)
local Installer = require(script.Parent.Installer)

export type Context = {
	ui: any,
	setStatus: (text: string) -> (),
	setFound: (module: ModuleScript?, flavor: string?) -> (),
	missingApi: () -> { string },
	runtimeTemplate: ModuleScript,
}

local Setup = {}

local function problem(ctx: Context, title: string, body: string)
	ctx.ui:dialog({ title = title, body = body, buttons = { { text = "OK" } } })
end

function Setup.run(ctx: Context): boolean
	ctx.setStatus("Looking for ProfileStore...")
	local found = Scanner.easy()
	if not found.module then
		ctx.setStatus("Looking deeper (reading every script)...")
		found = Scanner.deep()
	end

	local module, flavor = found.module, found.flavor
	if not module then
		local choice = ctx.ui:dialog({
			title = "No ProfileStore found",
			body = "DataGuard protects player data saved with ProfileStore, and this game doesn't have it yet.\n\nInstall the official ProfileStore (by MadStudioRoblox, from GitHub)? Studio may ask you once to allow access to github.com.",
			buttons = { { text = "Install", style = "primary" }, { text = "Cancel" } },
		})
		if choice ~= "Install" then
			ctx.setStatus("Setup cancelled. Nothing was changed.")
			return false
		end
		ctx.setStatus("Downloading ProfileStore...")
		local ok, result = pcall(Installer.fetchPFS, "ProfileStore")
		if not ok then
			ctx.setStatus("Download failed.")
			problem(ctx, "Couldn't download ProfileStore", `{result}\n\nIf Studio asked about HTTP access, allow it and try again.`)
			return false
		end
		module, flavor = result, "ProfileStore"
	end

	ctx.setFound(module, flavor)
	local missing = ctx.missingApi()
	if #missing > 0 then
		ctx.setStatus("This ProfileStore is missing functions DataGuard needs.")
		problem(ctx, "This ProfileStore looks incomplete", `It is missing: {table.concat(missing, ", ")}.\n\nIt may be an old or edited copy. Developer tools > Install ProfileStore from Git gets a fresh one.`)
		return false
	end

	ctx.setStatus("Installing DataGuard...")
	local ok, err = pcall(Installer.installRuntime, ctx.runtimeTemplate, module :: ModuleScript)
	if not ok then
		ctx.setStatus("Install failed.")
		problem(ctx, "Couldn't install DataGuard", tostring(err))
		return false
	end
	ctx.setStatus("DataGuard is set up. Add your player data below.")
	return true
end

return Setup
