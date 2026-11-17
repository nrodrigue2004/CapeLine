-- NemesisFx: the look of a nemesis in the world (spec: Hero MMO features > Nemesis; H5). Its body is a
-- Brute Bot drawn by EnemyRenderer; this rides on it: its name and rank over its head, its colour set as a
-- cape (or not) and a head piece, one visible piece per trait (extra plates, a second arm cannon, a heal
-- drone orbiting it, a summoner's antenna; the cloak flickers it out), the glowing weak point on its back
-- once your Intel is complete, the red warning shapes of its signature attacks, and the teleport flash
-- when it escapes. PLACEHOLDER ART: plain parts until the nemesis renderer on the R15 rig (art pass).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local NemesisMath = require(Shared:WaitForChild("NemesisMath"))
local Net = require(Shared:WaitForChild("Net"))

local EnemyRenderer = require(script.Parent.Parent.Controllers.EnemyRenderer)
local Juice = require(script.Parent.Juice)

local NemesisFx = {}

local N = Config.Nemesis
local WARN = Color3.fromRGB(255, 60, 50)
local folder: Folder
type Rig = {
	parts: { { p: BasePart, off: CFrame, spin: boolean? } },
	tag: BillboardGui,
	core: BasePart?,
	last: Vector3?,
	facing: Vector3,
	cloakUntil: number,
}
local rigs: { [number]: Rig } = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function part(size: Vector3, color: Color3, shape: Enum.PartType?, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	return p
end

local function drop(id: number)
	local r = rigs[id]
	if r then
		for _, x in r.parts do
			x.p:Destroy()
		end
		r.tag:Destroy()
		rigs[id] = nil
	end
end

local function build(d: { [string]: any })
	drop(d.id)
	local set = N.colors[d.colors or 1] or N.colors[1]
	local main, trim = rgb(set[1]), rgb(set[2])
	local parts = {}
	local function add(p: BasePart, off: CFrame, spin: boolean?)
		table.insert(parts, { p = p, off = off, spin = spin })
	end
	-- its head piece and cape (the build shows as the shoulders' width)
	local wide = if d.build == "bulky" or d.build == "spiked" then 1.3 else 1
	add(part(Vector3.new(5 * wide, 1, 3), trim, nil, Enum.Material.Metal), CFrame.new(0, 3.2, 0))
	if d.head == "horned" then
		add(part(Vector3.new(0.6, 2.2, 0.6), trim), CFrame.new(-1.2, 6.2, 0) * CFrame.Angles(0, 0, 0.4))
		add(part(Vector3.new(0.6, 2.2, 0.6), trim), CFrame.new(1.2, 6.2, 0) * CFrame.Angles(0, 0, -0.4))
	elseif d.head == "dome" then
		add(part(Vector3.new(3, 3, 3), main, Enum.PartType.Ball, Enum.Material.Glass), CFrame.new(0, 5.8, 0))
	elseif d.head == "cyclops" then
		add(
			part(Vector3.new(1.2, 1.2, 1.2), WARN, Enum.PartType.Ball, Enum.Material.Neon),
			CFrame.new(0, 5.4, -1.4)
		)
	else
		add(
			part(Vector3.new(2.6, 0.5, 0.4), Color3.fromRGB(120, 230, 255), nil, Enum.Material.Neon),
			CFrame.new(0, 5.2, -1.4)
		)
	end
	if d.cape then
		add(part(Vector3.new(4.5 * wide, 6, 0.3), main, nil, Enum.Material.Fabric), CFrame.new(0, 0.5, 1.8))
	end
	-- traits: one visible piece each
	for i, t in N.traits do
		if NemesisMath.hasTrait(d.traits or 0, i) then
			if t.id == "plates" then
				add(
					part(Vector3.new(5.5 * wide, 3, 0.6), trim, nil, Enum.Material.DiamondPlate),
					CFrame.new(0, 1.4, -1.9)
				)
			elseif t.id == "second" then
				add(
					part(Vector3.new(1.2, 1.2, 4), trim, Enum.PartType.Cylinder, Enum.Material.Metal),
					CFrame.new(3.4 * wide, 2, -1) * CFrame.Angles(0, math.pi / 2, 0)
				)
			elseif t.id == "healDrone" then
				add(
					part(
						Vector3.new(1.4, 1.4, 1.4),
						Color3.fromRGB(120, 255, 140),
						Enum.PartType.Ball,
						Enum.Material.Neon
					),
					CFrame.new(4, 6, 0),
					true
				)
			elseif t.id == "summon" then
				add(part(Vector3.new(0.3, 3, 0.3), trim, nil, Enum.Material.Metal), CFrame.new(1, 7, 0.8))
			end
		end
	end
	local core: BasePart? = nil
	if d.weak then
		core = part(
			Vector3.new(1.8, 1.8, 1.8),
			Color3.fromRGB(255, 220, 60),
			Enum.PartType.Ball,
			Enum.Material.Neon
		)
		add(core :: BasePart, CFrame.new(0, 2.5, 2.2))
	end
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(220, 46)
	tag.StudsOffset = Vector3.new(0, 9.5, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 220
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.Bangers
	l.TextScaled = true
	l.TextColor3 = main
	l.TextStrokeTransparency = 0.2
	l.Text = string.upper(d.name or "") .. "  " .. string.rep("★", d.rank or 1)
	l.Parent = tag
	local anchor = part(Vector3.one * 0.2, main)
	anchor.Transparency = 1
	tag.Adornee = anchor
	tag.Parent = anchor
	add(anchor, CFrame.new(0, 4, 0))
	rigs[d.id] = { parts = parts, tag = tag, core = core, facing = Vector3.new(0, 0, -1), cloakUntil = 0 }
end

-- The red warning shapes where a signature attack lands
local function warn(d: { [string]: any })
	local y = d.y or 0
	for _, a in d.areas or {} do
		local p: Part
		if a.shape == "line" then
			local dir = Vector3.new(a.dx, 0, a.dz)
			local mid = Vector3.new(a.x, y, a.z) + dir * (a.length / 2)
			p = part(Vector3.new(a.r * 2, 0.3, a.length), WARN, nil, Enum.Material.Neon)
			p.CFrame = CFrame.lookAt(mid, mid + dir)
		else
			-- novas and cones show as a disc (a cone's wedge sits inside it)
			p = part(Vector3.new(0.3, a.r * 2, a.r * 2), WARN, Enum.PartType.Cylinder, Enum.Material.Neon)
			p.CFrame = CFrame.new(a.x, y, a.z) * CFrame.Angles(0, 0, math.pi / 2)
		end
		p.Transparency = 0.75
		TweenService:Create(p, TweenInfo.new(d.delay or 1), { Transparency = 0.35 }):Play()
		task.delay(d.delay or 1, function()
			TweenService:Create(p, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			task.delay(0.25, function()
				p:Destroy()
			end)
		end)
	end
end

local function flash(at: Vector3)
	local p = part(Vector3.one * 4, Color3.new(1, 1, 1), Enum.PartType.Ball, Enum.Material.Neon)
	p.CFrame = CFrame.new(at)
	TweenService:Create(p, TweenInfo.new(0.45), { Size = Vector3.one * 22, Transparency = 1 }):Play()
	task.delay(0.5, function()
		p:Destroy()
	end)
	Juice.fire("nemesisEscape", at, { mine = false })
end

local function step()
	local now = os.clock()
	for id, r in rigs do
		local pos = EnemyRenderer.position(id)
		if not pos then
			continue
		end
		if r.last then
			local mv = Vector3.new(pos.X - r.last.X, 0, pos.Z - r.last.Z)
			if mv.Magnitude > 0.05 then
				r.facing = r.facing:Lerp(mv.Unit, 0.2)
			end
		end
		r.last = pos
		local base = CFrame.lookAt(pos, pos + r.facing)
		local hidden = now < r.cloakUntil and math.floor(now * 12) % 3 ~= 0
		for _, x in r.parts do
			local off = x.off
			if x.spin then
				off = CFrame.Angles(0, now * 2, 0) * off
			end
			x.p.CFrame = base * off
			x.p.LocalTransparencyModifier = if hidden then 0.85 else 0
		end
	end
end

function NemesisFx.init()
	folder = Instance.new("Folder")
	folder.Name = "NemesisFx"
	folder.Parent = Workspace
	Net.listen("NemesisState", function(d: any)
		if type(d) ~= "table" then
			return
		end
		if d.k == "spawn" and d.id then
			build(d)
			local pos = EnemyRenderer.position(d.id)
			Juice.fire("nemesisArrive", pos, { mine = false })
		elseif d.k == "sig" then
			warn(d)
		elseif d.k == "cloak" and d.id and rigs[d.id] then
			rigs[d.id].cloakUntil = os.clock() + (d.time or 3)
		elseif (d.k == "escape" or d.k == "gloat" or d.k == "leave") and d.id then
			local r = rigs[d.id]
			local pos = (r and r.last) or EnemyRenderer.position(d.id)
			if pos then
				flash(pos)
			end
			drop(d.id)
		end
	end)
	RunService.Heartbeat:Connect(FrameProf.wrap("NemesisFx", step))
	-- a defeated nemesis (the Showdown) drops its look with its robot
	task.spawn(function()
		while true do
			task.wait(1)
			for id in rigs do
				if not EnemyRenderer.position(id) then
					drop(id)
				end
			end
		end
	end)
end

return NemesisFx
