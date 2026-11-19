-- JuiceFx: the juice table's visuals that no other module draws (spec: Audio, VFX and juice): the Credit
-- coin burst on a defeated robot, the safe-zone glow and Renown pop on a rescue, the medal stamp on an
-- incident clear, the gold ring on a revive, the level badge with the next unlock, the tier colour beam on a
-- gear drop, boss fireworks, the NEW badge on a purchase, the 5 s shield ring on a respawn, the contract
-- stamp, and dazed stars when you are stunned. Reduce flashing softens the flashes and stops the spins.
-- Built-in parts and UI only (no emitters past the budget). PLACEHOLDER ART until the art pass.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Progress = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progress"))

local Kit = require(script.Parent.Parent.Ui.Kit)
local Popups = require(script.Parent.Parent.Ui.Popups) -- pt-ui: one line for every popup
local State = require(script.Parent.Parent.State)

local JuiceFx = {}

JuiceFx.reduce = false -- Settings: reduce flashing (no spins, softer flashes)

local player = Players.LocalPlayer
local folder: Folder
local gui: ScreenGui
local stars: BillboardGui? = nil

local GOLD = Color3.fromRGB(255, 200, 60)
local MEDAL = {
	gold = Color3.fromRGB(255, 200, 60),
	silver = Color3.fromRGB(200, 210, 225),
	bronze = Color3.fromRGB(205, 130, 70),
}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function bit(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.Shape = shape or Enum.PartType.Block
	p.CFrame = cf
	p.Parent = folder
	return p
end

local function fadeOut(p: BasePart, time: number, props: { [string]: any }?)
	local goal = props or {}
	goal.Transparency = 1
	TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(p, time + 0.1)
end

local function ring(at: Vector3, radius: number, color: Color3, time: number)
	local p = bit(
		Vector3.new(0.4, 1, 1),
		CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.PartType.Cylinder
	)
	p.Transparency = 0.3
	fadeOut(p, time, { Size = Vector3.new(0.4, radius * 2, radius * 2) })
end

-- A word that pops up from a spot and floats (Renown pop, +Credits)
local function pop(at: Vector3, text: string, color: Color3)
	local a = Instance.new("Part")
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.Transparency = 1
	a.Size = Vector3.one
	a.Position = at
	a.Parent = folder
	local b = Instance.new("BillboardGui")
	b.Size = UDim2.fromOffset(160, 40)
	b.AlwaysOnTop = true
	b.MaxDistance = 220
	b.Parent = a
	local l = Kit.label({ Text = text, Size = UDim2.fromScale(1, 1), TextColor3 = color, maxText = 30 })
	l.TextStrokeTransparency = 0
	l.Parent = b
	TweenService
		:Create(a, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Position = at + Vector3.new(0, 8, 0) })
		:Play()
	TweenService:Create(l, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(a, 1.3)
end

-- A big stamp that slams onto the screen (medals, contracts, NEW)
local function stampNow(text: string, color: Color3, sub: string?): Frame
	local f = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(260, if sub then 110 else 80),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.15,
	})
	Kit.stroke(f, color, 4)
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, -16, 0, 60),
		Position = UDim2.fromOffset(8, 8),
		TextColor3 = color,
		maxText = 48,
	})
	l.TextStrokeTransparency = 0
	l.Parent = f
	if sub then
		local s = Kit.label({
			Text = sub,
			Size = UDim2.new(1, -16, 0, 30),
			Position = UDim2.fromOffset(8, 70),
			TextColor3 = Kit.color.paper,
			Font = Kit.bodyFont,
			maxText = 18,
		})
		s.Parent = f
	end
	local scale = Instance.new("UIScale")
	scale.Scale = if JuiceFx.reduce then 1 else 2.2
	scale.Parent = f
	f.Rotation = if JuiceFx.reduce then 0 else -12
	f.Parent = gui
	TweenService
		:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	TweenService:Create(f, TweenInfo.new(0.18), { Rotation = if JuiceFx.reduce then 0 else -6 }):Play()
	task.delay(1.8, function()
		TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 0.6 }):Play()
		TweenService:Create(f, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		for _, d in f:GetDescendants() do
			if d:IsA("TextLabel") then
				TweenService
					:Create(d, TweenInfo.new(0.25), { TextTransparency = 1, TextStrokeTransparency = 1 })
					:Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			end
		end
		task.delay(0.3, function()
			f:Destroy()
		end)
	end)
	return f
