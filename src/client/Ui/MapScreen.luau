-- MapScreen: the city map and fast travel (spec: Screens and UI > Map "Hub and outskirts, beacons,
-- safehouses, incidents, boss, the Crater, party; tap a marker to auto-fly; fast travel to beacons").
-- M4 shows the zones, districts, landmarks, the HQs (the Safehouse to the Vigil only), the 16 safehouses (bright once visited), the 12
-- beacons (gold once discovered, a tap flies there) and you. M6 adds the incidents near you (blue Vigil,
-- red Syndicate), running events (gold) and the world boss (big red). M10: your squad (squares in their
-- slot colours), colorblind-safe shapes (circle incident, star event, diamond boss), and a tap on an
-- incident, event or the boss auto-flies you there (Settings: tap to fly; needs flight). Lore step 10: side quest
-- givers with a chain for you ("!", gold when one is in progress) and the tracked step. Opens with M, the
-- MAP button or a tap on the radar.
-- The map pass (2026-11-19): a readable comic city map. Static layers are built once, the first time the map
-- opens (Shared.MapPlan): the land, this week's outskirts zones merged into a few dozen rectangles, each tiled
-- with its zone's pattern (suburb houses, fields, the coast, landmark rock), the coast's sand, the outskirts
-- roads and highways, the fixed city as two pictures drawn from the game's own layout (the hub with its
-- districts, and Uptown; art/map/draw.py, Config.MapArt), the landmarks, district and ring names, the HQs, then
-- the safehouses, beacons and world markers on top, and your arrow pointing where you face. Drag to pan, pinch,
-- the wheel or + and - to zoom, the dot button to centre on you; a drag never fast-travels by accident.
-- Until a picture's id is uploaded that layer is today's flat look (PLACEHOLDER ART for that layer only).

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Travel = require(Shared:WaitForChild("Travel"))
local SideQuestPlan = require(Shared:WaitForChild("SideQuestPlan"))
local MapPlan = require(Shared:WaitForChild("MapPlan"))
local WorldGen = require(Shared:WaitForChild("WorldGen"))
local UserInputService = game:GetService("UserInputService")

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local WorldClient = require(script.Parent.Parent.Controllers.WorldClient)
local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local SquadClient = require(script.Parent.Parent.Controllers.SquadClient)
local SettingsClient = require(script.Parent.Parent.Controllers.SettingsClient)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)

local MapScreen = {}

local C = Config.City
local W = Config.World
local ART = Config.MapArt
local MARGIN = ART.margin
local gui: ScreenGui
local panel: Frame
local map: Frame
local canvas: Frame -- the whole map, scaled by the zoom and moved by the pan inside `map` (which clips it)
local layers: { [string]: Frame } = {} -- ground, roads, city, names, icons, marks, you: drawn in that order
local you: Frame
local view: { zoom: number, u: number, v: number, pinch: number? } = { zoom = 1, u = 0.5, v = 0.5 }
local dragMoved = 0 -- pixels the current press has dragged (a drag is not a tap on a beacon)
local status: TextLabel
local markers: { [string]: GuiObject } = {}
local hqDots: { [string]: GuiObject } = {}
local info: any = nil

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- world x/z to a 0..1 map position (the whole map and its strip of sea, MapPlan.project)
local function toMap(x: number, z: number): (number, number)
	return MapPlan.project(C, MARGIN, x, z)
end

-- The zoom and pan (MapPlan.view keeps the map filling its frame)
-- the small names (beacons, HQs, landmarks, the rings): shown once the map is big enough to hold them
local tags: { GuiObject } = {}
local beaconTags: { GuiObject } = {}
local lastView: MapPlan.View? = nil
local iconScale = 1
local function applyView()
	local size = map.AbsoluteSize
	local vw = MapPlan.view(view.zoom, view.u, view.v, ART.maxZoom, size.X, size.Y)
	view.zoom, view.u, view.v = vw.zoom, vw.u, vw.v
	canvas.Size = UDim2.fromScale(vw.sx, vw.sy)
	canvas.Position = UDim2.fromScale(vw.x, vw.y)
	lastView = vw
	local roomy = vw.side >= ART.namesFrom
	-- icons shrink on a small map (a phone at zoom 1) so the city under them still shows
	local k = math.clamp(vw.side / ART.iconsFull, ART.iconsMin, 1)
	if math.abs(k - iconScale) > 0.02 then
		iconScale = k
		for _, name in { "icons", "marks" } do
			for _, c in layers[name]:GetChildren() do
				local base = c:GetAttribute("Base")
				if type(base) == "number" and c:IsA("GuiObject") then
					c.Size = UDim2.fromOffset(base * k, base * k)
				end
			end
		end
		for _, c in layers.names:GetChildren() do
			local bw, bh = c:GetAttribute("BaseW"), c:GetAttribute("BaseH")
			if type(bw) == "number" and type(bh) == "number" and c:IsA("GuiObject") then
				c.Size = UDim2.fromOffset(bw * k, bh * k)
			end
		end
	end
	for _, list in { tags, beaconTags } do
		for _, t in list do
			t.Visible = roomy
		end
	end
