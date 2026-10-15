-- PvP Panel (solo interfaz). Estilo negro/ámbar del hub.
-- Uso:
--   local Panel = loadstring(readfile("pvp/panel.luau"))()
--   local ui = Panel.new({ stages = {"Stage 1","Stage 2","Stage 3"}, pauseKey = Enum.KeyCode.F8 })
--   ui:OnToggle(function(on) end); ui:OnStage(function(index, name) end); ui:OnPause(function(paused) end)
--   ui:SetStatus("texto"); ui:SetEnabled(true); ui:SetStage(2); ui:SetPaused(false); ui:Destroy()
-- Si hay un panel anterior en getgenv().PvpPanel se destruye antes de crear el nuevo.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local env = (getgenv and getgenv()) or _G

local BLACK, PANEL, EDGE = Color3.fromRGB(10, 10, 10), Color3.fromRGB(18, 17, 15), Color3.fromRGB(52, 42, 20)
local AMBER, AMBER_DIM, TEXT, MUTED = Color3.fromRGB(255, 176, 32), Color3.fromRGB(120, 82, 14), Color3.fromRGB(235, 225, 205), Color3.fromRGB(140, 128, 105)
local RED = Color3.fromRGB(220, 70, 50)
local FONT, FONT_B = Enum.Font.Gotham, Enum.Font.GothamBold

local Panel = {}
Panel.__index = Panel

local function mount(gui)
	local ok = pcall(function()
		if gethui then gui.Parent = gethui() else error("x") end
        assert(gui.Parent ~= nil, "gethui returned nil")
	end)
	if not ok then
		ok = pcall(function()
            gui.Parent = game:GetService("CoreGui")
            assert(gui.Parent ~= nil, "CoreGui mount failed")
        end)
	end
	if not ok then
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end
end

local function tween(obj, props, t)
	TweenService:Create(obj, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = parent
	return c
end

local function stroke(parent, color, th)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = th or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function label(parent, text, size, color, font, pos, sz, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Font = font
	l.Position = pos
	l.Size = sz
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function fire(list, ...)
	for _, cb in ipairs(list) do
		task.spawn(cb, ...)
	end
end

function Panel.new(opts)
	opts = opts or {}
	if env.PvpPanel and env.PvpPanel.Destroy then
		pcall(function() env.PvpPanel:Destroy() end)
	end

	local self = setmetatable({}, Panel)
	self.stages = opts.stages or { "Stage 1", "Stage 2", "Stage 3" }
	self.pauseKey = opts.pauseKey or Enum.KeyCode.F8
	self.enabled = opts.enabled == true
	self.paused = false
	self.stage = opts.stage or 1
	self._cbToggle, self._cbStage, self._cbPause = {}, {}, {}
	self._conns = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "PvpPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	mount(gui)
	self.gui = gui

	local n = #self.stages
	local height = 124 + n * 30 + 8

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromOffset(230, height)
	root.Position = opts.position or UDim2.new(0, 16, 0.5, -height / 2)
	root.BackgroundColor3 = BLACK
	root.BorderSizePixel = 0
	root.Active = true
	root.Parent = gui
	corner(root, 8)
	stroke(root, EDGE, 1)
	self.root = root

	-- barra ámbar superior fina
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -16, 0, 2)
	bar.Position = UDim2.fromOffset(8, 0)
	bar.BackgroundColor3 = AMBER
	bar.BorderSizePixel = 0
	bar.Parent = root
	self.bar = bar

	-- cabecera (arrastrable)
	local head = Instance.new("Frame")
	head.Size = UDim2.new(1, 0, 0, 34)
	head.BackgroundTransparency = 1
	head.Parent = root
	label(head, "PVP", 14, AMBER, FONT_B, UDim2.fromOffset(14, 0), UDim2.new(0, 60, 1, 0))
	self.pauseTag = label(head, "", 11, RED, FONT_B, UDim2.new(1, -150, 0, 0), UDim2.fromOffset(136, 34), Enum.TextXAlignment.Right)

	local dragging, dragStart, startPos
	table.insert(self._conns, head.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, i.Position, root.Position
		end
	end))
	table.insert(self._conns, UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	table.insert(self._conns, UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	-- toggle principal
	local toggle = Instance.new("TextButton")
	toggle.Size = UDim2.new(1, -24, 0, 38)
	toggle.Position = UDim2.fromOffset(12, 40)
	toggle.AutoButtonColor = false
	toggle.Font = FONT_B
	toggle.TextSize = 13
	toggle.BorderSizePixel = 0
	toggle.Parent = root
	corner(toggle, 6)
	self.toggleStroke = stroke(toggle, AMBER_DIM, 1)
	self.toggle = toggle

	-- sección stages
	label(root, "STAGES", 10, MUTED, FONT_B, UDim2.fromOffset(14, 86), UDim2.new(1, -28, 0, 14))
	self.stageButtons = {}
	for idx, name in ipairs(self.stages) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -24, 0, 26)
		b.Position = UDim2.fromOffset(12, 104 + (idx - 1) * 30)
		b.AutoButtonColor = false
		b.Font = FONT
		b.TextSize = 12
		b.Text = name
		b.BorderSizePixel = 0
		b.Parent = root
		corner(b, 5)
		local s = stroke(b, EDGE, 1)
		self.stageButtons[idx] = { btn = b, stroke = s }
		table.insert(self._conns, b.MouseButton1Click:Connect(function()
			self:SetStage(idx)
		end))
		table.insert(self._conns, b.MouseEnter:Connect(function()
			if self.stage ~= idx then tween(b, { BackgroundColor3 = Color3.fromRGB(34, 28, 16) }) end
		end))
		table.insert(self._conns, b.MouseLeave:Connect(function()
			if self.stage ~= idx then tween(b, { BackgroundColor3 = PANEL }) end
		end))
	end

	-- pie: estado + pausa
	self.status = label(root, "", 11, MUTED, FONT, UDim2.new(0, 14, 1, -26), UDim2.new(1, -28, 0, 18))
	self.status.TextTruncate = Enum.TextTruncate.AtEnd

	table.insert(self._conns, toggle.MouseButton1Click:Connect(function()
		self:SetEnabled(not self.enabled)
	end))

	table.insert(self._conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == self.pauseKey then
			self:SetPaused(not self.paused)
		end
	end))

	self:_render(true)
	self:SetStatus("Pausa: " .. self.pauseKey.Name)
	env.PvpPanel = self
	return self
