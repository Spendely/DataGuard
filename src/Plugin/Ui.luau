--!strict
-- Small widget toolkit: themed labels, buttons, cards, rows, a copyable code box and a modal dialog.

local Ui = {}
Ui.__index = Ui

local ACCENT = Color3.fromRGB(0, 140, 255)
local DANGER = Color3.fromRGB(200, 70, 70)
local ERROR_TEXT = Color3.fromRGB(240, 110, 110)

local function color(c: Enum.StudioStyleGuideColor): Color3
	return (settings().Studio.Theme :: StudioTheme):GetColor(c)
end

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 4)
	c.Parent = parent
end

local function padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop, p.PaddingBottom = UDim.new(0, px), UDim.new(0, px)
	p.PaddingLeft, p.PaddingRight = UDim.new(0, px), UDim.new(0, px)
	p.Parent = parent
end

local function vertical(parent: Instance, gap: number)
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap)
	l.Parent = parent
end

export type Field = { key: string, label: string, kind: string, value: any?, placeholder: string? }
export type DialogButton = { text: string, style: string?, validate: boolean? }
export type DialogOptions = {
	title: string,
	body: string?,
	fields: { Field }?,
	buttons: { DialogButton },
	validate: ((values: { [string]: any }) -> string?)?,
}

