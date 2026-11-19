-- LoadoutScreen: the POWERS screen (spec: Loadout rules; Skill points, ranks and respec; Screens and UI >
-- Skill tree). Pick a power set tab, learn and rank abilities with Skill Points, pick a mod at rank 3,
-- and build a loadout: the set's basic, up to 4 skills (slots open at levels 1, 1, 5 and 10) and a super
-- (level 20), with the 52-point budget shown live. The second loadout opens at level 15. SAVE sends
-- Hero.Loadout; the server checks everything again and answers with a notice.
-- Opens with the POWERS button, L on a keyboard, or D-pad down.
-- PLACEHOLDER look until the UI pass (M10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)

local LoadoutScreen = {}

local A = Config.Abilities
local gui: ScreenGui
local panel: Frame
local grid: ScrollingFrame
local header: TextLabel
local budget: TextLabel
local noticeLabel: TextLabel
local slotButtons: { TextButton } = {}
local superButton: TextButton
local tabButtons: { [string]: TextButton } = {}
local loadoutTabs: { TextButton } = {}
local respecButton: TextButton

local viewSet = "Volt"
local tabsFrame: Frame? = nil
local buildTabs: () -> ()
local draft = { set = "Volt", skills = {} :: { string }, super = nil :: string? }
local draftIndex = 1
local selectedSlot = 1 -- 1..4 skills, 5 super

local REASONS = {
	["over budget"] = "Over the 52-point budget",
	["not learned"] = "Learn it first",
	["set locked"] = "Other paths of your archetype open at level 15",
	["borrow limit"] = "You can learn up to 5 skills from other paths",
	["main path only"] = "Basics and supers come from your main path",
	["not the main path"] = "Your loadout uses your main path",
	["super locked"] = "Supers open at level 20",
	["too many skills"] = "No free slot yet",
	combat = "Not while fighting (wait 5 s)",
	points = "Not enough Skill Points",
	credits = "Not enough Credits",
	cooldown = "Respec is cooling down",
	["max rank"] = "Already max rank",
	["second loadout locked"] = "Loadout 2 opens at level 15",
	rank = "Reach rank 3 first",
	safehouse = "Change loadouts and respec at your HQ or a safehouse",
}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function notice(text: string, good: boolean?)
	noticeLabel.Text = text
	noticeLabel.TextColor3 = if good then Color3.fromRGB(120, 230, 140) else Color3.fromRGB(255, 150, 120)
	Kit.pulse(noticeLabel, 0.08)
end

