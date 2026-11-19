-- Toasts: short pop-ups in the top middle of the screen (spec: Remote events > Toast; Juice table: level up,
-- loot). Level up is a big gold banner with what just unlocked; a drop is a card in its tier colour (gold
-- and purple drops get a burst); rewards show +Credits and +Renown; Second Wind and a save outage get a
-- line each; beacons, safehouses and the bank get one too; so do incidents, contracts, photos and events. At most 2 show at once (1 on a phone), the rest wait their turn in Ui.Popups (pt-ui 2026-11-19). PLACEHOLDER look until M10 and M11.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progress = require(Shared:WaitForChild("Progress"))
local GearMath = require(Shared:WaitForChild("GearMath"))
local SideQuestPlan = require(Shared:WaitForChild("SideQuestPlan"))
local VisitRules = require(Shared:WaitForChild("VisitRules")) -- WP12: the visit lines (fixed text)

local Kit = require(script.Parent.Kit)
local Juice = require(script.Parent.Parent.Fx.Juice)
local State = require(script.Parent.Parent.State)
local GearScreen = require(script.Parent.GearScreen)
local ContractBoard = require(script.Parent.ContractBoard)
local Popups = require(script.Parent.Popups)

local Toasts = {}

local G = Config.Gear
local gui: ScreenGui
local stack: Frame
local MAX = 4

local UNLOCK_NAMES: { [string]: string } = {
	GoldSash = "Gold Sash style",
	DockCoat = "Dock Coat style",
	PhotoFrame = "Photo frame",
	CafeSign = "Cafe sign for your HQ",
	Salute = "Salute emote",
	NullEcho = "Echo Drone, your drone buddy",
}
local M9_REASONS: { [string]: string } = {
	combat = "Not during a fight",
	scene = "Finish what you are doing first",
	busy = "Finish what you are doing first",
	side = "That is the other side's base",
	serviceLocked = "Locked tight. Just a maintenance stair",
	safehouse = "Switch heroes at your HQ or a safehouse",
	slot = "Buy that hero slot in the shop first",
	locked = "Buy that hero slot in the shop first",
	hq = "Buy styles from Gizmo at your HQ",
	rep = "Your side's reputation rank opens that style", -- lore step 12
	where = "Open the shop at your HQ, a safehouse or the menu",
	soon = "Coming soon",
	save = "Saving is down on this server. Rejoin to shop",
	slot3 = "Buy slot 3 first",
	owned = "You already own that",
}
local SQUAD_REASONS: { [string]: string } = {
	self = "That's you!",
	taken = "They are already in a squad",
	full = "The squad is full (4)",
	pending = "Invite already sent",
	busy = "They have another invite open",
	expired = "That invite ran out",
	gone = "They left the server",
	mission = "Not during a mission",
}
local PVP_REASONS: { [string]: string } = {
	level = "PvP opens at level 10",
	rate = "Wait a moment before switching again",
	safe = "Step out of the safe area to switch PvP on",
	combat = "PvP can switch off 60 s after the last PvP hit",
	crater = "Leave the Crater to switch PvP off",
}

-- WP4: why a REMATCH ping or ACCEPT did not go (fixed lines)
local REMATCH_REASONS: { [string]: string } = {
	none = "The rematch chance has passed",
	flag = "Switch PvP on first, then tap again",
	gone = "They left the server",
	wait = "You pinged them a moment ago",
	late = "That rematch ping ran out",
}

local MISSION_REASONS: { [string]: string } = {
	level = "Reach the mission's level first",
	locked = "Finish the mission before this one first",
	combat = "Not during a fight",
	busy = "Finish what you are doing first",
	full = "Too many missions running: try again in a minute",
	loading = "Still loading",
	mission = "That mission cannot be started here",
}

local SQ_IDS = {
	sqStart = 1,
	sqStep = 1,
	sqDone = 1,
	sqHold = 1,
	sqWait = 1,
	sqLocked = 1,
	sqTest = 1,
	sqRetired = 1,
	sqEncore = 1,
}
-- Why a side quest chain could not be taken from the Journal (SideQuestPlan.accept reasons)
local SQ_LOCKED = {
	level = "You need a higher level for that side quest",
	story = "Play further in the story first",
	after = "Finish the chain before this one first",
	npc = "Talk to its giver to take that one",
	done = "You already finished that side quest",
}

