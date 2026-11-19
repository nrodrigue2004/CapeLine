-- BlockClient: hold Block (spec: Hero MMO features > Block, breaker and interrupt; H1). Q on PC (Alt until 2026-11-19), LB on a
-- gamepad, the shield button above FLY on phones (Hud). While held: half speed (MoveController scale), no
-- casting (CombatClient.blocked), and the Guard ring drains. The server owns the bar (GuardState); this
-- keeps a copy for the ring, refilling it between updates the way Shared.GuardMath does.
-- GuardState's `cut` drops an interrupted charge or wind-up (CombatClient.cancelHold).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local InputController = require(script.Parent.InputController)
local MoveController = require(script.Parent.MoveController)
local CombatClient = require(script.Parent.CombatClient)
local State = require(script.Parent.Parent.State)

local BlockClient = {}

local G = Config.Guard
BlockClient.Changed = Signal.new() -- (on) the block started or ended (the server's word)
BlockClient.Cut = Signal.new() -- (num) one of your charges or wind-ups was interrupted

local server = { guard = G.block.guardMax, on = false, at = os.clock(), brokenUntil = 0 }
local wantOn = false
local pressedAt = 0
local REPLY = 0.4 -- a GuardState this long after the press is the server's answer to it

-- The Guard bar now (0 to 1) for the ring round the shield button
function BlockClient.guard(): number
	local g = server.guard
	if not server.on then
		local idle = os.clock() - server.at - G.block.refillDelay
		if idle > 0 then
			g = math.min(G.block.guardMax, g + idle * G.block.refill)
		end
	end
	return g / G.block.guardMax
end

function BlockClient.blocking(): boolean
	return wantOn and server.on
end

function BlockClient.broken(): boolean
	return os.clock() < server.brokenUntil
end

local function setWant(on: boolean)
	if wantOn == on then
		return
	end
	wantOn = on
	if on then
		pressedAt = os.clock()
	end
	-- predict the slow and the cast lock at once; the server's GuardState settles it
	MoveController.setScale("block", if on then G.block.moveMult else nil)
	Net.send("CombatBlock", on)
end

function BlockClient.init()
	CombatClient.blocked = function()
		return wantOn
	end
	InputController.Pressed:Connect(function(action)
		if action == "Block" then
			setWant(true)
		end
	end)
	InputController.Released:Connect(function(action)
		if action == "Block" then
			setWant(false)
		end
	end)
	Net.listen("GuardState", function(data)
		local was = server.on
		server.guard = data.guard or server.guard
		server.on = data.on == true
		server.at = os.clock()
		server.brokenUntil = os.clock() + (data.broken or 0)
		if wantOn and not server.on and (data.reply or data.ended or os.clock() - pressedAt > REPLY) then
			-- refused (low Guard, staggered, a safehouse) or shattered: let go until pressed again
			wantOn = false
			MoveController.setScale("block", nil)
		elseif server.on and not wantOn then
			Net.send("CombatBlock", false) -- let go before the server's answer arrived
		end
		if was ~= server.on then
			BlockClient.Changed:Fire(server.on)
		end
		if data.cut then
			CombatClient.cancelHold(data.cut, data.cd or 0)
			BlockClient.Cut:Fire(data.cut)
		end
	end)
	State.Changed:Connect(function()
		if wantOn and not InputController.isDown("Block") then
			setWant(false)
		end
	end)
end

return BlockClient
