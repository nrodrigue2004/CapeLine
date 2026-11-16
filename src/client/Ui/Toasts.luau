-- Toasts: short pop-ups in the top middle of the screen (spec: Remote events > Toast; Juice table: level up,
-- loot). Level up is a big gold banner with what just unlocked; a drop is a card in its tier colour (gold
-- and purple drops get a burst); rewards show +Credits and +Renown; Second Wind and a save outage get a
-- line each; beacons, safehouses and the bank get one too; so do incidents, contracts, photos and events. At most 4 show at once; older ones slide out. PLACEHOLDER look until M10 and M11.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progress = require(Shared:WaitForChild("Progress"))
local GearMath = require(Shared:WaitForChild("GearMath"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local GearScreen = require(script.Parent.GearScreen)
local ContractBoard = require(script.Parent.ContractBoard)

local Toasts = {}

local G = Config.Gear
local gui: ScreenGui
local stack: Frame
local MAX = 4

local REP_NAMES = { league = "LEAGUE", syndicate = "SYNDICATE", city = "CITY" }
local UNLOCK_NAMES: { [string]: string } = {
	MayorsSash = "Mayor's Sash style",
	DockCoat = "Dock Coat style",
	PhotoFrame = "Photo frame",
	CafeSign = "Cafe sign for your HQ",
	Salute = "Salute emote",
	NullEcho = "Null Echo, your drone buddy",
}
local M9_REASONS: { [string]: string } = {
	combat = "Not during a fight",
	scene = "Finish what you are doing first",
	busy = "Finish what you are doing first",
	side = "That is the other side's base",
	safehouse = "Switch heroes at your HQ or a safehouse",
	slot = "Buy that hero slot in the shop first",
	locked = "Buy that hero slot in the shop first",
	hq = "Buy styles from Gizmo at your HQ",
	where = "Open the shop at your HQ, a safehouse or the menu",
	soon = "Coming soon",
	slot3 = "Buy slot 3 first",
	owned = "You already own that",
}
local PVP_REASONS: { [string]: string } = {
	level = "PvP opens at level 10",
	rate = "Wait a moment before switching again",
	safe = "Step out of the safe area to switch PvP on",
	combat = "PvP can switch off 60 s after the last PvP hit",
	crater = "Leave the Comet Crater to switch PvP off",
}

local MISSION_REASONS: { [string]: string } = {
	level = "Reach the mission's level first",
	locked = "Finish the mission before it first",
	combat = "Leave combat first",
	busy = "Finish what you are doing first",
	full = "Every mission pocket is in use: try again in a minute",
	loading = "Still loading",
	mission = "That mission cannot be started here",
}

local function push(text: string, color: Color3, big: boolean?, life: number?)
	local kids = {}
	for _, c in stack:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(kids, c)
		end
	end
	if #kids >= MAX then
		table.sort(kids, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		kids[1]:Destroy()
	end
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, 0, 0, if big then 54 else 34),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.2,
		TextColor3 = color,
		TextStrokeTransparency = 0.4,
		LayoutOrder = math.floor(os.clock() * 100),
		maxText = if big then 40 else 22,
	})
	Kit.round(l, 8)
	Kit.stroke(l, color, if big then 3 else 2)
	l.Parent = stack
	Kit.pulse(l, if big then 0.35 else 0.15)
	task.delay(life or 3.5, function()
		if l.Parent then
			TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1 })
				:Play()
			task.wait(0.3)
			l:Destroy()
		end
	end)
end

function Toasts.show(data: { [string]: any })
	local id = data.id
	if id == "levelUp" then
		local unlock = Progress.UNLOCKS[data.level]
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
				color
			)
		else
			push(
				string.format("%s  (ilvl %d)", GearScreen.pieceName(piece), piece.ilvl),
				color,
				piece.tier >= 4,
				4.5
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
			string.format("%s CLEARED!  %s", string.upper(data.name or "Incident"), medal),
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
		push("SNAP! Sneak Bot photographed", Kit.color.volt)
	elseif id == "event" then
		push(string.format("EVENT: %s!", string.upper(data.name or "")), Kit.color.gold, true, 5)
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
			string.format("%s REPUTATION RANK %d", REP_NAMES[data.track] or "", data.rank or 1),
			Kit.color.gold,
			true,
			4.5
		)
	elseif id == "unlock" then
		local name = UNLOCK_NAMES[data.name or ""] or data.name or ""
		push(string.format("UNLOCKED: %s", string.upper(name)), Kit.color.gold, true, 4.5)
	elseif id == "choiceKept" then
		push("Your first choice stands on a replay", Kit.color.paper)
	elseif id == "missionRefused" then
		push(MISSION_REASONS[data.reason or ""] or "You cannot start that mission now", Kit.color.paper)
	elseif id == "questStep" then
		local q = Config.Story.quests[data.num or 0]
		if q then
			push(string.format("%s: step %d of 3", q.npc, math.min(3, data.step or 1)), Kit.color.paper)
		end
	elseif id == "questDone" then
		local q = Config.Story.quests[data.num or 0]
		if q then
			push(string.format("QUEST DONE: %s", string.upper(q.npc)), Kit.color.gold, true, 4.5)
		end
	elseif id == "raceReset" then
		push("Out of time! Back to the first ring", Kit.color.paper)
	elseif id == "wrongSide" then
		push("Talk to the mentor of your own side", Kit.color.paper)
	elseif id == "pvpOn" then
		push("PVP ON: other flagged players can fight you", Color3.fromRGB(255, 120, 110), true)
	elseif id == "pvpOff" then
		push("PvP off", Kit.color.paper)
	elseif id == "pvpRefused" then
		local text = PVP_REASONS[data.reason or ""]
		if text then
			push(text, Kit.color.paper)
		end
	elseif id == "craterIn" then
		push("COMET CRATER: PVP ZONE, +50% RENOWN", Color3.fromRGB(255, 120, 110), true)
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
		push("Retiring opens at level 40", Kit.color.paper)
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
		push("NEW STYLE! Equip it in GEAR > Show Style", Kit.color.gold, true, 4)
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
	stack.Parent = gui
	State.Toast:Connect(Toasts.show)
end

return Toasts
