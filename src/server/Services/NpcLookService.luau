-- NpcLookService: loads the real Roblox hair the robots wear (Config.NpcLooks.hairs: free catalog items made by
-- Roblox) once at boot, into ReplicatedStorage.NpcLooks.Hair, where every device clones it onto its own robot
-- rigs (NpcRig.wear). InsertService only loads items Roblox or the game's owner made; each one is also checked
-- to be Roblox's own before it is kept, so no player-made item ever shows. An item that fails is skipped and
-- the robots fall back to their plain hair.

local InsertService = game:GetService("InsertService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local NpcLookService = {}

local function madeByRoblox(id: number): boolean
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
	end)
	return ok and type(info) == "table" and info.Creator ~= nil and info.Creator.Name == "Roblox"
end

local function load(name: string, id: number, into: Folder)
	if not madeByRoblox(id) then
		warn(string.format("[NpcLooks] hair %s (%d) is not a Roblox item; skipped", name, id))
		return
	end
	local ok, model = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok or not model then
		warn(string.format("[NpcLooks] hair %s (%d) did not load: %s", name, id, tostring(model)))
		return
	end
	local acc = model:FindFirstChildWhichIsA("Accessory", true)
	if acc then
		for _, d in acc:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		acc.Name = name
		acc.Parent = into
	end
	model:Destroy()
end

function NpcLookService.init()
	local folder = Instance.new("Folder")
	folder.Name = "NpcLooks"
	local hair = Instance.new("Folder")
	hair.Name = "Hair"
	hair.Parent = folder
	folder.Parent = ReplicatedStorage
	for name, id in Config.NpcLooks.hairs do
		task.spawn(load, name, id, hair)
	end
end

return NpcLookService
