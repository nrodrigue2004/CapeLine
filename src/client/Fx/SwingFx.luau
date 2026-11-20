-- SwingFx: the Swing's lines on every screen (nate's playtest 2026-11-19: "Swinging should feel like Spider-Man").
-- Your own line runs from your right hand to MoveController.swingPose.anchor and shoots out to it in
-- feel.shoot seconds with a little whip in it; other heroes' lines come from their SwingAt attribute (MoveGuard
-- sets it from MoveLine), the nearest few by quality preset (feel.others) within feel.othersRange. The line is
-- one Beam a hero between two world attachments in Terrain (no parts, nothing to collide). A line with nothing
-- to hang from flicks out along the aim and drops away (the miss cue) with a dull click; a shot thwips; a
-- release whooshes (louder on a sweet one, Config.Move.mobility.swing.release.sweet). The line takes the worn
-- travel style's colour (MoveController.lineColor, TravelStyleFx). Looks only: it never moves anyone.
-- PLACEHOLDER ART: a plain white beam until a web texture is drawn and uploaded; recorded sounds (Config.Audio swingShoot, swingRelease, swingMiss).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local FrameProf = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FrameProf"))

local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)

local SwingFx = {}

local SW = Config.Move.mobility.swing
local FEEL = SW.feel
local me = Players.LocalPlayer
local WHITE = Color3.fromRGB(240, 240, 248)

type Line = {
	beam: Beam,
	a0: Attachment,
	a1: Attachment,
	at: Vector3?, -- where it hangs (nil: hidden)
	shotAt: number,
	color: Color3?,
}
local lines: { [Player]: Line } = {}
local miss: { line: Line, from: Vector3, dir: Vector3, start: number }? = nil
local missLine: Line? = nil -- one, kept

local function newLine(): Line
	local terrain = Workspace.Terrain
	local a0 = Instance.new("Attachment")
	a0.Name = "SwingLine0"
	a0.Parent = terrain
	local a1 = Instance.new("Attachment")
	a1.Name = "SwingLine1"
	a1.Parent = terrain
	local b = Instance.new("Beam")
	b.Name = "SwingLine"
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = FEEL.width
	b.Width1 = FEEL.width * 0.7
	b.FaceCamera = true
	b.LightEmission = 0.25
	b.Segments = 12
	b.Color = ColorSequence.new(WHITE)
	b.Transparency = NumberSequence.new(0.05)
	b.Enabled = false
	b.Parent = terrain
	return { beam = b, a0 = a0, a1 = a1, at = nil, shotAt = 0 }
end

local function lineOf(p: Player): Line
	local l = lines[p]
	if not l then
		l = newLine()
		lines[p] = l
	end
	return l
end

local function free(p: Player)
	local l = lines[p]
	if l then
		l.beam:Destroy()
		l.a0:Destroy()
		l.a1:Destroy()
		lines[p] = nil
	end
end

-- the hand a line leaves from (the R15 right hand, else the arm or the root)
local function handOf(p: Player): Vector3?
	local char = p.Character
	if not char then
		return nil
	end
	local hand = char:FindFirstChild("RightHand")
		or char:FindFirstChild("Right Arm")
		or char:FindFirstChild("HumanoidRootPart")
	return if hand and hand:IsA("BasePart") then hand.Position else nil
end

-- draw a line from `from` toward `to`, `k` (0..1) of the way out, with a whip while it flies
local function draw(l: Line, from: Vector3, to: Vector3, k: number, color: Color3)
	l.a0.WorldPosition = from
	l.a1.WorldPosition = from:Lerp(to, k)
	local whip = (1 - k) * 2.2
	l.beam.CurveSize0 = whip
	l.beam.CurveSize1 = -whip * 0.6
	if l.color ~= color then
		l.color = color
		l.beam.Color = ColorSequence.new(color)
	end
	l.beam.Enabled = true
end

local function step(_dt: number)
	local now = os.clock()
	local shoot = FEEL.shoot
	-- yours
	local pose = MoveController.swingPose
	local mine = pose.anchor
	local hand = handOf(me)
	if mine and hand then
		local l = lineOf(me)
		local k = math.clamp((now - pose.shotAt) / shoot, 0, 1)
		draw(l, hand, mine, k, MoveController.lineColor or WHITE)
	elseif lines[me] then
		lines[me].beam.Enabled = false
	end
	-- the miss cue: out along the aim, then it drops and fades
	local m = miss
	if m then
		local t = now - m.start
		local out, fall = 0.12, 0.3
		if t > out + fall or not hand then
			m.line.beam.Enabled = false
			miss = nil
		else
			local reach = 40 * math.clamp(t / out, 0, 1)
			local tip = m.from + m.dir * reach - Vector3.new(0, math.max(0, t - out) * 60, 0)
			draw(m.line, hand, tip, 1, MoveController.lineColor or WHITE)
			m.line.beam.Transparency = NumberSequence.new(math.clamp((t - out) / fall, 0, 1) * 0.9 + 0.05)
		end
	end
	-- the others: the nearest few with a line out
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local most = FEEL.others[QualityController.name] or FEEL.others.medium
	local shown = 0
	for _, p in Players:GetPlayers() do
		if p ~= me then
			local at = p:GetAttribute("SwingAt")
			local from = if typeof(at) == "Vector3" then handOf(p) else nil
			if
				from
				and typeof(at) == "Vector3"
				and shown < most
				and (from - camPos).Magnitude <= FEEL.othersRange
			then
				shown += 1
				local l = lineOf(p)
				if l.at ~= at then
					l.at = at
					l.shotAt = now
				end
				draw(l, from, at, math.clamp((now - l.shotAt) / shoot, 0, 1), WHITE)
			elseif lines[p] then
				lines[p].beam.Enabled = false
				lines[p].at = nil
			end
		end
	end
end

function SwingFx.init()
	MoveController.SwingShot:Connect(function(anchor: Vector3)
		AudioController.play("swingShoot", anchor)
		if miss then
			miss.line.beam.Enabled = false
			miss = nil
		end
	end)
	MoveController.SwingReleased:Connect(function(v: Vector3, sweet: boolean)
		if v.Magnitude >= FEEL.whoosh then
			local row = Config.Audio.sounds.swingRelease
			AudioController.play("swingRelease", nil, {
				volume = row.volume * (if sweet then 1.2 else 0.7),
				pitch = row.pitch * (0.85 + 0.3 * math.clamp(v.Magnitude / SW.release.cap, 0, 1)),
			})
		end
	end)
	MoveController.SwingMissed:Connect(function(from: Vector3, look: Vector3)
		AudioController.play("swingMiss")
		local l = missLine or newLine()
		missLine = l
		l.beam.Transparency = NumberSequence.new(0.05)
		local dir = (look + Vector3.new(0, SW.lifts[1], 0)).Unit
		miss = { line = l, from = from, dir = dir, start = os.clock() }
	end)
	Players.PlayerRemoving:Connect(free)
	RunService.RenderStepped:Connect(FrameProf.wrap("SwingFx", step))
end

return SwingFx
