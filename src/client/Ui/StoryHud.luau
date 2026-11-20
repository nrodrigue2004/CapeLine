-- StoryHud: the story on screen (spec: The opening; First 30 seconds; Suit up; Act 1; Side quests).
-- * The Ceremony prologue (lore step 3): the camera beats' letterbox and SKIP are the cutscene player's
--   (CinemaClient and CinemaHud since lore step 7: one way for every camera beat), the subtitles (Crane on the stage,
--   Patch on the radio, Lodestar; fixed lines from Config.Story.opening.lines by side, shown by the guide line
--   queue, Ui.GuideHud, since lore step 6), SPARK DETECTED, the
--   the CAPELINE title card, and a quick fade on each cut. The HUD
--   shows only the beat's verb buttons (Hud.setFocus); a marker shows where to go; other screens stay hidden.
--   The world side (stage, crowd, camera, effects) is PrologueFx.
-- * The choice card: two (or three) big verb buttons.
-- * Suit Up: the run's end (lore step 2: the hero was made in the creator before the opening began).
-- * Missions: a fade on each trip, the objective tracker with a LEAVE button (each side reads its own goal),
--   the result card, and (lore step 5) the camera beats: the same letterbox and subtitles as the prologue, with
--   the beat's fixed lines by side (StoryFx moves the camera).
-- * The ending broadcast (lore step 5): after Live, a news-style screen: BREAKING NEWS, the registration law,
--   Crane's lines, and PUBLIC ENEMY #1 over the hero's own name. Nothing flashes.
-- * Side quests (lore step 10): the tracked chain's step tracker with its marker or search circle; giver and
--   step lines through GuideHud, a step's scene through CinemaClient, the finale's name card (CinemaHud).
-- * Side quest juice (the juice pass, 2026-11-18; Config.Audio.sideQuest, Shared.QuestJuice): every chain's
--   accept (NEW QUEST!), each step done (its word stamp and pay), the finale's name card sting, the encore, the
--   finale won (fireworks and VICTORY!), the chain done (the result card with its title and cosmetic, confetti
--   and the victory sting) and the finale lost (TRY AGAIN! when Downed while the villain stands).
-- The title card shows the drawn CAPELINE logo (Config.Ui.logo; DRAFT until nate OKs it), the typed title before it loads.

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
local SideQuestPlan = require(Shared:WaitForChild("SideQuestPlan"))
local GuidePlan = require(Shared:WaitForChild("GuidePlan"))
local Net = require(Shared:WaitForChild("Net"))
local QuestJuice = require(Shared:WaitForChild("QuestJuice"))

local Kit = require(script.Parent.Kit)
local Popups = require(script.Parent.Popups) -- pt-ui: one line for every popup
local Dismiss = require(script.Parent.Dismiss) -- fix-hud
local Hud = require(script.Parent.Hud)
local GuideHud = require(script.Parent.GuideHud)
local CinemaHud = require(script.Parent.CinemaHud)
local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local PvpClient = require(script.Parent.Parent.Controllers.PvpClient)
local Juice = require(script.Parent.Parent.Fx.Juice)

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
local foldChip: Frame -- missions lane: the folded tracker keeps LEAVE (and a tap to unfold) on screen
local resultCard: Frame
local questPanel: Frame
local questTitle: TextLabel
local questText: TextLabel
local questFill: Frame
local detected: TextLabel
local hintLabel: TextLabel -- the prologue's one plain instruction (kid-proof, nate's playtest 2026-11-18)
local titleCard: Frame
local titleLogo: ImageLabel? = nil -- the drawn logo on the title card (Config.Ui.logo)
local titleScale: UIScale? = nil
local markerPart: Part
local markerGui: BillboardGui
local markerText: TextLabel
-- fix-hud (nate, gaps7: "need a way to get rid of popups"): the trackers' X folds them until the next step
local hiddenMission: string? = nil
-- first-30: the next story mission's card (Config.Ui.nextMission) and the mission its X folded
local nextPanel: Frame
local nextTitle: TextLabel
local nextText: TextLabel
local nextStart: TextButton
local nextNum: number? = nil
local hiddenNext: number? = nil
local hiddenQuest: string? = nil
local areaPart: Part

local HIDE_IN_OPENING = { "WorldHud", "ContractBoard", "Gear", "Loadout", "Map" }

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

---------------------------------------------------------------------------
-- The prologue's screen: letterbox, subtitles, SPARK DETECTED, the title card
---------------------------------------------------------------------------

