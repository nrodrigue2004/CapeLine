-- MapScreen: the city map and fast travel (spec: Screens and UI > Map "Hub and outskirts, beacons,
-- safehouses, incidents, boss, the Crater, party; tap a marker to auto-fly; fast travel to beacons").
-- M4 shows the zones, districts, landmarks, the HQs (the Safehouse to the Vigil only), the 16 safehouses (bright once visited), the 12
-- beacons (gold once discovered, a tap flies there) and you. M6 adds the incidents near you (blue Vigil,
-- red Syndicate), running events (gold) and the world boss (big red). M10: your squad (squares in their
-- slot colours), colorblind-safe shapes (circle incident, star event, diamond boss), and a tap on an
-- incident, event or the boss auto-flies you there (Settings: tap to fly; needs flight). Lore step 10: side quest
-- givers with a chain for you ("!", gold when one is in progress) and the tracked step. Opens with M, the
-- MAP button or a tap on the radar.
-- PLACEHOLDER ART: flat coloured frames until the art pass.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Travel = require(Shared:WaitForChild("Travel"))
local SideQuestPlan = require(Shared:WaitForChild("SideQuestPlan"))

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
local gui: ScreenGui
local panel: Frame
local map: Frame
local you: Frame
local status: TextLabel
local markers: { [string]: GuiObject } = {}
local hqDots: { [string]: GuiObject } = {}
local info: any = nil

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- world x/z to a 0..1 map position
local function toMap(x: number, z: number): (number, number)
	local half = C.mapSize / 2
	return (x + half) / C.mapSize, (z + half) / C.mapSize
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
	f.Parent = map
	return f
end

local function dot(name: string, x: number, z: number, size: number, color: Color3): TextButton
	local u, v = toMap(x, z)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(u, v)
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = color
	b.ZIndex = 3
	Kit.round(b, size // 2)
	Kit.stroke(b, Kit.color.ink, 2)
	b.Parent = map
	return b
end

local function draw()
	if not info then
		return
	end
	for _, m in markers do
		m:Destroy()
	end
	table.clear(markers)
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
			if visited then rgb(C.palette.respawn) else Kit.color.muted
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
		markers["s" .. s.id] = d
	end
	for _, b in info.beacons do
		local found = Travel.has(profile.beacons or 0, b.id)
		local d = dot(
			"Beacon" .. b.id,
			b.x,
			b.z,
			Config.Ui.touchTarget * 0.55,
			if found then Kit.color.gold else Kit.color.muted
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
		d.Activated:Connect(function()
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

local function buildBase()
	local half = C.mapSize / 2
	local suburbs = C.hub.max + W.rings.suburbsTo * C.tile
	local farm = C.hub.max + W.rings.farmlandTo * C.tile
	rect("Coast", -half, -half, half, half, rgb(C.palette.sand))
	rect("Farmland", -farm, -farm, farm, farm, rgb(C.palette.crop))
	rect("Suburbs", -suburbs, -suburbs, suburbs, suburbs, rgb(C.palette.grass))
	rect("Hub", C.hub.min, C.hub.min, C.hub.max, C.hub.max, rgb(C.palette.sidewalk))
	local names = { Downtown = "DOWNTOWN", Docks = "DOCKS", OldTown = "OLD TOWN", Uptown = "UPTOWN" } -- UPTOWN: PLACEHOLDER NAME
	for id, d in C.districts do
		rect(id, d.minX, d.minZ, d.maxX, d.maxZ, rgb(C.palette.slate), names[id])
	end
	local lmNames = { CometCrater = "THE CRATER", RadioHill = "RADIO HILL", OldQuarry = "OLD QUARRY" }
	for _, lm in info.landmarks do
		local f = rect(
			lm.id,
			lm.x - lm.size / 2,
			lm.z - lm.size / 2,
			lm.x + lm.size / 2,
			lm.z + lm.size / 2,
			if lm.id == "CometCrater" then Color3.fromRGB(140, 60, 70) else rgb(C.palette.rock),
			lmNames[lm.id]
		)
		Kit.round(f, 6)
	end
	for _, hq in info.hq do
		local color = if hq.side == "hero" then Kit.color.vigil else Kit.color.syndicate
		local d = dot("HQ_" .. hq.side, hq.x, hq.z, 18, color)
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
		hqDots[hq.side] = d
	end
	you = Kit.frame({
		Name = "You",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Kit.color.paper,
		ZIndex = 5,
	})
	Kit.round(you, 7)
	Kit.stroke(you, Kit.color.volt, 3)
	you.Parent = map
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
local function flyable(d: TextButton, at: Vector3, name: string)
	d.Activated:Connect(function()
		if not SettingsClient.on("tapToFly") then
			MapScreen.say(name)
			return
		end
		if MoveController.flyTo(at) then
			MapScreen.say("Flying to " .. name .. ": move to take over")
			task.delay(0.6, MapScreen.close)
		else
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
				flyable(d, Vector3.new(at[1], Config.City.ground.y, at[2]), giver.name)
				table.insert(worldMarks, d)
			end
		end
	end
	local q = StoryClient.quest
	if q and q.target then
		local d = dot("SideQuest", q.target[1], q.target[3], 14, Kit.color.gold)
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
		flyable(d, Vector3.new(b.x, b.y or Config.City.ground.y, b.z), "the world boss")
		local l = Kit.label({
			Text = "BOSS",
			Size = UDim2.fromScale(1, 1),
			TextColor3 = Kit.color.paper,
			Rotation = -45,
			maxText = 12,
		})
		l.Parent = d
		table.insert(worldMarks, d)
	end
end

function MapScreen.open()
	if not info and not loadInfo() then
		-- the world is still being built (spec: every screen has an error state)
		State.Toast:Fire({ id = "note", text = "The map is still loading. Try again in a moment." })
		return
	end
	if not you then
		buildBase()
	end
	panel.Visible = true
	draw()
	drawWorld()
	task.spawn(function()
		local tick = 0
		while panel.Visible do
			tick += 1
			if tick % 5 == 0 then
				drawWorld()
			end
			local char = Players.LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local u, v = toMap(root.Position.X, root.Position.Z)
				you.Position = UDim2.fromScale(math.clamp(u, 0, 1), math.clamp(v, 0, 1))
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
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = map
	map.Parent = panel
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
