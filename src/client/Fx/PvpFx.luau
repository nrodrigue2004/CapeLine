-- PvpFx: what PvP and death look like in the world, drawn on this device (spec: The PvP flag "Visible";
-- Defeat and death; the juice table rows Downed, Revive, PvP flag on).
-- * Rings: a flagged player stands in a ring, blue and round for the Vigil, red and square for the
--   Syndicate (colorblind-safe); it grows in
--   when the flag turns on and is faint while spawn protection lasts.
-- * Downed: a grey pulse ring under the kneeling hero.
-- * PvP defeat: the hero overloads into sparks (the Overload attribute ticks up on the server).
-- * Pings: Help, Here and Danger markers over the spot, for a few seconds.
-- The rings are Blender meshes (art/blender/rings.py, ReplicatedStorage.Art.Rings; Everything Left 385): the Vigil's
-- round band with inward chevrons, the Syndicate's notched square, the Downed ring's dashes and plus marks.
-- PLACEHOLDER ART: flat neon discs while Art.Rings is not imported; the pings are text markers.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MeshFix = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshFix"))

local State = require(script.Parent.Parent.State)
local PvpClient = require(script.Parent.Parent.Controllers.PvpClient)
local CombatFx = require(script.Parent.CombatFx)
local Kit = require(script.Parent.Parent.Ui.Kit)

local PvpFx = {}

local folder: Folder
local rings: { [Player]: { part: BasePart, on: boolean, square: boolean? } } = {}
local downRings: { [Player]: BasePart } = {}
local overloads: { [Player]: number } = {}

local PING = {
	{ text = "HELP!", color = Color3.fromRGB(255, 220, 90), mark = "help", shape = "circle" },
	{ text = "HERE", color = Color3.fromRGB(120, 220, 255), mark = "here", shape = "circle" },
	{ text = "▲ DANGER", color = Color3.fromRGB(255, 90, 80), mark = "danger", shape = "triangle" }, -- the triangle: colorblind-safe danger
}

-- A ring's mesh lying flat (size studs across), or nil while Art.Rings is not imported
local RING_UP = 0.12
local function ringMesh(name: string, color: Color3, size: number): MeshPart?
	local art = ReplicatedStorage:FindFirstChild("Art")
	local set = art and art:FindFirstChild("Rings")
	local src = set and set:FindFirstChild(name, true)
	if not (src and src:IsA("MeshPart")) then
		return nil
	end
	local p = MeshFix.clone(src)
	for _, c in p:GetChildren() do
		c:Destroy()
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(size, RING_UP, size)
	p.Transparency = 0.25
	p.Parent = folder
	return p
end

-- Where a ring lies: flat under the root (a mesh is flat as drawn; the old disc is a cylinder turned on its side)
local function lay(p: BasePart, at: Vector3, yaw: number)
	if p:IsA("MeshPart") then
		p.CFrame = CFrame.new(at) * CFrame.Angles(0, yaw, 0) * MeshFix.turn("Rings")
	elseif (p :: Part).Shape == Enum.PartType.Block then
		p.CFrame = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	else
		p.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
	end
end

-- A size as the part wants it (a mesh and a block lie flat on y; the old disc's thin axis is x)
local function across(p: BasePart, size: number): Vector3
	if p:IsA("MeshPart") then
		return Vector3.new(size, RING_UP, size)
	elseif (p :: Part).Shape == Enum.PartType.Block then
		return Vector3.new(size * 0.886, 0.2, size * 0.886)
	end
	return Vector3.new(0.2, size, size)
end

local function ring(color: Color3, size: number): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.2, size, size)
	p.Transparency = 0.45
	p.Parent = folder
	return p
end

