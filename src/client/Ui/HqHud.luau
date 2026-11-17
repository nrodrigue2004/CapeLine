-- HqHud: the HQ's station panels (spec: Hero HQ stations; Character slots; Legacy).
-- * COMMAND TABLE: the Contract Board, the Journal, and HEROES (your character slots: switch, start a new
--   hero in a free slot, or buy slot 3 or 4 in the shop).
-- * GIZMO'S BENCH: 40 base styles for Credits (never stats), GEAR (upgrade with Lumen Dust) and UPGRADE HQ.
-- * MANNEQUINS: save the look you wear, wear a saved one, or EDIT LOOK (the creator, class changes too).
-- * TRAINING ROOM: the damage-per-second meter, POWERS, and the 60 s boss sim (HQ level 3) with its timer.
-- * TROPHY WALL: pick which earned trophies show. HALL OF LEGENDS: Retire at level 40, with a confirm.
-- PLACEHOLDER look until the UI pass (M10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ShopRules = require(Shared:WaitForChild("ShopRules"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local GearMath = require(Shared:WaitForChild("GearMath"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local HqClient = require(script.Parent.Parent.Controllers.HqClient)
local GearScreen = require(script.Parent.GearScreen)
local LoadoutScreen = require(script.Parent.LoadoutScreen)
local Journal = require(script.Parent.Journal)
local CreatorScreen = require(script.Parent.CreatorScreen)
local ShopHud = require(script.Parent.ShopHud)

local HqHud = {}

local H = Config.Hq
local T = Config.Ui.touchTarget
local TITLES = {
	command = "COMMAND TABLE",
	gizmo = "GIZMO'S BENCH",
	mannequins = "MANNEQUINS",
	training = "TRAINING ROOM",
	trophies = "TROPHY WALL",
	legends = "HALL OF LEGENDS",
}

local gui: ScreenGui
local panel: Frame
local title: TextLabel
local body: ScrollingFrame
local meter: TextLabel
local simBar: Frame
local simFill: Frame
local simText: TextLabel
local current: string? = nil
local sub: string? = nil -- "heroes" under the command table, "confirm" under the hall
local picks: { number } = {}
local lastDps: { [string]: any } = { dps = 0, total = 0 }

local function clearBody()
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local order = 0
local function row(text: string, onClick: (() -> ())?, color: Color3?, waits: boolean?): TextButton
	order += 1
	local b = Kit.button({
		Text = text,
		pending = waits == true,
		Size = UDim2.new(1, -8, 0, T),
		LayoutOrder = order,
		BackgroundColor3 = color or Kit.color.paper,
		maxText = 20,
	}, onClick)
	b.Parent = body
	return b
end

local function note(text: string)
	order += 1
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, -8, 0, 22),
		AutomaticSize = Enum.AutomaticSize.Y, -- phone pass: long notes wrap instead of shrinking
		LayoutOrder = order,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 14,
	})
	l.Parent = body
end

local draw: () -> ()

local function heroName(titleId: number?, nounId: number?): string
	return CreatorRules.heroName(Config, titleId or 0, nounId or 0) or "Unnamed hero"
end

local function drawHeroes()
	local roster = State.profile.roster or {}
	local max = CreatorRules.maxSlots({ purchases = { slots = State.profile.slots or 0 } })
	for slot = 1, 4 do
		local c = roster[slot]
		if c then
			local active = slot == (State.profile.active or 1)
			row(
				string.format(
					"%s%s  Lv %d %s%s",
					if active then "▶ " else "",
					string.upper(heroName(c.titleId, c.nounId)),
					c.level or 1,
					c.classId or "",
					if (c.legacy or 0) > 0 then "  ★" .. c.legacy else ""
				),
				function()
					if not active then
						Net.send("HeroSelect", slot)
					end
				end,
				if active then Kit.color.gold else Kit.color.paper
			)
		elseif slot <= max then
			row("+ NEW HERO (slot " .. slot .. ")", function()
				Net.send("HeroSelect", slot)
			end, Kit.color.gold, true)
		else
			row("SLOT " .. slot .. ": BUY IN THE SHOP", function()
				HqHud.close()
				ShopHud.open("slots")
			end, Kit.color.muted)
		end
	end
	row("BACK", function()
		sub = nil
		draw()
	end)
end

local function drawCommand()
	if sub == "heroes" then
		drawHeroes()
		return
	end
	row("CONTRACT BOARD", function()
		Net.send("HqBoard")
		HqHud.close()
	end, Kit.color.gold)
	row("JOURNAL (story replays, side quests)", function()
		HqHud.close()
		Journal.open()
	end)
	row("HEROES (character slots)", function()
		sub = "heroes"
		draw()
	end)
end

local function drawGizmo()
	local s = HqClient.state()
	local owned = {}
	for _, id in State.profile.styles or {} do
		owned[id] = true
	end
	row("GEAR (upgrade with Lumen Dust)", function()
		HqHud.close()
		GearScreen.open()
	end)
	if s.upgrade then
		row(
			string.format("UPGRADE HQ to level %d: %s Credits", (s.level or 1) + 1, Kit.comma(s.upgrade)),
			function()
				Net.send("HqUpgrade")
			end,
			Kit.color.gold
		)
	else
		note("Your HQ is at its top level")
	end
	note("Gizmo's styles: looks only, never stats. Credits: " .. Kit.comma(State.hero.credits or 0))
	for _, e in ShopRules.gizmo(Config) do
		local slotIdx = GearMath.styleParts(e.id)
		local slot = Config.Gear.slotOrder[slotIdx] or ""
		local have = owned[e.id] == true
		row(
			string.format(
				"%s  (%s, %s)  %s",
				e.row.name or "Style",
				slot,
				e.row.tier,
				if have then "OWNED" else Kit.comma(e.price) .. " CR"
			),
			function()
				if not have then
					Net.send("GizmoBuy", e.id)
				end
			end,
			if have then Kit.color.muted else Kit.color.paper
		)
	end
end

local function drawMannequins()
	local s = HqClient.state()
	local looks = State.profile.looks or {}
	row("EDIT LOOK (creator, class)", function()
		HqHud.close()
		CreatorScreen.open({ mode = "edit", hq = true })
	end, Kit.color.gold)
	for n = 1, H.levels.mannequins[#H.levels.mannequins] do
		local open = n <= (s.mannequins or 1)
		local saved = looks[n] ~= nil and (looks[n][1] or 0) ~= 0
		if open then
			row(string.format("MANNEQUIN %d: SAVE MY LOOK", n), function()
				Net.send("LookSave", n)
			end, nil, true)
			if saved then
				row(string.format("MANNEQUIN %d: WEAR", n), function()
					Net.send("LookWear", n)
				end, Kit.color.gold, true)
			end
		else
			note(string.format("Mannequin %d opens at HQ level 2", n))
		end
	end
end

local function drawTraining()
	local s = HqClient.state()
	row("POWERS (try a new loadout)", function()
		HqHud.close()
		LoadoutScreen.open()
	end)
	if s.bossSim then
		row(string.format("BOSS SIM: %s HP in %d s", Kit.comma(H.bossSim.hp), H.bossSim.time), function()
			Net.send("HqBossSim")
		end, Kit.color.gold, true)
		note("Step out of the red rings")
	else
		note(string.format("The boss sim opens at HQ level %d", H.levels.bossSim))
	end
end

local function drawTrophies()
	local s = HqClient.state()
	local slots = s.trophySlots or 3
	local earned = s.earned or {}
	if #earned == 0 then
		note("Earn trophies: bosses, the story, rescues, Fame and more")
	end
	note(string.format("Pick up to %d to show", slots))
	for _, idx in earned do
		local t = H.trophies[idx]
		local on = table.find(picks, idx) ~= nil
		row((if on then "✓ " else "") .. t.name, function()
			local at = table.find(picks, idx)
			if at then
				table.remove(picks, at)
			elseif #picks < slots then
				table.insert(picks, idx)
			end
			draw()
		end, if on then Kit.color.gold else Kit.color.paper)
	end
	if #earned > 0 then
		row("SAVE THE WALL", function()
			Net.send("HqTrophies", picks)
		end, Kit.color.gold, true)
	end
end

local function drawLegends()
	local s = HqClient.state()
	note(
		string.format(
			"%d statue%s in the hall",
			#(s.statues or {}),
			if #(s.statues or {}) == 1 then "" else "s"
		)
	)
	if sub == "confirm" then
		note("Retire this hero? They become a statue here. You start again at level 1 with the same look,")
		note("name and side, keep your Fame and reputation, and earn a Legacy rank (+XP and Credits).")
		row("YES, RETIRE", function()
			Net.send("HqRetire")
			sub = nil
			HqHud.close()
		end, Kit.color.gold)
		row("NOT YET", function()
			sub = nil
			draw()
		end)
		return
	end
	if s.canRetire then
		row("RETIRE (Legacy)", function()
			sub = "confirm"
			draw()
		end, Kit.color.gold)
	else
		note(string.format("Retiring opens at level %d", H.legacy.level))
	end
end

draw = function()
	clearBody()
	order = 0
	if not current then
		panel.Visible = false
		return
	end
	panel.Visible = true
	title.Text = TITLES[current] or ""
	meter.Visible = current == "training"
	if current == "command" then
		drawCommand()
	elseif current == "gizmo" then
		drawGizmo()
	elseif current == "mannequins" then
		drawMannequins()
	elseif current == "training" then
		drawTraining()
	elseif current == "trophies" then
		drawTrophies()
	elseif current == "legends" then
		drawLegends()
	end
	row("SHOP", function()
		HqHud.close()
		ShopHud.open()
	end, Kit.color.paper)
	row("CLOSE", HqHud.close, Kit.color.muted)
end

function HqHud.open(name: string)
	current = name
	sub = nil
	if name == "trophies" then
		picks = table.clone(HqClient.state().trophies or {})
	end
	draw()
end

function HqHud.close()
	current = nil
	sub = nil
	draw()
end

function HqHud.isOpen(): boolean
	return current ~= nil
end

local function build()
	gui = Kit.screen("HqHud", 7)
	panel = Kit.frame({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0.42, 0, 0.8, 0),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	Kit.stroke(panel, Kit.color.gold, 3)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(300, 260)
	limit.MaxSize = Vector2.new(520, 640)
	limit.Parent = panel
	panel.Parent = gui
	title = Kit.label({
		Text = "",
		Size = UDim2.new(1, -16, 0, 36),
		Position = UDim2.fromOffset(8, 6),
		TextColor3 = Kit.color.gold,
		maxText = 30,
	})
	title.Parent = panel
	meter = Kit.label({
		Text = "DPS 0",
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 44),
		TextColor3 = Kit.color.paper,
		Visible = false,
		maxText = 24,
	})
	meter.Parent = panel
	body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(8, 80)
	body.Size = UDim2.new(1, -16, 1, -88)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.ScrollBarThickness = 6
	body.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = body
	-- the boss sim's bar (top middle, shown while it runs)
	simBar = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.new(0.5, 0, 0, 26),
		BackgroundColor3 = Kit.color.ink,
		Visible = false,
	})
	simBar.Parent = gui
	simFill = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 120, 60) })
	simFill.Parent = simBar
	simText = Kit.label({
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.3,
		ZIndex = 2,
		maxText = 20,
	})
	simText.Parent = simBar
