-- AudioController: every sound on this device (spec: Audio, VFX and juice; Music "Three loops: city patrol
-- (day and night versions), boss theme, victory sting. Music ducks 40% for the boss siren and voices").
-- * play(id, at?): a juice action's sound from Config.Audio.sounds, 2D or at a spot in the world (3D, from
--   a pool of 24 so a big fight never piles up sounds). Effects group. playSpec(row, at?) plays any other row
--   the same way (a path's own sound layer, Config.Audio.paths).
-- * loop(id, on, volume?): held sounds (flight wind, the Downed heartbeat).
-- * voice(userId, line): a hero's voice pack line (player attribute Voice, ids in Config.Shop.voiceSounds),
--   at most one per hero every 2.5 s; the music ducks under it. Voice group (inside Effects).
-- * Music: patrol day or night by the world clock, the boss theme near a live boss, the victory sting when
--   one falls; crossfaded over 1.5 s. Music group.
-- * Every Kit button taps (Kit.Clicked).
-- Ids are 0 until nate picks licence-checked sounds; the fallbacks are Roblox's built-in client sounds.
-- PLACEHOLDER SOUND until then.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local WorldClient = require(script.Parent.WorldClient)
local Kit = require(script.Parent.Parent.Ui.Kit)

local AudioController = {}

local A = Config.Audio
local player = Players.LocalPlayer

local groups: { [string]: SoundGroup } = {}
local holder: Folder
local pool: { { part: Part, sound: Sound } } = {}
local nextSlot = 1
local loops: { [string]: Sound } = {}
local lastVoice: { [number]: number } = {}
local tracks: { [string]: Sound } = {}
local currentTrack = ""
local duckUntil = 0
local ducked = false

local function group(name: string, parent: Instance?): SoundGroup
	local g = groups[name]
	if g then
		return g
	end
	local found = SoundService:FindFirstChild(name, true)
	if found and found:IsA("SoundGroup") then
		g = found
	else
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = parent or SoundService
	end
	groups[name] = g :: SoundGroup
	return g :: SoundGroup
end

-- The id to play: the licensed asset when set, else the built-in fallback
function AudioController.idOf(spec: { [string]: any }?): string?
	if not spec then
		return nil
	end
	if (spec.asset or 0) > 0 then
		return "rbxassetid://" .. tostring(spec.asset)
	end
	return spec.fallback
end

local function newSound(spec: { [string]: any }, g: SoundGroup): Sound?
	local id = AudioController.idOf(spec)
	if not id then
		return nil
	end
	local snd = Instance.new("Sound")
	snd.SoundId = id
	snd.Volume = spec.volume or 0.5
	snd.PlaybackSpeed = spec.pitch or 1
	snd.SoundGroup = g
	return snd
end

local function slot(): { part: Part, sound: Sound }
	local s = pool[nextSlot]
	if not s then
		local p = Instance.new("Part")
		p.Name = "Sound"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.one
		p.Parent = holder
		local snd = Instance.new("Sound")
		snd.RollOffMode = Enum.RollOffMode.InverseTapered
		snd.RollOffMinDistance = 12
		snd.Parent = p
		s = { part = p, sound = snd }
		pool[nextSlot] = s
	end
	nextSlot = nextSlot % A.pool + 1
	return s
end

local function vary(spec: { [string]: any }): number
	local v = spec.vary or 0
	return (spec.pitch or 1) * (1 + (math.random() * 2 - 1) * v)
end

-- Play one juice action's sound. `at` is a world spot (3D) or nil (2D, on you). opts: pitch, volume
function AudioController.play(id: string, at: Vector3?, opts: { [string]: any }?)
	AudioController.playSpec(A.sounds[id], at, opts)
end

-- Play a sound row that is not a juice action (a path's own layer: Config.Audio.paths)
function AudioController.playSpec(row: { [string]: any }?, at: Vector3?, opts: { [string]: any }?)
	if not row then
		return
	end
	local spec = row :: { [string]: any }
	local sid = AudioController.idOf(spec)
	if not sid then
		return
	end
	local o = opts or {}
	if at and spec.range then
		local cam = Workspace.CurrentCamera
		if cam and (cam.CFrame.Position - at).Magnitude > spec.range * 1.2 then
			return -- too far to hear
		end
		local s = slot()
		s.part.Position = at
		local snd = s.sound
		snd:Stop()
		snd.SoundId = sid
		snd.Volume = o.volume or spec.volume
		snd.PlaybackSpeed = o.pitch or vary(spec)
		snd.RollOffMaxDistance = spec.range
		snd.SoundGroup = group("Effects")
		snd:Play()
	else
		local snd = newSound(spec, group("Effects"))
		if not snd then
			return
		end
		snd.Volume = o.volume or spec.volume
		snd.PlaybackSpeed = o.pitch or vary(spec)
		snd.Parent = holder
		snd.Ended:Once(function()
			snd:Destroy()
		end)
		snd:Play()
		task.delay(6, function()
			if snd.Parent then
				snd:Destroy()
			end
		end)
	end
	if spec.duck then
		AudioController.duck(4)
	end
end

-- A held sound on you (flight wind, the Downed heartbeat); volume can follow speed
function AudioController.loop(id: string, on: boolean, volume: number?)
	local snd = loops[id]
	if not on then
		if snd and snd.IsPlaying then
			snd:Stop()
		end
		return
	end
	if not snd then
		local spec = A.sounds[id]
		local made = spec and newSound(spec, group("Effects"))
		if not made then
			return
		end
		made.Looped = true
		made.Parent = holder
		loops[id] = made
		snd = made
	end
	local s = snd :: Sound
	if volume then
		s.Volume = volume
	end
	if not s.IsPlaying then
		s:Play()
	end
end

-- Duck the music for a few seconds (the boss siren, voice lines)
function AudioController.duck(seconds: number)
	duckUntil = math.max(duckUntil, os.clock() + seconds)
end

-- A hero's voice line (line = "super", "rescue", ...). Other heroes' lines are heard close by only.
function AudioController.voice(userId: number?, line: string)
	local p = if userId then Players:GetPlayerByUserId(userId) else player
	if not p then
		return
	end
	local now = os.clock()
	if now - (lastVoice[p.UserId] or -99) < A.voice.gap then
		return
	end
	local idx = table.find(A.voice.lines, line)
	local pack = p:GetAttribute("Voice")
	local ids = typeof(pack) == "string" and Config.Shop.voiceSounds[pack]
	local asset = idx and ids and ids[idx] or 0
	if asset <= 0 then
		return -- PLACEHOLDER: no voice clips until nate picks licensed ones
	end
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if p ~= player then
		local cam = Workspace.CurrentCamera
		if not root or not cam or (cam.CFrame.Position - root.Position).Magnitude > A.voice.range then
			return
		end
	end
	lastVoice[p.UserId] = now
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://" .. tostring(asset)
	snd.Volume = 0.8
	snd.SoundGroup = group("Voice", group("Effects"))
	snd.RollOffMaxDistance = A.voice.range
	snd.Parent = if p ~= player and root then root else holder
	snd.Ended:Once(function()
		snd:Destroy()
	end)
	snd:Play()
	AudioController.duck(2)
end

---------------------------------------------------------------------------
-- Music
---------------------------------------------------------------------------

local function track(name: string): Sound?
	local t = tracks[name]
	if t then
		return t
	end
	local spec = A.music[name]
	if not spec or (spec.asset or 0) <= 0 then
		return nil -- PLACEHOLDER: silent until licensed tracks are picked
	end
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://" .. tostring(spec.asset)
	snd.Looped = not spec.sting
	snd.Volume = 0
	snd.SoundGroup = group("Music")
	snd.Parent = holder
	tracks[name] = snd
	return snd
end

local function level(name: string): number
	local spec = A.music[name]
	return (spec and spec.volume or 0.4) * (if ducked then A.music.duck else 1)
end

local function switch(name: string)
	if name == currentTrack then
		return
	end
	local old = tracks[currentTrack]
	if old then
		TweenService:Create(old, TweenInfo.new(A.music.fade), { Volume = 0 }):Play()
		task.delay(A.music.fade, function()
			if currentTrack ~= old.Name then
				old:Stop()
			end
		end)
	end
	currentTrack = name
	local new = track(name)
	if new then
		new.Name = name
		new.Volume = 0
		new:Play()
		TweenService:Create(new, TweenInfo.new(A.music.fade), { Volume = level(name) }):Play()
	end
end

local function nearBoss(): boolean
	local b = WorldClient.boss
	if not (b.state == 2 or b.state == 3) or not b.x then
		return false
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return false
	end
	local p = cam.CFrame.Position
	return (Vector3.new(b.x, p.Y, b.z) - p).Magnitude <= A.music.bossRange
end

local function musicTick()
	local want = if nearBoss() then "boss" elseif WorldClient.isNight() then "patrolNight" else "patrolDay"
	if currentTrack ~= "victory" or not (tracks.victory and tracks.victory.IsPlaying) then
		switch(want)
	end
	local d = os.clock() < duckUntil
	if d ~= ducked then
		ducked = d
		local t = tracks[currentTrack]
		if t then
			TweenService:Create(t, TweenInfo.new(0.3), { Volume = level(currentTrack) }):Play()
		end
	end
end

function AudioController.init()
	holder = Instance.new("Folder")
	holder.Name = "Sounds"
	holder.Parent = Workspace
	group("Music")
	group("Effects")
	group("Voice", group("Effects"))
	Kit.Clicked:Connect(function()
		AudioController.play("ui")
	end)
	WorldClient.BossResult:Connect(function(r)
		if r.defeated then
			switch("victory")
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("AudioController", function(dt)
		acc += dt
		if acc >= 0.5 then
			acc = 0
			musicTick()
		end
	end))
end

return AudioController
