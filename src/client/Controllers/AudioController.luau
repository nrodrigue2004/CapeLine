-- AudioController: every sound on this device (spec: Audio, VFX and juice; Music "Three loops: city patrol
-- (day and night versions), boss theme, victory sting. Music ducks 40% for the boss siren and voices").
-- * play(id, at?): a juice action's sound from Config.Audio.sounds, 2D or at a spot in the world (3D, from
--   a pool of 24 so a big fight never piles up sounds). playSpec(row, at?) plays any other row the same way (a
--   path's own sound layer, Config.Audio.paths; the living city, Config.Life.sounds).
-- * The sounds pass (2026-11-19, nate: "need better sounds badly"): a row plays its recorded clip, a region of one
--   of the uploaded atlases (Config.AudioClips via Shared.SoundPick: PlaybackRegion, LoopRegion for loops), a
--   random variant of 2 to 4 with no immediate repeat, its pitch and volume spread a little each play; the built-in
--   `fallback` still plays while an atlas has no id. Rows play in sub-groups of Effects (Combat, World, Ui,
--   Ambience; Voice) under a gentle compressor; big booms duck the city bed and the music for a moment
--   (Config.Audio.mix.duck); the same row starts at most once every mix.gap seconds; big 3D sounds stay at full
--   volume further out (mix.near).
-- * loop(id, on, volume?): held sounds (flight wind, the Super Speed rush, the Downed heartbeat); rows with
--   `speedPitch` rise in pitch with the volume they are given (the speed).
-- * voice(userId, line): a hero's voice pack line (player attribute Voice, ids in Config.Shop.voiceSounds),
--   at most one per hero every 2.5 s; the music ducks under it. Voice group (inside Effects).
-- * Music (Config.Audio.music, our own tracks in the Music atlas): patrol day or night by the world clock, the boss
--   theme near a live boss, the victory sting when one falls; crossfaded over 1.5 s. Music group, its tracks in
--   Music.Score (the duck moves Score, the settings slider moves Music).
-- * The city bed (Config.Life.sounds.bed, Config.Audio.bed): the district's loop where the camera is, the rooftop
--   wind mixed in by height, silent underwater and in the pockets far above the city. Ambience group.
-- * Every Kit button taps (Kit.Clicked).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundPick = require(Shared:WaitForChild("SoundPick"))
local LifePlan = require(Shared:WaitForChild("LifePlan"))
local DeepLayout = require(Shared:WaitForChild("DeepLayout"))
local MusicPlan = require(Shared:WaitForChild("MusicPlan"))

local WorldClient = require(script.Parent.WorldClient)
local Kit = require(script.Parent.Parent.Ui.Kit)

local AudioController = {}

local A = Config.Audio
local MIX = A.mix
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
local victoryUntil = 0
local lastPlay: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastVariant: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
local beds: { [string]: Sound } = {}
local duckSet: { [string]: boolean } = {}
local uiSet: { [string]: boolean } = {}
for _, id in MIX.duck.ids do
	duckSet[id] = true
end
for _, id in MIX.ui do
	uiSet[id] = true
end

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

-- The group a row plays in: Ui rows by id, else by its atlas (Hits -> Combat, World -> World, Ui -> Ui)
local ATLAS_GROUP = { Hits = "Combat", World = "World", Ui = "Ui", Loops = "World", Ambient = "World" }
local function groupFor(_spec: { [string]: any }, id: string?, pick: SoundPick.Pick?): SoundGroup
	local name = if id and uiSet[id] then "Ui" elseif pick then ATLAS_GROUP[pick.atlas] or "World" else nil
	if not name then
		return group("Effects")
	end
	return group(name, group("Effects"))
end

-- The id to play: the recorded clip's atlas, else the licensed asset, else the built-in fallback
function AudioController.idOf(spec: { [string]: any }?): string?
	if not spec then
		return nil
	end
	local pick = SoundPick.resolve(Config, spec)
	if pick then
		return pick.id
	end
	if (spec.asset or 0) > 0 then
		return "rbxassetid://" .. tostring(spec.asset)
	end
	return spec.fallback
end

-- Point a Sound at one clip region (or clear the regions for a whole-file sound). Returns the region's length.
local function aim(snd: Sound, pick: SoundPick.Pick?, spec: { [string]: any }): number
	if not pick then
		snd.PlaybackRegionsEnabled = false
		snd.TimePosition = 0
		return 6
	end
	local idx = SoundPick.choose(#pick.regions, lastVariant[spec], math.random())
	lastVariant[spec] = idx
	local r = pick.regions[idx]
	snd.PlaybackRegionsEnabled = true
	snd.PlaybackRegion = NumberRange.new(r.start, r.start + r.length)
	snd.LoopRegion = NumberRange.new(r.start, r.start + r.length)
	snd.TimePosition = r.start
	return r.length
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
		snd.RollOffMinDistance = MIX.near.default
		snd.Parent = p
		s = { part = p, sound = snd }
		pool[nextSlot] = s
	end
	nextSlot = nextSlot % A.pool + 1
	return s
end

-- Big moments: the city bed and the music dip for a moment under the boom (a side-chain duck)
local fxDuckUntil = 0
local function duckFx()
	local D = MIX.duck
	local now = os.clock()
	local was = now < fxDuckUntil
	fxDuckUntil = now + D.time
	if was then
		return
	end
	for _, name in { "Ambience", "Score" } do
		local g = groups[name]
		if g then
			TweenService:Create(g, TweenInfo.new(0.06), { Volume = D.to }):Play()
		end
	end
	task.delay(D.time, function()
		if os.clock() < fxDuckUntil - 0.01 then
			return -- a later boom holds the duck; its own delay lifts it
		end
		for _, name in { "Ambience", "Score" } do
			local g = groups[name]
			if g then
				TweenService:Create(g, TweenInfo.new(0.6), { Volume = 1 }):Play()
			end
		end
	end)
end

-- Play one juice action's sound. `at` is a world spot (3D) or nil (2D, on you). opts: pitch, volume
-- a scene's own track while it plays (the intro film: Fx.IntroFilm), nil: the world picks
AudioController.musicOverride = nil :: string?
-- (first-30, context music) set at boot (init.client): what is going on now, for Shared.MusicPlan (the menu, the
-- prologue's beat, a cutscene, an HQ, the deep, a mission, the last hit); the boss, the night and the override are
-- filled in here
AudioController.musicContext = nil :: (() -> MusicPlan.Context)?

function AudioController.play(id: string, at: Vector3?, opts: { [string]: any }?)
	AudioController.playSpec(A.sounds[id], at, opts, id)
end

-- Play a sound row that is not a juice action (a path's own layer: Config.Audio.paths; Config.Life.sounds)
function AudioController.playSpec(
	row: { [string]: any }?,
	at: Vector3?,
	opts: { [string]: any }?,
	id: string?
)
	if not row then
		return
	end
	local spec = row :: { [string]: any }
	local sid = AudioController.idOf(spec)
	if not sid then
		return
	end
	local now = os.clock()
	if now - (lastPlay[spec] or -1) < MIX.gap then
		return -- the same row a moment ago: one start is enough
	end
	lastPlay[spec] = now
	local o = opts or {}
	local pick = SoundPick.resolve(Config, spec)
	local u1, u2 = math.random(), math.random()
	local vol = if pick then SoundPick.volume(spec, o.volume, u1) else (o.volume or spec.volume)
	local pitch = if pick
		then SoundPick.pitch(spec, o.pitch, u2)
		else (o.pitch or (spec.pitch or 1) * (1 + (u2 * 2 - 1) * (spec.vary or 0)))
	local g = groupFor(spec, id, pick)
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
		aim(snd, pick, spec)
		snd.Volume = vol
		snd.PlaybackSpeed = pitch
		snd.RollOffMaxDistance = spec.range
		snd.RollOffMinDistance = if spec.range >= MIX.near.bigRange then MIX.near.big else MIX.near.default
		snd.SoundGroup = g
		snd:Play()
	else
		local snd = Instance.new("Sound")
		snd.SoundId = sid
		local length = aim(snd, pick, spec)
		snd.Volume = vol
		snd.PlaybackSpeed = pitch
		snd.SoundGroup = g
		snd.Parent = holder
		snd.Ended:Once(function()
			snd:Destroy()
		end)
		snd:Play()
		task.delay(length / math.max(pitch, 0.3) + 1, function()
			if snd.Parent then
				snd:Destroy()
			end
		end)
	end
	if spec.duck then
		AudioController.duck(4)
	end
	if id and duckSet[id] then
		duckFx()
	end
end

-- A held sound on you (flight wind, the Super Speed rush, the Downed heartbeat); volume can follow speed, and a
-- row with speedPitch rises in pitch with it (volume 0 -> speedPitch[1], loopMax -> speedPitch[2])
function AudioController.loop(id: string, on: boolean, volume: number?)
	local snd = loops[id]
	if not on then
		if snd and snd.IsPlaying then
			snd:Stop()
		end
		return
	end
	local spec = A.sounds[id]
	if not snd then
		local sid = AudioController.idOf(spec)
		if not spec or not sid then
			return
		end
		local pick = SoundPick.resolve(Config, spec)
		local made = Instance.new("Sound")
		made.SoundId = sid
		made.Volume = spec.volume or 0.5
		made.PlaybackSpeed = if pick then spec.clipPitch or 1 else spec.pitch or 1
		made.SoundGroup = groupFor(spec, id, pick)
		made.Looped = true
		aim(made, pick, spec)
		made.Parent = holder
		loops[id] = made
		snd = made
	end
	local s = snd :: Sound
	if volume then
		s.Volume = volume
		local sp = spec and spec.speedPitch
		if sp and SoundPick.resolve(Config, spec) then
			local k = math.clamp(volume / (spec.loopMax or 0.5), 0, 1)
			s.PlaybackSpeed = sp[1] + (sp[2] - sp[1]) * k
		end
	end
	if not s.IsPlaying then
		local pick = SoundPick.resolve(Config, spec)
		if pick then
			s.TimePosition = pick.regions[1].start
		end
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
	local sid = spec and AudioController.idOf(spec)
	if not spec or not sid or sid == spec.fallback then
		return nil -- silent until the Music atlas has an id
	end
	local snd = Instance.new("Sound")
	snd.SoundId = sid
	snd.Looped = not spec.sting
	snd.Volume = 0
	snd.SoundGroup = group("Score", group("Music"))
	snd.Parent = holder
	aim(snd, SoundPick.resolve(Config, spec), spec)
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
		local pick = SoundPick.resolve(Config, A.music[name])
		if pick and (A.music[name].sting or not new.IsPlaying) then
			new.TimePosition = pick.regions[1].start -- a sting from its top every time; a loop where it was
		end
		if not new.IsPlaying then
			new:Play()
		end
		local fadeIn = if A.music[name].sting then 0.05 else A.music.fade
		TweenService:Create(new, TweenInfo.new(fadeIn), { Volume = level(name) }):Play()
		if A.music[name].sting and pick then
			victoryUntil = os.clock() + pick.regions[1].length
		end
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
	local ctx: MusicPlan.Context = if AudioController.musicContext then AudioController.musicContext() else {}
	ctx.override = AudioController.musicOverride
	ctx.boss = nearBoss()
	ctx.night = WorldClient.isNight()
	local want = MusicPlan.pick(Config, ctx)
	if not A.music[want] or (not track(want) and want ~= "patrolDay" and want ~= "patrolNight") then
		-- a loop without its upload yet: the patrol loop keeps playing
		want = if ctx.night then "patrolNight" else "patrolDay"
	end
	local stinging = currentTrack == "victory" and os.clock() < victoryUntil
	if not stinging then
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

-- The victory sting (Config.Audio.music.victory) over the patrol music, as after a boss: a side quest chain's end
-- (while the sting has no id yet the patrol music just keeps playing)
function AudioController.victory()
	if track("victory") then
		currentTrack = "" -- replay it from the top even if it was the last track
		switch("victory")
	end
end

---------------------------------------------------------------------------
-- The city bed
---------------------------------------------------------------------------

local function bed(name: string): Sound?
	local b = beds[name]
	if b then
		return b
	end
	local spec = Config.Life.sounds.bed[name]
	local pick = spec and SoundPick.resolve(Config, spec)
	if not pick then
		return nil -- silent until the Loops atlas has an id
	end
	local snd = Instance.new("Sound")
	snd.Name = "Bed" .. name
	snd.SoundId = pick.id
	snd.Looped = true
	snd.Volume = 0
	snd.SoundGroup = group("Ambience", group("Effects"))
	aim(snd, pick, spec)
	-- start each bed at a different point of its loop, so two districts' copies never line up
	snd.TimePosition = pick.regions[1].start + (#name * 3.7) % pick.regions[1].length
	snd.Parent = holder
	beds[name] = snd
	return snd
end

local BEDS = {
	Downtown = "Downtown",
	Uptown = "Uptown",
	OldTown = "OldTown",
	Docks = "Docks",
	Outskirts = "Outskirts",
}

-- Which bed plays here and how much rooftop wind: (district, rooftop 0..1), or nil underwater and far above the city
function AudioController.bedAt(p: Vector3): (string?, number)
	local Bd = A.bed
	local half = Config.City.mapSize / 2
	if p.Y > Bd.maxY or math.abs(p.X) > half or math.abs(p.Z) > half then
		return nil, 0
	end
	if DeepLayout.underwater(Config, p.X, p.Y, p.Z) then
		return nil, 0
	end
	-- the park is no district (Config.City.districts): its own bed of birdsong (alive-world 2026-11-20)
	local pb = Config.Park and Config.Park.bounds
	local inPark = pb and p.X >= pb.minX and p.X <= pb.maxX and p.Z >= pb.minZ and p.Z <= pb.maxZ
	local d = if inPark then "Park" else BEDS[LifePlan.districtAt(Config, p.X, p.Z)] or "Outskirts"
	local roof = math.clamp((p.Y - Bd.roofLow) / (Bd.roofHigh - Bd.roofLow), 0, 1)
	return d, roof
end

local function bedTick()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local here, roof = AudioController.bedAt(cam.CFrame.Position)
	local L = Config.Life.sounds.bed
	local fade = TweenInfo.new(A.bed.fade)
	for name in L do
		local want = 0
		if here and name == "Rooftop" then
			want = L.Rooftop.volume * roof
		elseif here and name == here then
			want = L[name].volume * (1 - 0.5 * roof)
		end
		local snd = beds[name] or (want > 0 and bed(name)) or nil
		if snd then
			if want > 0 and not snd.IsPlaying then
				if snd.IsPaused then
					snd:Resume()
				else
					snd:Play()
				end
			end
			if math.abs(snd.Volume - want) > 0.005 then
				TweenService:Create(snd, fade, { Volume = want }):Play()
			end
			if want <= 0 and snd.IsPlaying and snd.Volume <= 0.005 then
				snd:Pause() -- silent beds stop costing anything
			end
		end
	end
end

function AudioController.init()
	holder = Instance.new("Folder")
	holder.Name = "Sounds"
	holder.Parent = Workspace
	local fx = group("Effects")
	group("Music")
	group("Score", group("Music"))
	group("Voice", fx)
	for _, name in MIX.groups do
		group(name, fx)
	end
	if not fx:FindFirstChildOfClass("CompressorSoundEffect") then
		local C = MIX.compressor
		local comp = Instance.new("CompressorSoundEffect")
		comp.Threshold = C.threshold
		comp.Ratio = C.ratio
		comp.Attack = C.attack
		comp.Release = C.release
		comp.GainMakeup = C.makeup
		comp.Parent = fx
	end
	-- load the atlases up front, so the first punch is not silent while its file streams in
	task.spawn(function()
		local list = {}
		for atlas, id in Config.AudioClips.atlases do
			if id > 0 then
				local s = Instance.new("Sound")
				s.Name = "Atlas" .. atlas
				s.SoundId = "rbxassetid://" .. string.format("%d", id)
				s.Parent = holder
				table.insert(list, s)
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
	Kit.Clicked:Connect(function()
		AudioController.play("ui")
	end)
	WorldClient.BossResult:Connect(function(r)
		if r.defeated then
			AudioController.victory()
		end
	end)
	local acc, bedAcc = 0, 0
	RunService.Heartbeat:Connect(FrameProf.wrap("AudioController", function(dt)
		acc += dt
		bedAcc += dt
		if acc >= 0.5 then
			acc = 0
			musicTick()
		end
		if bedAcc >= A.bed.every then
			bedAcc = 0
			bedTick()
		end
	end))
end

return AudioController
