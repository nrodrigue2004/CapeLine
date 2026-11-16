-- GadgetClient: the GADGET button (spec: Tiers, slots: the gadget slot holds one active gadget). Sends the
-- aim; the server checks the cooldown and range and answers. The Grappling Hook then pulls this hero along
-- an arc to the hooked point (the server already allowed the distance). Smoke, the shield drone and the
-- decoy draw a placeholder effect for everyone (PLACEHOLDER ART until M11).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local InputController = require(script.Parent.InputController)
local MoveController = require(script.Parent.MoveController)
local CombatFx = require(script.Parent.Parent.Fx.CombatFx)
local State = require(script.Parent.Parent.State)

local GadgetClient = {}

local G = Config.Gear.gadgets
local readyAt = 0
local length = 1

-- 0 when ready, 1 right after use (the HUD sweep)
function GadgetClient.fraction(): number
	return math.clamp((readyAt - os.clock()) / length, 0, 1)
end

local function draw(kind: string, at: Vector3)
	local style = State.hero.fxStyle or "Comic"
	if kind == "SmokeBomb" then
		CombatFx.field(at, G.SmokeBomb.radius, G.SmokeBomb.blind, style, Color3.fromRGB(150, 150, 160), false)
	elseif kind == "Decoy" then
		CombatFx.field(at, 4, G.Decoy.duration, style, Color3.fromRGB(170, 200, 255), false)
	elseif kind == "ShieldDrone" then
		CombatFx.buffPop(at, style, Color3.fromRGB(170, 225, 255))
	end
end

function GadgetClient.init()
	InputController.Pressed:Connect(function(action)
		if action ~= "Gadget" or not State.hero.gadget or os.clock() < readyAt then
			return
		end
		Net.send("GadgetUse", Workspace.CurrentCamera.CFrame.LookVector)
	end)
	Net.listen("GadgetResult", function(data)
		if not data.ok then
			return
		end
		if data.by then
			if data.target then
				draw(data.kind, data.target)
			end
			return
		end
		length = math.max(1, data.cd or 1)
		readyAt = os.clock() + length
		local row = G[data.kind]
		if data.kind == "GrapplingHook" and data.target then
			MoveController.arcTo(data.target, row.time, row.height)
		elseif data.target then
			draw(data.kind, data.target)
		end
	end)
end

return GadgetClient
