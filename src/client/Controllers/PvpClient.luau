-- PvpClient: the client's view of PvP, death and safety (spec: The PvP flag; Defeat and death; Reports).
-- Nothing here is trusted: the server owns the flag, every hit and every respawn.
-- * flag: the latest FlagState (switch, flagged, Crater warning, seconds until it may turn off, protection)
-- * down: the latest DownState (Downed timer, revive progress, Give Up, the respawn picker's safehouses)
-- * pings: Help, Here and Danger markers from nearby players; results: the PvP win and defeat cards
-- * targets: when you are flagged, the other flagged players your aim can lock (combat id PVP_BASE + slot is
--   the server's; the client sends the player's user id hint only through the aim it already sends)
-- * mutes: quick-mute hides a player's chat on this device (TextChatService), until you leave

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local PvpRules = require(Shared:WaitForChild("PvpRules"))

local State = require(script.Parent.Parent.State)

local PvpClient = {}

local player = Players.LocalPlayer

PvpClient.Changed = Signal.new() -- (what) "flag", "down"
PvpClient.Ping = Signal.new() -- (ping) a marker to draw
PvpClient.Result = Signal.new() -- (result) a PvP win or defeat card
PvpClient.MutesChanged = Signal.new()

PvpClient.flag =
	{ on = false, flagged = false, crater = "out", warnLeft = 0, offIn = 0, protectLeft = 0 } :: {
		[string]: any,
	}
PvpClient.flagAt = 0 -- os.clock() of the last FlagState (timers count down from it)
PvpClient.down = { downed = false } :: { [string]: any }
PvpClient.downAt = 0
PvpClient.muted = {} :: { [number]: boolean }

local lastAsk = -math.huge

function PvpClient.flagged(): boolean
	return PvpClient.flag.flagged == true
end

function PvpClient.downed(): boolean
	return player:GetAttribute("Downed") == true
end

-- The flag button shows from level 10
function PvpClient.canFlag(): boolean
	return (State.hero.level or 1) >= Config.Pvp.minLevel
end

-- Seconds before the button may be pressed again (the server allows one switch every 5 s)
function PvpClient.askIn(): number
	return math.max(0, Config.Pvp.flag.setEvery - (os.clock() - lastAsk))
end

function PvpClient.setFlag(on: boolean)
	if PvpClient.askIn() > 0 then
		return
	end
	lastAsk = os.clock()
	Net.send("FlagSet", if on then 1 else 0)
end

function PvpClient.leaveCrater()
	Net.send("CraterLeave")
end

function PvpClient.revive(userId: number)
	Net.send("ReviveStart", userId)
end

function PvpClient.giveUp()
	Net.send("DownGiveUp")
end

function PvpClient.chooseRespawn(id: number)
	Net.send("RespawnChoose", id)
end

function PvpClient.ping(kind: number, pos: Vector3)
	Net.send("PingPlace", kind, pos)
end

function PvpClient.report(userId: number, reason: number)
	Net.send("ReportPlayer", userId, reason)
end

function PvpClient.mute(userId: number, on: boolean)
	PvpClient.muted[userId] = on or nil
	PvpClient.MutesChanged:Fire()
end

-- Other flagged players a flagged hero can aim at: their combat id (the PvpId attribute) and position
function PvpClient.targets(): { { player: Player, id: number, pos: Vector3 } }
	local out = {}
	if not PvpClient.flagged() then
		return out
	end
	for _, p in Players:GetPlayers() do
		local id = p:GetAttribute("PvpId")
		if p ~= player and id and p:GetAttribute("Pvp") and not p:GetAttribute("Downed") then
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				table.insert(out, { player = p, id = id, pos = root.Position })
			end
		end
	end
	return out
end

-- A flagged player's position by combat id (beams that follow a PvP target)
function PvpClient.position(id: number): Vector3?
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("PvpId") == id then
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			return root and root.Position
		end
	end
	return nil
end

-- The ring colour for a side (blue League, red Syndicate)
function PvpClient.ringColor(side: string?): Color3
	local c = if side == "villain" then Config.Pvp.ring.villain else Config.Pvp.ring.hero
	return Color3.fromRGB(c[1], c[2], c[3])
end

function PvpClient.fameRank(p: Player): number
	return p:GetAttribute("FameRank") or PvpRules.fameRank(Config, p:GetAttribute("Fame") or 0)
end

function PvpClient.init()
	Net.listen("FlagState", function(f)
		PvpClient.flag = f
		PvpClient.flagAt = os.clock()
		if f.reason then
			State.Toast:Fire({ id = "pvpRefused", reason = f.reason, offIn = f.offIn })
		end
		PvpClient.Changed:Fire("flag")
	end)
	Net.listen("DownState", function(d)
		PvpClient.down = d
		PvpClient.downAt = os.clock()
		PvpClient.Changed:Fire("down")
	end)
	Net.listen("PingShow", function(p)
		PvpClient.Ping:Fire(p)
	end)
	Net.listen("PvpResult", function(r)
		PvpClient.Result:Fire(r)
	end)
	-- quick-mute: muted players' chat is not shown on this device
	task.spawn(function()
		local ok, general = pcall(function()
			local channels = TextChatService:WaitForChild("TextChannels", 20)
			return channels and channels:WaitForChild("RBXGeneral", 20)
		end)
		if ok and general and general:IsA("TextChannel") then
			general.ShouldDeliverCallback = function(message: TextChatMessage)
				local src = message.TextSource
				return not (src and PvpClient.muted[src.UserId])
			end
		end
	end)
end

return PvpClient
