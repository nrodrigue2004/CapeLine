-- Plates: a name plate over every other player (spec: The PvP flag "Visible"; Reports "Report on every name
-- plate ... Quick-mute on every plate"; Fame ranks). The plate shows the display name, the Fame or Infamy
-- rank, a PVP tag in the side colour when flagged and DOWNED when Downed. Tapping the plate opens a small
-- menu: REPORT (preset reasons only, no typed text) and MUTE or UNMUTE (hides their chat on this device).
-- The default Roblox name over the head is hidden so only one plate shows. M9: the hero name (Title + Noun)
-- is big, the Roblox display name sits small under it (so reports always name the player), with a star
-- per Legacy rank.
-- PLACEHOLDER look until the UI pass (M10).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = require(script.Parent.Kit)
local PvpClient = require(script.Parent.Parent.Controllers.PvpClient)
local SquadClient = require(script.Parent.Parent.Controllers.SquadClient)
local PhaseClient = require(script.Parent.Parent.Controllers.PhaseClient) -- "Hide you fully" (nate, 2026-11-20)

local Plates = {}

local player = Players.LocalPlayer
local U = Config.Ui

local gui: ScreenGui
local menu: Frame
local menuTitle: TextLabel
local muteButton: TextButton
local squadButton: TextButton
local reasonRow: Frame
local menuFor: Player? = nil
local reportButton: TextButton
local plates: { [Player]: { bb: BillboardGui, name: TextLabel, who: TextLabel, tag: TextLabel } } = {}

-- The report reasons take the place of REPORT, MUTE and INVITE inside the menu (under it, the row was off a
-- phone's screen)
local function showReasons(on: boolean)
	reasonRow.Visible = on
	reportButton.Visible = not on
	muteButton.Visible = not on
	squadButton.Visible = not on
end

local function closeMenu()
	menu.Visible = false
	showReasons(false)
	menuFor = nil
end

local function openMenu(p: Player)
	menuFor = p
	menuTitle.Text = string.upper(p.DisplayName)
	muteButton.Text = if PvpClient.muted[p.UserId] then "UNMUTE" else "MUTE"
	local mate = SquadClient.isMate(p)
	squadButton.Text = if mate
		then "IN YOUR SQUAD"
		elseif p:GetAttribute("Squad") then "IN A SQUAD"
		else "INVITE TO SQUAD"
	squadButton.AutoButtonColor = not mate and p:GetAttribute("Squad") == nil
	showReasons(false)
	menu.Visible = true
	Kit.bounce(menu)
end

-- H7: accolade plate trims by id (Config.Badges groups whose accolade is a trim)
local TRIMS: { [string]: { number } } = {}
for _, g in Config.Badges.groups do
	if g.accolade and g.accolade.kind == "trim" then
		TRIMS[g.accolade.id] = g.accolade.color
	end
end
for _, t in Config.Pass.trims do -- H8: the Hero Pass's plate trims
	TRIMS[t.id] = t.color
end

local function refresh(p: Player)
	local pl = plates[p]
	if not pl then
		return
	end
	-- a hero in another phase (a private mission run's, or the open world's seen from inside one) has no plate here
	pl.bb.Enabled = PhaseClient.seesPlayer(p)
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
	-- H4: a sidekick inside a mission pocket (raised to the mission level minus 1)
	if p:GetAttribute("Sidekick") then
		table.insert(bits, 1, "★ " .. Config.Sidekick.badge)
	end
	if PvpClient.muted[p.UserId] then
		table.insert(bits, "MUTED")
	end
	-- M10: squadmates carry the squad emblem in their slot colour
	if SquadClient.isMate(p) then
		local e = SquadClient.state.emblem
		table.insert(bits, 1, (if e then e.glyph .. " " else "") .. "SQUAD")
		local slot = SquadClient.slotOf(p)
		local c = Config.Squad.colors[slot or 1] or Config.Squad.colors[1]
		pl.tag.TextColor3 = Color3.fromRGB(c[1], c[2], c[3])
	end
	pl.tag.Text = table.concat(bits, "  ")
	local hero = p:GetAttribute("HeroName")
	local legacy = p:GetAttribute("Legacy")
	local stars = if typeof(legacy) == "number" and legacy > 0
		then "  " .. string.rep("★", math.min(legacy, 5))
		else ""
	-- lore step 2: the origin's title ("Lab-Born") before the player's name
	-- H7: the title picked in the Badge Book replaces it (fixed text only)
	local picked = p:GetAttribute("Title")
	local origin = if typeof(picked) == "string" and picked ~= ""
		then picked
		else p:GetAttribute("OriginTitle")
	local title = if typeof(origin) == "string" and origin ~= "" then origin .. "  " else ""
	if typeof(hero) == "string" and hero ~= "" then
		pl.name.Text = string.upper(hero)
		pl.who.Text = title .. "@" .. p.DisplayName .. stars
	else
		pl.name.Text = p.DisplayName
		pl.who.Text = stars
	end
	pl.name.TextColor3 = if rank >= #Config.Pvp.fame.ranks then Kit.color.gold else Kit.color.paper -- gold trim
	-- H7: an accolade plate trim (a finished badge group) outlines the name in its colour
	local trim = TRIMS[p:GetAttribute("PlateTrim") :: any]
	local stroke = pl.name:FindFirstChild("AccoladeTrim") :: UIStroke?
	if trim and not stroke then
		local st = Instance.new("UIStroke")
		st.Name = "AccoladeTrim"
		st.Thickness = 2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		st.Parent = pl.name
		stroke = st
	end
	if stroke then
		stroke.Enabled = trim ~= nil
		if trim then
			stroke.Color = Color3.fromRGB(trim[1], trim[2], trim[3])
		end
	end
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
	bb.Size = UDim2.fromOffset(190, 62)
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
	local who = Kit.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 26),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.3,
		Font = Kit.bodyFont,
		maxText = 11,
	})
	who.Parent = bb
	local tag = Kit.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 43),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.3,
		Font = Kit.bodyFont,
		maxText = 12,
	})
	tag.Parent = bb
	plates[p] = { bb = bb, name = name, who = who, tag = tag }
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
	for _, attr in
		{
			"Pvp",
			"PvpSide",
			"Downed",
			"Fame",
			"FameRank",
			"Side",
			"HeroName",
			"Legacy",
			"OriginTitle",
			"Title",
			"PlateTrim",
			"Squad",
			"SquadSlot",
			"Sidekick",
			"Phase",
		}
	do
		p:GetAttributeChangedSignal(attr):Connect(function()
			refresh(p)
		end)
	end