local function draw(text: string, color: Color3, big: boolean?, life: number?): TextLabel
	local kids = {}
	for _, c in stack:GetChildren() do
		if c:IsA("TextLabel") and c.Name ~= "More" then
			table.insert(kids, c)
		end
	end
	if #kids >= MAX then
		table.sort(kids, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		kids[1]:Destroy()
	end
	-- a comic speech bubble (2026-11-18): the toast's colour fills it (plain lines are white), lettered in ink
	-- (or white outlined in ink on a dark fill), ink outline and hard shadow, leaning alternately, and the
	-- newest wears the bubble's tail
	local fill = if color == Kit.color.paper then Kit.color.white else color
	local dark = Kit.luma(fill) < 0.5
	local order = math.floor(os.clock() * 100)
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, 0, 0, if big then 54 else 34),
		BackgroundColor3 = fill,
		BackgroundTransparency = 0,
		TextColor3 = if dark then Kit.color.white else Kit.color.ink,
		TextStrokeColor3 = Kit.color.ink,
		TextStrokeTransparency = if dark then 0 else 1,
		LayoutOrder = order,
		Rotation = if order % 2 == 0 then -Config.Ui.ink.tilt else Config.Ui.ink.tilt,
		maxText = if big then 40 else 22,
	})
	Kit.round(l, 12)
	Kit.stroke(l, Kit.color.ink, if big then 4 else 3)
	for _, c in stack:GetChildren() do
		local old = c:FindFirstChild("Ink") and c.Ink:FindFirstChild("Tail")
		if old then
			old:Destroy()
		end
	end
	local tail = Instance.new("TextLabel")
	tail.Name = "Tail"
	tail.BackgroundTransparency = 1
	tail.Text = "▼"
	tail.TextScaled = true
	tail.TextColor3 = Kit.color.ink
	tail.Size = UDim2.fromOffset(20, 16)
	tail.Position = UDim2.new(0, 34, 1, 1)
	tail.ZIndex = -100
	tail.Parent = l:FindFirstChild("Ink")
	l.Parent = stack
	Kit.pulse(l, if big then 0.35 else 0.15)
	task.delay(life or 3.5, function()
		if l.Parent then
			TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1 })
				:Play()
			if tail.Parent then
				TweenService:Create(tail, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			end
			task.wait(0.3)
			l:Destroy()
		end
	end)
	return l
end

-- pt-ui (2026-11-19): every toast waits its turn in Ui.Popups (at most 2 at once, 1 on a phone; Config.Ui.popups).
-- How a toast ranks: the answer to a tap is urgent (it pushes the oldest other toast off), alerts and big
-- moments come first, the small notes last (and fold into "+N more" if they wait too long); a burst of the same
-- kind merges (rewards add up, drops read "+2 more").
local URGENT = {
	note = true,
	contractRefused = true,
	missionRefused = true,
	slotRefused = true,
	hqRefused = true,
	shopRefused = true,
	squadRefused = true,
	pvpRefused = true,
	rematchRefused = true,
	reviveBlocked = true,
	sqLocked = true,
	reported = true,
	reportedAlready = true,
	contestWait = true,
	choiceKept = true,
	slotSwitched = true,
	respawnPick = true,
	respawnSet = true,
	squadInvited = true,
	rematchSent = true,
	lookSaved = true,
	lookWorn = true,
	lookBad = true,
	hqMax = true,
	hqCredits = true,
	hqLocked = true,
	mannequinLocked = true,
	retireLevel = true,
	scanner = true,
	devBuy = true,
	pvpOn = true,
	pvpOff = true,
	banked = true,
	visit = true,
}
local ALERT = {
	saveDown = true,
	secondWind = true,
	revivedBy = true,
	fuse = true,
	courier = true,
	courierLate = true,
	craterIn = true,
	rematchOn = true,
	news = true,
	newsFlash = true,
}
local GROUP = { reward = "reward", loot = "loot", beat = "beat", sqStep = "sq", badgeMate = "badgeMate" }
local PRI = Config.Ui.popups.pri
local cur: { [string]: any } = { pri = PRI.minor }