end

-- A plain square-cornered frame over a world rectangle on a layer (static map shapes: no ink, no halftone)
local function plain(layer: string, r: MapPlan.Rect, color: Color3, name: string?): Frame
	local u, v, du, dv = MapPlan.rectUV(C, MARGIN, r)
	local f = Instance.new("Frame")
	f.Name = name or "Shape"
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromScale(u, v)
	f.Size = UDim2.fromScale(du, dv)
	f.Parent = layers[layer]
	return f
end

-- A picture over a world rectangle (a city picture, or a zone tiled with its pattern, one tile a repeat)
local function picture(layer: string, r: MapPlan.Rect, id: number, tile: number?): ImageLabel
	local u, v, du, dv = MapPlan.rectUV(C, MARGIN, r)
	local img = Instance.new("ImageLabel")
	img.Name = "Picture"
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Image = "rbxassetid://" .. id
	img.Position = UDim2.fromScale(u, v)
	img.Size = UDim2.fromScale(du, dv)
	if tile then
		img.ScaleType = Enum.ScaleType.Tile
		img.TileSize = UDim2.fromScale(tile / (r.x1 - r.x0), tile / (r.z1 - r.z0))
	end
	img.Parent = layers[layer]
	return img
end

local function rect(
	name: string,
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number,
	color: Color3,
	label: string?
)
	local u0, v0 = toMap(minX, minZ)
	local u1, v1 = toMap(maxX, maxZ)
	local f = Kit.frame({
		Name = name,
		Position = UDim2.fromScale(u0, v0),
		Size = UDim2.fromScale(u1 - u0, v1 - v0),
		BackgroundColor3 = color,
		round = false,
		ink = false,
	})
	if label then
		local l = Kit.label({
			Text = label,
			Size = UDim2.fromScale(1, 0.3),
			Position = UDim2.fromScale(0, 0.35),
			TextColor3 = Kit.color.paper,
			TextStrokeTransparency = 0.3,
			maxText = 14,
		})
		l.Parent = f
	end
	f.Parent = layers.city
	return f
end