-- One line about what an ability does, from its numbers
local function describe(eff: any): string
	local parts = {}
	local shape = eff.shape
	if shape == "bolt" then
		table.insert(
			parts,
			if eff.channel then string.format("Beam %.0f s", eff.channel * (eff.tick or 0.25)) else "Shot"
		)
	elseif shape == "chain" then
		table.insert(parts, string.format("Jumps to %d", eff.targets or 3))
	elseif shape == "dash" then
		table.insert(parts, string.format("Dash %d", math.floor(eff.range)))
	elseif shape == "cone" then
		table.insert(parts, "Cone")
	elseif shape == "arc" then
		table.insert(
			parts,
			if eff.hits
				then string.format("%d-hit combo", #eff.hits)
				elseif eff.channel then string.format("%d cuts", eff.channel)
				else "Melee"
		)
	elseif shape == "nova" then
		table.insert(parts, string.format("Burst r%d", math.floor(eff.radius)))
	elseif shape == "field" then
		table.insert(parts, string.format("Field r%d, %.0f s", math.floor(eff.radius), eff.duration))
	elseif shape == "line" then
		table.insert(parts, string.format("Line %d", math.floor(eff.range)))
	elseif shape == "leap" then
		table.insert(parts, string.format("Leap %d, r%d", math.floor(eff.range), math.floor(eff.radius)))
	elseif shape == "throw" then
		table.insert(parts, "Lift and throw")
	elseif shape == "buff" then
		local v = eff.value or 0
		local what = ({
			attackSpeed = "attack speed",
			shield = "health shield",
			mitigation = "less damage",
			power = "power",
			speed = "run speed",
			parry = "parry",
		})[eff.buff] or eff.buff
		if eff.buff == "parry" then
			table.insert(parts, string.format("Parry %.1f s", eff.duration))
		else
			table.insert(
				parts,
				string.format("+%d%% %s %.0f s", math.floor(v * 100 + 0.5), what, eff.duration)
			)
		end
		if eff.allies then
			table.insert(parts, "allies")
		end
	elseif shape == "wall" then
		table.insert(parts, string.format("%d wall pieces", eff.pieces or 3))
	elseif shape == "ramp" then
		table.insert(parts, string.format("Ice ramp %.0f s", eff.duration))
	end
	if eff.coeff and eff.coeff > 0 then
		table.insert(parts, string.format("%.2fx", eff.coeff))
	end
	if eff.status then
		table.insert(
			parts,
			eff.status .. (if eff.statusDur then string.format(" %.1f s", eff.statusDur) else "")
		)
	end
	if eff.slot ~= "basic" then
		table.insert(parts, string.format("%.0f s cd", eff.cd))
	end
	return table.concat(parts, ", ")
end

local function pips(rank: number, max: number): string
	local s = ""
	for i = 1, max do
		s ..= if i <= rank then "●" else "○"
	end
	return s
end

local refresh: () -> ()

local function equip(id: string)
	local row = A.list[id]
	local h = State.hero
	if row.slot == "super" then
		if not AbilityRules.superUnlocked(Config, h.level) then
			notice(REASONS["super locked"])
			return
		end
		draft.super = id
		selectedSlot = 5
	elseif row.slot == "skill" then
		local slots = AbilityRules.skillSlots(Config, h.level)
		local existing = table.find(draft.skills, id)
		if existing then
			table.remove(draft.skills, existing)
		end
		local at = math.min(selectedSlot, slots)
		if at > #draft.skills + 1 then
			at = #draft.skills + 1
		end
		if at > slots then
			notice(REASONS["too many skills"])
			return
		end
		draft.skills[at] = id
		selectedSlot = math.min(slots, at + 1)
	end
	refresh()
end

local function card(id: string, order: number): Frame
	local h = State.hero
	local row = A.list[id]
	local rank = h.ranks[id] or 0
	local eff = AbilityRules.effective(Config, id, math.max(rank, 1), h.mods[id])
	local unlocked = AbilityRules.setUnlocked(Config, h.level, row.set, h.startSet)
	local f = Kit.frame({
		Name = id,
		LayoutOrder = order,
		BackgroundColor3 = if unlocked then Kit.color.paper else Color3.fromRGB(150, 150, 160),
	})
	Kit.stroke(f, rgb(A.setColor[row.set]), 3)
	-- gap-icons (2026-11-19): the power's comic icon at the top left; the name and cost move over for it
	local icon = Kit.icon("ability", id, {
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(6, 4),
		ImageTransparency = if unlocked then 0 else 0.45,
	})
	local textX = if icon then 50 else 6
	if icon then
		icon.Parent = f
	end
	local title = Kit.label({
		Text = string.upper(row.name),
		Size = UDim2.new(1, -textX - 6, 0, 22),
		Position = UDim2.fromOffset(textX, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 20,
	})
	title.Parent = f
	local tag = if row.slot == "basic"
		then "BASIC"
		elseif row.slot == "super" then "SUPER"
		elseif row.travel then string.format("TRAVEL  %d PTS", row.pts)
		else string.format("%d PTS", row.pts)
	local sub = Kit.label({
		Text = tag .. "   " .. (if row.slot == "basic" then "" else pips(rank, AbilityRules.maxRank(row))),
		Size = UDim2.new(1, -textX - 6, 0, 16),
		Position = UDim2.fromOffset(textX, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Kit.bodyFont,
		TextColor3 = Kit.color.muted,
		maxText = 13,
	})
	sub.Parent = f
	local desc = Kit.label({
		Text = describe(eff),
		Size = UDim2.new(1, -12, 0, 30),
		Position = UDim2.fromOffset(6, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Font = Kit.bodyFont,
		maxText = 12,
	})
	desc.Parent = f
	if not unlocked or (row.set ~= h.startSet and row.slot ~= "skill") then
		local lock = Kit.label({
			Text = if unlocked then "MAIN PATH ONLY" else string.format("LOCKED: LEVEL %d", A.borrowLevel),
			Size = UDim2.new(1, -12, 0, 22),
			Position = UDim2.new(0, 6, 1, -28),
			maxText = 16,
		})
		lock.Parent = f
		return f
	end
	if row.slot ~= "basic" then
		local ok, reason, pts, cr = AbilityRules.canRank(Config, h, id, Config.Dev.freeRankCredits)
		local cost = if cr > 0
			then string.format("%d PT %s CR", pts, Kit.comma(cr))
			else string.format("%d PT", pts)
		local label = if rank == 0 then "LEARN " .. cost else "RANK UP " .. cost
		if reason == "max rank" then
			label = "MAX"
		end
		local rb = Kit.button({
			pending = true,
			Text = label,
			Size = UDim2.new(0.5, -9, 0, 40), -- phone pass: a 40 px tap target, two lines
			Position = UDim2.new(0, 6, 1, -44),
			TextWrapped = true,
			BackgroundColor3 = if ok then Kit.color.gold else Color3.fromRGB(190, 190, 195),
			maxText = 14,
		}, function()
			if ok then
				Net.send("SkillsRank", row.num)
			else
				notice(REASONS[reason or ""] or "Can't rank that yet")
			end
		end)
		rb.Parent = f
		local eb = Kit.button({
			Text = if rank > 0 then "EQUIP" else "-",
			Size = UDim2.new(0.5, -9, 0, 40),
			Position = UDim2.new(0.5, 3, 1, -44),
			BackgroundColor3 = if rank > 0 then rgb(A.setColor[row.set]) else Color3.fromRGB(190, 190, 195),
			maxText = 14,
		}, function()
			if rank > 0 then
				equip(id)
			else
				notice(REASONS["not learned"])
			end
		end)
		eb.Parent = f
		-- mods at rank 3 (rank 2 for supers)
		local modRank = if row.slot == "super" then 2 else 3
		if row.mods and rank >= modRank then
			for k, mod in row.mods do
				local picked = h.mods[id] == k
				local mb = Kit.button({
					pending = true,
					Text = mod.name,
					Size = UDim2.new(0.5, -9, 0, 24),
					Position = UDim2.new((k - 1) * 0.5, if k == 1 then 6 else 3, 1, -66),
					BackgroundColor3 = if picked
						then Color3.fromRGB(120, 230, 140)
						else Color3.fromRGB(225, 225, 230),
					maxText = 12,
				}, function()
					Net.send("SkillsMod", row.num, k)
				end)
				mb.Parent = f
			end
		end
	end
	return f
end

-- gap-icons: a loadout slot shows its power's icon at the left, the name beside it (no icon: the name alone)
local function slotIcon(b: TextButton, id: string?)
	local pad = b:FindFirstChildOfClass("UIPadding") -- Kit.button's own (8 px a side)
	local icon = b:FindFirstChild("SlotIcon") :: ImageLabel?
	local on = id ~= nil and Kit.iconCell("ability", id) ~= nil
	if on and not icon then
		local made = Kit.icon("ability", id, {
			Name = "SlotIcon",
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromOffset(40, 40),
			ZIndex = b.ZIndex,
		}) :: ImageLabel
		made.Parent = b
		icon = made
	end
	if icon and on and id then
		Kit.setIcon(icon, "ability", id)
	end
	-- a phone's slots are too narrow for icon and name: the icon alone, centred (the cards above name it)
	local alone = on and Kit.compact()
	if alone then
		b.Text = ""
	end
	local left = if on and not alone then 52 else 8
	if pad and pad.PaddingLeft.Offset ~= left then
		pad.PaddingLeft = UDim.new(0, left)
		if b:FindFirstChild("InkLine") then
			Kit.ink(b) -- re-place the ink shadow (it undoes the padding)
		end
	end
	if icon then
		icon.Visible = on
		icon.AnchorPoint = if alone then Vector2.new(0.5, 0.5) else Vector2.new(0, 0.5)
		icon.Position = if alone
			then UDim2.fromScale(0.5, 0.5)
			else UDim2.new(0, 5 - (if pad then left else 0), 0.5, 0) -- 5 px in from the button's edge
	end
end

local function slotText(id: string?, lockedAt: number?): string
	if lockedAt then
		return string.format("LV %d", lockedAt)
	end
	if not id then
		return "+"
	end
	return string.upper(A.list[id].name)
end

-- one tab per path of the hero's archetype (rebuilt when the archetype changes)
local tabsClass: string? = nil
buildTabs = function()
	local classId = State.hero.classId
	if not tabsFrame or tabsClass == classId then
		return
	end
	tabsClass = classId
	for _, b in tabButtons do
		b:Destroy()
	end
	table.clear(tabButtons)
	for _, set in AbilityRules.paths(Config, classId) do
		local b = Kit.button({
			Text = string.upper(A.setName[set] or set),
			Size = UDim2.new(0.2, -6, 1, 0),
			TextWrapped = true, -- phone pass: two lines on a narrow tab
			maxText = 18,
		}, function()
			viewSet = set
			refresh()
		end)
		b.Parent = tabsFrame
		tabButtons[set] = b
	end
end

refresh = function()
	if not panel or not panel.Visible then
		return
	end
	local h = State.hero
	header.Text = string.format("POWERS   LV %d   SKILL POINTS %d", h.level, h.points or 0)
	buildTabs()
	local borrowed = AbilityRules.borrowed(Config, h.ranks, h.startSet)
	for set, b in tabButtons do
		local open = AbilityRules.setUnlocked(Config, h.level, set, h.startSet)
		local name = string.upper(A.setName[set] or set)
		b.Text = if set == h.startSet
			then name .. " (MAIN)"
			elseif open then string.format("%s  %d/%d", name, borrowed, A.borrowMax)
			else string.format("%s LV%d", name, A.borrowLevel)
		b.BackgroundColor3 = if set == viewSet then rgb(A.setColor[set]) else Color3.fromRGB(210, 210, 215)
	end
	for i, b in loadoutTabs do
		local locked = i == 2 and h.level < A.secondLoadoutLevel
		b.Text = if locked then string.format("LOADOUT 2 (LV %d)", A.secondLoadoutLevel) else "LOADOUT " .. i
		b.BackgroundColor3 = if i == draftIndex then Kit.color.gold else Color3.fromRGB(210, 210, 215)
	end
	local used = AbilityRules.loadoutPoints(Config, draft.skills)
	budget.Text = string.format(
		"BUDGET %d / %d   MAIN PATH %s",
		used,
		A.loadoutCap,
		string.upper(A.setName[draft.set] or draft.set)
	)
	budget.TextColor3 = if used > A.loadoutCap then Color3.fromRGB(255, 120, 100) else Kit.color.paper
	local slots = AbilityRules.skillSlots(Config, h.level)
	for i, b in slotButtons do
		local lockedAt = if i > slots then A.slotLevels[i] else nil
		b.Text = slotText(draft.skills[i], lockedAt)
		slotIcon(b, if lockedAt then nil else draft.skills[i])
		b.BackgroundColor3 = if i == selectedSlot then Kit.color.gold else Kit.color.paper
	end
	superButton.Text =
		slotText(draft.super, if AbilityRules.superUnlocked(Config, h.level) then nil else A.superLevel)
	slotIcon(superButton, if AbilityRules.superUnlocked(Config, h.level) then draft.super else nil)
	superButton.BackgroundColor3 = if selectedSlot == 5 then Kit.color.gold else Kit.color.paper
	local left = math.max(0, h.respecIn or 0)
	respecButton.Text = if left > 0 then string.format("RESPEC %s", Kit.time(left)) else "RESPEC"
	for _, c in grid:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local n = 0
	for _, id in A.order do
		if A.list[id].set == viewSet then
			n += 1
			card(id, n).Parent = grid
		end
	end
end

local function loadDraft(index: number)
	local h = State.hero
	local l = (h.loadouts and h.loadouts[index]) or h.loadout
	draftIndex = index
	draft = { set = l.set or h.setId, skills = table.clone(l.skills or {}), super = l.super }
	viewSet = draft.set
	selectedSlot = math.min(#draft.skills + 1, math.max(1, AbilityRules.skillSlots(Config, h.level)))
end

local function save()
	local function num(id: string?): number
		return if id then A.list[id].num else 0
	end
	local setNum = table.find(A.sets, draft.set) or 1
	local s = draft.skills
	Net.send("HeroLoadout", draftIndex, setNum, num(s[1]), num(s[2]), num(s[3]), num(s[4]), num(draft.super))
end

function LoadoutScreen.open()
	loadDraft(State.hero.loadoutIndex or 1)
	Kit.opening("LoadoutScreen", panel, LoadoutScreen.close, true)
	panel.Visible = true
	refresh()
end

function LoadoutScreen.close()
	panel.Visible = false
end

function LoadoutScreen.toggle()
	if panel.Visible then
		LoadoutScreen.close()
	else
		LoadoutScreen.open()
	end
end

function LoadoutScreen.init()
	gui = Kit.screen("Loadout", 5)
	panel = Kit.frame({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.92, 0),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(980, 720)
	limit.Parent = panel
	panel.Parent = gui
	header = Kit.label({
		Text = "POWERS",
		Size = UDim2.new(1, -140, 0, 34),
		Position = UDim2.fromOffset(14, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 30,
	})
	header.Parent = panel
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(Config.Ui.touchTarget, Config.Ui.touchTarget - 10),
		Position = UDim2.new(1, -Config.Ui.touchTarget - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, LoadoutScreen.close)
	close.Parent = panel
	-- set tabs
	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, -20, 0, 40)
	tabs.Position = UDim2.fromOffset(10, 48)
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 6)
	tl.Parent = tabs
	tabs.Parent = panel
	tabsFrame = tabs
	-- the cards
	grid = Instance.new("ScrollingFrame")
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Size = UDim2.new(1, -20, 1, -250)
	grid.Position = UDim2.fromOffset(10, 94)
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(220, 150)
	gl.CellPadding = UDim2.fromOffset(8, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	grid.Parent = panel
	-- the loadout row
	local bottom = Instance.new("Frame")
	bottom.BackgroundTransparency = 1
	bottom.Size = UDim2.new(1, -20, 0, 150)
	bottom.Position = UDim2.new(0, 10, 1, -152)
	bottom.Parent = panel
	budget = Kit.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		maxText = 20,
	})
	budget.Parent = bottom
	for i = 1, 2 do
		local b = Kit.button({
			Text = "LOADOUT " .. i,
			Size = UDim2.fromOffset(170, 28),
			Position = UDim2.new(1, -350 + (i - 1) * 176, 0, 0),
			maxText = 14,
		}, function()
			if i == 2 and State.hero.level < A.secondLoadoutLevel then
				notice(REASONS["second loadout locked"])
				return
			end
			loadDraft(i)
			refresh()
		end)
		b.Parent = bottom
		loadoutTabs[i] = b
	end
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 56)
	row.Position = UDim2.fromOffset(0, 30)
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 6)
	rl.Parent = row
	row.Parent = bottom
	for i = 1, 4 do
		local b = Kit.button({
			Text = "+",
			Size = UDim2.new(0.18, -6, 1, 0),
			BackgroundColor3 = Kit.color.paper,
			TextWrapped = true,
			maxText = 14,
		}, function()
			if selectedSlot == i and draft.skills[i] then
				table.remove(draft.skills, i) -- a second tap clears the slot
			end
			selectedSlot = i
			refresh()
		end)
		b.Parent = row
		slotButtons[i] = b
	end
	superButton = Kit.button({
		Text = "+",
		Size = UDim2.new(0.22, -6, 1, 0),
		BackgroundColor3 = Kit.color.paper,
		TextWrapped = true,
		maxText = 14,
	}, function()
		if selectedSlot == 5 and draft.super then
			draft.super = nil
		end
		selectedSlot = 5
		refresh()
	end)
	superButton.Parent = row
	noticeLabel = Kit.label({
		Text = "Tap a slot, then EQUIP a power. Skills come from any unlocked set.",
		Size = UDim2.new(0.6, 0, 0, 24),
		Position = UDim2.fromOffset(0, 92),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.muted,
		Font = Kit.bodyFont,
		maxText = 14,
	})
	noticeLabel.Parent = bottom
	local primary = Kit.button({
		Text = "SET PRIMARY",
		Size = UDim2.fromOffset(150, 40),
		Position = UDim2.new(1, -470, 1, -42),
		BackgroundColor3 = Kit.color.paper,
		maxText = 16,
	}, function()
		if not AbilityRules.setUnlocked(Config, State.hero.level, viewSet, State.hero.startSet) then
			notice(REASONS["set locked"])
			return
		end
		draft.set = viewSet -- the primary set gives the basic attack and the look
		refresh()
	end)
	primary.Visible = false -- the main path is set in the creator (one free change before level 10)
	primary.Parent = bottom
	respecButton = Kit.button({
		pending = true,
		Text = "RESPEC",
		Size = UDim2.fromOffset(150, 40),
		Position = UDim2.new(1, -312, 1, -42),
		BackgroundColor3 = Color3.fromRGB(255, 150, 120),
		maxText = 16,
	}, function()
		Net.send("SkillsRespec")
	end)
	respecButton.Parent = bottom
	local saveB = Kit.button({
		Text = "SAVE",
		Size = UDim2.fromOffset(150, 40),
		Position = UDim2.new(1, -154, 1, -42),
		BackgroundColor3 = Color3.fromRGB(120, 230, 140),
		maxText = 18,
	}, save)
	saveB.Parent = bottom

	-- phone pass: the panel fits the screen (Kit.fit); on a phone the loadout row becomes a column on the
	-- right so the cards keep the height to scroll, and every button stays a thumb's size
	budget.TextWrapped = true
	noticeLabel.TextWrapped = true
	Kit.fit(panel, 600, 286, 980, 720)
	local function place()
		local compact = Kit.compact()
		for i, b in loadoutTabs do
			b.Size = if compact then UDim2.new(0.5, -3, 0, 40) else UDim2.fromOffset(170, 40)
			b.Position = if compact
				then UDim2.new((i - 1) * 0.5, (i - 1) * 3, 0, 38)
				else UDim2.new(1, -350 + (i - 1) * 176, 0, 0)
		end
		for _, b in slotButtons do
			b.Size = if compact then UDim2.new(0.2, -5, 1, 0) else UDim2.new(0.18, -6, 1, 0)
		end
		superButton.Size = if compact then UDim2.new(0.2, -5, 1, 0) else UDim2.new(0.22, -6, 1, 0)
		if compact then
			tabs.Size = UDim2.new(1, -330, 0, 40)
			grid.Size = UDim2.new(1, -330, 1, -100)
			bottom.Position = UDim2.new(1, -310, 0, 48)
			bottom.Size = UDim2.new(0, 300, 1, -54)
			budget.Size = UDim2.new(1, 0, 0, 34)
			row.Position = UDim2.fromOffset(0, 82)
			row.Size = UDim2.new(1, 0, 0, 48)
			noticeLabel.Position = UDim2.fromOffset(0, 134)
			noticeLabel.Size = UDim2.new(1, 0, 0, 40)
			respecButton.Size = UDim2.new(0.5, -3, 0, 44)
			respecButton.Position = UDim2.new(0, 0, 1, -44)
			saveB.Size = UDim2.new(0.5, -3, 0, 44)
			saveB.Position = UDim2.new(0.5, 3, 1, -44)
		else
			tabs.Size = UDim2.new(1, -20, 0, 40)
			grid.Size = UDim2.new(1, -20, 1, -250)
			bottom.Position = UDim2.new(0, 10, 1, -152)
			bottom.Size = UDim2.new(1, -20, 0, 150)
			budget.Size = UDim2.new(1, -360, 0, 36)
			row.Position = UDim2.fromOffset(0, 40)
			row.Size = UDim2.new(1, 0, 0, 50)
			noticeLabel.Position = UDim2.fromOffset(0, 96)
			noticeLabel.Size = UDim2.new(0.6, 0, 0, 50)
			respecButton.Size = UDim2.fromOffset(150, 44)
			respecButton.Position = UDim2.new(1, -312, 1, -46)
			saveB.Size = UDim2.fromOffset(150, 44)
			saveB.Position = UDim2.new(1, -154, 1, -46)
		end
	end
	place()
	Kit.LayoutChanged:Connect(function()
		place()
		refresh() -- the slots' icon-only phone look follows the screen size
	end)

	InputController.Pressed:Connect(function(action)
		if action == "Loadout" then
			LoadoutScreen.toggle()
		end
	end)
	State.Changed:Connect(refresh)
	State.Notice:Connect(function(ok, reason)
		if ok then
			notice("Done", true)
		else
			notice(REASONS[reason or ""] or ("Not allowed: " .. tostring(reason)))
		end
	end)
end

return LoadoutScreen