local function buildPrologue()
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
	hintLabel = Kit.label({
		Name = "PrologueHint",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.7, 0.07),
		TextColor3 = Kit.color.gold,
		TextStrokeTransparency = 0,
		maxText = 40,
		Visible = false,
		ZIndex = 33,
	})
	hintLabel.Parent = gui
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
	if (Config.Ui.logo or 0) ~= 0 then
		-- the drawn CAPELINE logo (art/ui/logo.py, the main menu's) over the typed title once it has loaded, slammed
		-- in from big like a comic cover (list-combat 2026-11-20; the card was the plain Kit title)
		local drawn = Instance.new("ImageLabel")
		drawn.Name = "Logo"
		drawn.BackgroundTransparency = 1
		drawn.AnchorPoint = Vector2.new(0.5, 0.5)
		drawn.Position = UDim2.fromScale(0.5, 0.46)
		drawn.Size = UDim2.fromScale(0.8, 0.34)
		drawn.ScaleType = Enum.ScaleType.Fit
		drawn.Image = "rbxassetid://" .. Config.Ui.logo
		drawn.ImageTransparency = 1
		drawn.ZIndex = 47
		local scale = Instance.new("UIScale")
		scale.Parent = drawn
		drawn.Parent = titleCard
		titleLogo, titleScale = drawn, scale
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({ drawn })
			end)
			if drawn.IsLoaded and drawn.Parent then
				drawn.ImageTransparency = 0
				title.TextTransparency = 1
				title.TextStrokeTransparency = 1
			end
		end)
	end
end