local function dot(
	name: string,
	x: number,
	z: number,
	size: number,
	color: Color3,
	layer: string?
): TextButton
	local u, v = toMap(x, z)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(u, v)
	b.Size = UDim2.fromOffset(size * iconScale, size * iconScale)
	b:SetAttribute("Base", size)
	b.BackgroundColor3 = color
	b.ZIndex = 3
	Kit.round(b, size // 2)
	Kit.stroke(b, Kit.color.ink, 2)
	b.Parent = layers[layer or "marks"]
	return b
end

-- gap-icons2 (2026-11-19): a dot shows its comic symbol on its colorblind shape (Kit.showMark), a little
-- bigger than the plain dot (grow); false (the dot keeps today's look) while the icon sheets are not uploaded
local function iconDot(
	d: TextButton,
	shape: string,
	color: Color3,
	group: string,
	key: any,
	grow: number
): boolean
	if not Kit.showMark(d, shape, color, group, key) then
		return false
	end
	d.BackgroundTransparency = 1
	d.Text = ""
	d.Rotation = 0
	local st = d:FindFirstChildOfClass("UIStroke")
	if st then
		st.Enabled = false
	end
	for _, name in { "Lamp", "BossText" } do
		local c = d:FindFirstChild(name)
		if c and c:IsA("GuiObject") then
			c.Visible = false
		end
	end
	local base = (d:GetAttribute("Base") :: number) * grow
	d:SetAttribute("Base", base)
	d.Size = UDim2.fromOffset(base * iconScale, base * iconScale)
	return true
end

local function draw()
	if not info then
		return
	end
	for _, m in markers do
		m:Destroy()
	end
	table.clear(markers)
	table.clear(beaconTags)
	-- the Vigil's Safehouse is a hideout: only the Vigil have it on their map (nate's lore plan Q2)
	if hqDots.hero then
		hqDots.hero.Visible = State.hero.side ~= "villain"
	end
	local profile = State.profile
	for _, s in info.safehouses do
		local visited = Travel.has(profile.safehouses or 0, s.id)
		local isHome = s.id == profile.lastSafehouse
		local d = dot(
			"Safehouse" .. s.id,
			s.x,
			s.z,
			if isHome then 14 else 10,
			if visited then rgb(C.palette.respawn) else Kit.color.muted,
			"icons"
		)
		-- a rounded square with an S (diamonds are the boss's shape)
		local corner = d:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, 3)
		end
		d.Text = "S"
		d.TextScaled = true
		d.Font = Kit.font
		d.TextColor3 = Kit.color.ink
		iconDot(d, "square", d.BackgroundColor3, "marker", "safehouse", 1.8)
		markers["s" .. s.id] = d
	end
	for _, b in info.beacons do
		local found = Travel.has(profile.beacons or 0, b.id)
		local d = dot(
			"Beacon" .. b.id,
			b.x,
			b.z,
			Config.Ui.touchTarget * 0.55,
			if found then Kit.color.gold else Kit.color.muted,
			"icons"
		)
		local l = Kit.label({
			Text = if found then b.name else "?",
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(120, 16),
			Position = UDim2.new(0.5, 0, 1, 2),
			TextColor3 = if found then Kit.color.gold else Kit.color.muted,
			TextStrokeTransparency = 0.2,
			Font = Kit.bodyFont,
			maxText = 12,
		})
		l.Parent = d
		table.insert(beaconTags, l)
		-- a beacon reads as a lamp in a ring: lit (paper) once found, dark until then
		local lamp = Instance.new("Frame")
		lamp.Name = "Lamp"
		lamp.AnchorPoint = Vector2.new(0.5, 0.5)
		lamp.Position = UDim2.fromScale(0.5, 0.5)
		lamp.Size = UDim2.fromScale(0.4, 0.4)
		lamp.BorderSizePixel = 0
		lamp.BackgroundColor3 = if found then Kit.color.paper else Kit.color.ink
		lamp.ZIndex = 3
		Kit.round(lamp, 99)
		lamp.Parent = d
		iconDot(d, "circle", if found then Kit.color.gold else Kit.color.muted, "marker", "beacon", 1.3)
		d.Activated:Connect(function()
			if dragMoved > 8 then
				return -- the end of a pan, not a tap
			end
			if not found then
				status.Text = "Find this beacon first: touch it to unlock fast travel"
				return
			end
			status.Text = "Flying to " .. b.name .. "..."
			Net.send("MoveFastTravel", b.id)
		end)
		markers["b" .. b.id] = d
	end
	status.Text = string.format(
		"Beacons %d / %d   Safehouses %d / %d   Tap a gold beacon to fast travel",
		Travel.count(profile.beacons or 0),
		#W.beacons,
		Travel.count(profile.safehouses or 0),
		#W.safehouses
	)
end

-- The fallback for a city picture not uploaded yet: today's flat district squares (PLACEHOLDER ART)
local DISTRICT_NAMES = { Downtown = "DOWNTOWN", Docks = "DOCKS", OldTown = "OLD TOWN", Uptown = "UPTOWN" } -- UPTOWN: PLACEHOLDER NAME
local function flatCity(which: string)
	if which == "Hub" then
		rect("Hub", C.hub.min, C.hub.min, C.hub.max, C.hub.max, rgb(C.palette.sidewalk))
	end
	for id, d in C.districts do
		if (id == "Uptown") == (which == "Uptown") then
			rect(id, d.minX, d.minZ, d.maxX, d.maxZ, rgb(C.palette.slate))
		end
	end
end

local ZONE_COLORS = {
	suburbs = C.palette.grass,
	farmland = C.palette.crop,
	coast = { 150, 176, 110 },
	landmark = C.palette.rock,
}

-- The arrow you are: a paper disc in your volt ring with a nose that points where you face
local function buildYou()
	you = Instance.new("Frame")
	you.Name = "You"
	you.AnchorPoint = Vector2.new(0.5, 0.5)
	you.Size = UDim2.fromOffset(22, 22)
	you.BackgroundTransparency = 1
	you.ZIndex = 5
	you.Parent = layers.you
	local nose = Instance.new("Frame")
	nose.Name = "Nose"
	nose.AnchorPoint = Vector2.new(0.5, 0.5)
	nose.Position = UDim2.fromScale(0.5, 0.12)
	nose.Size = UDim2.fromScale(0.5, 0.5)
	nose.Rotation = 45
	nose.BorderSizePixel = 0
	nose.BackgroundColor3 = Kit.color.volt
	nose.ZIndex = 5
	Kit.stroke(nose, Kit.color.ink, 2)
	nose.Parent = you
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.55)
	disc.Size = UDim2.fromScale(0.72, 0.72)
	disc.BorderSizePixel = 0
	disc.BackgroundColor3 = Kit.color.paper
	disc.ZIndex = 6
	Kit.round(disc, 99)
	Kit.stroke(disc, Kit.color.volt, 3)
	disc.Parent = you