local function rootOf(p: Player): BasePart?
	local char = p.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function step(now: number)
	for _, p in Players:GetPlayers() do
		local root = rootOf(p)
		local want = p:GetAttribute("Pvp") == true and root ~= nil
		local r = rings[p]
		-- colorblind-safe: Vigil rings are round, Syndicate rings are square (spec: Accessibility)
		local square = p:GetAttribute("PvpSide") == "villain"
		if r and (r :: any).square ~= square then
			r.part:Destroy()
			rings[p] = nil
			r = nil
		end
		if want and root then
			if not r then
				local color = PvpClient.ringColor(p:GetAttribute("PvpSide"))
				local part: BasePart = ringMesh(if square then "RingSquare" else "RingRound", color, 1)
					or ring(color, 1)
				if square and not part:IsA("MeshPart") then
					(part :: Part).Shape = Enum.PartType.Block
				end
				part.Size = across(part, 1)
				r = { part = part, on = true, square = square } :: any
				rings[p] = r
				-- the ring grows in (the "PvP flag on" beat)
				TweenService
					:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = across(part, 7) })
					:Play()
			end
			local ring0 = (r :: any).part :: BasePart
			ring0.Color = PvpClient.ringColor(p:GetAttribute("PvpSide"))
			local faint = p:GetAttribute("Protected") == true
			ring0.Transparency = if ring0:IsA("MeshPart")
				then (if faint then 0.75 else 0.2)
				else (if faint then 0.8 else 0.4)
			lay(ring0, root.Position - Vector3.new(0, 2.9, 0), if square then math.rad(45) else now * 0.6)
		elseif r then
			r.part:Destroy()
			rings[p] = nil
		end
		-- Downed: a grey ring that pulses
		local downed = p:GetAttribute("Downed") == true and root ~= nil
		local d = downRings[p]
		if downed and root then
			if not d then
				local grey = Color3.fromRGB(170, 170, 180)
				d = ringMesh("RingDowned", grey, 6) or ring(grey, 6)
				downRings[p] = d
			end
			local pulse = 6 + math.sin(now * 5) * 1.2
			local dp = d :: BasePart
			dp.Size = across(dp, pulse)
			lay(dp, root.Position - Vector3.new(0, 2.8, 0), -now * 0.8)
		elseif d then
			d:Destroy()
			downRings[p] = nil
		end
	end
end

-- The PvP defeat burst: the hero overloads into sparks
local function watchOverload(p: Player)
	overloads[p] = (p:GetAttribute("Overload") or 0) :: number
	p:GetAttributeChangedSignal("Overload"):Connect(function()
		local n = (p:GetAttribute("Overload") or 0) :: number
		if n == overloads[p] then
			return
		end
		overloads[p] = n
		local root = rootOf(p)
		if root then
			local style = if p == Players.LocalPlayer
				then State.hero.fxStyle
				else (p:GetAttribute("FxStyle") or "Comic")
			for i = 0, 2 do
				task.delay(i * 0.12, function()
					CombatFx.burst(
						root.Position
							+ Vector3.new(math.random(-2, 2), math.random(-1, 2), math.random(-2, 2)),
						style,
						Color3.fromRGB(170, 230, 255)
					)
				end)
			end
		end
	end)
end

local function showPing(ping: any)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(ping.x, ping.y + 4, ping.z)
	anchor.Parent = folder
	local row = PING[ping.kind] or PING[2]
	local bb = Instance.new("BillboardGui")
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(120, 46)
	bb.LightInfluence = 0
	bb.MaxDistance = 1000
	bb.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.6)
	label.Font = Enum.Font.Bangers
	label.TextScaled = true
	label.TextColor3 = row.color
	label.TextStrokeTransparency = 0.2
	label.Text = if ping.downed then "HELP!" else row.text
	label.Parent = bb
	-- gap-icons2: the ping's comic icon on its shape above the word (the word then drops its triangle)
	local mark = Instance.new("Frame")
	mark.BackgroundTransparency = 1
	mark.AnchorPoint = Vector2.new(0.5, 1)
	mark.Position = UDim2.fromScale(0.5, 0)
	mark.Size = UDim2.fromOffset(40, 40)
	mark.Parent = bb
	local key = if ping.downed then "help" else row.mark
	if Kit.showMark(mark, if ping.downed then "circle" else row.shape, row.color, "marker", key) then
		bb.Size = UDim2.fromOffset(120, 46)
		bb.StudsOffset = Vector3.new(0, 2, 0)
		if not ping.downed and row.mark == "danger" then
			label.Text = "DANGER"
		end
	end
	local who = Instance.new("TextLabel")
	who.BackgroundTransparency = 1
	who.Position = UDim2.fromScale(0, 0.6)
	who.Size = UDim2.fromScale(1, 0.4)
	who.Font = Enum.Font.GothamBold
	who.TextScaled = true
	who.TextColor3 = Color3.new(1, 1, 1)
	who.TextStrokeTransparency = 0.3
	who.Text = (if ping.squad then "SQUAD  " else "") .. (ping.name or "")
	who.Parent = bb
	Debris:AddItem(anchor, ping.life or 8)
end

function PvpFx.init()
	folder = Instance.new("Folder")
	folder.Name = "PvpFx"
	folder.Parent = Workspace
	for _, p in Players:GetPlayers() do
		watchOverload(p)
	end
	Players.PlayerAdded:Connect(watchOverload)
	Players.PlayerRemoving:Connect(function(p)
		local r = rings[p]
		if r then
			r.part:Destroy()
			rings[p] = nil
		end
		local d = downRings[p]
		if d then
			d:Destroy()
			downRings[p] = nil
		end
		overloads[p] = nil
	end)
	PvpClient.Ping:Connect(showPing)
	RunService.RenderStepped:Connect(FrameProf.wrap("PvpFx", function()
		step(os.clock())
	end))
end

return PvpFx