local function cut()
	fade.BackgroundTransparency = 0
	TweenService:Create(fade, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
end

-- The subtitles (lore step 6): the beat's timed lines go to the guide line queue (GuideHud), which shows
-- each until the next (at most Config.Story.guides.queue.hold) with its speaker's portrait and blip. The
-- cache's table keys the beat: a prologue beat's name, or a mission's camera beat (its step table).
-- (act1-choices) a scene's `when` lines read by this hero's own picks (the Journal's StoryState), so the cache
-- keys the picks too
local lineCache: { step: any, side: string?, list: { any }, picks: string? } =
	{ step = nil, side = nil, list = {}, picks = nil }
local function sceneText(st: any, side: string, t: number)
	local j = StoryClient.journal
	local choices = j and j.choices or {}
	local picks = table.concat(choices, ",")
	if lineCache.step ~= st or lineCache.side ~= side or lineCache.picks ~= picks then
		lineCache = { step = st, side = side, list = StoryPlan.sceneLines(st, side, choices), picks = picks }
	end
	GuideHud.timeline(lineCache, lineCache.list, t)
end

-- (onboarding check 2026-11-18) a beat a quick player leaves early (or the short suit beat) hands its unheard
-- lines to the next player-paced beat (at most Config.Ui.prologue.carry), so Patch's first words are never lost
-- to a fast Leap; camera and timed beats keep their own timing and take nothing.
local prologueLast: { step: string?, t: number } = { step = nil, t = 0 }
local function prologueText(step: string?, t: number)
	if not step then
		GuideHud.timeline(nil, nil, 0)
		prologueLast.step, prologueLast.t = nil, 0
		return
	end
	local beat = step :: string
	local side = StoryClient.opening.side or "hero"
	if lineCache.step ~= beat or lineCache.side ~= side then
		local list = OpeningPlan.lines(Config, beat, side)
		if not OpeningPlan.CUT[beat] and not OpeningPlan.timed(Config, beat) then
			local prev = prologueLast.step
			local carried = if prev
					and prev ~= beat
					and not OpeningPlan.CUT[prev]
					and lineCache.step == prev
				then GuidePlan.unheard(
					Config,
					lineCache.list,
					prologueLast.t,
					U.prologue.heard,
					U.prologue.carry
				)
				else {}
			list = GuidePlan.withCarry(Config, carried, list)
		end
		lineCache = { step = beat, side = side, list = list }
	end
	prologueLast.step, prologueLast.t = beat, t
	GuideHud.timeline(lineCache, lineCache.list, t)
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

local function setMarker(t: { number }?, showDistance: boolean, label: string?)
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
		markerText.Text = label or "" -- the prologue's goal word (Config.Ui.prologue.goals)
	end
end

---------------------------------------------------------------------------
-- Choice card, trackers, result, side quest lines
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

local function missionName(num: number): string
	local m = S.missions[num]
	return if m then m.name else ""
end

-- The result card's lines: { text, colour, size, counts up (the pay line) }; it closes after 5.5 s
local cardToken = 0
local function fillCardNow(lines: { any }, credits: number, renown: number)
	for _, c in resultCard:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
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
				return Kit.payLine(credits, renown, k)
			end)
		end
	end
	resultCard.Visible = true
	Kit.pulse(resultCard, 0.2)
	cardToken += 1
	local token = cardToken
	task.delay(5.5, function()
		if token == cardToken then
			resultCard.Visible = false
		end
	end)
end

-- pt-ui: the result card waits its turn in Ui.Popups ("missionResult")
local function fillCard(lines: { any }, credits: number, renown: number)
	Popups.show("missionResult", function()
		fillCardNow(lines, credits, renown)
		return resultCard
	end, function()
		return resultCard.Visible
	end, function()
		resultCard.Visible = false
	end, function()
		-- fix-hud: Settings "Popups: Important only" shows this one line instead (title and pay)
		local first = lines[1]
		local title = if first and type(first[1]) == "string" then first[1] .. "  " else ""
		return title .. Kit.payLine(credits, renown, 1)
	end)
end

local function showResult(r: { [string]: any })
	-- a side quest's pocket run (r.sq: its chain's bit) carries the chain's name; the step's own juice follows
	local sq = r.sq and SideQuestPlan.byBit(Config, r.sq)
	if sq then
		fillCard({
			{ string.format("%s CLEAR!", string.upper(sq.name)), Kit.color.gold, 34 },
			{ Kit.payLine(r.credits or 0, r.renown or 0, 1), Kit.color.paper, 20, true },
		}, r.credits or 0, r.renown or 0)
		return
	end
	local lines = {
		{ string.format("%s CLEAR!", string.upper(missionName(r.num or 0))), Kit.color.gold, 34 },
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
	else
		table.insert(lines, { "Replay: first-clear rewards already earned", Kit.color.muted, 14 })
	end
	fillCard(lines, r.credits or 0, r.renown or 0)
end

---------------------------------------------------------------------------
-- Side quest juice (the juice pass): the toasts SideQuestService sends, the finale's card, Downed in a finale
---------------------------------------------------------------------------

-- the last finale this device tracked (where its villain stands and its card), for the win and the retry
local finale: { bit: number, at: Vector3?, name: string? }? = nil

local function sideOf(): string
	return State.hero.side or "hero"
end

-- A chain done: the result card with its title, pay and each cosmetic it gives
local function questResult(chain: any, credits: number?, renown: number?)
	local r = QuestJuice.result(Config, chain, credits, renown)
	local lines = {
		{ r.title, Kit.color.gold, 34 },
		{ Kit.payLine(r.credits, r.renown, 1), Kit.color.paper, 20, true },
	}
	for _, text in r.rewards do
		table.insert(lines, { text, Kit.color.gold, 18 })
	end
	fillCard(lines, r.credits, r.renown)
end

local function questToast(data: { [string]: any })
	local id = data.id
	local chain = SideQuestPlan.byBit(Config, data.bit or 0)
	local name = chain and string.upper(chain.name) or nil
	if id == "sqStart" and chain then
		Juice.fire("questAccept", nil, { name = name })
	elseif id == "sqStep" and chain then
		local idx = (data.step or 2) - 1 -- data.step is the step that comes next
		local row = QuestJuice.step(Config, QuestJuice.kindOf(chain, idx, sideOf()))
		Juice.fire("questStep", nil, {
			word = row and row.word,
			sub = string.format("STEP %d OF %d", idx, #chain.steps),
			credits = data.credits,
		})
	elseif id == "sqWait" then
		local q = StoryClient.quest
		local qc = q and SideQuestPlan.byBit(Config, q.bit or 0)
		local row = QuestJuice.step(Config, qc and QuestJuice.kindOf(qc, q and q.step or 0, sideOf()))
		Juice.fire("questStep", nil, { wait = true, word = row and row.word })
	elseif id == "sqTest" then
		-- Dev: a kind test done gets its kind's stamp, so every kind's juice can be tried alone
		local dk = Config.SideQuests.devKinds[data.n or 0]
		local row = QuestJuice.step(Config, dk and dk.kind)
		Juice.fire("questStep", nil, { word = row and row.word, sub = "KIND TEST" })
	elseif id == "sqEncore" then
		local q = StoryClient.quest
		local qc = q and SideQuestPlan.byBit(Config, q.bit or 0)
		local card = qc and SideQuestPlan.card(qc, q and q.step or 0, 2)
		local at = q and q.target and Vector3.new(q.target[1], q.target[2], q.target[3]) or nil
		Juice.fire("questEncore", at, { name = card and string.upper(card.name) or nil })
	elseif id == "sqDone" and chain then
		-- the finale won: fireworks where the villain fell, then the chain's result card
		local f = if finale and finale.bit == chain.bit then finale else nil
		local villain = if type(chain.villain) == "table" then string.upper(chain.villain.name) else nil
		Juice.fire("questFinale", f and f.at, { name = villain, mine = true })
		finale = nil
		task.delay(Config.Audio.sideQuest.doneDelay, function()
			Juice.fire("questDone", nil, { mine = true })
			questResult(chain, data.credits, data.renown)
		end)
	end
end

-- A side quest giver or step speaks (lore step 10): fixed lines from Config.SideQuests through the guide line
-- box; a step's scene plays in the next quiet moment
-- fix-respawn (nate's playtest 2026-11-19: "unresponsive buttons when trying to talk to npcs or start side
-- quests"): a giver's Talk answers on this device at once (the click, and the giver's "..." in the line box), and
-- the server's answer to your own press cuts in front of any radio line playing (it used to wait its turn behind
-- it, seconds with nothing on screen). No answer in TALK_WAIT s says so.
local TALK_WAIT = 2.5
local talkAsked: { [string]: number } = {}
local function talkPressed(giver: string)
	if not Config.SideQuests.givers[giver] then
		return
	end
	Kit.Clicked:Fire()
	GuideHud.say(giver, "...", { cut = true, hold = TALK_WAIT, tag = "sqTalk" })
	local at = os.clock()
	talkAsked[giver] = at
	task.delay(TALK_WAIT, function()
		if talkAsked[giver] == at then
			talkAsked[giver] = nil
			GuideHud.cancel("sqTalk")
			State.Toast:Fire({ id = "note", text = "No answer: try talking again" })
		end
	end)
end
StoryHud.talkPressed = talkPressed

local function showTalk(t: { [string]: any })
	local side = State.hero.side or "hero"
	local chain = SideQuestPlan.byBit(Config, t.bit or 0)
	local mine = type(t.giver) == "string" and talkAsked[t.giver] ~= nil
	if type(t.giver) == "string" then
		talkAsked[t.giver] = nil
	end
	GuideHud.cancel("sqTalk")
	if t.kind == "refused" then
		return -- the reason is on its toast (Toasts sqLocked)
	end
	if t.kind == "none" then
		local who = t.giver
		local gv = type(who) == "string" and Config.SideQuests.givers[who]
		if gv then
			-- (lore step 11, the character lines: a giver's own `none` line, by side)
			local own = if type(gv.none) == "string"
				then gv.none
				elseif type(gv.none) == "table" then GuidePlan.lineText(gv.none, side)
				else nil
			GuideHud.say(who, own or Config.SideQuests.none, { tag = "sideQuest", cut = mine })
			if t.why and t.why ~= "done" then
				-- what the giver's next chain waits for (a level, a mission, another chain)
				State.Toast:Fire({ id = "sqLocked", why = t.why, n = t.n })
			end
		end
		return
	end
	if not chain then
		return
	end
	if t.kind == "step" then
		local step = chain.steps[t.step or 0]
		if not step then
			return
		end
		for _, l in step.lines or {} do
			local text = GuidePlan.lineText(l, side)
			if text then
				GuideHud.say(l.who, text, { tag = "sideQuest" })
			end
		end
		if step.scene then
			CinemaClient.playScene(step.scene)
		end
		return
	end
	local line = chain.lines and chain.lines[t.kind]
	local text = line and GuidePlan.lineText(line, side)
	if text then
		GuideHud.say(chain.giver, text, { tag = "sideQuest", cut = mine })
	end
end

-- The tracker's title and text for the tracked step (a Dev kind test reads Config.SideQuests.devKinds)
local cardShown: { [string]: boolean } = {}
local function questLines(q: { [string]: any }, side: string): (string?, string?)
	local goal, title
	if q.test then
		goal = Config.SideQuests.devKinds[q.test]
		title = "KIND TEST"
	else
		local chain = SideQuestPlan.byBit(Config, q.bit or 0)
		local step = chain and chain.steps[q.step or 0]
		goal = step and SideQuestPlan.goal(step, side)
		title = chain and string.format("%s  %d/%d", string.upper(chain.name), q.step or 1, #chain.steps)
	end
	if not goal or not title then
		return nil, nil
	end
	if q.wait then
		return title, S.wait[if side == "villain" then "villain" else "hero"]
	end
	return title, SideQuestPlan.text(goal, side)
end

---------------------------------------------------------------------------
-- The ending broadcast (lore step 5): a news-style screen after Live
---------------------------------------------------------------------------

local news: Frame
local newsParts: { [string]: TextLabel } = {}
local newsOn: { id: string, at: number }? = nil

local function buildBroadcast()
	news = Kit.frame({
		Name = "Broadcast",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(14, 18, 34),
		round = false,
		Visible = false,
		ZIndex = 48,
	})
	news.Parent = gui
	local band = Kit.frame({
		Name = "Band",
		Position = UDim2.fromScale(0, 0.05),
		Size = UDim2.fromScale(1, 0.09),
		BackgroundColor3 = Color3.fromRGB(200, 30, 40),
		round = false,
		ZIndex = 49,
	})
	band.Parent = news
	local function label(name: string, props: { [string]: any }): TextLabel
		props.Name = name
		props.ZIndex = props.ZIndex or 50
		props.TextStrokeTransparency = props.TextStrokeTransparency or 0.4
		local l = Kit.label(props)
		newsParts[name] = l
		return l
	end
	label("Breaking", {
		Position = UDim2.new(0, U.safe + 8, 0, 0),
		Size = UDim2.new(0.45, -U.safe, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		maxText = 34,
	}).Parent =
		band
	label("Channel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -U.safe - 8, 0, 0),
		Size = UDim2.new(0.45, -U.safe, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 20,
	}).Parent =
		band
	label("Headline", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromScale(0.86, 0.1),
		TextColor3 = Kit.color.gold,
		maxText = 60,
	}).Parent =
		news
	label("Speaker", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.33),
		Size = UDim2.fromScale(0.7, 0.06),
		TextColor3 = rgb(S.guides.speakers.crane.color),
		maxText = 20,
	}).Parent =
		news
	label("Line", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.8, 0.1),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 24,
	}).Parent =
		news
	label("Enemy", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromScale(0.8, 0.1),
		TextColor3 = Color3.fromRGB(255, 70, 70),
		TextStrokeTransparency = 0,
		maxText = 54,
	}).Parent =
		news
	label("Name", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.65),
		Size = UDim2.fromScale(0.7, 0.08),
		TextColor3 = Kit.color.paper,
		maxText = 40,
	}).Parent =
		news
	label("Sign", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.75),
		Size = UDim2.fromScale(0.6, 0.06),
		TextColor3 = Kit.color.gold,
		maxText = 26,
	}).Parent =
		news
	local tick = Kit.frame({
		Name = "Ticker",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -U.safe),
		Size = UDim2.new(1, 0, 0.08, 0),
		BackgroundColor3 = Color3.fromRGB(240, 200, 60),
		round = false,
		ZIndex = 49,
	})
	tick.Parent = news
	label("Ticker", {
		Position = UDim2.new(0, U.safe + 8, 0, 0),
		Size = UDim2.new(1, -3 * U.safe - 24 - 96, 1, 0), -- clear of CLOSE
		TextColor3 = Kit.color.ink,
		Font = Kit.bodyFont,
		TextStrokeTransparency = 1,
		maxText = 18,
	}).Parent =
		tick
	local close = Kit.button({
		Name = "Close",
		Text = "CLOSE",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -U.safe, 1, -U.safe),
		Size = UDim2.fromOffset(96, 44),
		BackgroundColor3 = Kit.color.paper,
		ZIndex = 51,
	}, function()
		newsOn = nil
		news.Visible = false
	end)
	close.Parent = news