end

local function buildBase()
	-- the layers, bottom to top (siblings draw in ZIndex order)
	for i, name in { "ground", "roads", "city", "names", "icons", "marks", "you" } do
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		f.ZIndex = i
		f.Parent = canvas
		layers[name] = f
	end
	local half = C.mapSize / 2
	plain("ground", { x0 = -half, z0 = -half, x1 = half, z1 = half }, rgb(C.palette.grass), "Land")
	-- this week's outskirts (the seed's tiles), merged into rectangles, each tiled with its zone's pattern
	local tiles = WorldGen.tiles(C, W, info.seed or 0)
	for _, zr in MapPlan.zones(C, W, tiles) do
		local id = ART.patterns[zr.zone] or 0
		if id ~= 0 then
			picture("ground", zr, id, C.tile).Name = zr.zone
		else
			plain("ground", zr, rgb(ZONE_COLORS[zr.zone] or C.palette.grass), zr.zone)
		end
	end
	for _, r in MapPlan.sand(C, W, tiles) do
		plain("ground", r, rgb(C.palette.sand), "Sand")
	end
	-- roads, highways with a gold centre line
	for _, r in MapPlan.roads(C, W, tiles) do
		plain("roads", r, rgb(C.palette.road), if r.highway then "Highway" else "Road")
		if r.highway then
			local wide = r.x1 - r.x0 > r.z1 - r.z0
			local cx, cz = (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2
			local line = if wide
				then { x0 = r.x0, x1 = r.x1, z0 = cz - 2, z1 = cz + 2 }
				else { x0 = cx - 2, x1 = cx + 2, z0 = r.z0, z1 = r.z1 }
			plain("roads", line, Kit.color.gold, "Line")
		end
	end
	-- the fixed city: its pictures, or the flat squares until they are uploaded
	for which, r in MapPlan.cityImages(C) do
		local id = ART.city[which] or 0
		if id ~= 0 then
			picture("city", r, id).Name = which
		else
			flatCity(which)
		end
	end
	-- the landmarks: the Crater's blast ring in red, the others a rock badge
	for _, lm in info.landmarks do
		local r = {
			x0 = lm.x - lm.size / 2,
			z0 = lm.z - lm.size / 2,
			x1 = lm.x + lm.size / 2,
			z1 = lm.z + lm.size / 2,
		}
		local crater = lm.id == "CometCrater"
		local f = plain("city", r, if crater then rgb(C.palette.crater) else rgb(C.palette.rock), lm.id)
		f.BackgroundTransparency = if crater then 0.15 else 0.35
		Kit.round(f, if crater then 999 else 10)
		Kit.stroke(f, if crater then Color3.fromRGB(235, 60, 50) else Kit.color.ink, if crater then 4 else 2)
	end
	-- names: districts big, landmarks in gold, the outskirts rings small and faint
	for _, lb in MapPlan.labels(C, W, DISTRICT_NAMES) do
		local u, v = toMap(lb.x, lb.z)
		local big = lb.kind == "district"
		local l = Kit.label({
			Name = "Name",
			Text = lb.text,
			AnchorPoint = Vector2.new(0.5, if lb.kind == "landmark" then 0 else 0.5),
			Position = UDim2.new(u, 0, v, if lb.kind == "landmark" then 2 else 0),
			Size = UDim2.fromOffset(if big then 120 else 100, if big then 22 else 16),
			TextColor3 = if lb.kind == "landmark"
				then Kit.color.gold
				elseif big then Kit.color.paper
				else Color3.fromRGB(235, 240, 220),
			TextStrokeColor3 = Kit.color.ink,
			TextStrokeTransparency = if big then 0 else 0.25,
			TextTransparency = if lb.kind == "zone" then 0.2 else 0,
			maxText = if big then 22 else 14,
			ink = false,
		})
		l.Parent = layers.names
		l:SetAttribute("BaseW", l.Size.X.Offset)
		l:SetAttribute("BaseH", l.Size.Y.Offset)
		if not big then
			table.insert(tags, l)
		end
	end
	for _, hq in info.hq do
		local color = if hq.side == "hero" then Kit.color.vigil else Kit.color.syndicate
		local d = dot("HQ_" .. hq.side, hq.x, hq.z, 18, color, "icons")
		d.Rotation = 0
		local l = Kit.label({
			Text = string.upper(Config.Hq.names[hq.side] or ""),
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(120, 16),
			Position = UDim2.new(0.5, 0, 1, 2),
			TextColor3 = color,
			TextStrokeTransparency = 0.2,
			Font = Kit.bodyFont,
			maxText = 12,
		})
		l.Parent = d
		table.insert(tags, l)
		iconDot(d, "square", color, "marker", if hq.side == "hero" then "hqHero" else "hqVillain", 1.4)
		hqDots[hq.side] = d
	end
	buildYou()
end

local function loadInfo(): boolean
	local value = ReplicatedStorage:FindFirstChild("WorldInfo")
	if value and value:IsA("StringValue") and value.Value ~= "" then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, value.Value)
		if ok then
			info = data
			return true
		end
	end
	return false