local function specFor(data: { [string]: any }): { [string]: any }
	local id = data.id
	if URGENT[id] then
		return { pri = PRI.story, urgent = true }
	elseif ALERT[id] then
		return { pri = PRI.alert }
	end
	local minor = GROUP[id] ~= nil or id == "skillPoint" or id == "photo" or id == "photoRecon"
	if id == "loot" and data.piece and data.piece.tier >= 4 then
		minor = false
	end
	return {
		pri = if minor then PRI.minor else PRI.result,
		group = if id == "loot" and not minor then nil else GROUP[id],
		stale = if minor then 8 else nil,
	}
end

-- a reward burst adds up into one line
local function sumReward(a: any, b: any): any
	local credits = (a.credits or 0) + (b.credits or 0)
	local renown = (a.renown or 0) + (b.renown or 0)
	local out = table.clone(a)
	out.credits, out.renown = credits, renown
	out.text = string.format("+%s CREDITS   +%s RENOWN", Kit.comma(credits), Kit.comma(renown))
	out.summed = true
	return out
end

local function push(text: string, color: Color3, big: boolean?, life: number?, after: ((TextLabel) -> ())?)
	local spec = table.clone(cur)
	spec.life = (life or 3.5) + 0.4
	spec.data = { text = text, color = color, big = big, life = life, after = after }
	if spec.group == "reward" then
		spec.data.credits, spec.data.renown = cur.credits, cur.renown
		spec.merge = sumReward
	end
	Popups.toast(spec, function(d: any, count: number): TextLabel
		local t = d.text
		if count > 1 and not d.summed then
			t = string.format("%s  +%d more", t, count - 1)
		end
		local l = draw(t, d.color, d.big, d.life)
		if d.after then
			d.after(l)
		end
		return l
	end)
end

-- gap-icons (2026-11-19): a loot toast wears the piece's icon (slot symbol in its tier frame) as a sticker
-- over the bubble's left end; the text moves over for it. No uploaded icon: the plain bubble.
local function lootIcon(l: TextLabel, piece: any)
	local h = l.Size.Y.Offset
	local size = h + 10
	local icon = GearScreen.pieceIcon(piece, {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = l.ZIndex + 1,
	})
	if not icon then
		return
	end
	icon.Parent = l
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, size)
	pad.Parent = l
	-- the shadow folder lays out inside the padding (Kit.ink undoes it on a size change)
	if l:FindFirstChild("InkLine") then
		Kit.ink(l)
	end
	icon.Position = UDim2.new(0, -6 - size, 0.5, 0) -- the padded content box starts `size` in
	-- fades out with the bubble
	l:GetPropertyChangedSignal("TextTransparency"):Connect(function()
		for _, i in { icon, icon:FindFirstChild("Icon") } do
			(i :: ImageLabel).ImageTransparency = l.TextTransparency
		end
	end)
end

-- The juice action a toast stands for (spec: juice rows with a sound and a visual)
local function juice(data: { [string]: any })
	local id = data.id
	if id == "levelUp" then
		Juice.fire("levelUp", nil, { level = data.level })
	elseif id == "reward" and data.action == "rescue" then
		local char = Players.LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		Juice.fire("rescue", root and root.Position, { renown = data.renown })
	elseif id == "loot" and data.piece and data.kind ~= "salvaged" then
		Juice.fire("gearDrop", nil, { tier = GearMath.tierName(Config, data.piece) })
	elseif id == "incident" then
		Juice.fire("incidentClear", nil, { medal = data.medal })
	elseif id == "beat" then
		local b = Config.Incidents.beats[data.beat or ""]
		if b then
			local at = if data.x then Vector3.new(data.x, data.y, data.z) else nil
			Juice.fire(b.juice, at, { mine = false })
		end
	elseif id == "contract" then
		Juice.fire("contractDone", nil, { name = data.name })
	elseif id == "revived" or id == "revivedBy" or id == "defused" or id == "photoRecon" then
		local char = Players.LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		Juice.fire("revive", root and root.Position)
	elseif id == "bought" or id == "styleBought" then
		Juice.fire("purchase", nil, { name = data.name })
	elseif id == "pvpOn" or id == "rematchOn" then
		Juice.fire("pvpFlag")
	elseif id == "visit" and (data.say == "welcome" or data.say == "kicked" or data.say == "hostLeft") then
		Juice.fire("fastTravel") -- WP12: the whoosh into a friend's HQ and back out
	end