end

-- pt-ui: a stamp waits its turn with every other card in Ui.Popups ("stamp": dropped if it could not show
-- within a few seconds, so a late stamp never lands on a quiet moment)
local function stamp(text: string, color: Color3, sub: string?)
	Popups.show("stamp", function()
		return stampNow(text, color, sub)
	end)
end

local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Paper confetti falling over the screen (none with reduce flashing)
local function confetti(n: number)
	if JuiceFx.reduce then
		return
	end
	for _ = 1, n do
		local p = Kit.frame({
			Position = UDim2.new(math.random(), 0, -0.05, 0),
			Size = UDim2.fromOffset(8, 14),
			BackgroundColor3 = Color3.fromHSV(math.random(), 0.75, 1),
			round = false,
			Rotation = math.random(0, 360),
		})
		p.Parent = gui
		local t = 1.6 + math.random() * 1.2
		TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(p.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.05, 0),
			Rotation = p.Rotation + math.random(-360, 360),
		}):Play()
		Debris:AddItem(p, t + 0.1)
	end
end

---------------------------------------------------------------------------
-- The juice rows
---------------------------------------------------------------------------

-- Enemy defeated: a Credit coin burst (spec "Credit coin burst")
function JuiceFx.defeat(at: Vector3?)
	if not at then
		return
	end
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		local c = bit(
			Vector3.new(0.3, 1.1, 1.1),
			CFrame.new(at) * CFrame.Angles(0, a, math.rad(90)),
			GOLD,
			Enum.PartType.Cylinder
		)
		c.Material = Enum.Material.SmoothPlastic
		local out = at + Vector3.new(math.cos(a) * 4, 3 + (i % 3), math.sin(a) * 4)
		TweenService:Create(c, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = out,
		}):Play()
		task.delay(0.35, function()
			fadeOut(c, 0.5, { Position = out - Vector3.new(0, 3, 0) })
		end)
	end
end

-- Citizen rescued: a safe-zone glow and a Renown pop
function JuiceFx.rescue(at: Vector3?, data: { [string]: any }?)
	if not at then
		return
	end
	ring(at - Vector3.new(0, 2.5, 0), 12, Color3.fromRGB(120, 255, 170), 0.9)
	local renown = data and data.renown
	pop(at + Vector3.new(0, 3, 0), if renown then "+" .. renown .. " RENOWN" else "SAVED!", GOLD)
end

-- Incident cleared: the medal stamp (gold, silver or bronze)
function JuiceFx.incidentClear(_at: Vector3?, data: { [string]: any }?)
	local medal = data and data.medal or "bronze"
	stamp(string.upper(medal), MEDAL[medal] or MEDAL.bronze, "INCIDENT CLEARED")
end

-- Revived: a gold ring rising round the hero
function JuiceFx.revive(at: Vector3?)
	if not at then
		return
	end
	ring(at - Vector3.new(0, 2.5, 0), 8, GOLD, 0.8)
	ring(at, 6, GOLD, 1)
end

