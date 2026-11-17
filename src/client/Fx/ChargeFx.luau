-- ChargeFx: the look of a charge-up power (spec: Hero MMO features > Charge-up powers; H2). Any hero
-- charging one (the Charging attribute, the ability's number) glows in their energy colour, brighter as the
-- charge fills over the row's `max` seconds, and flashes white with a ping when full. Your own button ring is
-- drawn by the Hud and the aim by AimPreview. PLACEHOLDER ART: a Highlight until the effects pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local FrameProf = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FrameProf"))

local CombatFx = require(script.Parent.CombatFx)
local Juice = require(script.Parent.Juice)

local ChargeFx = {}

local A = Config.Abilities
local C = Config.Combat.charge
local player = Players.LocalPlayer
local glows: { [Player]: { hl: Highlight, t0: number, num: number, full: boolean } } = {}

local function stop(p: Player)
	local g = glows[p]
	if g then
		g.hl:Destroy()
		glows[p] = nil
	end
end

local function step()
	local now = os.clock()
	for _, p in Players:GetPlayers() do
		local num = p:GetAttribute("Charging")
		local char = p.Character
		local g = glows[p]
		if type(num) ~= "number" or not char then
			if g then
				stop(p)
			end
		else
			local row = A.byNum[num]
			if g and g.num ~= num then
				stop(p)
				g = nil
			end
			if not g and row then
				local hl = Instance.new("Highlight")
				hl.DepthMode = Enum.HighlightDepthMode.Occluded
				hl.FillColor = CombatFx.colorOf(row.set, p.UserId)
				hl.OutlineColor = hl.FillColor
				hl.FillTransparency = 1
				hl.OutlineTransparency = 1
				hl.Adornee = char
				hl.Parent = char
				g = { hl = hl, t0 = now, num = num, full = false }
				glows[p] = g
			end
			if g and row then
				local max = if row.charge then row.charge.max else C.full
				local level = math.clamp((now - g.t0 - C.start) / math.max(0.05, max - C.start), 0, 1)
				g.hl.FillTransparency = 1 - 0.45 * level
				g.hl.OutlineTransparency = 0.6 - 0.5 * level
				if level >= 1 and not g.full then
					g.full = true
					g.hl.FillColor = Color3.new(1, 1, 1)
					TweenService:Create(g.hl, TweenInfo.new(0.3), { FillColor = g.hl.OutlineColor }):Play()
					local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
					if p ~= player and root then
						Juice.fire("chargeFull", root.Position, { mine = false }) -- yours plays in CombatClient
					end
				end
			end
		end
	end
end

function ChargeFx.init()
	Players.PlayerRemoving:Connect(stop)
	RunService.RenderStepped:Connect(FrameProf.wrap("ChargeFx", step))
end

return ChargeFx
