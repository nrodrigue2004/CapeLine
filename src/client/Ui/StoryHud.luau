-- StoryHud: the story on screen (spec: The opening; First 30 seconds; Suit up; Act 1; Side quests).
-- * The cinematic: 4 comic panels over 20 seconds (the comet, two rooftop silhouettes, the shadow over the
--   moon, down to the street), skippable after 2 s. The opening runs underneath, so a skip never skips the
--   control hand-off or the first incident.
-- * The opening: the HUD shows only the step's verb button (Hud.setFocus), a marker shows where to go, and
--   other screens stay hidden; the sky holds at dusk (StoryClient). No words except verb buttons.
-- * The choice card: two (or three) big verb buttons.
-- * Suit Up: the hero creator (CreatorScreen, M9) opens with the side the choice picked.
-- * Missions: a fade on each trip, the objective tracker with a LEAVE button, and the result card.
-- * Side quests: the NPC's speech bubble and the pinned step's tracker, with its marker or search circle.
-- PLACEHOLDER ART: the cinematic panels are flat shapes until the art pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))

local Kit = require(script.Parent.Kit)
local CreatorScreen = require(script.Parent.CreatorScreen)
local Hud = require(script.Parent.Hud)
local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local InputController = require(script.Parent.Parent.Controllers.InputController)

local StoryHud = {}

local S = Config.Story
local U = Config.Ui
local player = Players.LocalPlayer

local gui: ScreenGui
local fade: Frame
local choiceCard: Frame
local tracker: Frame
local trackTitle: TextLabel
local trackText: TextLabel
local trackFill: Frame
local leaveButton: TextButton
local resultCard: Frame
local bubble: Frame
local questPanel: Frame
local questTitle: TextLabel
local questText: TextLabel
local questFill: Frame
local skipFlight: TextButton
local markerPart: Part
local markerGui: BillboardGui
local markerText: TextLabel
local areaPart: Part

local HIDE_IN_OPENING = { "WorldHud", "ContractBoard", "Gear", "Loadout", "Map" }

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

---------------------------------------------------------------------------
-- The cinematic (PLACEHOLDER ART: flat comic panels)
---------------------------------------------------------------------------

local function panel(parent: Instance, color: Color3): Frame
	local f = Kit.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		round = false,
		Visible = false,
	})
	f.Parent = parent
	return f
end

local function shape(parent: Instance, color: Color3, pos: UDim2, size: UDim2, round: number?): Frame
	local f = Kit.frame({
		Position = pos,
		Size = size,
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		round = false,
	})
	if round then
		Kit.round(f, round)
	end
	f.Parent = parent
	return f
end