-- Level up: the level badge spins in and the next unlock lights up
local function levelBadge(_at: Vector3?, data: { [string]: any }?): Frame
	local lvl = data and data.level or State.hero.level or 1
	local badge = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = GOLD,
	})
	Kit.round(badge, 75)
	Kit.stroke(badge, Kit.color.ink, 5)
	local n = Kit.label({
		Text = tostring(lvl),
		Size = UDim2.fromScale(1, 0.7),
		Position = UDim2.fromScale(0, 0.08),
		TextColor3 = Kit.color.ink,
		maxText = 90,
	})
	n.Parent = badge
	local l = Kit.label({
		Text = "LEVEL",
		Size = UDim2.fromScale(1, 0.2),
		Position = UDim2.fromScale(0, 0.74),
		TextColor3 = Kit.color.ink,
		maxText = 22,
	})
	l.Parent = badge
	badge.Parent = gui
	if not JuiceFx.reduce then
		badge.Rotation = -360
		TweenService:Create(badge, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Rotation = 0,
		}):Play()
	end
	-- the next unlock: a dark silhouette that lights up
	local nextAt, unlock = nil, nil
	for L = lvl + 1, math.min(lvl + 20, Config.Stats.levelCap) do
		local text = Progress.unlockAt(Config, L)
		if text then
			nextAt, unlock = L, text
			break
		end
	end
	if unlock then
		local s = Kit.label({
			Text = string.format("NEXT AT %d: %s", nextAt, string.upper(unlock)),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.42, 84),
			Size = UDim2.fromOffset(340, 30),
			TextColor3 = Kit.color.muted,
			maxText = 22,
		})
		s.TextStrokeTransparency = 0.2
		s.Parent = gui
		TweenService:Create(s, TweenInfo.new(0.8, Enum.EasingStyle.Sine), { TextColor3 = GOLD }):Play()
		Debris:AddItem(s, 2.6)
	end
	local root = myRoot()
	if root then
		ring(root.Position, 10, GOLD, 0.9)
	end
	task.delay(2.2, function()
		TweenService
			:Create(
				badge,
				TweenInfo.new(0.3),
				{ BackgroundTransparency = 1, Size = UDim2.fromOffset(60, 60) }
			)
			:Play()
		n.Visible = false
		l.Visible = false
		Debris:AddItem(badge, 0.35)
	end)
	return badge
end

function JuiceFx.levelUp(at: Vector3?, data: { [string]: any }?)
	-- pt-ui: the badge waits its turn in Ui.Popups ("levelBadge"); the LEVEL toast always shows
	Popups.show("levelBadge", function()
		return levelBadge(at, data)
	end)
end

-- Gear drop: a beam in the tier's colour (Legendary and up chime twice; Juice plays the chimes)
function JuiceFx.gearDrop(at: Vector3?, data: { [string]: any }?)
	local tier = data and data.tier or "Common"
	local def = Config.Gear.tiers[tier]
	local color = if def then rgb(def.color) else Kit.color.paper
	local where = at or (myRoot() and (myRoot() :: BasePart).Position)
	if not where then
		return
	end
	local beam = bit(Vector3.new(1.2, 60, 1.2), CFrame.new(where + Vector3.new(0, 28, 0)), color)
	beam.Transparency = 0.35
	fadeOut(beam, 2.5, { Size = Vector3.new(0.2, 60, 0.2) })
end

-- Boss defeated: fireworks over the boss and confetti on screen
function JuiceFx.bossDefeated(at: Vector3?)
	local where = at or (myRoot() and (myRoot() :: BasePart).Position)
	if where then
		for i = 1, 5 do
			task.delay(i * 0.25, function()
				local sky = where
					+ Vector3.new(math.random(-40, 40), 60 + math.random(0, 30), math.random(-40, 40))
				local c = Color3.fromHSV(math.random(), 0.7, 1)
				ring(sky, 14, c, 0.9)
				local core = bit(Vector3.one * 3, CFrame.new(sky), c, Enum.PartType.Ball)
				fadeOut(core, 0.8, { Size = Vector3.one * 10 })
			end)
		end
	end
	confetti(40)
end

-- Purchase: the NEW badge
function JuiceFx.purchase(_at: Vector3?, data: { [string]: any }?)
	stamp("NEW!", GOLD, data and data.name)
end

-- Respawn: the protect shield ring for 5 s
function JuiceFx.respawn()
	local root = myRoot()
	if not root then
		return
	end
	local shell = bit(Vector3.one * 9, root.CFrame, Kit.color.volt, Enum.PartType.Ball)
	shell.Material = Enum.Material.ForceField
	shell.Transparency = 0.2
	local alive = true
	local conn = RunService.RenderStepped:Connect(FrameProf.wrap("JuiceFx", function()
		local r = myRoot()
		if alive and r then
			shell.CFrame = r.CFrame
		end
	end))
	task.delay(Config.Pvp.spawnProtect, function()
		alive = false
		conn:Disconnect()
		fadeOut(shell, 0.3)
	end)
end

-- Contract done: a stamp and the reward banner
function JuiceFx.contractDone(_at: Vector3?, data: { [string]: any }?)
	stamp("DONE!", Kit.color.health, data and data.name and string.upper(data.name) or "CONTRACT")
