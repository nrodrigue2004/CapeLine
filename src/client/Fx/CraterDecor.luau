--!strict
-- CraterDecor: this device's loose lab debris on the Crater's floor (lore step 9; gap-wrecks, 2026-11-19). The
-- server dresses the blasted Crane lab in art/blender/crater.py's meshes (CityBuilder, Shared.CraterArtKit); this
-- scatters the small bits (rubble, pipes, a console, plates) by the device's preset (Config.Presets <preset>.ruins:
-- none on phones), the same seeded layout on every device of a preset (CraterArtKit.bits), clear of the lab's
-- walls and the open middle. Ghost meshes only: no collision, queries or touches, no shadows. Built once the
-- camera comes within NEAR studs of the Crater, dropped past FAR, rebuilt when the preset changes; checked once a
-- second (no per-frame loop). Nothing imported in Art.Crater: nothing drawn (the bits are extra dressing).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CraterArtKit = require(Shared:WaitForChild("CraterArtKit"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))
local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local CraterDecor = {}
CraterDecor.built = 0 -- meshes this device drew (the Dev panel can show it)

local NEAR, FAR = 600, 800
local folder: Folder? = nil
local crater: any = nil
local builtFor = "" -- the preset the bits were built for ("" none)

local function source(name: string): MeshPart?
	local art = ReplicatedStorage:FindFirstChild("Art")
	local root = art and art:FindFirstChild("Crater")
	local src = root and root:FindFirstChild(name, true)
	return if src and src:IsA("MeshPart") then src else nil
end

local function clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	CraterDecor.built = 0
	builtFor = ""
end

local function build(preset: string)
	clear()
	builtFor = preset
	local bits = CraterArtKit.bits(Config, crater.x, crater.z, crater.art, preset)
	if #bits == 0 then
		return
	end
	local ready = CraterArtKit.readyLooks(Config, function(name: string): boolean
		return source(name) ~= nil
	end)
	local f = Instance.new("Folder")
	f.Name = "CraterDecor"
	for _, b in bits do
		local fit = CraterArtKit.fit(Config, b.look)
		if not fit or not ready[b.look] then
			continue
		end
		local place = {
			look = b.look,
			cx = b.x,
			cy = crater.floorY + fit.frame[2] / 2,
			cz = b.z,
			sx = fit.frame[1],
			sy = fit.frame[2],
			sz = fit.frame[3],
			ry = b.ry,
		}
		local at = CFrame.new(place.cx, place.cy, place.cz) * CFrame.Angles(0, math.rad(b.ry), 0)
		for _, m in CraterArtKit.meshes(Config, place) do
			local src = source(m.name)
			if not src then
				continue
			end
			local p = MeshFix.clone(src)
			for _, c in p:GetChildren() do
				if m.maps and c:IsA("SurfaceAppearance") then
					c.AlphaMode = Enum.AlphaMode.Overlay
				else
					c:Destroy()
				end
			end
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Size = Vector3.new(m.size[1], m.size[2], m.size[3])
			p.CFrame = at * CFrame.new(m.offset[1], m.offset[2], m.offset[3]) * MeshFix.of(p) -- the import's turn
			p.Color = Color3.fromRGB(m.color[1], m.color[2], m.color[3])
			p.Transparency = m.alpha
			p.Parent = f
			CraterDecor.built += 1
		end
	end
	f.Parent = Workspace
	folder = f
end

local function check()
	local cam = Workspace.CurrentCamera
	if not crater or not cam then
		return
	end
	local pos = cam.CFrame.Position
	local d = Vector2.new(pos.X - crater.x, pos.Z - crater.z).Magnitude
	if builtFor == "" and d < NEAR then
		build(QualityController.name)
	elseif builtFor ~= "" and d > FAR then
		clear()
	end
end

function CraterDecor.init()
	task.spawn(function()
		local value = ReplicatedStorage:WaitForChild("WorldInfo", 120)
		if not value or not value:IsA("StringValue") then
			return
		end
		local ok, info = pcall(HttpService.JSONDecode, HttpService, value.Value)
		if not ok or type(info) ~= "table" then
			return
		end
		for _, lm in info.landmarks or {} do
			if type(lm.art) == "table" and type(lm.floorY) == "number" then
				crater = lm
			end
		end
		if not crater then
			return
		end
		QualityController.Changed:Connect(function(name: string)
			if builtFor ~= "" and builtFor ~= name then
				build(name)
			end
		end)
		while true do
			check()
			task.wait(1)
		end
	end)
end

return CraterDecor