end

local function showBroadcast(id: string)
	local e = S.ending[id]
	if not e then
		return
	end
	newsParts.Breaking.Text = e.breaking
	newsParts.Channel.Text = e.channel
	newsParts.Headline.Text = e.headline
	newsParts.Ticker.Text = e.ticker
	newsParts.Enemy.Text = e.enemy
	newsParts.Sign.Text = e.sign
	local name = player:GetAttribute("HeroName")
	newsParts.Name.Text =
		string.upper(if typeof(name) == "string" and name ~= "" then name else player.DisplayName)
	newsOn = { id = id, at = os.clock() }
	news.Visible = true
	news.BackgroundTransparency = 1
	TweenService:Create(news, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
end

-- Each frame while it plays: Crane's line for the moment, then PUBLIC ENEMY #1 and the hero's name
local function broadcastFrame(now: number)
	local on = newsOn
	if not on then
		return
	end
	local e = S.ending[on.id]
	local t = now - on.at
	if t > e.seconds then
		newsOn = nil
		news.Visible = false
		return
	end
	local show = nil
	for _, l in e.lines do
		if t >= l.at then
			show = l
		end
	end
	newsParts.Speaker.Visible = show ~= nil
	newsParts.Line.Visible = show ~= nil
	if show then
		local who = S.guides.speakers[show.who] or S.guides.speakers.crane
		newsParts.Speaker.Text = who.name
		newsParts.Line.Text = show.text
	end
	local enemy = t >= e.enemyAt
	newsParts.Enemy.Visible = enemy
	newsParts.Name.Visible = enemy
	newsParts.Sign.Visible = t >= e.seconds - 4
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
		-- (first-30 polish) the world markers and the boss bar also step aside for a letterboxed cutscene
		local off = inOpening or CinemaClient.letterboxed()
		for _, name in HIDE_IN_OPENING do
			local g = pg:FindFirstChild(name) :: ScreenGui?
			if g then
				g.Enabled = not off
			end
		end
	end
	if inOpening and step then
		Hud.setFocus(StoryClient.VERBS[step] or {})
	elseif Hud.focused() then
		Hud.setFocus(nil)
	end
	-- (the letterbox and SKIP are the cutscene player's: PrologueFx plays the CUT beats through CinemaClient)
	-- a quick fade from black on each cut to a new place
	if step and step ~= lastStep and (step == "leap" or step == "tunnel" or step == "title") then
		cut()
	end
	if not step then
		titleCard.Visible = false
		detected.Visible = false
	end
	lastStep = step or ""
end

local sceneFocus = false
-- {Action} in a prologue hint, the way this device shows it: the key, the controller button, or the HUD button
local function keyOf(action: string): string
	local dev = InputController.device
	if dev == "touch" then
		return "the " .. string.upper(action == "Basic" and "attack" or action) .. " button"
	end
	local k = if dev == "gamepad" then InputController.padHints[action] else InputController.hints[action]
	return if k then string.upper(k) else string.upper(action)
end

local function frame()
	local now = os.clock()
	local o = StoryClient.opening
	local step = StoryClient.openingStep()
	-- the beat's plain instruction stays on screen until the beat is done (never on the camera beats)
	local hint = step
		and not OpeningPlan.CUT[step]
		and not o.hold
		and OpeningPlan.hint(Config, step, o.side or "hero", keyOf)
	hintLabel.Visible = hint ~= nil and hint ~= false and not CinemaClient.playing()
	if hint then
		hintLabel.Text = hint
	end
	local m = StoryClient.mission
	local q = StoryClient.quest
	-- the marker: the prologue's beat, else the mission's, else the pinned quest's
	if step then
		-- (prologue-cine, nate 2026-11-20: "dont have the player run to the gold marker": the directed beats have none)
		local directed = OpeningPlan.CUT[step] or Config.Story.opening.qte.beats[step]
		setMarker(if directed then nil else o.target, false, U.prologue.goals[step])
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
	-- a mission's camera beat (lore step 5): letterbox and subtitles, no tracker
	local scene, sceneT = StoryClient.missionScene()
	if not step then
		-- (the letterbox is the cutscene player's: StoryFx plays the beat through CinemaClient)
		-- the action buttons step aside for the beat (phones too), and come back after it
		if (scene ~= nil) ~= sceneFocus then
			sceneFocus = scene ~= nil
			Hud.setFocus(if sceneFocus then {} else nil)
		end
	end
	-- the mission tracker (fix-hud: its X or Backspace fold it until the next step)
	local mKey = string.format("%s:%s", tostring(m.num), tostring(m.step))
	if (m.num or 0) > 0 and not scene and hiddenMission ~= mKey then
		tracker.Visible = true
		trackTitle.Text = string.format("MISSION %d: %s", m.num, string.upper(missionName(m.num)))
		trackText.Text = string.format("%s  (%d/%d)", m.text or "", m.step or 1, m.steps or 1)
		trackFill.Size = UDim2.fromScale(math.clamp((m.have or 0) / math.max(1, m.need or 1), 0, 1), 1)
		leaveButton.Visible = not m.done
		foldChip.Visible = false
	else
		tracker.Visible = false
		-- (missions lane 2026-11-20, nate stuck in the Safehouse: folding the tracker used to hide LEAVE too)
		foldChip.Visible = (m.num or 0) > 0 and not scene and not m.done and hiddenMission == mKey
	end
	-- the side quest tracker (not in a mission)
	if q and not StoryClient.inMission() and not StoryClient.inOpening() then
		local title, text = questLines(q, State.hero.side or "hero")
		local qKey = string.format("%s:%s", tostring(q.bit or q.test), tostring(q.step))
		questPanel.Visible = title ~= nil and hiddenQuest ~= qKey
		if title and text then
			questTitle.Text = title
			local left = if q.left then q.left - (now - (q.received or now)) else nil
			questText.Text = text
				.. (if left then string.format("  %ds", math.max(0, math.ceil(left))) else "")
			questFill.Size = UDim2.fromScale(math.clamp((q.have or 0) / math.max(1, q.need or 1), 0, 1), 1)
		end
		-- the finale's name card, once a step, when the hero comes within reach of the mini villain
		local card, target = q.card, q.target
		-- (lore step 11, chain 2: a finale with an encore shows the second villain's card too: its phase)
		local key =
			string.format("%s:%s:%s", tostring(q.bit or q.test), tostring(q.step), tostring(q.phase or 1))
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if card and not q.test then
			finale = {
				bit = q.bit or 0,
				at = if target then Vector3.new(target[1], target[2], target[3]) else nil,
				name = string.upper(card.name),
			}
		end
		if card and target and root and not cardShown[key] then
			local d = (root.Position - Vector3.new(target[1], target[2], target[3])).Magnitude
			if d <= Config.SideQuests.finale.reach then
				cardShown[key] = true
				CinemaHud.nameCard("", card.name, card.title)
				Juice.fire("questVillain", nil, { mine = false })
			end
		end
	else
		questPanel.Visible = false
	end
	-- first-30: the next story mission, out in the city with nothing else on (no quest, card or busy screen)
	local num, open = StoryHud.nextMission()
	local busy = (Popups.busy ~= nil and Popups.busy()) or Popups.cardUp()
	nextNum = if open then num else nil
	if num and not questPanel.Visible and not tracker.Visible and not busy and hiddenNext ~= num then
		local NM = U.nextMission
		nextPanel.Visible = true
		local m = S.missions[num]
		if Kit.compact() and not open then
			nextTitle.Text = string.format(NM.pillLevel, num, m.minLevel)
		else
			nextTitle.Text = string.format(
				if Kit.compact() then NM.pillTitle else NM.title,
				num,
				string.upper(missionName(num))
			)
		end
		nextText.Text = if open
			then S.missions[num].blurb or ""
			else string.format(NM.level, S.missions[num].minLevel)
		nextStart.Visible = open
	else
		nextPanel.Visible = false
	end
	-- the prologue's words: subtitles, SPARK DETECTED, the title card
	local t = if o.hold then 0 else StoryClient.beatTime()
	-- (a device-started scene feeds its own lines: CinemaHud)
	if not CinemaClient.ownLines() then
		if scene and not step then
			sceneText(scene, StoryClient.mission.side or "hero", sceneT)
		else
			prologueText(if o.hold then nil else step, t)
		end
	end
	broadcastFrame(now)
	-- the guide line box: under the letterbox on a camera beat; open-world lines wait while the prologue, a
	-- mission or the broadcast is on; the box steps away from the full-screen broadcast
	local cinematic = (step ~= nil and OpeningPlan.CUT[step] == true and not o.hold)
		or (scene ~= nil and not step)
		or CinemaClient.letterboxed()
	GuideHud.setScene(
		cinematic,
		step ~= nil or StoryClient.inMission() or newsOn ~= nil or CinemaClient.playing(),
		newsOn ~= nil
	)
	detected.Visible = step == "scan" and t >= S.opening.beats.scan * 0.42
	local showTitle = step == "title" and t >= S.opening.beats.title * 0.55
	if showTitle and not titleCard.Visible then
		titleCard.BackgroundTransparency = 1
		TweenService:Create(titleCard, TweenInfo.new(0.8), { BackgroundTransparency = 0 }):Play()
		if titleLogo and titleScale then
			-- the logo slams in: big, then settles with a little overshoot
			titleScale.Scale = 1.6
			TweenService:Create(
				titleScale,
				TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()
		end
	end
	titleCard.Visible = showTitle
end

-- first-30: the story mission the Journal pins next and whether it can start now ("open"); nil when a side quest
-- chain is pinned, the prologue is next or every mission that is out is done. Out in the city only: not in the
-- prologue, a held ceremony or a mission.
function StoryHud.nextMission(): (number?, boolean)
	local j = StoryClient.journal
	if
		not j
		or (j.pinned or 0) ~= 0
		or StoryClient.inOpening()
		or StoryClient.held()
		or StoryClient.inMission()
	then
		return nil, false
	end
	local num = StoryPlan.nextMission(Config, j)
	local m = num and S.missions[num]
	if not num or not m or m.opening then
		return nil, false
	end
	local st = StoryPlan.state(Config, j, State.hero.level or 1, num)
	if st ~= "open" and st ~= "level" then
		return nil, false
	end
	return num, st == "open"
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
	-- the folded tracker: MISSION (unfold) and LEAVE, always reachable
	foldChip = Kit.frame({
		Name = "MissionFolded",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(196, 44),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	foldChip.Parent = gui
	local unfold = Kit.button({
		Text = "MISSION",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.fromOffset(100, 40),
		BackgroundColor3 = Kit.color.gold,
		maxText = 16,
	}, function()
		hiddenMission = nil
	end)
	unfold.Parent = foldChip
	local leave2 = Kit.button({
		Text = "LEAVE",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -2, 0, 2),
		Size = UDim2.fromOffset(84, 40),
		BackgroundColor3 = Kit.color.paper,
		maxText = 16,
	}, StoryClient.leave)
	leave2.Parent = foldChip
	-- (fix-hud: and clear of the X's 40 px next to LEAVE)
	trackTitle.Size = UDim2.new(1, -150, 0, 22)
	trackText.Size = UDim2.new(1, -150, 0, 18)
	questPanel, questTitle, questText, questFill = buildTracker("Quest", 136)
	questTitle.Size = UDim2.new(1, -56, 0, 22) -- fix-hud: clear of the X
	questText.Size = UDim2.new(1, -56, 0, 18)
	-- first-30: the next mission's card in the quest tracker's slot, START where LEAVE sits on the mission's
	nextPanel, nextTitle, nextText = buildTracker("NextMission", U.nextMission.y)
	local nextBar = nextPanel:FindFirstChildWhichIsA("Frame")
	if nextBar then
		nextBar.Visible = false
	end
	nextText.TextWrapped = true
	nextStart = Kit.button({
		Text = U.nextMission.start,
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Kit.color.gold,
		maxText = 16,
	}, function()
		if nextNum then
			StoryClient.enter(nextNum)
		end
	end)
	nextStart.Name = "Start"
	nextStart.Parent = nextPanel
	-- a phone's HUD has no room for the card under the top row: a one-line pill between the status panel and the
	-- action buttons (Config.Ui.nextMission.pill), the blurb left out
	local function nextLayout()
		local NM = U.nextMission
		-- START (64 px) in the right corner, the X just left of it (Dismiss inset 66), the words clear of both
		nextTitle.Position = UDim2.fromOffset(8, 4)
		if Kit.compact() then
			local pill = NM.pill
			nextPanel.AnchorPoint = Vector2.new(0, 0)
			nextPanel.Position = UDim2.fromOffset(pill.x, pill.y)
			nextPanel.Size = UDim2.fromOffset(pill.w, pill.h)
			nextTitle.Size = UDim2.new(1, -118, 1, -8)
			nextText.Parent = nil -- no room for the blurb on a phone's pill
			nextStart.Size = UDim2.fromOffset(64, pill.h)
			nextStart.Position = UDim2.new(1, 0, 0.5, 0)
		else
			nextPanel.AnchorPoint = Vector2.new(0.5, 0)
			nextPanel.Position = UDim2.new(0.5, 0, 0, NM.y)
			nextPanel.Size = UDim2.new(0.6, 0, 0, 64)
			nextTitle.Size = UDim2.new(1, -118, 0, 22)
			nextText.Size = UDim2.new(1, -118, 0, 34)
			nextText.Parent = nextPanel
			nextStart.Size = UDim2.fromOffset(64, 44)
			nextStart.Position = UDim2.new(1, -2, 0.5, 0)
		end
	end
	nextLayout()
	Kit.LayoutChanged:Connect(nextLayout)
	GuideHud.keepClear(nextPanel)
	Dismiss.attach(nextPanel, function()
		local n = StoryHud.nextMission()
		hiddenNext = n
		nextPanel.Visible = false
	end, { thin = true, tap = false, inset = 66 })
	-- the guide line box keeps clear of the trackers and the choice card (lore step 6)
	GuideHud.keepClear(tracker)
	GuideHud.keepClear(questPanel)
	GuideHud.keepClear(choiceCard)
	-- fix-hud: the trackers' X (Backspace too) folds them until the next step; never the choice card (a story
	-- choice waits for its answer)
	Dismiss.attach(tracker, function()
		local m = StoryClient.mission
		hiddenMission = string.format("%s:%s", tostring(m.num), tostring(m.step))
		tracker.Visible = false
	end, { thin = true, tap = false, inset = 96 })
	Dismiss.attach(questPanel, function()
		local q = StoryClient.quest
		if q then
			hiddenQuest = string.format("%s:%s", tostring(q.bit or q.test), tostring(q.step))
		end
		questPanel.Visible = false
	end, { thin = true, tap = false })
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
	buildPrologue()
	buildBroadcast()
	buildMarker()
	StoryClient.Changed:Connect(function(what)
		if what == "opening" then
			refreshOpening()
		elseif what == "choice" then
			refreshChoice()
		end
	end)
	StoryClient.Result:Connect(showResult)
	-- act1-choices: what the picked option says, right after the pick (fixed lines, Config.Story.choices)
	StoryClient.Picked:Connect(function(id: number, option: number)
		local o = StoryPlan.option(Config, id, State.hero.side or "hero", option)
		for _, l in (o and o.say) or {} do
			GuideHud.say(l.who, l.text, { tag = "choice" })
		end
	end)
	Net.listen("Toast", function(data: any)
		if type(data) == "table" and type(data.id) == "string" and string.sub(data.id, 1, 2) == "sq" then
			questToast(data)
		end
	end)
	-- the finale lost: Downed while the tracked chain's villain still stands
	local wasDown = false
	PvpClient.Changed:Connect(function(what)
		if what ~= "down" then
			return
		end
		local down = PvpClient.down.downed == true
		local q = StoryClient.quest
		if down and not wasDown and q and q.card and not q.test and not StoryClient.inMission() then
			Juice.fire("questRetry", nil, { name = string.upper(q.card.name), mine = false })
		end
		wasDown = down
	end)
	StoryClient.Broadcast:Connect(showBroadcast)
	StoryClient.Talk:Connect(showTalk)
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, who)
		local giver = prompt:GetAttribute("Giver")
		if who == Players.LocalPlayer and type(giver) == "string" then
			talkPressed(giver)
		end
	end)
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