end

-- H7: a badge earned: the stamp with the badge's name, then confetti
function JuiceFx.badgeEarned(_at: Vector3?, data: { [string]: any }?)
	stamp("BADGE!", GOLD, data and data.name and string.upper(data.name) or nil)
	confetti(24)
end

-- The Rogues File: a page filled (NEW PAGE! with the rogue's name), a gold boss page (gold, confetti) or a
-- collection milestone (the page count and the look piece it gave)
function JuiceFx.roguePage(_at: Vector3?, data: { [string]: any }?)
	local d = data or {}
	if d.milestone then
		stamp(
			string.format("%d PAGES!", d.milestone),
			GOLD,
			d.piece and string.upper(d.piece) or "ROGUES FILE"
		)
		confetti(30)
	elseif d.gold then
		stamp("GOLD PAGE!", GOLD, d.name and string.upper(d.name) or "ROGUES FILE")
		confetti(30)
	else
		stamp("NEW PAGE!", Kit.color.paper, d.name and string.upper(d.name) or "ROGUES FILE")
	end
end

-- WP1: the daily streak reward claimed: the DAY N! stamp (the title's name on day 7) and confetti
function JuiceFx.dailyClaim(_at: Vector3?, data: { [string]: any }?)
	local d = data or {}
	local sub = if d.title
		then "NEW TITLE: " .. string.upper(d.title)
		else string.format("STREAK %d", d.streak or 1)
	stamp(string.format("DAY %d!", d.day or 1), GOLD, sub)
	confetti(if d.title then 60 else 24)
end

-- WP1: a daily quest done: the DAILY! stamp with its line; all three done adds confetti
function JuiceFx.dailyQuest(_at: Vector3?, data: { [string]: any }?)
	local d = data or {}
	stamp(if d.all then "ALL DONE!" else "DAILY!", Kit.color.health, d.text and string.upper(d.text) or nil)
	if d.all then
		confetti(40)
	end
end

---------------------------------------------------------------------------
-- Side quest chains (the juice pass, 2026-11-18; Config.Audio.sideQuest, StoryHud fires them). data: name (the
-- chain's or villain's, from Config), word (the step's stamp word), sub, credits, wait
---------------------------------------------------------------------------

-- A chain taken: the NEW QUEST! stamp with its name and a little confetti
function JuiceFx.questAccept(_at: Vector3?, data: { [string]: any }?)
	local d = data or {}
	stamp("NEW QUEST!", GOLD, d.name)
	confetti(12)
	local root = myRoot()
	if root then
		ring(root.Position - Vector3.new(0, 2.5, 0), 9, GOLD, 0.7)
	end
end

-- A step done: the step's word stamp (CAUGHT!, HELD!...) with how far along the chain is, a ring round the hero
-- and the pay pop; your part done while the other side works: the ring and the word pop only
function JuiceFx.questStep(_at: Vector3?, data: { [string]: any }?)
	local d = data or {}
	local root = myRoot()
	if root then
		ring(root.Position - Vector3.new(0, 2.5, 0), if d.wait then 7 else 10, Kit.color.health, 0.7)
	end
	if d.wait then
		if root then
			pop(root.Position + Vector3.new(0, 4, 0), d.word or "DONE!", Kit.color.health)
		end
		return
	end
	stamp(d.word or "STEP DONE!", Kit.color.health, d.sub)
	if root and (d.credits or 0) > 0 then
		pop(root.Position + Vector3.new(0, 4, 0), "+" .. Kit.comma(d.credits) .. " CREDITS", GOLD)
	end
end

-- The encore: the first villain is down and the second lands: the ENCORE! stamp and a burst where it lands
function JuiceFx.questEncore(at: Vector3?, data: { [string]: any }?)
	local d = data or {}
	stamp("ENCORE!", Color3.fromRGB(255, 120, 90), d.name)
	if at then
		ring(at, 16, Color3.fromRGB(255, 120, 90), 0.8)
	end
end

-- The finale won: fireworks over where the villain fell and the VICTORY! stamp with its name
function JuiceFx.questFinale(at: Vector3?, data: { [string]: any }?)
	local d = data or {}
	local where = at or (myRoot() and (myRoot() :: BasePart).Position)
	if where then
		for i = 1, 4 do
			task.delay(i * 0.2, function()
				local sky = where
					+ Vector3.new(math.random(-24, 24), 30 + math.random(0, 20), math.random(-24, 24))
				local c = Color3.fromHSV(math.random(), 0.7, 1)
				ring(sky, 10, c, 0.8)
				local core = bit(Vector3.one * 2.5, CFrame.new(sky), c, Enum.PartType.Ball)
				fadeOut(core, 0.7, { Size = Vector3.one * 8 })
			end)
		end
		ring(where, 14, GOLD, 0.9)
	end
	stamp(d.word or "VICTORY!", GOLD, d.name and (d.name .. " DEFEATED") or nil)
end

-- The chain done: confetti over the result card (StoryHud draws the card) and a gold ring round the hero
function JuiceFx.questDone()
	confetti(60)
	local root = myRoot()
	if root then
		ring(root.Position - Vector3.new(0, 2.5, 0), 12, GOLD, 1)
		ring(root.Position, 8, GOLD, 1.2)
	end
end

-- The finale lost (Downed while the villain stands): the TRY AGAIN! stamp with the villain's name
function JuiceFx.questRetry(_at: Vector3?, data: { [string]: any }?)
	local d = data or {}
	stamp("TRY AGAIN!", Kit.color.paper, d.name)
end

-- H7: a collection find: a sparkle burst where it lay and a "2 / 8" pop with the set's name
function JuiceFx.collectFind(at: Vector3?, data: { [string]: any }?)
	local where = at or (myRoot() and (myRoot() :: BasePart).Position)
	if not where then
		return
	end
	ring(where, 6, Color3.fromRGB(150, 230, 255), 0.6)
	local text = if data and data.count
		then string.format("%s %d / %d", string.upper(data.name or "FIND"), data.found or 0, data.count)
		else "FOUND!"
	pop(where + Vector3.new(0, 3, 0), text, GOLD)
end

-- side-content (2026-11-19): a lore page read: the book bursts into a fan of glowing pages that flutter up and out,
-- a warm gold ring and the "PAGE 3 / 21" pop (LoreClient shows the caption card itself); a district or the whole
-- set done adds the stamp with its title and a little confetti
function JuiceFx.lorePage(at: Vector3?, data: { [string]: any }?)
	local d = data or {}
	local where = at or (myRoot() and (myRoot() :: BasePart).Position)
	if not where then
		return
	end
	local paper = Color3.fromRGB(255, 244, 214)
	ring(where, 8, Color3.fromRGB(255, 214, 110), 0.7)
	ring(where + Vector3.new(0, 1.5, 0), 5, paper, 0.5)
	local n = if JuiceFx.reduce then 5 else 12
	for i = 1, n do
		local a = i / n * math.pi * 2
		local out = Vector3.new(math.cos(a), 0.6 + (i % 3) * 0.35, math.sin(a))
		local pg = bit(
			Vector3.new(0.9, 0.05, 1.2),
			CFrame.new(where) * CFrame.Angles(math.random() * 3, a, math.random() * 3),
			paper
		)
		pg.Material = Enum.Material.SmoothPlastic
		fadeOut(pg, 0.9 + (i % 4) * 0.1, {
			CFrame = CFrame.new(where + out * (5 + (i % 3) * 2))
				* CFrame.Angles(math.random() * 6, a * 2, math.random() * 6),
		})
	end
	if d.count then
		pop(where + Vector3.new(0, 3, 0), string.format("LORE %d / %d", d.found or 0, d.count), GOLD)
	end
	if d.title then
		stamp(
			if d.all then "ARCHIVE COMPLETE!" else "DISTRICT READ!",
			GOLD,
			"TITLE: " .. string.upper(d.title)
		)
		confetti(if d.all then 60 else 24)
	end
end

-- side-content (2026-11-19): a mobility rank trained: a rush of speed lines out from your feet, a blue ring and the
-- TRAINED! stamp with the rank's name
function JuiceFx.moveTrain(_at: Vector3?, data: { [string]: any }?)
	local d = data or {}
	local root = myRoot()
	if root then
		local feet = root.Position - Vector3.new(0, 2.5, 0)
		ring(feet, 10, Color3.fromRGB(110, 190, 255), 0.6)
		ring(feet, 6, Color3.new(1, 1, 1), 0.4)
		for i = 1, (if JuiceFx.reduce then 4 else 10) do
			local a = i / 10 * math.pi * 2
			local dir = Vector3.new(math.cos(a), 0.15, math.sin(a))
			local line =
				bit(Vector3.new(0.2, 0.2, 3), CFrame.lookAt(feet, feet + dir), Color3.fromRGB(200, 230, 255))
			fadeOut(
				line,
				0.45,
				{ CFrame = CFrame.lookAt(feet + dir * 9, feet + dir * 10), Size = Vector3.new(0.1, 0.1, 6) }
			)
		end
	end
	stamp("TRAINED!", Color3.fromRGB(110, 190, 255), d.name and string.upper(d.name) or nil)
end

-- H7: a costume contest calls for contestants: a small "CONTEST!" stamp
function JuiceFx.contestCall()
	stamp("CONTEST!", Color3.fromRGB(200, 140, 255), "COSTUME CONTEST ON THE PLAZA")
end

-- H7: the results: confetti for everyone, the WINNER stamp on the winner's screen
function JuiceFx.contestWin(_at: Vector3?, data: { [string]: any }?)
	if data and data.mine then
		stamp("WINNER!", GOLD, "COSTUME CONTEST")
		confetti(60)
	else
		confetti(20)
	end
end

-- A famous fake unmasked (lore step 4; Juice.fire("unmask")): its face cracks to show metal: a white flash on
-- the screen when it is near you (soft with reduce flashing), a burst of metal glints and a red "FAKE!" pop
function JuiceFx.unmask(at: Vector3?, data: { [string]: any }?)
	if not at then
		return
	end
	ring(at, 9, Color3.fromRGB(255, 240, 220), 0.35)
	ring(at, 5, Color3.fromRGB(255, 70, 60), 0.5)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local g = bit(
			Vector3.new(0.2, 0.2, 1.4),
			CFrame.lookAt(at, at + Vector3.new(math.cos(a), 0.5, math.sin(a))),
			Color3.fromRGB(205, 210, 220)
		)
		g.Material = Enum.Material.Metal
		fadeOut(g, 0.45, { CFrame = g.CFrame * CFrame.new(0, 0, -6) })
	end
	pop(at + Vector3.new(0, 3, 0), "FAKE!", Color3.fromRGB(255, 70, 60))
	if data and data.near then
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = if JuiceFx.reduce then 0.85 else 0.35
		f.ZIndex = 50
		f.Parent = gui
		TweenService:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
			:Play()
		Debris:AddItem(f, 0.4)
	end
end

-- Dazed stars over your head while a stun holds you (PvP crowd control)
function JuiceFx.dazed(on: boolean)
	if not on then
		if stars then
			stars:Destroy()
			stars = nil
		end
		return
	end
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if stars or not head then
		return
	end
	local b = Instance.new("BillboardGui")
	b.Name = "Dazed"
	b.Size = UDim2.fromOffset(90, 30)
	b.StudsOffset = Vector3.new(0, 2.2, 0)
	b.AlwaysOnTop = true
	b.Adornee = head
	b.Parent = folder
	local l =
		Kit.label({ Text = "★ ★ ★", Size = UDim2.fromScale(1, 1), TextColor3 = GOLD, maxText = 24 })
	l.TextStrokeTransparency = 0
	l.Parent = b
	stars = b
	task.spawn(function()
		local t = 0
		while stars == b do
			t += RunService.RenderStepped:Wait()
			if not JuiceFx.reduce then
				l.Rotation = math.sin(t * 6) * 12
				b.StudsOffset = Vector3.new(math.sin(t * 4) * 0.4, 2.2, 0)
			end
		end
	end)
end

function JuiceFx.init()
	folder = Instance.new("Folder")
	folder.Name = "JuiceFx"
	folder.Parent = Workspace
	gui = Kit.screen("Juice", 15)
	-- dazed stars follow the local stun
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("JuiceFx", function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local cc = State.status and State.status.cc
		local stun = cc and cc.stun
		JuiceFx.dazed(stun ~= nil and os.clock() < stun.untilT)
	end))
end

return JuiceFx