end

local function build()
	gui = Kit.screen("Plates", 7)
	menu = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(340, 150 + U.touchTarget + 8),
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
	reportButton = Kit.button({
		Text = "REPORT",
		Size = UDim2.fromOffset(150, U.touchTarget),
		Position = UDim2.fromOffset(12, 56),
		BackgroundColor3 = Color3.fromRGB(240, 110, 90),
	}, function()
		showReasons(true)
	end)
	reportButton.Parent = menu
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
	squadButton = Kit.button({
		Text = "INVITE TO SQUAD",
		Size = UDim2.fromOffset(316, U.touchTarget),
		Position = UDim2.fromOffset(12, 64 + U.touchTarget),
		BackgroundColor3 = Kit.color.gold,
	}, function()
		local p = menuFor
		if p and not SquadClient.isMate(p) and p:GetAttribute("Squad") == nil then
			SquadClient.invite(p.UserId)
			closeMenu()
		end
	end)
	squadButton.Parent = menu
	-- the preset reasons (no typed text), in the menu under its title
	reasonRow = Kit.frame({
		Name = "Reasons",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(1, 0, 0, U.touchTarget * 2 + 12),
		Position = UDim2.new(0.5, 0, 0, 48),
		BackgroundTransparency = 1,
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
	SquadClient.Changed:Connect(function()
		for p in plates do
			refresh(p)
		end
	end)
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
	player:GetAttributeChangedSignal("Phase"):Connect(function()
		for p in plates do
			refresh(p)
		end
	end)
	PvpClient.MutesChanged:Connect(function()
		for p in plates do
			refresh(p)
		end
	end)
end

return Plates