end

-- Incidents, events and the boss: redrawn every second while the map is open
local worldMarks: { GuiObject } = {}
-- Tap-to-fly on a world marker
-- boss fights pass 2 (2026-11-20): a hero who cannot fly (most new heroes at their first boss) gets there another way:
-- `travel` targets fast travel to the found beacon nearest them when that saves BOSS_TRAVEL_GAIN studs, else the tap
-- says how far it is and to follow the marker
local BOSS_TRAVEL_GAIN = 600
local function myFlat(): Vector3?
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end
local function getThere(at: Vector3, name: string): boolean
	local me = myFlat()
	if not me or not info then
		return false
	end
	local profile = State.profile
	local b, d = Travel.nearestFound(
		info.beacons,
		profile and profile.beacons or 0,
		at.X,
		at.Z,
		me.X,
		me.Z,
		BOSS_TRAVEL_GAIN
	)
	local far = math.floor(((at - me) * Vector3.new(1, 0, 1)).Magnitude)
	if b and d then
		MapScreen.say(
			string.format(
				"Fast travel to %s, %dm from %s",
				(b :: any).name or "a beacon",
				math.floor(d),
				name
			)
		)
		Net.send("MoveFastTravel", b.id)
		task.delay(0.6, MapScreen.close)
	elseif Travel.count(profile and profile.beacons or 0) == 0 then
		MapScreen.say(
			string.format(
				"%s is %dm away: follow the red marker (touch beacons to unlock fast travel)",
				name,
				far
			)
		)
	else
		MapScreen.say(string.format("%s is %dm away: follow the red marker", name, far))
	end
	return true
end

local function flyable(d: TextButton, at: Vector3, name: string, travel: boolean?)
	d.Activated:Connect(function()
		if dragMoved > 8 then
			return -- the end of a pan, not a tap
		end
		if not SettingsClient.on("tapToFly") then
			if not (travel and getThere(at, name)) then
				MapScreen.say(name)
			end
			return
		end
		if MoveController.flyTo(at) then
			MapScreen.say("Flying to " .. name .. ": move to take over")
			task.delay(0.6, MapScreen.close)
		elseif not (travel and getThere(at, name)) then
			MapScreen.say("Unlock flight to fly there")
		end
	end)
end

