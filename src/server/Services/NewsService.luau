-- NewsService: the in-city news (nate's lore, build plan step 7; Shared.NewsPlan, Config.Cinema.news). Turns
-- what players on this server did into facts and sends them to every device (NewsFact), where the big screens
-- and the HUD's corner TV show them: a world boss landing (a flash on every HUD), a boss brought down or
-- escaping, a famous fake's face cracked (a flash), incident streaks, robot heists and Act 1 missions
-- finished. A fact carries only ids: the kind, the hero's CreatorRules title and noun ids (the safe name
-- system; a blocked or missing name reads "A HERO") and one number. No free text ever goes out.
-- * The big screens hang where NewsPlan.screens says (Downtown towers by the plaza, the plaza's frame, the
--   Crane billboard on Uptown's landmark); a screen on a building that collapses goes dark until repaired.
--   Each screen's frame (and the plaza's legs) wears its Blender look from ReplicatedStorage.Art.News once all its
--   meshes are imported (gap-news, Shared.NewsArtKit: bezel, header or marquee, lamps, pillars or catwalk); the
--   plain frame and legs are then hidden, the screen part stays as it is, and nothing collides, as before.
--   Nothing imported: the plain dark panels and frame show (PLACEHOLDER ART fallback).
-- * A joining device gets the feed so far.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local NewsPlan = require(Shared:WaitForChild("NewsPlan"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local BuildingState = require(Shared:WaitForChild("BuildingState"))
local NewsArtKit = require(Shared:WaitForChild("NewsArtKit"))

local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local BuildingService = require(script.Parent.BuildingService)
local IncidentService = require(script.Parent.IncidentService)
local BossService = require(script.Parent.BossService)
local MissionService = require(script.Parent.MissionService)

local NewsService = {}

local CODE = NewsPlan.CODE
local feed = NewsPlan.feed()
local streaks: { [number]: any } = {}
local screens: { { part: BasePart, building: number?, dressed: { BasePart }, plan: any, behind: { number }? } } =
	{}

-- The hero's safe name ids (title, noun), or nil for a bot or a name that is not allowed
local function nameIds(player: Player?): (number?, number?)
	local profile = player and DataService.get(player)
	if not profile then
		return nil, nil
	end
	local c = ProfileSchema.active(profile)
	local t, n = c and c.titleId, c and c.nounId
	if type(t) ~= "number" or type(n) ~= "number" or not CreatorRules.nameOk(Config, t, n) then
		return nil, nil
	end
	return t, n
end

local function wire(f: NewsPlan.Fact, now: number): { [string]: any }
	return { k = f.k, t = f.t, n = f.n, a = f.a, g = math.max(0, now - (f.at or now)) }
end

-- Add a fact and send it to everyone (a repeat is dropped)
function NewsService.post(kind: string, player: Player?, a: number?)
	local code = CODE[kind]
	if not code then
		return
	end
	local t, n = nameIds(player)
	local fact: NewsPlan.Fact = { k = code, t = t, n = n, a = a }
	if NewsPlan.text(Config, fact, "X") == nil then
		return -- a bad number: no template fits
	end
	local now = os.clock()
	if NewsPlan.push(Config, feed, fact, now) then
		Net.fireAll("NewsFact", { list = { wire(fact, now) } })
	end
end

local function heroPlayer(heroId: number?): Player?
	local h = heroId and HeroService.byId(heroId)
	return h and h.player
end

-- Dev panel: post a sample of each kind as you
function NewsService.dev(player: Player, what: number)
	local kinds = { "boss", "bossDown", "unmask", "streak", "heist", "act1" }
	local kind = kinds[what] or "boss"
	local args = {
		boss = Config.Boss.bosses[Config.Boss.order[1]].num,
		bossDown = Config.Boss.bosses[Config.Boss.order[1]].num,
		unmask = Config.Enemies.Bulwark.typeId,
		streak = 3,
		heist = 0,
		act1 = 2,
	}
	-- a dev post skips the repeat rule (each tap shows)
	for i = #feed, 1, -1 do
		if feed[i].k == CODE[kind] then
			table.remove(feed, i)
		end
	end
	NewsService.post(kind, player, args[kind])
end

---------------------------------------------------------------------------
-- The big screens (dark panels on a frame; dressed in Art.News's looks once imported)
---------------------------------------------------------------------------

-- The source MeshPart named `name` in Art.News, or nil
local function source(name: string): MeshPart?
	local art = ReplicatedStorage:FindFirstChild("Art")
	local set = art and art:FindFirstChild("News")
	local src = set and set:FindFirstChild(name, true)
	return if src and src:IsA("MeshPart") then src else nil
end

-- One look's meshes round the screen at cf (its centre, front at -z); empty when the look is not all imported
local function dress(parent: Instance, look: string, cf: CFrame, name: string): { BasePart }
	local out = {}
	if not NewsArtKit.ready(Config, look, function(n: string): boolean
		return source(n) ~= nil
	end) then
		return out
	end
	for _, m in NewsArtKit.meshes(Config, look) do
		local src = source(m.name) :: MeshPart
		local p = src:Clone()
		-- a textured mesh keeps its SurfaceAppearance (the baked maps; opaque, so the part colour never shows)
		for _, c in p:GetChildren() do
			if m.maps and c:IsA("SurfaceAppearance") then
				c.AlphaMode = Enum.AlphaMode.Overlay
			else
				c:Destroy()
			end
		end
		p.Name = name .. m.name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = Vector3.new(m.size[1], m.size[2], m.size[3])
		p.CFrame = cf * CFrame.new(m.offset[1], m.offset[2], m.offset[3])
		p.Color = Color3.fromRGB(m.color[1], m.color[2], m.color[3])
		local ok, mat = pcall(function()
			return (Enum.Material :: any)[m.mat]
		end)
		p.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
		p.Transparency = m.alpha
		p.CastShadow = m.mat ~= "Neon" and m.alpha == 0
		p:SetAttribute("Alpha", m.alpha)
		p.Parent = parent
		table.insert(out, p)
	end
	return out
end

local function panel(parent: Instance, size: Vector3, cf: CFrame, color: Color3, name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

local function buildScreens()
	local world = CityBuilder.world
	if not world then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "NewsScreens"
	folder.Parent = Workspace
	for i, s in NewsPlan.screens(Config, world) do
		local pos = Vector3.new(s.x, s.y, s.z)
		local cf = CFrame.lookAt(pos, pos + Vector3.new(s.nx, 0, s.nz))
		local screen =
			panel(folder, Vector3.new(s.w, s.h, 0.6), cf, Color3.fromRGB(16, 18, 28), "Screen" .. i)
		screen:SetAttribute("Kind", s.kind)
		-- the frame round it
		local plain = {}
		plain[1] = panel(
			folder,
			Vector3.new(s.w + 2, s.h + 2, 0.4),
			cf * CFrame.new(0, 0, 0.5),
			Color3.fromRGB(40, 42, 54),
			"Frame" .. i
		)
		if s.kind == "plaza" then
			local gy = Config.City.ground.y
			local legH = s.y - s.h / 2 - gy
			for _, side in { -1, 1 } do
				local leg = cf * CFrame.new(side * (s.w / 2 - 1.5), -s.h / 2 - legH / 2, 0.8)
				table.insert(
					plain,
					panel(folder, Vector3.new(1.4, legH, 1.4), leg, Color3.fromRGB(40, 42, 54), "Leg" .. i)
				)
			end
		end
		-- its Blender look (the frame and legs it stands for hide; they never collided, nor do the meshes)
		local look = NewsArtKit.lookFor(s.kind)
		local dressed = if look then dress(folder, look, cf, "Look" .. i) else {}
		if #dressed > 0 then
			for _, p in plain do
				p.Transparency = 1
				p.CastShadow = false
			end
		end
		table.insert(
			screens,
			{ part = screen, building = s.building, dressed = dressed, plan = s, behind = nil }
		)
	end
end

-- A screen on a collapsed building goes dark (and its SurfaceGui with it, on the device), and since fix-destroy
-- (2026-11-19) so does one whose wall behind it took a hole: it falls with the panel (NewsHud drops a copy)
local function watchScreens()
	local book = BuildingService.book
	for _, s in screens do
		if s.building and not s.behind and book then
			local grid = BuildingState.grid(Config.Destruction, book, s.building)
			s.behind = if grid then NewsPlan.behind(grid, s.plan) else {}
		end
		if s.building then
			local down = NewsPlan.screenDown(
				BuildingService.state(s.building),
				s.behind or {},
				book and book.gone[s.building] or nil
			)
			if (s.part:GetAttribute("Down") == true) ~= down then
				s.part:SetAttribute("Down", down)
				s.part.Transparency = if down then 1 else 0
				for _, p in s.dressed do
					p.Transparency = if down then 1 else (p:GetAttribute("Alpha") :: number? or 0)
				end
			end
		end
	end
end

function NewsService.init()
	BossService.Arrived:Connect(function(bossId: string)
		local b = Config.Boss.bosses[bossId]
		if b then
			NewsService.post("boss", nil, b.num)
		end
	end)
	BossService.Ended:Connect(function(bossId: string, defeated: boolean, top: number?)
		local b = Config.Boss.bosses[bossId]
		if b then
			NewsService.post(
				if defeated then "bossDown" else "bossAway",
				if defeated then heroPlayer(top) else nil,
				b.num
			)
		end
	end)
	EnemyService.Unmasked:Connect(function(kind: string, heroId: number?)
		local e = Config.Enemies[kind]
		local p = heroPlayer(heroId)
		if e and p then
			NewsService.post("unmask", p, e.typeId)
		end
	end)
	-- WP5: a Suspicious Hero's mask cracked (the hero who cracked it, else the incident's own hero)
	IncidentService.FakeUnmasked:Connect(function(inc: any, heroId: number?)
		local p = heroPlayer(heroId) or heroPlayer(inc.owner)
		if p then
			NewsService.post(if inc.side == "villain" then "fakeSyndicate" else "fakeVigil", p, 0)
		end
	end)
	IncidentService.Cleared:Connect(function(inc: any)
		local p = heroPlayer(inc.owner)
		if not p then
			return
		end
		if inc.plan and inc.plan.tid == "RobotHeist" then
			NewsService.post(if inc.side == "villain" then "heistVillain" else "heist", p, 0)
		end
		local n = NewsPlan.streak(Config, streaks, inc.owner, os.clock())
		if n then
			NewsService.post("streak", p, n)
		end
	end)
	MissionService.Cleared:Connect(function(player: Player, num: number, info: any)
		local m = Config.Story.missions[num]
		if m and not m.opening and not (info and info.taskForce) then
			NewsService.post("act1", player, num)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			if player.Parent and #feed > 0 then
				local now = os.clock()
				local list = {}
				for i = #feed, 1, -1 do
					table.insert(list, wire(feed[i], now))
				end
				Net.fire("NewsFact", player, { list = list, join = true })
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		streaks[player.UserId] = nil
	end)
	task.spawn(function()
		while not CityBuilder.world do
			task.wait(1)
		end
		buildScreens()
		while true do
			task.wait(1)
			watchScreens()
		end
	end)
end

return NewsService