function Ui.new(widget: DockWidgetPluginGui)
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BorderSizePixel = 0
	background.Parent = widget

	local root = Instance.new("ScrollingFrame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.AutomaticCanvasSize = Enum.AutomaticSize.Y
	root.CanvasSize = UDim2.new()
	root.ScrollBarThickness = 6
	root.Parent = background
	padding(root, 10)
	vertical(root, 8)

	local self = setmetatable({ background = background, root = root, order = 0, closeDialog = nil :: ((string?) -> ())? }, Ui)
	self:retheme()
	return self
end

function Ui:retheme()
	self.background.BackgroundColor3 = color(Enum.StudioStyleGuideColor.MainBackground)
end

function Ui:clear()
	for _, child in self.root:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.order = 0
end

function Ui:_place(gui: GuiObject, parent: Instance?)
	self.order += 1
	gui.LayoutOrder = self.order
	gui.Parent = parent or self.root
end

export type LabelOptions = { parent: Instance?, size: number?, bold: boolean?, dim: boolean?, color: Color3?, code: boolean? }

function Ui:label(text: string, opts: LabelOptions?): TextLabel
	local o = opts or {}
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.TextWrapped = true
	l.RichText = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = if o.code then Enum.Font.Code elseif o.bold then Enum.Font.SourceSansBold else Enum.Font.SourceSans
	l.TextSize = o.size or 15
	l.TextColor3 = o.color or color(if o.dim then Enum.StudioStyleGuideColor.DimmedText else Enum.StudioStyleGuideColor.MainText)
	l.Text = text
	self:_place(l, o.parent)
	return l
end

export type ButtonOptions = { parent: Instance?, style: string?, height: number?, width: number? }

function Ui:button(text: string, onClick: () -> (), opts: ButtonOptions?): TextButton
	local o = opts or {}
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(o.width or 1, if o.width then -4 else 0, 0, o.height or 28)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.SourceSansSemibold
	b.TextSize = 15
	b.Text = text
	b.AutoButtonColor = true
	if o.style == "primary" then
		b.BackgroundColor3, b.TextColor3 = ACCENT, Color3.new(1, 1, 1)
	elseif o.style == "danger" then
		b.BackgroundColor3, b.TextColor3 = DANGER, Color3.new(1, 1, 1)
	else
		b.BackgroundColor3 = color(Enum.StudioStyleGuideColor.Button)
		b.TextColor3 = color(Enum.StudioStyleGuideColor.ButtonText)
	end
	corner(b)
	self:_place(b, o.parent)
	b.MouseButton1Click:Connect(function()
		task.spawn(function()
			local ok, err = pcall(onClick)
			if not ok then
				warn(`[DataGuard] {err}`)
			end
		end)
	end)
	return b
end

function Ui:card(parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color(Enum.StudioStyleGuideColor.Item)
	corner(f, 6)
	padding(f, 8)
	vertical(f, 4)
	self:_place(f, parent)
	return f
end

function Ui:row(parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundTransparency = 1
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, 4)
	l.Parent = f
	self:_place(f, parent)
	return f
end

-- Read-only box the user can select and copy from.
function Ui:codeBox(text: string, parent: Instance?): TextBox
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.TextEditable = false
	box.ClearTextOnFocus = false
	box.MultiLine = true
	box.TextWrapped = true
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.Font = Enum.Font.Code
	box.TextSize = 13
	box.Text = text
	box.BorderSizePixel = 0
	box.BackgroundColor3 = color(Enum.StudioStyleGuideColor.InputFieldBackground)
	box.TextColor3 = color(Enum.StudioStyleGuideColor.MainText)
	corner(box)
	padding(box, 6)
	self:_place(box, parent)
	return box
end

-- Modal dialog. Yields until a button is pressed; returns (button text or nil, field values).
function Ui:dialog(opts: DialogOptions): (string?, { [string]: any })
	if self.closeDialog then
		self.closeDialog(nil)
	end

	local overlay = Instance.new("TextButton") -- swallows clicks behind the dialog
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.ZIndex = 5
	overlay.Parent = self.background

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(1, -24, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = color(Enum.StudioStyleGuideColor.MainBackground)
	panel.BorderSizePixel = 0
	panel.Parent = overlay
	corner(panel, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color(Enum.StudioStyleGuideColor.Border)
	stroke.Parent = panel
	padding(panel, 12)
	vertical(panel, 8)

	self:label(opts.title, { parent = panel, size = 18, bold = true })
	if opts.body then
		self:label(opts.body, { parent = panel })
	end

	local getters: { [string]: () -> any } = {}
	for _, field in opts.fields or {} do
		self:label(field.label, { parent = panel, size = 14, dim = true })
		if field.kind == "toggle" then
			local state = field.value == true
			local b: TextButton
			b = self:button(if state then "Yes" else "No", function()
				state = not state
				b.Text = if state then "Yes" else "No"
			end, { parent = panel })
			getters[field.key] = function()
				return state
			end
		else
			local box = Instance.new("TextBox")
			box.Size = UDim2.new(1, 0, 0, 28)
			box.ClearTextOnFocus = false
			box.Text = if field.value ~= nil then tostring(field.value) else ""
			box.PlaceholderText = field.placeholder or ""
			box.Font = Enum.Font.SourceSans
			box.TextSize = 15
			box.TextXAlignment = Enum.TextXAlignment.Left
			box.BorderSizePixel = 0
			box.BackgroundColor3 = color(Enum.StudioStyleGuideColor.InputFieldBackground)
			box.TextColor3 = color(Enum.StudioStyleGuideColor.MainText)
			box.PlaceholderColor3 = color(Enum.StudioStyleGuideColor.DimmedText)
			corner(box)
			local inner = Instance.new("UIPadding")
			inner.PaddingLeft = UDim.new(0, 6)
			inner.Parent = box
			self:_place(box, panel)
			getters[field.key] = function()
				return box.Text
			end
		end
	end

	local errorLabel = self:label("", { parent = panel, color = ERROR_TEXT })
	errorLabel.Visible = false

	local done = Instance.new("BindableEvent")
	local result: string? = nil
	local values: { [string]: any } = {}
	local closed = false
	local function close(pressed: string?)
		if closed then
			return
		end
		closed = true
		result = pressed
		self.closeDialog = nil
		overlay:Destroy()
		done:Fire()
	end
	self.closeDialog = close

	local buttonRow = self:row(panel)
	local width = 1 / #opts.buttons
	for _, spec in opts.buttons do
		self:button(spec.text, function()
			for key, get in getters do
				values[key] = get()
			end
			if spec.validate and opts.validate then
				local problem = opts.validate(values)
				if problem then
					errorLabel.Text = problem
					errorLabel.Visible = true
					return
				end
			end
			close(spec.text)
		end, { parent = buttonRow, style = spec.style, width = width })
	end

	if not closed then
		done.Event:Wait()
	end
	done:Destroy()
	return result, values
end

return Ui