end

-- The offline drones' COLLECT card (spec: Wait table "Away ... collected with one tap")
local dronesCard: Frame? = nil
local function showDrones(d: { [string]: any })
	if dronesCard then
		dronesCard:Destroy()
	end
	local card = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(360, 150),
		BackgroundColor3 = Kit.color.night,
	})
	Kit.stroke(card, Kit.color.gold, 3)
	local hours = math.floor((d.minutes or 0) / 60)
	local l = Kit.label({
		Text = string.format(
			"YOUR DRONES ARE BACK\n%s Credits from %s away",
			Kit.comma(d.credits or 0),
			if hours >= 1 then hours .. " h" else (d.minutes or 0) .. " min"
		),
		Size = UDim2.new(1, -20, 0, 70),
		Position = UDim2.fromOffset(10, 8),
		TextColor3 = Kit.color.gold,
		TextWrapped = true,
		maxText = 22,
	})
	l.Parent = card
	local b = Kit.button({
		Text = "COLLECT",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(200, T),
	}, function()
		Net.send("HqCollect")
		card:Destroy()
		if dronesCard == card then
			dronesCard = nil
		end
	end)
	b.Parent = card
	card.Parent = gui
	Kit.pulse(card, 0.2)
	dronesCard = card
end

function HqHud.init()
	build()
	Net.listen("DronesReady", showDrones)
	HqClient.Station:Connect(function(name)
		if name then
			HqHud.open(name)
		else
			HqHud.close()
			simBar.Visible = false
		end
	end)
	HqClient.Changed:Connect(function(s)
		if not s.on then
			HqHud.close()
			simBar.Visible = false
		elseif current then
			draw()
		end
	end)
	HqClient.Dps:Connect(function(p)
		lastDps = p
		meter.Text = string.format("DPS %s   TOTAL %s", Kit.comma(p.dps or 0), Kit.comma(p.total or 0))
		if p.sim then
			simBar.Visible = true
			simFill.Size = UDim2.fromScale(math.clamp(p.sim.hp / math.max(1, p.sim.max), 0, 1), 1)
			simText.Text = string.format("BOSS SIM  %s HP  %d s", Kit.comma(p.sim.hp), p.sim.left)
		end
		if p.simDone then
			simBar.Visible = false
			State.Toast:Fire({
				id = "bossSim",
				killed = p.simDone.killed,
				time = p.simDone.time,
				dealt = p.simDone.dealt,
			})
		end
	end)
	State.ProfileChanged:Connect(function()
		if current then
			draw()
		end
	end)
end

function HqHud.dps(): { [string]: any }
	return lastDps
end

return HqHud
