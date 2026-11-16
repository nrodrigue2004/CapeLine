-- Plates: a name plate over every other player (spec: The PvP flag "Visible"; Reports "Report on every name
-- plate ... Quick-mute on every plate"; Fame ranks). The plate shows the display name, the Fame or Infamy
-- rank, a PVP tag in the side colour when flagged and DOWNED when Downed. Tapping the plate opens a small
-- menu: REPORT (preset reasons only, no typed text) and MUTE or UNMUTE (hides their chat on this device).
-- The default Roblox name over the head is hidden so only one plate shows. Titles join in M9.
-- PLACEHOLDER look until the UI pass (M10).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = require(script.Parent.Kit)
local PvpClient = require(script.Parent.Parent.Controllers.PvpClient)

local Plates = {}

local player = Players.LocalPlayer
local U = Config.Ui

local gui: ScreenGui
local menu: Frame
local menuTitle: TextLabel
local muteButton: TextButton
local reasonRow: Frame
local menuFor: Player? = nil
local plates: { [Player]: { bb: BillboardGui, name: TextLabel, tag: TextLabel } } = {}

local function closeMenu()
	menu.Visible = false
	reasonRow.Visible = false
	menuFor = nil
end

local function openMenu(p: Player)
	menuFor = p
	menuTitle.Text = string.upper(p.DisplayName)
	muteButton.Text = if PvpClient.muted[p.UserId] then "UNMUTE" else "MUTE"
	reasonRow.Visible = false
	menu.Visible = true
	Kit.bounce(menu)
end

local function refresh(p: Player)
	local pl = plates[p]
	if not pl then
		return
	end
	local bits = {}
	local rank = PvpClient.fameRank(p)
	local side = p:GetAttribute("PvpSide") or p:GetAttribute("Side")
	table.insert(bits, (if side == "villain" then "INFAMY " else "FAME ") .. rank)
	if p:GetAttribute("Pvp") then
		table.insert(bits, "PVP")
		pl.tag.TextColor3 = PvpClient.ringColor(side)
	else
		pl.tag.TextColor3 = Kit.color.paper
	end
	if p:GetAttribute("Downed") then
		table.insert(bits, "DOWNED")
	end
	if PvpClient.muted[p.UserId] then
		table.insert(bits, "MUTED")
	end
	pl.tag.Text = table.concat(bits, "  ")
	pl.name.TextColor3 = if rank >= #Config.Pvp.fame.ranks then Kit.color.gold else Kit.color.paper -- gold trim
end

local function attach(p: Player, char: Model)
	local head = char:WaitForChild("Head", 10) :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local old = plates[p]
	if old then
		old.bb:Destroy()
	end
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "Plate_" .. p.UserId
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(180, 46)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.MaxDistance = 140
	bb.Active = true
	bb.ResetOnSpawn = false
	bb.Parent = gui.Parent
	local button = Instance.new("TextButton")
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.Text = ""
	button.Parent = bb
	button.Activated:Connect(function()
		openMenu(p)
	end)
	local name = Kit.label({
		Text = p.DisplayName,
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.2,
		maxText = 22,
	})
	name.Parent = bb
	local tag = Kit.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 26),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.3,
		Font = Kit.bodyFont,
		maxText = 12,
	})
	tag.Parent = bb
	plates[p] = { bb = bb, name = name, tag = tag }
	refresh(p)
end

local function watch(p: Player)
	if p == player then
		return
	end
	p.CharacterAdded:Connect(function(char)
		attach(p, char)
	end)
	if p.Character then
		task.spawn(attach, p, p.Character)
	end
	for _, attr in { "Pvp", "PvpSide", "Downed", "Fame", "FameRank", "Side" } do
		p:GetAttributeChangedSignal(attr):Connect(function()
			refresh(p)
		end)
	end
end

local function build()
	gui = Kit.screen("Plates", 7)
	menu = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(340, 150),
		Position = UDim2.fromScale(0.5, 0.45),
		BackgroundColor3 = Kit.color.night,
		Visible = false,
	})
	Kit.stroke(menu, Kit.color.paper, 2)
	menu.Parent = gui
	menuTitle = Kit.label({
		Size = UDim2.new(1, -60, 0, 36),
		Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		maxText = 26,
	})
	menuTitle.Parent = menu
	local close = Kit.button({
		Text = "X",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(U.touchTarget - 8, U.touchTarget - 8),
		Position = UDim2.new(1, -6, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, closeMenu)
	close.Parent = menu
	local report = Kit.button({
		Text = "REPORT",
		Size = UDim2.fromOffset(150, U.touchTarget),
		Position = UDim2.fromOffset(12, 56),
		BackgroundColor3 = Color3.fromRGB(240, 110, 90),
	}, function()
		reasonRow.Visible = not reasonRow.Visible
	end)
	report.Parent = menu
	muteButton = Kit.button({
		Text = "MUTE",
		Size = UDim2.fromOffset(150, U.touchTarget),
		Position = UDim2.fromOffset(178, 56),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		local p = menuFor
		if p then
			PvpClient.mute(p.UserId, not PvpClient.muted[p.UserId])
			muteButton.Text = if PvpClient.muted[p.UserId] then "UNMUTE" else "MUTE"
			refresh(p)
		end
	end)
	muteButton.Parent = menu
	-- the preset reasons (no typed text)
	reasonRow = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(340, U.touchTarget * 2 + 12),
		Position = UDim2.new(0.5, 0, 1, 8),
		BackgroundColor3 = Kit.color.night,
		Visible = false,
	})
	reasonRow.Parent = menu
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(160, U.touchTarget - 4)
	grid.CellPadding = UDim2.fromOffset(8, 6)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = reasonRow
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.Parent = reasonRow
	for i, reason in Config.Pvp.report.reasons do
		local b = Kit.button(
			{ Text = string.upper(reason), BackgroundColor3 = Kit.color.paper, maxText = 16 },
			function()
				local p = menuFor
				if p then
					PvpClient.report(p.UserId, i)
				end
				closeMenu()
			end
		)
		b.Parent = reasonRow
	end
end

function Plates.init()
	build()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		local pl = plates[p]
		if pl then
			pl.bb:Destroy()
			plates[p] = nil
		end
		if menuFor == p then
			closeMenu()
		end
	end)
	PvpClient.MutesChanged:Connect(function()
		for p in plates do
			refresh(p)
		end
	end)
end

return Plates
