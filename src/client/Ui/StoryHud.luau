-- StoryHud: the story on screen (spec: The opening; First 30 seconds; Suit up; Act 1; Side quests).
-- * The Ceremony prologue (lore step 3): letterbox bars on the camera beats, the subtitles (Crane on the stage,
--   Patch on the radio, Lodestar; fixed lines from Config.Story.opening.lines by side), SPARK DETECTED, the
--   SKIP button (camera beats, replays only), the CAPELINE title card, and a quick fade on each cut. The HUD
--   shows only the beat's verb buttons (Hud.setFocus); a marker shows where to go; other screens stay hidden.
--   The world side (stage, crowd, camera, effects) is PrologueFx.
-- * The choice card: two (or three) big verb buttons.
-- * Suit Up: the run's end (lore step 2: the hero was made in the creator before the opening began).
-- * Missions: a fade on each trip, the objective tracker with a LEAVE button, and the result card.
-- * Side quests: the NPC's speech bubble and the pinned step's tracker, with its marker or search circle.
-- PLACEHOLDER ART: the title card is the plain Kit title until the art pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))
local OpeningPlan = require(Shared:WaitForChild("OpeningPlan"))

local Kit = require(script.Parent.Kit)
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
local skipBeat: TextButton
local bars: { Frame } = {}
local subtitle: Frame
local subName: TextLabel
local subText: TextLabel
local radioTag: TextLabel
local detected: TextLabel
local titleCard: Frame
local markerPart: Part
local markerGui: BillboardGui
local markerText: TextLabel
local areaPart: Part

local HIDE_IN_OPENING = { "WorldHud", "ContractBoard", "Gear", "Loadout", "Map" }

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

---------------------------------------------------------------------------
-- The prologue's screen: letterbox, subtitles, SPARK DETECTED, the title card
---------------------------------------------------------------------------

local function buildPrologue()
	for i = 1, 2 do
		local bar = Kit.frame({
			Name = if i == 1 then "LetterTop" else "LetterBottom",
			AnchorPoint = Vector2.new(0, if i == 1 then 0 else 1),
			Position = UDim2.fromScale(0, if i == 1 then 0 else 1),
			Size = UDim2.fromScale(1, 0.1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			round = false,
			Visible = false,
			ZIndex = 30,
		})
		bar.Parent = gui
		table.insert(bars, bar)
	end
	subtitle = Kit.frame({
		Name = "Subtitle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.11, 6),
		Size = UDim2.new(0.7, 0, 0, 66),
		BackgroundColor3 = Kit.color.ink,
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 32,
	})
	local slimit = Instance.new("UISizeConstraint")
	slimit.MaxSize = Vector2.new(600, 66)
	slimit.Parent = subtitle
	subtitle.Parent = gui
	subName = Kit.label({
		Name = "Speaker",
		Size = UDim2.new(1, -90, 0, 22),
		Position = UDim2.fromOffset(10, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 18,
		ZIndex = 33,
	})
	subName.Parent = subtitle
	radioTag = Kit.label({
		Name = "Radio",
		Text = "RADIO",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 4),
		Size = UDim2.fromOffset(70, 20),
		TextColor3 = Color3.fromRGB(120, 230, 255),
		maxText = 14,
		Visible = false,
		ZIndex = 33,
	})
	radioTag.Parent = subtitle
	subText = Kit.label({
		Name = "Line",
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 27),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 16,
		ZIndex = 33,
	})
	subText.Parent = subtitle
	detected = Kit.label({
		Name = "Detected",
		Text = S.opening.detected,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.14),
		TextColor3 = Color3.fromRGB(255, 60, 60),
		TextStrokeTransparency = 0,
		maxText = 64,
		Visible = false,
		ZIndex = 34,
	})
	detected.Parent = gui
	titleCard = Kit.frame({
		Name = "TitleCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 14, 30),
		round = false,
		Visible = false,
		ZIndex = 45,
	})
	titleCard.Parent = gui
	local title = Kit.label({
		Name = "Title",
		Text = "CAPELINE",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.8, 0.2),
		TextColor3 = Kit.color.gold,
		TextStrokeTransparency = 0,
		maxText = 110,
		ZIndex = 46,
	})
	title.Parent = titleCard
end

