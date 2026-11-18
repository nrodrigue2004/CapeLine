-- PvpHud: PvP and death on screen (spec: The PvP flag; the Crater; Defeat and death; juice rows Downed and
-- PvP flag on). Buttons carry verbs only.
-- * PVP button (level 10+): OFF or ON in the side colour; while it may not turn off it shows the seconds
--   left; a protection badge shows the 5 s spawn shield.
-- * The Crater: a red border warning with a 5 s count and a LEAVE button, then "PVP ZONE" while
--   inside (with the +50% Renown note).
-- * Downed: a grey edge with a heartbeat pulse, the seconds left, GIVE UP, a HELP ping button and who is
--   reviving you. Defeated: the respawn picker (nearest, or any visited safehouse) and the count.
-- * REVIVE: a big button when a Downed player is next to you; hold your spot until the ring fills.
-- * The PvP card: "You beat X" with the Credits and Fame (or why it paid less), or "X beat you" and the
--   Credits lost. Gear is never lost, and the card says so.
-- * WP4 REMATCH (spec: Social > Rivalry): after a PvP defeat a REMATCH button pings that winner once (45 s);
--   the winner gets a fixed "X WANTS A REMATCH" card with ACCEPT and NO for 15 s. Fixed text only.
-- PLACEHOLDER look until the UI pass (M10).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PvpRules = require(Shared:WaitForChild("PvpRules"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local PvpClient = require(script.Parent.Parent.Controllers.PvpClient)
local Juice = require(script.Parent.Parent.Fx.Juice)
local LoadoutScreen = require(script.Parent.LoadoutScreen)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)

local PvpHud = {}

local U = Config.Ui
local D = Config.Pvp.downed
local player = Players.LocalPlayer

local gui: ScreenGui
local flagButton: TextButton
local flagNote: TextLabel
local protectBadge: TextLabel
local craterBar: Frame
local craterText: TextLabel
local craterLeave: TextButton
local downGui: ScreenGui
local downLayer: Frame
local downText: TextLabel
local downSub: TextLabel
local giveUpButton: TextButton
local helpButton: TextButton
local pickRow: Frame
local reviveButton: TextButton
local reviveFill: Frame
local resultCard: Frame
local resultTitle: TextLabel
local resultText: TextLabel
local rematchButton: TextButton
local downStack: Frame -- the Downed and Defeated words and buttons (REMATCH joins it while Defeated)
local askCard: Frame
local askText: TextLabel
local askBar: Frame
local ask: { from: number, untilT: number, life: number }? = nil

local reviving: { userId: number, startT: number, doneT: number }? = nil
local nearDowned: Player? = nil
local loadoutButton: TextButton
local loadoutAfter = false -- CHOOSE LOADOUT tapped: the POWERS screen opens when you are back

local CUT_TEXT = {
	["repeat"] = "You beat them twice already: no pay for 30 minutes",
	gap = "They are 10+ levels below you: no pay",
	trade = "Trading wins pays nothing",
	side = "Same side: half pay",
	boss = "During a boss fight: half pay",
}

local function sideColor(): Color3
	return PvpClient.ringColor(State.hero.side)
end

local function build()
	gui = Kit.screen("PvpHud", 6)
	local s = U.touchTarget
	-- the PVP switch, under the wallet (top right)
	flagButton = Kit.button({
		Name = "Pvp",
		Text = "PVP OFF",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(s * 2, s - 8),
		Position = UDim2.new(1, -U.safe - 70, 0, U.safe + s + 28),
		BackgroundColor3 = Kit.color.paper,
		Visible = false,
		maxText = 20,
	}, function()
		if PvpClient.askIn() <= 0 then
			PvpClient.setFlag(not PvpClient.flag.on)
		end
	end)
	Kit.stroke(flagButton, Kit.color.ink, 2)
	flagButton.Parent = gui
	flagNote = Kit.label({
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(240, 16),
		Position = UDim2.new(1, -U.safe - 70, 0, U.safe + s * 2 + 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.3,
		Font = Kit.bodyFont,
		maxText = 12,
	})
	flagNote.Parent = gui
	-- phone pass: the switch joins the top row; its note sits under the row's middle
	Kit.dock(flagButton, "Pvp", 6)
	flagNote.AnchorPoint = Vector2.new(0.5, 0)
	flagNote.Position = UDim2.new(0.5, 0, 0, U.safe + s + 2)
	flagNote.TextXAlignment = Enum.TextXAlignment.Center
	protectBadge = Kit.label({
		Text = "SHIELDED",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(200, 26),
		Position = UDim2.new(0.5, 0, 0, U.safe + 64),
		TextColor3 = Color3.fromRGB(150, 220, 255),
		TextStrokeTransparency = 0.2,
		Visible = false,
		maxText = 22,
	})
	protectBadge.Parent = gui

	-- the Crater warning: a red bar across the top with the count and LEAVE
	craterBar = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(420, 64),
		Position = UDim2.new(0.5, 0, 0, U.safe + 96),
		BackgroundColor3 = Color3.fromRGB(200, 40, 40),
		Visible = false,
	})
	Kit.stroke(craterBar, Kit.color.ink, 3)
	craterBar.Parent = gui
	craterText = Kit.label({
		Text = "",
		Size = UDim2.new(1, -150, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		maxText = 24,
	})
	craterText.Parent = craterBar
	craterLeave = Kit.button({
		Text = "LEAVE",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(120, s - 8),
		Position = UDim2.new(1, -8, 0.5, 0),
	}, function()
		PvpClient.leaveCrater()
	end)
	craterLeave.Parent = craterBar

	-- Downed and Defeated: their own screen over every panel (the shop at 18, the creator at 20, settings
	-- at 22 drew over it), and going Downed closes the open panels (Kit.closePanels)
	downGui = Kit.screen("Downed", 25)
	downLayer = Kit.frame({
		Name = "Downed",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		round = false,
		Visible = false,
	})
	downLayer.Parent = downGui
	local edge = Instance.new("UIStroke")
	edge.Thickness = 40
	edge.Color = Color3.fromRGB(120, 120, 130)
	edge.Transparency = 0.35
	edge.Name = "Edge"
	local edgeFrame = Kit.frame({
		Size = UDim2.new(1, -40, 1, -40),
		Position = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		round = false,
	})
	edge.Parent = edgeFrame
	edgeFrame.Parent = downLayer
	-- the words and buttons in one stack: 22% down the screen, or up from the bottom on a short phone
	-- (CHOOSE LOADOUT, its last row, was off a 375 px phone's screen)
	local stackH = 116 + 2 * s + (s - 8)
	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.BackgroundTransparency = 1
	stack.Size = UDim2.fromOffset(600, stackH)
	stack.Parent = downLayer
	downStack = stack
	local function placeStack()
		local a = Kit.area()
		local margin = Config.Ui.phone.panelMargin
		if a.Y * 0.22 + stackH > a.Y - margin then
			stack.AnchorPoint = Vector2.new(0.5, 1)
			stack.Position = UDim2.new(0.5, 0, 1, -margin)
		else
			stack.AnchorPoint = Vector2.new(0.5, 0)
			stack.Position = UDim2.fromScale(0.5, 0.22)
		end
	end
	placeStack()
	Kit.LayoutChanged:Connect(placeStack)
	downText = Kit.label({
		Text = "DOWNED",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(420, 52),
		Position = UDim2.new(0.5, 0, 0, 0),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.1,
		maxText = 48,
	})
	downText.Parent = stack
	downSub = Kit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(460, 26),
		Position = UDim2.new(0.5, 0, 0, 56),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.2,
		Font = Kit.bodyFont,
		maxText = 18,
	})
	downSub.Parent = stack
	giveUpButton = Kit.button({
		Text = "GIVE UP",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(s * 3, s),
		Position = UDim2.new(0.5, -s * 1.6, 0, 96),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		PvpClient.giveUp()
	end)
	giveUpButton.Parent = stack
	helpButton = Kit.button({
		Text = "HELP",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(s * 3, s),
		Position = UDim2.new(0.5, s * 1.6, 0, 96),
	}, function()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			PvpClient.ping(1, root.Position)
		end
	end)
	helpButton.Parent = stack
	pickRow = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(600, s),
		Position = UDim2.new(0.5, 0, 0, 104 + s),
		BackgroundTransparency = 1,
		round = false,
		Visible = false,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = pickRow
	-- spec: Wait table "Defeated | Respawn 5 s at a safehouse with a Choose Loadout button on screen"
	loadoutButton = Kit.button({
		Text = "CHOOSE LOADOUT",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(240, s - 8),
		Position = UDim2.new(0.5, 0, 0, 116 + 2 * s),
		Visible = false,
		maxText = 20,
	}, function()
		loadoutAfter = true
		loadoutButton.Text = "OPENS WHEN YOU ARE BACK"
	end)
	loadoutButton.Parent = stack
	player.CharacterAdded:Connect(function()
		loadoutButton.Text = "CHOOSE LOADOUT"
		if loadoutAfter then
			loadoutAfter = false
			task.delay(0.6, LoadoutScreen.open)
		end
	end)
	pickRow.Parent = stack

	-- REVIVE next to a Downed player
	reviveButton = Kit.button({
		Text = "REVIVE",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(s * 3, s + 8),
		Position = UDim2.new(0.5, 0, 1, -U.safe - 180),
		Visible = false,
	}, function()
		local target = nearDowned
		if target then
			local now = os.clock()
			reviving = {
				userId = target.UserId,
				startT = now,
				doneT = now + PvpRules.reviveTime(Config, State.hero.classId),
			}
			PvpClient.revive(target.UserId)
		end
	end)
	reviveButton.Parent = gui
	reviveFill = Kit.frame({
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(0, 0, 0, 6),
		Position = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 240, 150),
		round = false,
	})
	reviveFill.Parent = reviveButton

	-- the PvP result card
	resultCard = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(380, 96),
		Position = UDim2.new(0.5, 0, 0, U.safe + 170),
		BackgroundColor3 = Kit.color.night,
		Visible = false,
	})
	Kit.stroke(resultCard, Kit.color.gold, 3)
	resultCard.Parent = gui
	resultTitle = Kit.label({
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.fromOffset(8, 6),
		TextColor3 = Kit.color.gold,
		maxText = 32,
	})
	resultTitle.Parent = resultCard
	resultText = Kit.label({
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.fromOffset(8, 48),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 15,
	})
	resultText.Parent = resultCard
