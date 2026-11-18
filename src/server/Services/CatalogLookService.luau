-- CatalogLookService: loads the Roblox catalog hair and facial hair heroes wear (Config.CatalogLooks; nate,
-- 2026-11-18: "why do you keep creating faces, hair, and facial hair like roblox doesnt already have a shit ton").
-- Each item is loaded once at boot through a HumanoidDescription (Players:CreateHumanoidModelFromDescription
-- works for any catalog item, Roblox's or a UGC creator's), its Accessory is kept in ReplicatedStorage.
-- CatalogLooks named by asset id, and every device clones it from there (LookKit.catalogAccessory), so the
-- server's hero and the creator's preview wear the very same item. Faces need no load: their image ids are in
-- Config.CatalogLooks. An item that fails (deleted, off the catalog) is skipped and that look shows no hair.
-- When the last item is in, every hero's look is rebuilt (Loaded).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local CatalogLookService = {}

CatalogLookService.Loaded = Signal.new() -- every item tried (the looks rebuild)
CatalogLookService.done = false

local PARALLEL = 4 -- loads at once
local folder: Folder

local function load(id: number, field: string)
	local desc = Instance.new("HumanoidDescription")
	desc[field] = tostring(id)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	desc:Destroy()
	if not ok or not model then
		warn(string.format("[CatalogLooks] %d did not load: %s", id, tostring(model)))
		return
	end
	local acc = model:FindFirstChildWhichIsA("Accessory")
	if acc then
		for _, d in acc:GetDescendants() do
			if d:IsA("LuaSourceContainer") or d:IsA("Weld") or d:IsA("WeldConstraint") then
				d:Destroy()
			end
		end
		acc.Name = tostring(id)
		acc.Parent = folder
	else
		warn(string.format("[CatalogLooks] %d has no accessory", id))
	end
	model:Destroy()
end

function CatalogLookService.init()
	folder = Instance.new("Folder")
	folder.Name = "CatalogLooks"
	folder.Parent = ReplicatedStorage
	local queue = {}
	for _, row in Config.CatalogLooks.hair do
		table.insert(queue, { row[2], "HairAccessory" })
	end
	for _, row in Config.CatalogLooks.beards do
		table.insert(queue, { row[2], "FaceAccessory" })
	end
	task.spawn(function()
		local running, n = 0, 0
		for _, item in queue do
			while running >= PARALLEL do
				task.wait(0.05)
			end
			running += 1
			task.spawn(function()
				load(item[1], item[2])
				running -= 1
				n += 1
			end)
		end
		while running > 0 do
			task.wait(0.1)
		end
		CatalogLookService.done = true
		print(string.format("[CatalogLooks] %d of %d catalog items loaded", #folder:GetChildren(), #queue))
		CatalogLookService.Loaded:Fire()
	end)
end

return CatalogLookService
