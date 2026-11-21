--!strict
-- HallClient: Crane's Hero Hall on this device (Config.Hall; the server's HallService runs its prompts, dummies,
-- Burst Test and launch pad). It dresses the Hall's tagged city parts as they stream in:
-- * the signs over the doors and the big one on the east face ("HERO HALL"), the lobby's wall screens (WEEKLY
--   BOARDS, CONTRACT BOARD, SQUADS) and the training floor's Burst Test board (this server's best five)
-- * warm lights under the ceiling panels, a glow on the lift stops, the Burst pad and the launch pad
-- * the Hall of Fame: the week's top three of the first board (BoardPlaza) as gold statues with name plates
-- * the training dummies (HqClient's robot) at HallState's spots, aim-assisted like the HQ's (CombatClient)
-- * the meter while you hit them (HallDps), and the launch pad: standing on it tells the server (HallPad), which
--   answers with the arc (HallLaunch, MoveController.launchTo)
-- The shop counter, the boards and the squad board open their panels here (the prompts' Terminal attribute).
-- PLACEHOLDER ART: plain parts and gold blocky statues until a Blender pass.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local RigMath = require(Shared:WaitForChild("RigMath"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))
local BodyShape = require(Shared:WaitForChild("BodyShape"))

local State = require(script.Parent.Parent.State)
local Kit = require(script.Parent.Parent.Ui.Kit)
local CombatClient = require(script.Parent.CombatClient)
local HqClient = require(script.Parent.HqClient)
local MoveController = require(script.Parent.MoveController)

local HallClient = {}

local H = Config.Hall
local player = Players.LocalPlayer

local dummyFolder: Folder? = nil
local statueFolder: Folder? = nil
local dummies: { { id: number, pos: Vector3 } } = {}
local hall: { [string]: any }? = nil
local scoreRows: TextLabel? = nil
local fame: { { name: string, value: number } } = {}
local meter: TextLabel? = nil
local meterUntil = 0

local GOLD = Color3.fromRGB(226, 182, 70)
local NAVY = Color3.fromRGB(34, 48, 96)

local function root(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- A SurfaceGui on a part's face toward (fx, fz)
local function surface(part: BasePart, fx: number, fz: number): SurfaceGui
	local old = part:FindFirstChild("HallGui")
	if old then
		old:Destroy()
	end
	local g = Instance.new("SurfaceGui")
	g.Name = "HallGui"
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 30
	g.LightInfluence = 0
	g.MaxDistance = 600
	g.Face = if fx > 0
		then Enum.NormalId.Right
		elseif fx < 0 then Enum.NormalId.Left
		elseif fz > 0 then Enum.NormalId.Back
		else Enum.NormalId.Front
	g.Adornee = part
	g.Parent = part
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = NAVY
	bg.BorderSizePixel = 0
	bg.Parent = g
	return g
end

local function words(g: SurfaceGui, text: string, color: Color3, size: UDim2?, pos: UDim2?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size or UDim2.fromScale(0.94, 0.8)
	l.Position = pos or UDim2.fromScale(0.03, 0.1)
	l.Font = Kit.font
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.Text = text
	l.Parent = g.Frame
	return l
end

local SCREENS = {
	hallBoards = { "WEEKLY BOARDS", "Press B to see the top heroes" },
	hallContracts = { "CONTRACT BOARD", "Press B for today's jobs" },
	hallSquads = { "SQUADS", "Press B to team up" },
}

local function drawScore()
	local l = scoreRows
	if not l then
		return
	end
	local rows = {}
	for i, r in (hall and hall.best) or {} do
		table.insert(rows, string.format("%d. %s  %s", i, tostring(r[1]), Kit.comma(r[2] or 0)))
	end
	if #rows == 0 then
		table.insert(rows, "No scores yet. Stand on the orange pad and press B!")
	end
	l.Text = table.concat(rows, "\n")
end

local function dress(part: BasePart)
	local tag = part:GetAttribute("Tag")
	if type(tag) ~= "string" or string.sub(tag, 1, 4) ~= "hall" then
		return
	end
	if tag == "hallSign" then
		local big = part:GetAttribute("Ref") == 1
		local wide = part.Size.X > part.Size.Z
		local fx = if wide
			then 0
			else (if part.Position.X > (hall and hall.centre[1] or part.Position.X - 1) then 1 else -1)
		local fz = if wide
			then (if part.Position.Z > (hall and hall.centre[2] or part.Position.Z - 1) then 1 else -1)
			else 0
		local g = surface(part, fx, fz)
		g.PixelsPerStud = if big then 16 else 30
		local l = words(g, H.name, GOLD)
		l.Font = Enum.Font.Bangers
		if big then
			words(
				g,
				"CRANE INDUSTRIES",
				Color3.fromRGB(220, 226, 240),
				UDim2.fromScale(0.6, 0.18),
				UDim2.fromScale(0.2, 0.8)
			)
			l.Size = UDim2.fromScale(0.94, 0.66)
		end
	elseif SCREENS[tag] then
		local s = SCREENS[tag]
		local faceZ = -((part:GetAttribute("Ref") or 1) :: number)
		local g = surface(part, 0, faceZ)
		words(g, s[1], GOLD, UDim2.fromScale(0.9, 0.42), UDim2.fromScale(0.05, 0.1))
		words(g, s[2], Color3.fromRGB(230, 234, 246), UDim2.fromScale(0.9, 0.22), UDim2.fromScale(0.05, 0.62))
	elseif tag == "hallScore" then
		local g = surface(part, 0, 1)
		words(
			g,
			string.format("BURST TEST: %d SECONDS", H.training.burst.seconds),
			GOLD,
			UDim2.fromScale(0.9, 0.2),
			UDim2.fromScale(0.05, 0.04)
		)
		local rows = words(
			g,
			"",
			Color3.fromRGB(230, 234, 246),
			UDim2.fromScale(0.9, 0.7),
			UDim2.fromScale(0.05, 0.27)
		)
		rows.TextXAlignment = Enum.TextXAlignment.Left
		rows.TextYAlignment = Enum.TextYAlignment.Top
		rows.Font = Kit.bodyFont
		scoreRows = rows
		drawScore()
	elseif tag == "hallLight" then
		if not part:FindFirstChild("HallLight") then
			local light = Instance.new("SurfaceLight")
			light.Name = "HallLight"
			light.Face = Enum.NormalId.Bottom
			light.Range = 22
			light.Angle = 120
			light.Brightness = 1.6
			light.Color = Color3.fromRGB(255, 240, 214)
			light.Parent = part
		end
	elseif tag == "hallLift" or tag == "hallBurst" or tag == "hallPad" or tag == "hallMeet" then
		if not part:FindFirstChild("HallLight") then
			local light = Instance.new("PointLight")
			light.Name = "HallLight"
			light.Range = if tag == "hallMeet" then 12 else 9
			light.Brightness = 1.2
			light.Color = part.Color
			light.Parent = part
		end
		if tag == "hallMeet" then
			part.Transparency = 0.35
			part.Material = Enum.Material.Neon
		end
	end
end

local function watchCity()
	local city = Workspace:WaitForChild("City", 120)
	if not city then
		return
	end
	city.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			task.defer(dress, d)
		end
	end)
	for _, d in city:GetDescendants() do
		if d:IsA("BasePart") then
			dress(d)
		end
	end
end

-- A gold statue of a top hero (the blocky R15 body, its rank's size) with a name plate
local function statue(
	f: Folder,
	at: { [string]: number },
	row: { name: string, value: number }?,
	rank: number
)
	local scale = (at.scale or 1) * 1.6
	local layout = RigMath.layout(Config.HeroRig, nil, scale)
	local colors: { [string]: Color3 } = {}
	for _, name in BodyShape.PARTS do
		colors[name] = if rank == 1
			then GOLD
			elseif rank == 2 then Color3.fromRGB(196, 200, 212)
			else Color3.fromRGB(196, 132, 84)
	end
	local rig = NpcRig.build(layout, "Statue", colors, Enum.Material.Metal)
	rig.model.Parent = f
	local base = Vector3.new(at.x, at.y, at.z)
	local face = if hall
		then Vector3.new(hall.centre[1], base.Y, hall.centre[2] - 40)
		else base + Vector3.new(0, 0, -1)
	NpcRig.place(rig, CFrame.lookAt(base, face))
	-- a heroic pose: one fist up
	NpcRig.bend(rig, "RightShoulder", CFrame.Angles(math.rad(170), 0, math.rad(-8)))
	local plate = Instance.new("BillboardGui")
	plate.Size = UDim2.fromOffset(170, 44)
	plate.StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0)
	plate.MaxDistance = 80
	plate.LightInfluence = 0
	plate.Adornee = rig.parts.Head
	plate.Parent = rig.model
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 0.25
	l.BackgroundColor3 = NAVY
	l.TextColor3 = GOLD
	l.Font = Kit.font
	l.TextScaled = true
	local board = Config.Boards.boards[1]
	l.Text = if row
		then string.format("#%d %s\n%s %s", rank, row.name, Kit.comma(row.value), board.units)
		else string.format("#%d  THIS COULD BE YOU\n%s", rank, board.name)
	l.Parent = plate
end

local function drawStatues()
	local f = statueFolder
	if not (f and hall and hall.statues) then
		return
	end
	f:ClearAllChildren()
	for i, at in hall.statues do
		statue(f, at, fame[i], i)
	end
end

local function drawDummies()
	local f = dummyFolder
	if not (f and hall) then
		return
	end
	f:ClearAllChildren()
	table.clear(dummies)
	local side = if State.hero and State.hero.side == "villain" then "villain" else "hero"
	for _, d in hall.dummies or {} do
		local pos = Vector3.new(d.x, d.y, d.z)
		HqClient.dummy(f, pos, d.big == 1, side)
		table.insert(dummies, { id = d.id, pos = pos })
	end
end

local function meterLabel(): TextLabel
	local l = meter
	if l then
		return l
	end
	local gui = Kit.screen("HallMeter", 5)
	local m = Kit.label({
		Name = "Meter",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.fromOffset(300, 30),
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.15,
		TextColor3 = GOLD,
		maxText = 22,
		Visible = false,
	})
	Kit.round(m, 10)
	Kit.stroke(m, Kit.color.ink, 2)
	m.Parent = gui
	meter = m
	return m
end

local function onDps(p: any)
	local l = meterLabel()
	if type(p.burstDone) == "number" then
		l.Text = string.format("BURST TEST: %s DAMAGE!", Kit.comma(p.burstDone))
		meterUntil = os.clock() + 5
	elseif type(p.burst) == "table" then
		l.Text = string.format("BURST TEST  %d s   %s", p.burst.left or 0, Kit.comma(p.burst.score or 0))
		meterUntil = os.clock() + 2
	else
		l.Text = string.format("DPS %s   TOTAL %s", Kit.comma(p.dps or 0), Kit.comma(p.total or 0))
		meterUntil = os.clock() + 2
	end
	l.Visible = true
end

-- the launch pad: standing on it (for a moment, alive, not in a story scene) asks the server
local padSince: number? = nil
local padSent = -math.huge
local function padStep()
	local pad = hall and hall.pad
	local r = root()
	if not (pad and r) then
		return
	end
	local p = r.Position
	local dx, dz = p.X - pad.x, p.Z - pad.z
	local on = dx * dx + dz * dz <= pad.r * pad.r and p.Y > pad.y - 1 and p.Y < pad.y + 7
	local now = os.clock()
	if not on then
		padSince = nil
		return
	end
	padSince = padSince or now
	if now - (padSince :: number) >= H.roof.pad.hold and now - padSent > 2 then
		padSent = now
		Net.send("HallPad")
	end
end

function HallClient.init()
	if not H.on then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "HeroHall"
	f.Parent = Workspace
	local df = Instance.new("Folder")
	df.Name = "Dummies"
	df.Parent = f
	dummyFolder = df
	local sf = Instance.new("Folder")
	sf.Name = "HallOfFame"
	sf.Parent = f
	statueFolder = sf
	Net.listen("HallState", function(p: any)
		if type(p) ~= "table" then
			return
		end
		local first = hall == nil
		hall = p
		drawScore()
		if first then
			drawDummies()
			drawStatues()
		end
	end)
	Net.listen("BoardPlaza", function(p: any)
		local rows = type(p) == "table" and type(p.boards) == "table" and p.boards[1]
		if type(rows) ~= "table" then
			return
		end
		local list = {}
		for i = 1, math.min(3, #rows) do
			local r = rows[i]
			table.insert(list, { name = tostring(r.name or "?"), value = tonumber(r.value) or 0 })
		end
		fame = list
		drawStatues()
	end)
	Net.listen("HallDps", onDps)
	Net.listen("HallLaunch", function(p: any)
		if type(p) ~= "table" or type(p.to) ~= "table" then
			return
		end
		MoveController.launchTo(Vector3.new(p.to[1], p.to[2], p.to[3]), p.time or 2.4, p.height or 60)
	end)
	CombatClient.addTargetSource(function()
		return dummies
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player then
			return
		end
		local t = prompt:GetAttribute("Terminal")
		if t == "hallShop" then
			require(script.Parent.Parent.Ui.ShopHud).open()
		elseif t == "hallBoards" then
			require(script.Parent.Parent.Ui.BoardHud).open()
		elseif t == "hallSquads" then
			require(script.Parent.Parent.Ui.SquadHud).open()
		end
	end)
	task.spawn(watchCity)
	RunService.Heartbeat:Connect(function()
		padStep()
		local l = meter
		if l and l.Visible and os.clock() > meterUntil then
			l.Visible = false
		end
	end)
	player.CharacterAdded:Connect(function()
		task.defer(drawDummies) -- a new slot may be the other side: the dummies wear its colours
	end)
end

return HallClient