local function playCinematic()
	local layer = Kit.frame({
		Name = "Cinematic",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		round = false,
		ZIndex = 50,
	})
	layer.Parent = gui
	local sky = Color3.fromRGB(14, 16, 40)
	local beats = {}
	-- 1: the comet breaking, the title card
	local p1 = panel(layer, sky)
	local comet =
		shape(p1, Color3.fromRGB(255, 240, 180), UDim2.fromScale(0.2, 0.2), UDim2.fromOffset(28, 28), 14)
	local tail =
		shape(p1, Color3.fromRGB(120, 210, 255), UDim2.fromScale(0.12, 0.12), UDim2.fromOffset(140, 6))
	tail.Rotation = 35
	local title = Kit.label({
		Text = "CAPELINE",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromScale(0.7, 0.16),
		TextColor3 = Kit.color.gold,
		TextStrokeTransparency = 0,
		TextTransparency = 1,
		maxText = 96,
	})
	title.Parent = p1
	table.insert(beats, {
		frame = p1,
		run = function(len)
			TweenService:Create(comet, TweenInfo.new(len), { Position = UDim2.fromScale(0.62, 0.42) }):Play()
			TweenService:Create(tail, TweenInfo.new(len), { Position = UDim2.fromScale(0.52, 0.34) }):Play()
			TweenService:Create(title, TweenInfo.new(1.2), { TextTransparency = 0 }):Play()
		end,
	})
	-- 2: shards fall; a hero silhouette and a masked silhouette on two rooftops
	local p2 = panel(layer, Color3.fromRGB(26, 22, 54))
	shape(p2, Color3.fromRGB(10, 10, 18), UDim2.fromScale(0.2, 0.86), UDim2.fromScale(0.34, 0.3))
	shape(p2, Color3.fromRGB(10, 10, 18), UDim2.fromScale(0.8, 0.84), UDim2.fromScale(0.34, 0.34))
	shape(p2, rgb(U.colors.league), UDim2.fromScale(0.2, 0.62), UDim2.fromOffset(18, 46), 6)
	shape(p2, rgb(U.colors.syndicate), UDim2.fromScale(0.8, 0.6), UDim2.fromOffset(18, 46), 6)
	local shards = {}
	for i = 1, 6 do
		local s = shape(
			p2,
			Color3.fromRGB(150, 230, 255),
			UDim2.fromScale(0.15 + i * 0.12, -0.05),
			UDim2.fromOffset(6, 16)
		)
		s.Rotation = 20
		table.insert(shards, s)
	end
	table.insert(beats, {
		frame = p2,
		run = function(len)
			for i, s in shards do
				TweenService:Create(s, TweenInfo.new(len * (0.6 + i * 0.05)), {
					Position = UDim2.fromScale(0.1 + i * 0.12, 0.75),
				}):Play()
			end
		end,
	})
	-- 3: the city flickers; a huge shadow crosses the moon
	local p3 = panel(layer, Color3.fromRGB(20, 20, 34))
	local moon =
		shape(p3, Color3.fromRGB(235, 235, 210), UDim2.fromScale(0.5, 0.35), UDim2.fromOffset(180, 180), 90)
	local shadow =
		shape(p3, Color3.fromRGB(8, 8, 12), UDim2.fromScale(-0.2, 0.36), UDim2.fromOffset(150, 220), 30)
	for i = 0, 7 do
		shape(
			p3,
			Color3.fromRGB(255, 220, 120),
			UDim2.fromScale(0.08 + i * 0.12, 0.88),
			UDim2.fromOffset(10, 10)
		)
	end
	table.insert(beats, {
		frame = p3,
		run = function(len)
			TweenService:Create(shadow, TweenInfo.new(len), { Position = UDim2.fromScale(1.2, 0.34) }):Play()
			TweenService
				:Create(moon, TweenInfo.new(len), { BackgroundColor3 = Color3.fromRGB(200, 120, 120) })
				:Play()
		end,
	})
	-- 4: down to the street, then the hand-off
	local p4 = panel(layer, Color3.fromRGB(255, 160, 90))
	shape(p4, Color3.fromRGB(60, 40, 60), UDim2.fromScale(0.5, 0.8), UDim2.fromScale(1, 0.4))
	table.insert(beats, {
		frame = p4,
		run = function(len)
			TweenService:Create(p4, TweenInfo.new(len), { BackgroundTransparency = 1 }):Play()
		end,
	})
	local skip = Kit.button({
		Text = "SKIP",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -U.safe, 1, -U.safe),
		Size = UDim2.fromOffset(U.touchTarget * 2, U.touchTarget),
		BackgroundColor3 = Kit.color.paper,
		Visible = false,
		ZIndex = 60,
	})
	skip.Parent = layer
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		TweenService:Create(layer, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		for _, d in layer:GetDescendants() do
			if d:IsA("GuiObject") then
				d.Visible = false
			end
		end
		task.delay(0.45, function()
			layer:Destroy()
		end)
	end
	skip.Activated:Connect(finish)
	task.delay(S.cinematic.skipAfter, function()
		if not done then
			skip.Visible = true
		end
	end)
	task.spawn(function()
		for i, beat in S.cinematic.beats do
			if done then
				return
			end
			for j, b in beats do
				b.frame.Visible = j == i
			end
			beats[i].run(beat.len)
			task.wait(beat.len)
		end
		finish()
	end)
end

---------------------------------------------------------------------------
-- The marker (the step's target) and the search circle
---------------------------------------------------------------------------

local function buildMarker()
	markerPart = Instance.new("Part")
	markerPart.Name = "StoryMarker"
	markerPart.Anchored = true
	markerPart.CanCollide = false
	markerPart.CanQuery = false
	markerPart.CanTouch = false
	markerPart.Transparency = 1
	markerPart.Size = Vector3.one
	markerPart.Parent = Workspace
	markerGui = Instance.new("BillboardGui")
	markerGui.AlwaysOnTop = true
	markerGui.LightInfluence = 0
	markerGui.Size = UDim2.fromOffset(80, 56)
	markerGui.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
	markerGui.Adornee = markerPart
	markerGui.Enabled = false
	markerGui.Parent = markerPart
	local diamond = Kit.frame({
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(0.5, -13, 0, 0),
		BackgroundColor3 = Kit.color.gold,
		round = false,
	})
	diamond.Rotation = 45
	Kit.stroke(diamond, Kit.color.ink, 2)
	diamond.Parent = markerGui
	markerText = Kit.label({
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 34),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.2,
		Font = Kit.bodyFont,
		maxText = 13,
	})
	markerText.Parent = markerGui
	areaPart = Instance.new("Part")
	areaPart.Name = "SearchArea"
	areaPart.Anchored = true
	areaPart.CanCollide = false
	areaPart.CanQuery = false
	areaPart.CanTouch = false
	areaPart.Shape = Enum.PartType.Cylinder
	areaPart.Material = Enum.Material.Neon
	areaPart.Color = Kit.color.gold
	areaPart.Transparency = 1
	areaPart.Parent = Workspace
end

local function setMarker(t: { number }?, showDistance: boolean)
	if not t then
		markerGui.Enabled = false
		return
	end
	markerPart.CFrame = CFrame.new(t[1], t[2], t[3])
	markerGui.Enabled = true
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if showDistance and root then
		markerText.Text =
			string.format("%d studs", math.floor((root.Position - markerPart.Position).Magnitude))
	else
		markerText.Text = ""
	end
end

---------------------------------------------------------------------------
-- Choice card, trackers, result, bubble
---------------------------------------------------------------------------

local function refreshChoice()
	for _, c in choiceCard:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local c = StoryClient.choice
	choiceCard.Visible = c ~= nil
	if not c then
		return
	end
	for i, label in c.labels do
		local b = Kit.button({
			Text = string.upper(label),
			Size = UDim2.new(1 / #c.labels, -12, 1, 0),
			LayoutOrder = i,
			BackgroundColor3 = if i == 1 then rgb(U.colors.league) else rgb(U.colors.syndicate),
			TextColor3 = Kit.color.paper,
			maxText = 34,
		}, function()
			StoryClient.pick(i)
		end)
		if c.id == 4 then
			b.BackgroundColor3 = Kit.color.gold
			b.TextColor3 = Kit.color.ink
		end
		b.Parent = choiceCard
		Kit.pulse(b, 0.2)
	end
end

local function buildTracker(name: string, y: number): (Frame, TextLabel, TextLabel, Frame)
	local f = Kit.frame({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(0.6, 0, 0, 64),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(420, 64)
	limit.Parent = f
	f.Parent = gui
	local title = Kit.label({
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 4),
		TextColor3 = Kit.color.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 20,
	})
	title.Parent = f
	local text = Kit.label({
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(8, 26),
		TextColor3 = Kit.color.paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Kit.bodyFont,
		maxText = 15,
	})
	text.Parent = f
	local bar = Kit.frame({
		Size = UDim2.new(1, -16, 0, 8),
		Position = UDim2.fromOffset(8, 50),
		BackgroundColor3 = Kit.color.muted,
	})
	bar.Parent = f
	local fill = Kit.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = Kit.color.gold })
	fill.Parent = bar
	return f, title, text, fill
end

local function missionName(num: number, side: string): string
	local m = S.missions[num]
	if not m then
		return ""
	end
	return if side == "villain" and m.villainName then m.villainName else m.name
end

local function showResult(r: { [string]: any })
	for _, c in resultCard:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local side = State.hero.side
	local lines = {
		{ string.format("%s CLEAR!", string.upper(missionName(r.num or 0, side))), Kit.color.gold, 34 },
		{
			string.format("+%s CREDITS   +%s RENOWN", Kit.comma(r.credits or 0), Kit.comma(r.renown or 0)),
			Kit.color.paper,
			20,
		},
	}
	if r.first then
		if (r.drops or 0) > 0 then
			table.insert(lines, { string.format("%d NEW GEAR", r.drops), Kit.color.paper, 18 })
		end
		if r.skillPoints then
			table.insert(lines, { string.format("+%d SKILL POINT", r.skillPoints), Kit.color.gold, 18 })
		end
		if r.rep then
			table.insert(lines, { string.format("+%d REPUTATION", r.rep), Kit.color.paper, 16 })
		end
		if r.epic then
			table.insert(lines, { "THE EPIC CRATE OPENED!", Color3.fromRGB(200, 120, 255), 20 })
		end
	else
		table.insert(lines, { "Replay: first-clear rewards already earned", Kit.color.muted, 14 })
	end
	for i, line in lines do
		local l = Kit.label({
			Text = line[1],
			Size = UDim2.new(1, -20, 0, if i == 1 then 44 else 26),
			LayoutOrder = i,
			TextColor3 = line[2],
			maxText = line[3],
		})
		l.Parent = resultCard
	end
	resultCard.Visible = true
	Kit.pulse(resultCard, 0.2)
	task.delay(5.5, function()
		resultCard.Visible = false
	end)
end

local bubbleUntil = 0
local function showTalk(num: number, line: number, side: string)
	local q = S.quests[num]
	if not q then
		return
	end
	local name = StoryPlan.npcName(Config, num, side)
	local text = if line >= 1 and line <= 3 then q.lines[line] else "Thanks again, friend!"
	local title = bubble:FindFirstChild("Name") :: TextLabel
	local body = bubble:FindFirstChild("Line") :: TextLabel
	title.Text = string.upper(name)
	body.Text = text
	bubble.Visible = true
	Kit.pulse(bubble, 0.15)
	bubbleUntil = os.clock() + 5
end

---------------------------------------------------------------------------
-- Each frame
---------------------------------------------------------------------------

local lastStep = ""
local function refreshOpening()
	local step = StoryClient.openingStep()
	local inOpening = StoryClient.inOpening()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, name in HIDE_IN_OPENING do
			local g = pg:FindFirstChild(name) :: ScreenGui?
			if g then
				g.Enabled = not inOpening
			end
		end
	end
	if inOpening and step then
		Hud.setFocus(StoryClient.VERBS[step] or {})
	elseif Hud.focused() then
		Hud.setFocus(nil)
	end
	-- Suit Up is the hero creator (M9): the side the choice picked comes in preset
	if step == "suitup" and lastStep ~= "suitup" then
		CreatorScreen.open({ mode = "create", side = StoryClient.opening.side or State.hero.side })
	elseif step ~= "suitup" and lastStep == "suitup" then
		CreatorScreen.closeMode("create")
	end
	skipFlight.Visible = step == "flight"
	if step == "leap" and lastStep == "" then
		playCinematic()
	end
	lastStep = step or ""
end

local function frame()
	local now = os.clock()
	local o = StoryClient.opening
	local step = StoryClient.openingStep()
	local m = StoryClient.mission
	local q = StoryClient.quest
	-- the marker: the opening's step, else the mission's, else the pinned quest's
	if step and step ~= "suitup" then
		setMarker(o.target, step == "flight")
	elseif (m.num or 0) > 0 and not m.done then
		setMarker(m.target, true)
	elseif q and q.target then
		setMarker(q.target, true)
	else
		setMarker(nil, false)
	end
	-- the find step's search circle
	local area = q and q.area
	if area and not StoryClient.inMission() then
		local y = Config.City.ground.y + 0.3
		areaPart.Size = Vector3.new(0.4, area[3] * 2, area[3] * 2)
		areaPart.CFrame = CFrame.new(area[1], y, area[2]) * CFrame.Angles(0, 0, math.rad(90))
		areaPart.Transparency = 0.8
	else
		areaPart.Transparency = 1
	end
	-- the mission tracker
	if (m.num or 0) > 0 then
		tracker.Visible = true
		trackTitle.Text =
			string.format("MISSION %d: %s", m.num, string.upper(missionName(m.num, State.hero.side)))
		trackText.Text = string.format("%s  (%d/%d)", m.text or "", m.step or 1, m.steps or 1)
		trackFill.Size = UDim2.fromScale(math.clamp((m.have or 0) / math.max(1, m.need or 1), 0, 1), 1)
		leaveButton.Visible = not m.done
	else
		tracker.Visible = false
	end
	-- the side quest tracker (not in a mission)
	if q and not StoryClient.inMission() and not StoryClient.inOpening() then
		local def = S.quests[q.num]
		local st = def and def.steps[q.step]
		questPanel.Visible = def ~= nil
		if def and st then
			questTitle.Text = string.format(
				"%s  %d/3",
				string.upper(StoryPlan.npcName(Config, q.num, State.hero.side)),
				q.step
			)
			local left = if q.left then q.left - (now - (q.received or now)) else nil
			questText.Text = st.text
				.. (if left then string.format("  %ds", math.max(0, math.ceil(left))) else "")
			questFill.Size = UDim2.fromScale(math.clamp((q.have or 0) / math.max(1, q.need or 1), 0, 1), 1)
		end
	else
		questPanel.Visible = false
	end
	if bubble.Visible and now > bubbleUntil then
		bubble.Visible = false
	end
end

function StoryHud.init()
	gui = Kit.screen("StoryHud", 7)
	fade = Kit.frame({
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		round = false,
		ZIndex = 40,
	})
	fade.Parent = gui
	choiceCard = Kit.frame({
		Name = "Choice",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -170),
		Size = UDim2.new(0.86, 0, 0, U.touchTarget + 30),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 15,
	})
	local climit = Instance.new("UISizeConstraint")
	climit.MaxSize = Vector2.new(560, U.touchTarget + 30)
	climit.Parent = choiceCard
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Padding = UDim.new(0, 12)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = choiceCard
	choiceCard.Parent = gui
	tracker, trackTitle, trackText, trackFill = buildTracker("Mission", 64)
	leaveButton = Kit.button({
		Text = "LEAVE",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 4),
		Size = UDim2.fromOffset(70, 26),
		BackgroundColor3 = Kit.color.paper,
		maxText = 16,
	}, StoryClient.leave)
	leaveButton.Parent = tracker
	trackTitle.Size = UDim2.new(1, -90, 0, 22)
	questPanel, questTitle, questText, questFill = buildTracker("Quest", 136)
	resultCard = Kit.frame({
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(0.8, 0, 0, 200),
		BackgroundColor3 = Kit.color.night,
		Visible = false,
		ZIndex = 18,
	})
	local rlimit = Instance.new("UISizeConstraint")
	rlimit.MaxSize = Vector2.new(480, 200)
	rlimit.Parent = resultCard
	local rlist = Instance.new("UIListLayout")
	rlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rlist.SortOrder = Enum.SortOrder.LayoutOrder
	rlist.Padding = UDim.new(0, 4)
	rlist.Parent = resultCard
	Kit.stroke(resultCard, Kit.color.gold, 3)
	resultCard.Parent = gui
	bubble = Kit.frame({
		Name = "Talk",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -200),
		Size = UDim2.new(0.8, 0, 0, 74),
		BackgroundColor3 = Kit.color.paper,
		Visible = false,
	})
	local blimit = Instance.new("UISizeConstraint")
	blimit.MaxSize = Vector2.new(460, 74)
	blimit.Parent = bubble
	Kit.stroke(bubble, Kit.color.ink, 3)
	bubble.Parent = gui
	local bname = Kit.label({
		Name = "Name",
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.fromOffset(8, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.ink,
		maxText = 20,
	})
	bname.Parent = bubble
	local bline = Kit.label({
		Name = "Line",
		Size = UDim2.new(1, -16, 0, 36),
		Position = UDim2.fromOffset(8, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.ink,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 18,
	})
	bline.Parent = bubble
	skipFlight = Kit.button({
		Text = "SKIP",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(110, U.touchTarget - 8),
		BackgroundColor3 = Kit.color.paper,
		Visible = false,
	}, StoryClient.skipFlight)
	skipFlight.Parent = gui
	buildMarker()
	StoryClient.Changed:Connect(function(what)
		if what == "opening" then
			refreshOpening()
		elseif what == "choice" then
			refreshChoice()
		end
	end)
	StoryClient.Result:Connect(showResult)
	StoryClient.Talk:Connect(showTalk)
	StoryClient.Fade:Connect(function()
		fade.BackgroundTransparency = 1
		TweenService:Create(fade, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()
		task.delay(1.4, function()
			TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		end)
	end)
	InputController.Pressed:Connect(function(action)
		if action == "Catch" and StoryClient.openingStep() == "catch" then
			StoryClient.catch()
		end
	end)
	RunService.RenderStepped:Connect(frame)
end

return StoryHud