local function drawWorld()
	for _, m in worldMarks do
		m:Destroy()
	end
	table.clear(worldMarks)
	for _, inc in WorldClient.incidents do
		if inc.state == WorldClient.ACTIVE then
			-- circles: incidents (colorblind-safe)
			local d = dot(
				"Incident",
				inc.pos.X,
				inc.pos.Z,
				14,
				if inc.side == "villain" then Kit.color.syndicate else Kit.color.vigil
			)
			iconDot(d, "circle", d.BackgroundColor3, "incident", inc.tid, 2)
			flyable(d, inc.pos, "the incident")
			table.insert(worldMarks, d)
		end
	end
	for _, ev in WorldClient.events do
		if ev.state == 0 then
			-- stars: events
			local d = dot("Event", ev.x, ev.z, 22, Kit.color.gold)
			d.BackgroundTransparency = 1
			d.Text = "★"
			d.TextScaled = true
			d.TextColor3 = Kit.color.gold
			d.TextStrokeTransparency = 0
			iconDot(d, "star", Kit.color.gold, "event", ev.id, 1.3)
			flyable(d, Vector3.new(ev.x, Config.City.ground.y, ev.z), "the event")
			table.insert(worldMarks, d)
		end
	end
	for _, m in SquadClient.state.members or {} do
		if m.userId ~= Players.LocalPlayer.UserId then
			local p = Players:GetPlayerByUserId(m.userId)
			local char = p and p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local far = SquadClient.positions[m.userId]
			local x, z = nil :: number?, nil :: number?
			if root then
				x, z = root.Position.X, root.Position.Z
			elseif far then
				x, z = far.X, far.Y
			end
			if x and z then
				-- squares: squadmates in their slot colour
				local col = Config.Squad.colors[m.slot or 1] or Config.Squad.colors[1]
				local d = dot("Squad", x, z, 14, Color3.fromRGB(col[1], col[2], col[3]))
				local corner = d:FindFirstChildOfClass("UICorner")
				if corner then
					corner.CornerRadius = UDim.new(0, 2)
				end
				local l = Kit.label({
					Text = m.name,
					AnchorPoint = Vector2.new(0.5, 0),
					Size = UDim2.fromOffset(110, 14),
					Position = UDim2.new(0.5, 0, 1, 2),
					TextColor3 = Color3.fromRGB(col[1], col[2], col[3]),
					TextStrokeTransparency = 0.3,
					Font = Kit.bodyFont,
					maxText = 11,
				})
				l.Parent = d
				iconDot(d, "square", Color3.fromRGB(col[1], col[2], col[3]), "marker", "squad", 1.4)
				table.insert(worldMarks, d)
			end
		end
	end
	-- lore step 10: side quest givers with a chain open or in progress for you ("!"), and the tracked step
	local okGivers, where = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("SideQuestGivers") or "{}")
	end)
	local j = StoryClient.journal
	if okGivers and type(where) == "table" and j then
		local want = {}
		for _, r in j.sq or {} do
			local chain = SideQuestPlan.byBit(Config, r.bit)
			if chain and (r.state == "open" or r.state == "active") then
				want[chain.giver] = want[chain.giver] or r.state == "active"
			end
		end
		for id, active in want do
			local at = where[id]
			local giver = Config.SideQuests.givers[id]
			if type(at) == "table" and giver then
				local d = dot("Giver", at[1], at[2], 20, if active then Kit.color.gold else Kit.color.paper)
				d.Text = "!"
				d.TextScaled = true
				d.TextColor3 = Kit.color.ink
				iconDot(d, "circle", d.BackgroundColor3, "marker", "giver", 1.3)
				flyable(d, Vector3.new(at[1], Config.City.ground.y, at[2]), giver.name)
				table.insert(worldMarks, d)
			end
		end
	end
	-- lore step 11: chain sites in existing buildings (HALO ACADEMY), named, while their chain is open or under
	-- way for you
	local okSites, sites = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("SideQuestSites") or "{}")
	end)
	if okSites and type(sites) == "table" and j then
		local live = {}
		for _, r in j.sq or {} do
			local chain = SideQuestPlan.byBit(Config, r.bit)
			if chain and (r.state == "open" or r.state == "active") then
				-- every site the chain uses (chain 2: the gala, the racers' meet and the bank)
				for _, id in SideQuestPlan.sites(chain) do
					live[id] = true
				end
			end
		end
		for id in live do
			local at = sites[id]
			local st = Config.SideQuests.sites[id]
			if type(at) == "table" and st then
				local d = dot("Site", at[1], at[2], 16, Kit.color.gold)
				local corner = d:FindFirstChildOfClass("UICorner")
				if corner then
					corner.CornerRadius = UDim.new(0, 2)
				end
				local l = Kit.label({
					Text = st.name, -- a fixed site name from Config.SideQuests.sites
					AnchorPoint = Vector2.new(0.5, 0),
					Size = UDim2.fromOffset(120, 14),
					Position = UDim2.new(0.5, 0, 1, 2),
					TextColor3 = Kit.color.gold,
					TextStrokeTransparency = 0.3,
					Font = Kit.bodyFont,
					maxText = 11,
				})
				l.Parent = d
				iconDot(d, "square", Kit.color.gold, "marker", "site", 1.5)
				flyable(d, Vector3.new(at[1], Config.City.ground.y, at[2]), st.name)
				table.insert(worldMarks, d)
			end
		end
	end
	local q = StoryClient.quest
	if q and q.target then
		local d = dot("SideQuest", q.target[1], q.target[3], 14, Kit.color.gold)
		iconDot(d, "circle", Kit.color.gold, "marker", "quest", 1.6)
		flyable(d, Vector3.new(q.target[1], q.target[2], q.target[3]), "your side quest")
		table.insert(worldMarks, d)
	end
	local b = WorldClient.boss
	if b.state == 1 or b.state == 2 or b.state == 3 then
		-- a diamond: the world boss
		local d = dot("Boss", b.x, b.z, 26, Color3.fromRGB(235, 60, 50))
		d.Rotation = 45
		local corner = d:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, 3)
		end
		flyable(d, Vector3.new(b.x, b.y or Config.City.ground.y, b.z), "the world boss", true)
		local l = Kit.label({
			Name = "BossText",
			Text = "BOSS",
			Size = UDim2.fromScale(1, 1),
			TextColor3 = Kit.color.paper,
			Rotation = -45,
			maxText = 12,
		})
		l.Parent = d
		iconDot(
			d,
			"diamond",
			Color3.fromRGB(235, 60, 50),
			"marker",
			if b.id and Kit.iconCell("marker", b.id) then b.id else "boss",
			1.2
		)
		table.insert(worldMarks, d)
	end