end

function Toasts.show(data: { [string]: any })
	local id = data.id
	juice(data)
	cur = specFor(data)
	cur.credits, cur.renown = data.credits, data.renown
	if id == "friendHere" then
		-- the friend boost (spec: Social table "+10% Renown per friend in the server, max +30%")
		if data.name then
			push(
				string.format("%s is here! FRIEND BOOST +%d%% Renown", data.name, data.pct or 0),
				Kit.color.gold,
				true
			)
		else
			push(
				string.format("FRIEND BOOST +%d%% Renown: friends in this server", data.pct or 0),
				Kit.color.gold
			)
		end
		return
	end
	if id == "note" then
		-- a plain line from a screen on this device (loading and error notes)
		push(tostring(data.text or ""), Kit.color.paper)
		return
	end
	if id == "levelUp" then
		local unlock = Progress.unlockAt(Config, data.level)
		push(string.format("LEVEL %d!", data.level), Kit.color.gold, true, 4.5)
		if unlock then
			push("Unlocked: " .. unlock, Kit.color.paper, false, 5)
		end
		push("+1 Skill Point (POWERS)", Kit.color.paper, false, 4)
	elseif id == "reward" then
		push(
			string.format(
				"+%s CREDITS   +%s RENOWN",
				Kit.comma(data.credits or 0),
				Kit.comma(data.renown or 0)
			),
			Kit.color.gold
		)
	elseif id == "loot" and data.piece then
		local piece = data.piece
		local tier = GearMath.tierName(Config, piece)
		local c = G.tiers[tier].color
		local color = Color3.fromRGB(c[1], c[2], c[3])
		if data.kind == "salvaged" then
			push(
				string.format("Stash full: %s became %d Dust", GearScreen.pieceName(piece), data.dust or 0),
				color,
				nil,
				nil,
				function(l)
					lootIcon(l, piece)
				end
			)
		else
			push(
				string.format("%s  (ilvl %d)", GearScreen.pieceName(piece), piece.ilvl),
				color,
				piece.tier >= 4,
				4.5,
				function(l)
					lootIcon(l, piece)
				end
			)
		end
	elseif id == "secondWind" then
		push("SECOND WIND!", Color3.fromRGB(255, 200, 60), true)
	elseif id == "beacon" then
		push(string.format("BEACON FOUND: %s", string.upper(data.name or "")), Kit.color.gold, true, 4)
		push(
			string.format(
				"Fast travel unlocked (%d / %d). Open the MAP to fly there.",
				data.found or 0,
				data.total or 12
			),
			Kit.color.paper,
			false,
			4.5
		)
	elseif id == "safehouse" then
		push(string.format("Safehouse found: %s", data.name or ""), Color3.fromRGB(120, 230, 150))
	elseif id == "respawnSet" then
		push(
			string.format("You will respawn at %s", data.name or "this safehouse"),
			Color3.fromRGB(120, 230, 150)
		)
	elseif id == "banked" then
		if (data.credits or 0) > 0 then
			push(string.format("Banked %s Credits: safe from PvP", Kit.comma(data.credits)), Kit.color.gold)
		else
			push("Nothing on hand to bank", Kit.color.paper)
		end
	elseif id == "incident" then
		local medal = string.upper(data.medal or "")
		push(
			string.format(
				"%s%s CLEARED!  %s",
				if data.heroic then Config.Heroic.tag .. " " else "",
				string.upper(data.name or "Incident"),
				medal
			),
			Kit.color.gold,
			true,
			3.5
		)
	elseif id == "contract" then
		push(
			string.format(
				"CONTRACT DONE: %s  +%s CREDITS  +%s RENOWN%s",
				string.upper(data.name or ""),
				Kit.comma(data.credits or 0),
				Kit.comma(data.renown or 0),
				if data.double then "  (x2)" else ""
			),
			Color3.fromRGB(255, 150, 70),
			true,
			4.5
		)
	elseif id == "contractRefused" then
		push(ContractBoard.REASONS[data.reason or ""] or "You cannot take that contract", Kit.color.paper)
	elseif id == "photo" then
		push("SNAP! " .. Config.Enemies.SneakBot.name .. " photographed", Kit.color.volt)
	-- 2026-11-17: the new activities' moments (fixed lines)
	elseif id == "beat" then
		local b = Config.Incidents.beats[data.beat or ""]
		if b then
			local heroicBeat = data.beat == "heroic"
			push(
				b.text,
				if heroicBeat
					then Color3.fromRGB(
						Config.Heroic.color[1],
						Config.Heroic.color[2],
						Config.Heroic.color[3]
					)
					else Kit.color.gold,
				heroicBeat or string.upper(b.text) == b.text,
				3
			)
		end
	elseif id == "photoRecon" then
		push("SNAP! Lookout photographed", Kit.color.volt)
	elseif id == "courier" then
		push(string.format("PARCEL! %d s to make every drop", data.left or 0), Kit.color.gold, true, 3)
	elseif id == "courierLate" then
		push("Too slow: the parcel is back on its roof", Kit.color.paper)
	elseif id == "fuse" then
		push(
			string.format("A charge is armed: %d s on the fuse", data.left or 0),
			Color3.fromRGB(255, 120, 90)
		)
	elseif id == "defused" then
		push("CHARGE DEFUSED!", Kit.color.gold, true, 3)
	elseif id == "fizzled" then
		push("The charge popped: the robots planted another one", Kit.color.paper)
	elseif id == "event" then
		push(
			string.format(
				"%sEVENT: %s!",
				if data.heroic then Config.Heroic.tag .. " " else "",
				string.upper(data.name or "")
			),
			Kit.color.gold,
			true,
			5
		)
		if data.text then
			push(data.text, Kit.color.paper, false, 5)
		end
	elseif id == "eventDone" then
		push(
			string.format(
				"%s DONE!  +%s CREDITS  +%s RENOWN",
				string.upper(data.name or "Event"),
				Kit.comma(data.credits or 0),
				Kit.comma(data.renown or 0)
			),
			Kit.color.gold,
			true,
			4.5
		)
		-- lore step 12: a side-vs-side event's result and the reputation it paid
		if data.winner then
			local mine = data.result == "win"
			push(
				string.format(
					"%s%s",
					if data.winner == "hero"
						then "THE VIGIL WINS!"
						elseif data.winner == "villain" then "THE SYNDICATE WINS!"
						else "NO WINNER THIS TIME",
					if (data.rep or 0) > 0
						then string.format(
							"  +%d %s",
							data.rep,
							string.upper(Config.Story.rep.words[data.track or ""] or "")
						)
						else ""
				),
				if mine then Kit.color.gold else Kit.color.paper,
				mine,
				4.5
			)
		end
	elseif id == "repUnlocks" then
		-- lore step 12: what a new reputation rank opened (Shared.RepTiers.unlocks)
		local parts = {}
		if data.hideout then
			table.insert(parts, string.upper(data.hideout))
		end
		if data.title then
			table.insert(parts, string.format('TITLE "%s"', string.upper(data.title)))
		end
		if (data.styles or 0) > 0 then
			table.insert(parts, string.format("%d NEW STYLES AT GIZMO'S", data.styles))
		end
		if #parts > 0 then
			push("OPENED: " .. table.concat(parts, ", "), Kit.color.gold, false, 5)
		end
	-- M7: the story
	elseif id == "catch" then
		push(string.format("+%d RENOWN", data.renown or 0), Kit.color.gold, true, 3)
	elseif id == "skillPoint" then
		push(
			string.format("+%d SKILL POINT%s (POWERS)", data.n or 1, if (data.n or 1) > 1 then "S" else ""),
			Kit.color.gold
		)
	elseif id == "repRank" then
		push(
			string.format(
				"%s RANK %d",
				string.upper(Config.Story.rep.labels[data.track] or ""),
				data.rank or 1
			),
			Kit.color.gold,
			true,
			4.5
		)
	elseif id == "unlock" then
		local name = UNLOCK_NAMES[data.name or ""] or data.name or ""
		push(string.format("UNLOCKED: %s", string.upper(name)), Kit.color.gold, true, 4.5)
	elseif id == "news" then
		-- lore step 5: a fake unmasked live goes out on every screen in the server (fixed text)
		local text = Config.Story.news[data.key or ""]
		if text then
			push(
				string.format(text, string.upper(tostring(data.name or ""))),
				Color3.fromRGB(255, 90, 90),
				true,
				5
			)
		end
	elseif id == "newsFlash" then
		-- lore step 7: a server-wide news flash (NewsHud builds the line from NewsPlan's fixed templates)
		if type(data.text) == "string" then
			push(data.text, Color3.fromRGB(255, 90, 90), true, 5)
		end
	elseif id == "choiceKept" then
		push("Your first choice stands on a replay", Kit.color.paper)
	elseif id == "missionRefused" then
		push(MISSION_REASONS[data.reason or ""] or "You cannot start that mission now", Kit.color.paper)
	elseif SQ_IDS[id] then
		-- lore step 10: side quest chains (names from Config.SideQuests; nothing free-typed)
		local chain = SideQuestPlan.byBit(Config, data.bit or 0)
		local name = if chain then string.upper(chain.name) else "SIDE QUEST"
		if id == "sqStart" then
			push("NEW SIDE QUEST: " .. name, Kit.color.gold, true)
		elseif id == "sqStep" and chain then
			push(string.format("%s: step %d of %d", name, data.step or 1, #chain.steps), Kit.color.paper)
		elseif id == "sqDone" then
			push("SIDE QUEST DONE: " .. name, Kit.color.gold, true, 4.5)
		elseif id == "sqHold" then
			push(name .. " is on hold. Resume it from the Journal", Kit.color.paper)
		elseif id == "sqEncore" then
			-- lore step 11, chain 2: the finale's first villain is down and the second lands
			push("ENCORE! The real villain takes the stage", Kit.color.gold, true)
		elseif id == "sqWait" then
			push("Your part is done. Help the others finish theirs", Kit.color.paper)
		elseif id == "sqLocked" then
			push(SQ_LOCKED[data.why or ""] or "You cannot take that side quest yet", Kit.color.paper)
		elseif id == "sqTest" then
			push("Kind test done", Kit.color.paper)
		elseif id == "sqRetired" then
			local n = data.credits or 0
			push(
				if n > 0
					then string.format("Old side quests retired: %d Credits for your progress", n)
					else "Old side quests retired: your rewards are kept",
				Kit.color.gold,
				true,
				5
			)
		end
	elseif id == "raceReset" then
		push("Out of time! Back to the first ring", Kit.color.paper)
	elseif id == "pvpOn" then
		push("PVP ON: other flagged players can fight you", Color3.fromRGB(255, 120, 110), true)
	elseif id == "pvpOff" then
		push("PvP off", Kit.color.paper)
	elseif id == "pvpRefused" then
		local text = PVP_REASONS[data.reason or ""]
		if text then
			push(text, Kit.color.paper)
		end
	elseif id == "rematchSent" then
		push("Rematch ping sent to " .. tostring(data.name or "them"), Kit.color.paper)
	elseif id == "rematchOn" then
		push(
			"REMATCH ON WITH " .. string.upper(tostring(data.name or "")) .. "!",
			Color3.fromRGB(255, 120, 110),
			true
		)
	elseif id == "rematchRefused" then
		local text = REMATCH_REASONS[data.reason or ""]
		if text then
			push(text, Kit.color.paper)
		end
	elseif id == "craterIn" then
		push("THE CRATER: PVP ZONE, +50% RENOWN", Color3.fromRGB(255, 120, 110), true)
	elseif id == "revived" then
		push(
			string.format("You revived %s  +%d Renown", data.name or "", data.renown or 0),
			Kit.color.gold,
			true
		)
	elseif id == "revivedBy" then
		push(string.format("%s got you back up!", data.name or "Someone"), Kit.color.gold)
	elseif id == "reviveBlocked" then
		push("They are in a PvP fight: only a flagged ally can help", Kit.color.paper)
	elseif id == "respawnPick" then
		push("Respawn point picked", Kit.color.paper)
	elseif id == "fameRank" then
		push(
			string.format("%s RANK %d!", if data.side == "villain" then "INFAMY" else "FAME", data.rank or 1),
			Kit.color.gold,
			true,
			4.5
		)
	elseif id == "reported" then
		push("Thanks. Our team will look at it.", Kit.color.paper)
	elseif id == "reportedAlready" then
		push("You already reported them recently", Kit.color.paper)
	elseif id == "piece" then
		push(string.format("NEW LOOK PIECE: %s", string.upper(data.name or "")), Kit.color.gold, true, 4)
	elseif id == "heroSaved" then
		push(string.format("%s IS READY", string.upper(data.name or "YOUR HERO")), Kit.color.gold, true, 4)
	elseif id == "slotRefused" then
		push(M9_REASONS[data.reason or ""] or "You cannot switch heroes right now", Kit.color.paper)
	elseif id == "slotSwitched" then
		push(string.format("Switched to hero slot %d", data.slot or 1), Kit.color.gold)
	elseif id == "hqRefused" then
		push(M9_REASONS[data.reason or ""] or "You cannot go in right now", Kit.color.paper)
	elseif id == "hqMax" then
		push("Your HQ is at its top level", Kit.color.paper)
	elseif id == "hqCredits" then
		push(string.format("The next HQ level costs %s Credits", Kit.comma(data.cost or 0)), Kit.color.paper)
	elseif id == "hqLevel" then
		push(string.format("HQ LEVEL %d!", data.level or 1), Kit.color.gold, true, 4.5)
	elseif id == "mannequinLocked" then
		push("Upgrade your HQ to use that mannequin", Kit.color.paper)
	elseif id == "lookSaved" then
		push(string.format("Look saved on mannequin %d", data.n or 1), Kit.color.gold)
	elseif id == "lookBad" then
		push("That look has pieces you no longer have", Kit.color.paper)
	elseif id == "lookWorn" then
		push(string.format("Wearing mannequin %d's look", data.n or 1), Kit.color.gold)
	elseif id == "hqLocked" then
		push(string.format("Opens at HQ level %d", data.level or 1), Kit.color.paper)
	elseif id == "retireLevel" then
		push(string.format("Retiring opens at level %d", Config.Stats.levelCap), Kit.color.paper)
	elseif id == "legacy" then
		push(string.format("LEGACY RANK %d!", data.rank or 1), Kit.color.gold, true, 5)
		push("Your statue stands in the Hall of Legends", Kit.color.paper, false, 5)
	elseif id == "drones" then
		push(
			string.format("Your drones brought back %s Credits", Kit.comma(data.credits or 0)),
			Kit.color.gold,
			true,
			4.5
		)
	elseif id == "shopRefused" then
		if data.reason == "credits" then
			push(string.format("You need %s Credits", Kit.comma(data.cost or 0)), Kit.color.paper)
		else
			push(M9_REASONS[data.reason or ""] or "You cannot buy that right now", Kit.color.paper)
		end
	elseif id == "styleBought" then
		push("NEW STYLE! Equip it in GEAR > STYLES", Kit.color.gold, true, 4)
	elseif id == "visit" then
		-- WP12: a visit line from Config.Hq.visit (fixed text; the name is a hero or display name)
		local key = data.say or ""
		local big = key == "welcome" or key == "arrived"
		push(
			VisitRules.line(Config, key, data.name),
			if big or key == "sent" then Kit.color.gold else Kit.color.paper,
			big,
			if big then 4.5 else nil
		)
	elseif id == "squadRefused" then
		push(SQUAD_REASONS[data.reason or ""] or "Squad: try again", Kit.color.paper)
	elseif id == "squadInvited" then
		push(string.format("Squad invite sent to %s", data.name or ""), Kit.color.paper)
	elseif id == "squadJoin" then
		push("YOU JOINED THE SQUAD", Kit.color.gold, true, 4)
		push("Shared incident rewards, no friendly hits, squad pings", Kit.color.paper, false, 4)
	elseif id == "squadJoined" then
		push(string.format("%s joined the squad", data.name or ""), Kit.color.gold)
	elseif id == "squadLeft" then
		push(string.format("%s left the squad", data.name or ""), Kit.color.paper)
	elseif id == "squadGone" then
		push("Your squad split up", Kit.color.paper)
	elseif id == "squadKicked" then
		push("You were removed from the squad", Kit.color.paper)
	elseif id == "bought" then
		push(string.format("THANKS! %s IS YOURS", string.upper(data.name or "")), Kit.color.gold, true, 4.5)
	elseif id == "bossSim" then
		if data.killed then
			push(string.format("BOSS SIM DOWN in %d s!", math.floor(data.time or 0)), Kit.color.gold, true, 5)
		else
			push(
				string.format("Time! You dealt %s damage", Kit.comma(data.dealt or 0)),
				Kit.color.paper,
				true,
				5
			)
		end
	elseif id == "devBuy" then
		push(
			string.format(
				"Dev buy %s: %s",
				data.key or "?",
				if data.ok then "granted" else "nothing (replay)"
			),
			Kit.color.paper
		)
	elseif id == "mentorPart" then
		-- H6: a part of your mentor's quest line done
		push(
			string.format("Mentor quest part %d of %d done", data.part or 0, data.of or 4),
			Kit.color.gold,
			true
		)
	elseif id == "badgeMate" then
		-- H7: a squadmate near you earned a badge
		push(
			string.format("%s earned the %s badge", data.who or "A squadmate", data.name or "?"),
			Kit.color.paper
		)
	elseif id == "accolade" then
		-- H7: a whole badge group done
		push(
			string.format("Accolade earned: %s (wear it from BADGES > TITLES)", data.name or "?"),
			Kit.color.gold,
			true
		)
	elseif id == "collectSet" then
		-- H7: a full collection set
		push(
			string.format(
				"%s complete! +%s Renown and the %s for your HQ",
				data.name or "Set",
				Kit.comma(data.renown or 0),
				data.prop or "prop"
			),
			Kit.color.gold,
			true
		)
	elseif id == "scanner" then
		push("HQ Scanner on: a marker now shows your nearest missing find", Kit.color.gold)
	elseif id == "contestPlace" then
		-- H7: your costume contest result
		push(
			string.format(
				"Costume contest: %s place, +%s Credits",
				({ "1st", "2nd", "3rd" })[data.place or 0] or ((data.place or 0) .. "th"),
				Kit.comma(data.credits or 0)
			),
			if (data.place or 9) <= 3 then Kit.color.gold else Kit.color.paper,
			(data.place or 9) <= 3
		)
	elseif id == "contestSkipped" then
		push(
			string.format(
				"Not enough players for the contest this time: +%s Credits for showing up",
				Kit.comma(data.credits or 0)
			),
			Kit.color.paper
		)
	elseif id == "episodeStep" then
		-- H8: a step of this week's episode
		push(
			string.format("Episode step done: %s  +%s Renown", data.text or "?", Kit.comma(data.renown or 0)),
			Kit.color.gold
		)
	elseif id == "episodeDone" then
		push(
			string.format(
				"Episode %s done! +%s Renown and the week's badge",
				data.name or "",
				Kit.comma(data.renown or 0)
			),
			Kit.color.gold,
			true
		)
	elseif id == "contestWait" then
		push("Watch every contestant before you vote", Kit.color.muted)
	elseif id == "saveDown" then
		push(
			"Saving is down right now: this session's progress will not be kept",
			Color3.fromRGB(255, 150, 120),
			false,
			10
		)
	end
end

function Toasts.init()
	gui = Kit.screen("Toasts", 8)
	stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, 70)
	stack.Size = UDim2.new(0.9, 0, 0, 260)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stack
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(420, 260)
	limit.Parent = stack
	-- pt-ui: "+N more" under the toasts for the small notes folded while the line was long (Ui.Popups)
	local chip = Kit.label({
		Name = "More",
		Text = "",
		Size = UDim2.new(0, 120, 0, 24),
		BackgroundColor3 = Kit.color.paper,
		BackgroundTransparency = 0,
		TextColor3 = Kit.color.ink,
		LayoutOrder = 2 ^ 30,
		Visible = false,
		maxText = 16,
	})
	Kit.round(chip, 10)
	Kit.stroke(chip, Kit.color.ink, 2)
	chip.Parent = stack
	Popups.chip = chip
	stack.Parent = gui
	State.Toast:Connect(Toasts.show)
end

return Toasts