end

-- WP4: the REMATCH ping (the loser's button) and the winner's "X wants a rematch" card
local function buildRematch()
	local s = U.touchTarget
	-- on the Downed screen's gui (25), so it shows over the Defeated screen and after respawn: while Defeated
	-- it sits in the stack's GIVE UP and HELP row (hidden then), after respawn where REVIVE goes (frameRematch)
	rematchButton = Kit.button({
		Name = "Rematch",
		Text = "REMATCH",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(s * 3, s),
		Position = UDim2.new(0.5, 0, 1, -U.safe - 180),
		BackgroundColor3 = Color3.fromRGB(255, 120, 110),
		Visible = false,
	}, function()
		PvpClient.askRematch()
		rematchButton.Visible = false
	end)
	Kit.stroke(rematchButton, Kit.color.ink, 3)
	rematchButton.Parent = downGui
	-- the winner's card takes the PvP result card's place (it fits a 360 px phone there)
	askCard = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(380, 118),
		Position = UDim2.new(0.5, 0, 0, U.safe + 170),
		BackgroundColor3 = Kit.color.night,
		Visible = false,
	})
	Kit.stroke(askCard, Color3.fromRGB(255, 120, 110), 3)
	askCard.Parent = gui
	askText = Kit.label({
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 6),
		TextColor3 = Kit.color.paper,
		maxText = 26,
	})
	askText.Parent = askCard
	askBar = Kit.frame({
		Size = UDim2.new(1, -20, 0, 4),
		Position = UDim2.fromOffset(10, 50),
		BackgroundColor3 = Color3.fromRGB(255, 120, 110),
		round = false,
	})
	askBar.Parent = askCard
	local function answer(yes: boolean)
		local a = ask
		ask = nil
		askCard.Visible = false
		if a then
			PvpClient.answerRematch(a.from, yes)
		end
	end
	local accept = Kit.button({
		Text = "ACCEPT",
		Size = UDim2.new(0.5, -15, 0, s - 10),
		Position = UDim2.new(0, 10, 1, -s + 2),
	}, function()
		answer(true)
	end)
	accept.Parent = askCard
	local no = Kit.button({
		Text = "NO",
		Size = UDim2.new(0.5, -15, 0, s - 10),
		Position = UDim2.new(0.5, 5, 1, -s + 2),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		answer(false)
	end)
	no.Parent = askCard
	PvpClient.RematchAsked:Connect(function(a)
		local life = tonumber(a.life) or Config.Pvp.rematch.answer
		ask = { from = tonumber(a.from) or 0, untilT = os.clock() + life, life = life }
		askText.Text = string.upper(tostring(a.name or "A HERO")) .. " WANTS A REMATCH"
		resultCard.Visible = false
		askCard.Visible = true
		Kit.bounce(askCard)
		Juice.fire("rally")
	end)
end

local function frameRematch(now: number)
	local defeated = downLayer.Visible and not giveUpButton.Visible and not helpButton.Visible
	local parent: Instance = if defeated then downStack else downGui
	if rematchButton.Parent ~= parent then
		rematchButton.Parent = parent
		if defeated then
			rematchButton.AnchorPoint = Vector2.new(0.5, 0)
			rematchButton.Position = UDim2.new(0.5, 0, 0, 96)
		else
			rematchButton.AnchorPoint = Vector2.new(0.5, 1)
			rematchButton.Position = UDim2.new(0.5, 0, 1, -U.safe - 180)
		end
	end
	rematchButton.Visible = PvpClient.canRematch(now)
		and not StoryClient.inOpening()
		and (defeated or not reviveButton.Visible)
	local a = ask
	if a then
		local left = a.untilT - now
		if left <= 0 then
			ask = nil
			askCard.Visible = false
		else
			askBar.Size = UDim2.new(math.clamp(left / a.life, 0, 1), -20, 0, 4)
			askCard.Visible = not resultCard.Visible -- the two cards share one place
		end
	end
end

-- The respawn picker: the nearest safehouse, or any one visited (names from the world map)
local function fillPicker(list: { number })
	for _, c in pickRow:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local names = {}
	for _, s in Config.World.safehouses or {} do
		names[s.id] = s.name
	end
	local function add(id: number, label: string)
		local b = Kit.button({
			Text = label,
			Size = UDim2.fromOffset(140, U.touchTarget - 8),
			BackgroundColor3 = Kit.color.paper,
			maxText = 16,
		}, function()
			PvpClient.chooseRespawn(id)
			for _, c in pickRow:GetChildren() do
				if c:IsA("TextButton") then
					c.BackgroundColor3 = Kit.color.paper
				end
			end
		end)
		b.Parent = pickRow
		b.Activated:Connect(function()
			b.BackgroundColor3 = Kit.color.gold
		end)
	end
	add(0, "NEAREST")
	for i, id in list do
		if i > 3 then
			break -- the phone row holds 4; the nearest covers the rest
		end
		add(id, string.upper(names[id] or ("SAFEHOUSE " .. id)))
	end
end

local function showResult(r: any)
	if r.won then
		resultTitle.Text = "YOU BEAT " .. string.upper(r.other or "")
		local parts = {}
		if (r.credits or 0) > 0 then
			table.insert(parts, "+" .. Kit.comma(r.credits) .. " Credits")
		end
		if (r.fame or 0) > 0 then
			table.insert(
				parts,
				"+" .. r.fame .. (if State.hero.side == "villain" then " Infamy" else " Fame")
			)
		end
		local cut = r.cut and CUT_TEXT[r.cut]
		resultText.Text = table.concat(parts, "   ") .. (if cut then ("\n" .. cut) else "")
	else
		resultTitle.Text = string.upper(r.other or "") .. " BEAT YOU"
		resultText.Text = if (r.credits or 0) > 0
			then ("-" .. Kit.comma(r.credits) .. " unbanked Credits. Gear is never lost.")
			else "Nothing lost. Bank Credits at a safehouse to keep them safe."
	end
	resultCard.Visible = true -- a newer fight's card covers a rematch ask; the ask comes back when it closes
	Kit.bounce(resultCard)
	task.delay(5, function()
		resultCard.Visible = false
	end)
end

local wasDowned = false
local function refreshDown()
	local d = PvpClient.down
	local now = os.clock()
	local since = now - PvpClient.downAt
	-- the muffled heartbeat while Downed (juice row Downed)
	if d.downed and not wasDowned then
		Juice.fire("downed", nil, { mine = true })
		Kit.closePanels() -- nothing covers the Downed screen
	end
	wasDowned = d.downed == true
	Juice.hold("downed", wasDowned)
	if d.downed then
		downLayer.Visible = true
		local left = math.max(0, (d.left or 0) - since)
		downText.Text = "DOWNED " .. math.ceil(left)
		if d.by then
			downSub.Text = d.by .. " is reviving you"
		elseif d.giveUp then
			downSub.Text = "Respawning..."
		else
			downSub.Text = "Crawl to safety or wait for help"
		end
		giveUpButton.Visible = d.giveUp == nil
		helpButton.Visible = true
		pickRow.Visible = true
		local edge = downLayer:FindFirstChild("Edge", true) :: UIStroke?
		if edge then
			edge.Transparency = 0.35 + math.sin(now * 6) * 0.15 -- the heartbeat
		end
	elseif d.defeated and since < (d.respawnIn or 5) + 0.5 then
		downLayer.Visible = true
		downText.Text = if d.pvp then "OVERLOADED" else "DEFEATED"
		downSub.Text = "Back in " .. math.max(0, math.ceil((d.respawnIn or 5) - since))
		giveUpButton.Visible = false
		helpButton.Visible = false
		pickRow.Visible = (d.respawnIn or 0) > 0
		loadoutButton.Visible = true
	else
		downLayer.Visible = false
	end
	if not d.defeated then
		loadoutButton.Visible = false
	end
end

local function findDowned(): Player?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or PvpClient.downed() then
		return nil
	end
	local best, bestD = nil, D.reviveRange
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("Downed") then
			local c = p.Character
			local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			local dist = r and (r.Position - root.Position).Magnitude
			if dist and dist <= bestD then
				best, bestD = p, dist
			end
		end
	end
	return best
end

local function frame()
	local now = os.clock()
	local f = PvpClient.flag
	local since = now - PvpClient.flagAt
	local hidden = StoryClient.inOpening()
	flagButton.Visible = PvpClient.canFlag() and not hidden
	if flagButton.Visible then
		local offIn = math.max(0, (f.offIn or 0) - since)
		if f.flagged then
			flagButton.Text = if f.crater == "in" then "PVP ZONE" else "PVP ON"
			flagButton.BackgroundColor3 = sideColor()
			flagNote.Text = if f.crater ~= "out"
				then "Leave the Crater to switch off"
				elseif f.on and offIn > 0 then ("Can switch off in " .. math.ceil(offIn) .. "s")
				else ""
		else
			flagButton.Text = "PVP OFF"
			flagButton.BackgroundColor3 = Kit.color.paper
			flagNote.Text = ""
		end
		flagButton.AutoButtonColor = PvpClient.askIn() <= 0
	else
		flagNote.Text = ""
	end
	protectBadge.Visible = (f.protectLeft or 0) - since > 0 and f.flagged == true
	-- the Crater
	if f.crater == "warn" then
		craterBar.Visible = true
		local left = math.max(0, (f.warnLeft or 0) - since)
		craterText.Text = if (State.hero.level or 1) >= Config.Pvp.minLevel
			then ("PVP ZONE IN " .. math.ceil(left))
			else "THE CRATER: PVP ZONE"
		craterLeave.Visible = true
	elseif f.crater == "in" then
		craterBar.Visible = true
		craterText.Text = "PVP ZONE  +50% RENOWN"
		craterLeave.Visible = false
	else
		craterBar.Visible = false
	end
	refreshDown()
	frameRematch(now)
	-- revive: the button near a Downed player, and its fill while holding the spot
	nearDowned = findDowned()
	local r = reviving
	if r then
		local target = Players:GetPlayerByUserId(r.userId)
		if not target or not target:GetAttribute("Downed") or nearDowned ~= target or now > r.doneT + 1 then
			reviving = nil
		end
	end
	reviveButton.Visible = nearDowned ~= nil
	local rv = reviving
	if rv then
		reviveFill.Size = UDim2.new(math.clamp((now - rv.startT) / (rv.doneT - rv.startT), 0, 1), 0, 0, 6)
	else
		reviveFill.Size = UDim2.new(0, 0, 0, 6)
	end
end

function PvpHud.init()
	build()
	buildRematch()
	PvpClient.Changed:Connect(function(what)
		local d = PvpClient.down
		if what == "down" and d.safehouses then
			fillPicker(d.safehouses) -- sent once per Downed or Defeated, so a pick stays lit
		end
	end)
	PvpClient.Result:Connect(showResult)
	RunService.RenderStepped:Connect(FrameProf.wrap("PvpHud", frame))
end

return PvpHud
