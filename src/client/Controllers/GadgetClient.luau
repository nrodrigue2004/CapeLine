-- GadgetClient: the GADGET button (spec: Tiers, slots: the gadget slot holds one active gadget). Sends the
-- aim; the server checks the cooldown and range and answers. The Grappling Hook then pulls this hero along
-- an arc to the hooked point (the server already allowed the distance). Smoke, the shield drone and the
-- decoy draw their looks for everyone through GadgetFx (gap polish 2026-11-19: a smoke cloud, a shield drone
-- with its bubble, and the decoy as a flickering hologram of the owner's own body).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local InputController = require(script.Parent.InputController)
local MoveController = require(script.Parent.MoveController)
local HeroAnimator = require(script.Parent.HeroAnimator)
local GadgetFx = require(script.Parent.Parent.Fx.GadgetFx)
local State = require(script.Parent.Parent.State)

local GadgetClient = {}

local G = Config.Gear.gadgets
local readyAt = 0
local length = 1

-- 0 when ready, 1 right after use (the HUD sweep)
function GadgetClient.fraction(): number
	return math.clamp((readyAt - os.clock()) / length, 0, 1)
end

local function draw(kind: string, at: Vector3, owner: Player?)
	if kind == "SmokeBomb" then
		GadgetFx.smoke(at)
	elseif kind == "Decoy" then
		if not GadgetFx.decoy(owner, at, G.Decoy.duration) then
			GadgetFx.field(at, G.Decoy.duration, State.hero.fxStyle or "Comic")
		end
	elseif kind == "ShieldDrone" then
		GadgetFx.drone(owner, G.ShieldDrone.duration)
		if owner == Players.LocalPlayer then
			-- your own shield can break early: the drone goes with it
			task.spawn(function()
				task.wait(0.6)
				local t0 = os.clock()
				while os.clock() - t0 < G.ShieldDrone.duration do
					if State.buff("shield") <= 0 then
						GadgetFx.endDrone(owner)
						return
					end
					task.wait(0.25)
				end
			end)
		end
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
			local who = HeroAnimator.byUserId(data.by)
			HeroAnimator.gadget(who, data.kind) -- their throw, toss or hook shot
			if data.target then
				draw(data.kind, data.target, who)
			end
			return
		end
		length = math.max(1, data.cd or 1)
		readyAt = os.clock() + length
		HeroAnimator.gadget(Players.LocalPlayer, data.kind)
		local row = G[data.kind]
		if data.kind == "GrapplingHook" and data.target then
			MoveController.arcTo(data.target, row.time, row.height)
		elseif data.target then
			draw(data.kind, data.target, Players.LocalPlayer)
		end
	end)
end

return GadgetClient