end

local opened = false
local openSeq = 0 -- each open's follow loop; a quick close and open (or a second open) ends the older one
function MapScreen.open()
	if not info and not loadInfo() then
		-- the world is still being built (spec: every screen has an error state)
		State.Toast:Fire({ id = "note", text = "The map is still loading. Try again in a moment." })
		return
	end
	if not you then
		buildBase()
	end
	Kit.opening("MapScreen", panel, MapScreen.close, true)
	panel.Visible = true
	if not opened then
		-- the first open shows your part of the city (zoom 2 on you); after that the map keeps its view
		opened = true
		local char = Players.LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			view.u, view.v = toMap(root.Position.X, root.Position.Z)
			view.zoom = ART.openZoom
		end
	end
	applyView()
	draw()
	drawWorld()
	applyView()
	openSeq += 1
	local seq = openSeq
	task.spawn(function()
		local tick = 0
		while panel.Visible and openSeq == seq do
			tick += 1
			if tick % 5 == 0 then
				drawWorld()
			end
			local char = Players.LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local u, v = toMap(root.Position.X, root.Position.Z)
				you.Position = UDim2.fromScale(math.clamp(u, 0, 1), math.clamp(v, 0, 1))
				-- the nose points where you face (screen up is north, -z)
				local look = root.CFrame.LookVector
				if look.X * look.X + look.Z * look.Z > 1e-4 then
					you.Rotation = math.deg(math.atan2(look.X, -look.Z))
				end
			end
			task.wait(0.2)
		end
	end)
end

function MapScreen.close()
	panel.Visible = false
end

function MapScreen.toggle()
	if panel.Visible then
		MapScreen.close()
	else
		MapScreen.open()
	end
end

function MapScreen.isOpen(): boolean
	return panel.Visible
end

function MapScreen.say(text: string)
	if status then
		status.Text = text
	end
end

-- Zoom by a factor about a point on the frame (0..1 across it), keeping that map point under it
function MapScreen.zoom(factor: number, fx: number?, fy: number?)
	applyView()
	local px, py = fx or 0.5, fy or 0.5
	local size = map.AbsoluteSize
	local before = lastView :: MapPlan.View
	local mu, mv = MapPlan.frameToMap(before, size.X, size.Y, px, py)
	view.zoom = math.clamp(view.zoom * factor, 1, ART.maxZoom)
	local side = view.zoom * math.max(1, math.min(size.X, size.Y))
	view.u = mu - (px - 0.5) * size.X / side
	view.v = mv - (py - 0.5) * size.Y / side
	applyView()
end