local function cut()
	fade.BackgroundTransparency = 0
	TweenService:Create(fade, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
end

-- The subtitle for this moment of the beat (each line stays until the next, or 5 s)
local lineCache: { step: string?, side: string?, list: { any } } = { step = nil, side = nil, list = {} }
local function prologueText(step: string?, t: number)
	if not step then
		subtitle.Visible = false
		return
	end
	local beat = step :: string
	local side = StoryClient.opening.side or "hero"
	if lineCache.step ~= beat or lineCache.side ~= side then
		lineCache = { step = beat, side = side, list = OpeningPlan.lines(Config, beat, side) }
	end
	local show = nil
	for i, l in lineCache.list do
		local nxt = lineCache.list[i + 1]
		local until_ = if nxt then math.min(nxt.at, l.at + 6) else l.at + 6
		if t >= l.at and t < until_ then
			show = l
		end
	end
	subtitle.Visible = show ~= nil
	if show then
		local who = S.opening.speakers[show.who] or S.opening.speakers.crane
		subName.Text = who.name
		subName.TextColor3 = rgb(who.color)
		radioTag.Visible = who.radio == true
		subText.Text = show.text
	end
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
			BackgroundColor3 = if i == 1 then rgb(U.colors.vigil) else rgb(U.colors.syndicate),
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
			Kit.payLine(r.credits or 0, r.renown or 0, 1),
			Kit.color.paper,
			20,
			true, -- counts up
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
			table.insert(lines, {
				string.format(
					"+%d %s",
					r.rep,
					string.upper(
						Config.Story.rep.words[if State.hero.side == "villain" then "syndicate" else "vigil"]
					)
				),
				Kit.color.paper,
				16,
			})
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
		if line[4] then
			Kit.countUp(l, 1.5, function(k)
				return Kit.payLine(r.credits or 0, r.renown or 0, k)
			end)
		end
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
	local o = StoryClient.opening
	local cutBeat = step ~= nil and OpeningPlan.CUT[step] == true
	for _, b in bars do
		b.Visible = cutBeat and not o.hold
	end
	skipBeat.Visible = step ~= nil and not o.hold and OpeningPlan.canSkip(step, o.replay == true)
	-- a quick fade from black on each cut to a new place
	if step and step ~= lastStep and (step == "leap" or step == "tunnel" or step == "title") then
		cut()
	end
	if not step then
		titleCard.Visible = false
		detected.Visible = false
		subtitle.Visible = false
	end
	lastStep = step or ""
end

local function frame()
	local now = os.clock()
	local o = StoryClient.opening
	local step = StoryClient.openingStep()
	local m = StoryClient.mission
	local q = StoryClient.quest
	-- the marker: the prologue's beat, else the mission's, else the pinned quest's
	if step then
		setMarker(if OpeningPlan.CUT[step] then nil else o.target, false)
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
	-- the prologue's words: subtitles, SPARK DETECTED, the title card
	local t = if o.hold then 0 else StoryClient.beatTime()
	prologueText(if o.hold then nil else step, t)
	detected.Visible = step == "scan" and t >= S.opening.beats.scan * 0.42
	local showTitle = step == "title" and t >= S.opening.beats.title * 0.55
	if showTitle and not titleCard.Visible then
		titleCard.BackgroundTransparency = 1
		TweenService:Create(titleCard, TweenInfo.new(0.8), { BackgroundTransparency = 0 }):Play()
	end
	titleCard.Visible = showTitle
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
		Size = UDim2.fromOffset(84, 40), -- phone pass: a 40 px tap target (the text rows stop short of it)
		BackgroundColor3 = Kit.color.paper,
		maxText = 16,
	}, StoryClient.leave)
	leaveButton.Parent = tracker
	trackTitle.Size = UDim2.new(1, -106, 0, 22)
	trackText.Size = UDim2.new(1, -106, 0, 18)
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
	buildPrologue()
	skipBeat = Kit.button({
		Name = "Skip",
		Text = "SKIP",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -U.safe, 1, -U.safe),
		Size = UDim2.fromOffset(U.touchTarget * 2, U.touchTarget),
		BackgroundColor3 = Kit.color.paper,
		Visible = false,
		ZIndex = 50,
	}, StoryClient.skipBeat)
	skipBeat.Parent = gui
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
		if action == "Basic" and StoryClient.openingStep() == "spark" then
			StoryClient.spark() -- the Spark fires (lore step 3)
		end
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("StoryHud", frame))
end

return StoryHud
