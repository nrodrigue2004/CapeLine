-- SideOnly: hides what is only for the other side (side-content, 2026-11-19; nate: "Side/radiant quests should be
-- different for hero/villain. You should only see the ones for your side"). The server tags a model "SideOnly"
-- with the side it serves (SideQuestService: a giver whose chains are all one side's, Duchess Vanta for the
-- Syndicate); on a device of the other side its parts, decals, signs and talk prompt are switched off (local only:
-- the model stays on the server and shows again if this hero's side changes). Event-driven, no per-frame work.

local CollectionService = game:GetService("CollectionService")

local State = require(script.Parent.Parent.State)

local SideOnly = {}

local TAG = "SideOnly"

local function mySide(): string
	return if State.hero and State.hero.side == "villain" then "villain" else "hero"
end

-- Show or hide one thing for this device's side
local function apply(m: Instance)
	local hide = m:GetAttribute(TAG) ~= nil and m:GetAttribute(TAG) ~= mySide()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if hide then 1 else 0
		elseif d:IsA("Decal") then
			if d:GetAttribute("SideOnlyAlpha") == nil then
				d:SetAttribute("SideOnlyAlpha", d.Transparency)
			end
			d.Transparency = if hide then 1 else d:GetAttribute("SideOnlyAlpha") :: number
		elseif
			d:IsA("BillboardGui")
			or d:IsA("SurfaceGui")
			or d:IsA("ProximityPrompt")
			or d:IsA("ParticleEmitter")
			or d:IsA("Light")
		then
			if d:GetAttribute("SideOnlyOn") == nil then
				d:SetAttribute("SideOnlyOn", (d :: any).Enabled)
			end
			(d :: any).Enabled = not hide and d:GetAttribute("SideOnlyOn") == true
		end
	end
end

local function applyAll()
	for _, m in CollectionService:GetTagged(TAG) do
		apply(m)
	end
end

SideOnly.apply = apply

function SideOnly.init()
	local last = mySide()
	local function watch(m: Instance)
		-- parts that stream in later get the same look (one deferred pass however many arrive at once)
		local queued = false
		m.DescendantAdded:Connect(function()
			if not queued then
				queued = true
				task.defer(function()
					queued = false
					apply(m)
				end)
			end
		end)
		task.defer(apply, m)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
	for _, m in CollectionService:GetTagged(TAG) do
		watch(m)
	end
	State.Changed:Connect(function()
		local now = mySide()
		if now ~= last then
			last = now
			applyAll()
		end
	end)
end

return SideOnly
