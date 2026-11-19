-- PocketArt: the pockets' kit look on the server (2026-11-19, the pocket kit pass; Shared.PocketDress,
-- Config.PocketKit). Before a pocket's boxes become parts, dress() gives them their kit looks (texture, tint,
-- material: never their place, size or solidity); after, tier1() builds the dressing every device sees (wall caps,
-- neon rims, the sign boards with their lettering) into the pocket's model, so it streams with the pocket, and
-- marks the model with its layout and index so each device adds its own tiers, lights and props (PocketDecor).
-- No per-frame work: everything is built once with the pocket.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PocketDress = require(Shared:WaitForChild("PocketDress"))
local SignKit = require(Shared:WaitForChild("SignKit"))

local PocketArt = {}

local function rgb(key: string): Color3
	local c = Config.City.palette[key] or { 255, 0, 255 }
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The kit looks on a built layout's boxes; returns its dressing (call before making the parts)
function PocketArt.dress(l: any, layout: string): PocketDress.Dress
	return PocketDress.apply(Config, l, layout)
end

-- The tier 1 dressing into the pocket's model (part: CityBuilder.part), and the marks PocketDecor reads
function PocketArt.tier1(
	model: Model,
	dress: PocketDress.Dress,
	l: any,
	layout: string,
	part: (any) -> BasePart
): number
	model:SetAttribute("PocketLayout", layout)
	model:SetAttribute("PocketIndex", l.index)
	local folder = Instance.new("Folder")
	folder.Name = "Dress"
	local n = 0
	for _, e in dress.extras do
		if e.tier == 1 then
			local p = part(e)
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			if e.sign then
				SignKit.letter(p, e.sign.text, rgb(e.sign.ink), {
					pixels = Config.PocketKit.sign.pixels,
					stroke = Config.PocketKit.sign.stroke,
				})
			end
			p.Parent = folder
			n += 1
		end
	end
	folder.Parent = model
	return n
end

return PocketArt