end

function Panel:_render(instant)
	local t = instant and 0 or 0.15
	local on = self.enabled
	self.toggle.Text = on and "ACTIVO" or "APAGADO"
	tween(self.toggle, {
		BackgroundColor3 = on and AMBER or PANEL,
		TextColor3 = on and BLACK or AMBER,
	}, t)
	self.toggleStroke.Color = on and AMBER or AMBER_DIM
	for idx, e in ipairs(self.stageButtons) do
		local sel = idx == self.stage
		tween(e.btn, {
			BackgroundColor3 = sel and AMBER_DIM or PANEL,
			TextColor3 = sel and TEXT or MUTED,
		}, t)
		e.stroke.Color = sel and AMBER or EDGE
		e.btn.Font = sel and FONT_B or FONT
	end
	self.pauseTag.Text = self.paused and ("PAUSA (" .. self.pauseKey.Name .. ")") or ""
	tween(self.bar, { BackgroundColor3 = self.paused and RED or AMBER, BackgroundTransparency = on and 0 or 0.6 }, t)
end

function Panel:SetEnabled(on, silent)
	on = on and true or false
	if self.enabled == on then return end
	self.enabled = on
	self:_render()
	if not silent then fire(self._cbToggle, on) end
end

function Panel:SetStage(idx, silent)
	if type(idx) ~= "number" or not self.stageButtons[idx] then return end
	if self.stage == idx then return end
	self.stage = idx
	self:_render()
	if not silent then fire(self._cbStage, idx, self.stages[idx]) end
end

function Panel:SetPaused(p, silent)
	p = p and true or false
	if self.paused == p then return end
	self.paused = p
	self:_render()
	if not silent then fire(self._cbPause, p) end
end

function Panel:IsEnabled() return self.enabled end
function Panel:IsPaused() return self.paused end
function Panel:GetStage() return self.stage, self.stages[self.stage] end
-- activo y sin pausa: lo que la lógica debe mirar antes de actuar
function Panel:IsRunning() return self.enabled and not self.paused end

function Panel:SetStatus(text)
	self.status.Text = tostring(text or "")
end

function Panel:SetVisible(v)
	self.gui.Enabled = v and true or false
end

function Panel:OnToggle(cb) table.insert(self._cbToggle, cb) end
function Panel:OnStage(cb) table.insert(self._cbStage, cb) end
function Panel:OnPause(cb) table.insert(self._cbPause, cb) end

function Panel:Destroy()
	for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
	self._conns = {}
	if self.gui then self.gui:Destroy() end
	if env.PvpPanel == self then env.PvpPanel = nil end
end

return Panel
