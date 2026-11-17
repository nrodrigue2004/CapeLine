-- NewsHud: the in-city news on this device (nate's lore, build plan step 7; Shared.NewsPlan, Config.Cinema.news).
-- * The feed: NewsFact facts from the server (ids only); every line is a fixed template with the hero's name
--   from the safe name system (CreatorRules.heroName of the fact's title and noun ids). No free text.
-- * The big screens (Workspace.NewsScreens, NewsService): each gets one SurfaceGui, built once: the channel
--   band (or BREAKING NEWS), the headline (Crane on TV, the fresh flash, or the latest fact) and a scrolling
--   ticker. Only screens near the camera scroll, a few times a second (phones).
-- * The corner TV on the HUD: a world boss landing or a fake unmasked flashes BREAKING NEWS on every HUD (the
--   boss also as a toast); other news shows on its ticker for a moment; with nothing new, Crane's segment airs
--   now and then. It stays off in the prologue, missions and cutscenes.
-- * Boss entrances (K2): a 3 s name card (CinemaHud) for each hero who arrives at a boss fight, the world
--   bosses and the fakes' battle forms in Live alike.
-- PLACEHOLDER ART: the TV and the screens are plain frames and text until the art pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local NewsPlan = require(Shared:WaitForChild("NewsPlan"))
local CinemaPlan = require(Shared:WaitForChild("CinemaPlan"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))

local Kit = require(script.Parent.Kit)
local Toasts = require(script.Parent.Toasts)
local GuideHud = require(script.Parent.GuideHud)
local CinemaHud = require(script.Parent.CinemaHud)
local WorldClient = require(script.Parent.Parent.Controllers.WorldClient)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)

local NewsHud = {}

local N = Config.Cinema.news
local player = Players.LocalPlayer
local feed = NewsPlan.feed()
NewsHud.feed = feed

local RED = Color3.fromRGB(200, 30, 40)
local NAVY = Color3.fromRGB(16, 22, 44)

type Screen = {
	gui: SurfaceGui,
	band: TextLabel,
	headline: TextLabel,
	ticker: TextLabel,
	part: BasePart,
	offset: number,
}
local screens: { Screen } = {}

local gui: ScreenGui
local tv: Frame
local tvBand: TextLabel
local tvLine: TextLabel
local tvTicker: TextLabel
local tvUntil = 0
local tvMode = "" -- "flash", "fact", "crane"
local tvOffset = 0
local nextCrane = os.clock() + 60
local tickerText = N.channel

local function nameOf(t: number?, n: number?): string?
	if type(t) ~= "number" or type(n) ~= "number" then
		return nil
	end
	return CreatorRules.heroName(Config, t :: number, n :: number)
end

local function line(f: NewsPlan.Fact): string
	return NewsPlan.text(Config, f, nameOf(f.t, f.n)) or N.channel
end

---------------------------------------------------------------------------
-- The corner TV
---------------------------------------------------------------------------

local function buildTv()
	gui = Kit.screen("NewsHud", 5)
	local compact = Kit.compact()
	tv = Kit.frame({
		Name = "CornerTv",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = if compact then UDim2.fromOffset(180, 96) else UDim2.fromOffset(230, 122),
		BackgroundColor3 = NAVY,
		Visible = false,
		ClipsDescendants = true,
		ZIndex = 4,
	})
	Kit.stroke(tv, Kit.color.ink, 3)
	tv.Parent = gui
	tvBand = Kit.label({
		Name = "Band",
		Size = UDim2.new(1, 0, 0.24, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = RED,
		TextColor3 = Kit.color.paper,
		maxText = 18,
		ZIndex = 5,
	})
	tvBand.Parent = tv
	tvLine = Kit.label({
		Name = "Line",
		Position = UDim2.new(0.04, 0, 0.27, 0),
		Size = UDim2.new(0.92, 0, 0.5, 0),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 16,
		ZIndex = 5,
	})
	tvLine.Parent = tv
	tvTicker = Kit.label({
		Name = "Ticker",
		Position = UDim2.new(0, 0, 0.8, 0),
		Size = UDim2.new(3, 0, 0.18, 0),
		BackgroundTransparency = 1,
		TextColor3 = Kit.color.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Kit.bodyFont,
		maxText = 12,
		ZIndex = 5,
	})
	tvTicker.Parent = tv
	GuideHud.keepClear(tv)
end

local function tvShow(mode: string, band: string, text: string, seconds: number)
	tvMode = mode
	tvBand.Text = band
	tvLine.Text = text
	tvBand.BackgroundColor3 = if mode == "flash" then RED else Kit.color.night
	tvTicker.Text = tickerText
	tvOffset = 0
	tvUntil = os.clock() + seconds
	tv.Visible = true
	if mode == "flash" then
		Kit.pulse(tv, 0.06)
	end
end

local function quiet(): boolean
	return not StoryClient.inOpening() and not StoryClient.inMission() and not CinemaClient.playing()
end

---------------------------------------------------------------------------
-- The big screens
---------------------------------------------------------------------------

local function screenLabel(
	parent: Instance,
	name: string,
	y: number,
	h: number,
	props: { [string]: any }
): TextLabel
	props.Name = name
	props.Position = props.Position or UDim2.fromScale(0.03, y)
	props.Size = props.Size or UDim2.fromScale(0.94, h)
	props.ZIndex = 2
	local l = Kit.label(props)
	l.Parent = parent
	return l
end

local function attach(part: BasePart)
	if part:FindFirstChild("News") then
		return
	end
	local sg = Instance.new("SurfaceGui")
	sg.Name = "News"
	sg.Face = Enum.NormalId.Front
	sg.LightInfluence = 0
	sg.Brightness = 1.6
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = if part.Size.X > 50 then 10 else 16
	sg.MaxDistance = 900
	sg.Adornee = part
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = NAVY
	bg.BorderSizePixel = 0
	bg.Parent = sg
	local band = screenLabel(bg, "Band", 0, 0.22, {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 0.22),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.color.night,
		TextColor3 = Kit.color.paper,
		maxText = 120,
	})
	local headline = screenLabel(bg, "Headline", 0.26, 0.5, {
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 90,
	})
	local ticker = screenLabel(bg, "Ticker", 0.8, 0.16, {
		Position = UDim2.fromScale(0, 0.8),
		Size = UDim2.fromScale(4, 0.16),
		TextColor3 = Kit.color.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Kit.bodyFont,
		maxText = 60,
	})
	sg.Parent = player:WaitForChild("PlayerGui")
	table.insert(
		screens,
		{ gui = sg, band = band, headline = headline, ticker = ticker, part = part, offset = 0 }
	)
end

local lastReel = ""
local function refreshScreens(now: number)
	local kind, what = NewsPlan.reel(Config, feed, now)
	local key = kind .. tostring(if type(what) == "table" then what.at else what)
	if key == lastReel then
		return
	end
	lastReel = key
	local band, text
	if kind == "breaking" then
		band, text = "BREAKING NEWS", line(what)
	elseif kind == "crane" then
		band, text = "CRANE INDUSTRIES  /  A MESSAGE FOR BRIGHTHARBOR", N.crane[what]
	else
		band, text = N.channel, if feed[1] then line(feed[1]) else N.channel
	end
	for _, s in screens do
		s.band.Text = band
		s.band.BackgroundColor3 = if kind == "breaking" then RED else Kit.color.night
		s.headline.Text = text
		s.ticker.Text = tickerText
	end
end

local lastScroll = 0
local function scroll(now: number)
	local step = 1 / N.tv.scroll
	if now - lastScroll < step then
		return
	end
	local dt = now - lastScroll
	lastScroll = now
	local cam = Workspace.CurrentCamera
	local eye = cam and cam.CFrame.Position
	for _, s in screens do
		local on = s.part.Parent ~= nil and s.part:GetAttribute("Down") ~= true
		s.gui.Enabled = on
		if on and eye and (s.part.Position - eye).Magnitude < 600 then
			s.offset = (s.offset + dt * N.tickerSpeed) % 1
			s.ticker.Position = UDim2.fromScale(-s.offset * 3, 0.8)
		end
	end
	if tv.Visible then
		tvOffset = (tvOffset + dt * N.tickerSpeed * 1.5) % 1
		tvTicker.Position = UDim2.new(-tvOffset * 2, 0, 0.8, 0)
	end
end

---------------------------------------------------------------------------
-- Facts and the boss's entrance
---------------------------------------------------------------------------

local function onFacts(data: any)
	if type(data) ~= "table" or type(data.list) ~= "table" then
		return
	end
	local now = os.clock()
	for _, f in data.list do
		if type(f) == "table" and type(f.k) == "number" then
			local fact: NewsPlan.Fact = {
				k = f.k,
				t = tonumber(f.t),
				n = tonumber(f.n),
				a = tonumber(f.a),
			}
			if
				NewsPlan.text(Config, fact, "X")
				and NewsPlan.push(Config, feed, fact, now - (tonumber(f.g) or 0))
			then
				if not data.join then
					local text = line(fact)
					if NewsPlan.flash(Config, fact) then
						tvShow("flash", "BREAKING NEWS", text, N.tv.seconds)
						if NewsPlan.KINDS[fact.k] == "boss" then
							Toasts.show({ id = "newsFlash", text = text })
						end
					elseif quiet() then
						tvShow("fact", N.channel, text, N.tv.fact)
					end
				end
			end
		end
	end
	tickerText = NewsPlan.ticker(Config, feed, nameOf)
	lastReel = ""
end

-- The name card for a hero who arrives at a boss fight (once a fight)
local cardFor: string? = nil
local nextCheck = 0
local function bossCheck(now: number)
	if now < nextCheck then
		return
	end
	nextCheck = now + Config.Cinema.nameCard.check
	local b = WorldClient.boss
	local id = b and b.id
	local def = id and Config.Boss.bosses[id]
	if not b or not def or (b.state ~= 2 and b.state ~= 3) then
		cardFor = nil
		return
	end
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not b.x then
		return
	end
	local d = (Vector3.new(b.x, root.Position.Y, b.z) - root.Position).Magnitude
	if CinemaPlan.nameCardDue(Config, b.state, d, def.arenaRadius or 200, cardFor == id) then
		cardFor = id
		CinemaHud.nameCard(id)
	end
end

local function frame()
	local now = os.clock()
	bossCheck(now)
	refreshScreens(now)
	scroll(now)
	if tv.Visible and (now >= tvUntil or (tvMode ~= "flash" and not quiet())) then
		tv.Visible = false
	end
	if not tv.Visible and quiet() and now >= nextCrane then
		nextCrane = now + N.tv.craneEvery
		local _, i = NewsPlan.reel(Config, {}, now)
		tvShow("crane", "SILAS CRANE  /  LIVE", N.crane[i] or N.crane[1], N.tv.crane)
	end
end

-- Dev panel: the corner TV's Crane segment now
function NewsHud.crane()
	local _, i = NewsPlan.reel(Config, {}, os.clock())
	tvShow("crane", "SILAS CRANE  /  LIVE", N.crane[i] or N.crane[1], N.tv.crane)
end

-- Dev panel: the name card for a boss now
function NewsHud.nameCard(bossId: string)
	CinemaHud.nameCard(bossId)
end

function NewsHud.init()
	buildTv()
	Net.listen("NewsFact", onFacts)
	task.spawn(function()
		local folder = Workspace:WaitForChild("NewsScreens", 120)
		if not folder then
			return
		end
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") and p:GetAttribute("Kind") then
				attach(p)
			end
		end
		folder.ChildAdded:Connect(function(p)
			task.wait(0.1)
			if p:IsA("BasePart") and p:GetAttribute("Kind") then
				attach(p)
			end
		end)
		lastReel = ""
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("NewsHud", frame))
end

return NewsHud