-- Centre the view on a world point (at this zoom, or the current one)
function MapScreen.lookAt(x: number, z: number, zoom: number?)
	view.u, view.v = toMap(x, z)
	view.zoom = zoom or view.zoom
	applyView()
end

-- Centre the view on you
function MapScreen.centre()
	if you then
		view.u, view.v = you.Position.X.Scale, you.Position.Y.Scale
		if view.zoom < 2 then
			view.zoom = 2
		end
		applyView()
	end
end

-- Drag to pan (mouse or one finger), pinch or the wheel to zoom, and the + / - / centre buttons
function MapScreen.bindPan()
	local pressing: InputObject? = nil
	local last = Vector2.zero
	map.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			if pressing == nil then
				pressing = input
				last = Vector2.new(input.Position.X, input.Position.Y)
				dragMoved = 0
			end
		end
	end)
	map.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local size = map.AbsoluteSize
			local fx = (input.Position.X - map.AbsolutePosition.X) / math.max(1, size.X)
			local fy = (input.Position.Y - map.AbsolutePosition.Y) / math.max(1, size.Y)
			MapScreen.zoom(if input.Position.Z > 0 then 1.25 else 0.8, fx, fy)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local p = pressing
		if not p or not panel.Visible then
			return
		end
		local moving = input == p
			or (
				p.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		if not moving then
			return
		end
		local now = Vector2.new(input.Position.X, input.Position.Y)
		local d = now - last
		last = now
		dragMoved += d.Magnitude
		local vw = lastView
		if vw and vw.side > 0 then
			view.u -= d.X / vw.side
			view.v -= d.Y / vw.side
			applyView()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local p = pressing
		if p and (input == p or input.UserInputType == p.UserInputType) then
			pressing = nil
			task.delay(0.05, function()
				dragMoved = 0 -- after the release's Activated has seen it
			end)
		end
	end)
	UserInputService.TouchPinch:Connect(function(_, scale: number, _, state: Enum.UserInputState)
		if not panel.Visible then
			return
		end
		if state == Enum.UserInputState.Change and scale > 0 then
			MapScreen.zoom(scale / (view.pinch or scale))
			view.pinch = scale
			dragMoved = 99 -- a pinch is never a tap
		else
			view.pinch = nil
		end
	end)
	local T = Config.Ui.touchTarget
	for i, b in { { "+", 1.5 }, { "-", 1 / 1.5 }, { "◎", 0 } } do
		local button = Kit.button({
			Name = "Zoom" .. i,
			Text = b[1],
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(T - 6, T - 6),
			Position = UDim2.new(1, -6, 0, 6 + (i - 1) * (T - 2)),
			BackgroundColor3 = Kit.color.paper,
			ZIndex = 20,
			maxText = 26,
		}, function()
			if b[2] == 0 then
				MapScreen.centre()
			else
				MapScreen.zoom(b[2])
			end
		end)
		button.Parent = map
	end
end

function MapScreen.init()
	gui = Kit.screen("Map", 6)
	panel = Kit.frame({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.94, 0),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	panel.Parent = gui
	local title = Kit.label({
		Text = "BRIGHTHARBOR",
		Size = UDim2.new(0.5, 0, 0, 30),
		Position = UDim2.fromOffset(14, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 28,
	})
	title.Parent = panel
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(Config.Ui.touchTarget, Config.Ui.touchTarget - 10),
		Position = UDim2.new(1, -Config.Ui.touchTarget - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, MapScreen.close)
	close.Parent = panel
	-- the map keeps a square shape inside the panel
	map = Kit.frame({
		Name = "Map",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 48),
		Size = UDim2.new(1, -28, 1, -96),
		BackgroundColor3 = rgb(C.palette.sea),
		ClipsDescendants = true,
		round = false,
	})
	map.Parent = panel
	-- the frame fills the panel (wide on a phone); the map inside is a square canvas (MapPlan.view)
	map:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if canvas and panel.Visible then
			applyView()
		end
	end)
	canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.Parent = map
	MapScreen.bindPan()
	status = Kit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(1, -28, 0, 22),
		Position = UDim2.new(0.5, 0, 1, -12),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 15,
	})
	status.Parent = panel
	InputController.Pressed:Connect(function(action)
		if action == "Map" then
			MapScreen.toggle()
		end
	end)
	State.ProfileChanged:Connect(function()
		if panel.Visible then
			draw()
		end
	end)
end

return MapScreen
