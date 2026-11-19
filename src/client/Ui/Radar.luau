-- Radar: the main HUD's radar, world clock, boss countdown and ping wheel (spec: Main HUD "radar with
-- incident markers, world clock, boss countdown, ping wheel"; Map "M or tap radar"; Accessibility
-- "colorblind-safe markers (shapes plus color: circle for incident, diamond for boss, triangle for danger)").
-- * A round radar under the status card turns with the camera (up is where you look) and shows incidents
--   (circles), events (stars), the world boss (diamond), danger pings (triangles) and squadmates (squares
--   in their slot colour) within 400 studs; farther ones sit on the rim. Tap it for the map.
-- * Under it: the world clock (day or night and the hour) and the boss timer.
-- * PING opens a wheel: HELP, HERE (where you aim) and DANGER; SQUAD opens the squad panel.
-- gap-icons2 (2026-11-19): each mark is its comic symbol on its shape (Shapes.apply with a Config.Icons key) and
-- the ping wheel's rows lead with the Help, Here and Danger icons; Kit shapes and glyphs without the sheets.
-- PLACEHOLDER look until the art pass: Kit shapes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = require(script.Parent.Kit)
local Shapes = require(script.Parent.Shapes)
local MapScreen = require(script.Parent.MapScreen)
local SquadHud = require(script.Parent.SquadHud)
local WorldClient = require(script.Parent.Parent.Controllers.WorldClient)
local PvpClient = require(script.Parent.Parent.Controllers.PvpClient)
local SquadClient = require(script.Parent.Parent.Controllers.SquadClient)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)

local Radar = {}

local U = Config.Ui
local SIZE = 132
local RANGE = 400 -- studs from the centre to the rim
local me = Players.LocalPlayer

local gui: ScreenGui
local disc: TextButton
local dots: { TextLabel } = {}
local clockText: TextLabel
local bossText: TextLabel
local boostText: TextLabel
local wheel: Frame
local dangers: { { pos: Vector3, untilT: number } } = {}

local function dot(i: number): TextLabel
	local d = dots[i]
	if not d then
		d = Kit.label({
			Text = "",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			TextColor3 = Kit.color.paper,
			ZIndex = 3,
			maxText = 14,
		})
		local stroke = Instance.new("UIStroke")
		stroke.Color = Kit.color.ink
		stroke.Thickness = 1.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = d
		d.Parent = disc
		dots[i] = d
	end
	return d
end

local function myPos(): Vector3?
	local char = me.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

local function place(
	n: number,
	at: Vector3,
	origin: Vector3,
	yaw: number,
	shape: string,
	color: Color3,
	size: number?,
	group: string?,
	key: any
)
	local d = dot(n)
	local off = Vector2.new(at.X - origin.X, at.Z - origin.Z)
	-- turn so the camera's forward points up
	local c, s = math.cos(yaw), math.sin(yaw)
	local r = Vector2.new(off.X * c - off.Y * s, off.X * s + off.Y * c)
	local dist = r.Magnitude
	if dist > RANGE then
		r = r.Unit * RANGE
	end
	local k = (SIZE / 2 - 8) / RANGE
	d.Position = UDim2.new(0.5, r.X * k, 0.5, r.Y * k)
	local px = size or 12
	d.Size = UDim2.fromOffset(px, px)
	Shapes.apply(d, shape, color, group, key)
	d.Visible = true
end

local function draw()
	-- the opening shows only its verb buttons (spec: first 30 seconds)
	gui.Enabled = not StoryClient.inOpening()
	local origin = myPos()
	local n = 0
	if origin and not StoryClient.inMission() then
		local look = Workspace.CurrentCamera.CFrame.LookVector
		-- rotate the world so the camera's forward (look.X, look.Z) maps to screen up (0, -1)
		local yaw = math.atan2(look.X, -look.Z)
		for _, inc in WorldClient.incidents do
			if inc.state == WorldClient.ACTIVE and inc.pos then
				n += 1
				local col = if inc.side == "villain" then Kit.color.syndicate else Kit.color.vigil
				place(n, inc.pos, origin, -yaw, "circle", col, 16, "incident", inc.tid)
			end
		end
		for _, ev in WorldClient.events do
			if ev.state == 0 and ev.x then
				n += 1
				place(n, Vector3.new(ev.x, 0, ev.z), origin, -yaw, "star", Kit.color.gold, 22, "event", ev.id)
			end
		end
		local b = WorldClient.boss
		if (b.state == 1 or b.state == 2 or b.state == 3) and b.x then
			n += 1
			place(
				n,
				Vector3.new(b.x, 0, b.z),
				origin,
				-yaw,
				"diamond",
				Color3.fromRGB(255, 90, 60),
				20,
				"marker",
				if b.id and Kit.iconCell("marker", b.id) then b.id else "boss"
			)
		end
		local now = os.clock()
		for i = #dangers, 1, -1 do
			if dangers[i].untilT < now then
				table.remove(dangers, i)
			end
		end
		for _, dz in dangers do
			n += 1
			place(n, dz.pos, origin, -yaw, "triangle", Color3.fromRGB(255, 90, 80), 20, "marker", "danger")
		end
		for _, m in SquadClient.state.members or {} do
			local p = Players:GetPlayerByUserId(m.userId)
			local char = p and p ~= me and p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local pos = if root then root.Position else nil
			local far = SquadClient.positions[m.userId]
			if not pos and far then
				pos = Vector3.new(far.X, 0, far.Y)
			end
			if pos and p ~= me then
				n += 1
				place(n, pos, origin, -yaw, "square", SquadHud.slotColor(m.slot), 16, "marker", "squad")
			end
		end
	end
	for i = n + 1, #dots do
		dots[i].Visible = false
	end
	-- the world clock: the cycle as a 24-hour day starting at dawn (06:00)
	local cyc = Config.World.clock.cycle
	local t = WorldClient.clockT() % cyc
	local hours = (6 + t / cyc * 24) % 24
	clockText.Text = string.format(
		"%s %02d:%02d",
		if WorldClient.isNight() then "NIGHT" else "DAY",
		math.floor(hours),
		math.floor((hours % 1) * 60)
	)
	local boost = me:GetAttribute("FriendBoost")
	boostText.Text = if typeof(boost) == "number" then string.format("FRIEND BOOST +%d%%", boost) else ""
	local s = WorldClient.boss
	local left = (s.at or 0) - (os.clock() - (s.received or os.clock()))
	if s.state == 1 then
		bossText.Text = "BOSS IN " .. Kit.time(math.max(0, left))
		bossText.TextColor3 = Color3.fromRGB(255, 120, 90)
	elseif s.state == 2 or s.state == 3 then
		bossText.Text = "◆ BOSS FIGHT!"
		bossText.TextColor3 = Color3.fromRGB(255, 120, 90)
	elseif left > 0 then
		bossText.Text = "Next boss " .. Kit.time(left)
		bossText.TextColor3 = Kit.color.paper
	else
		bossText.Text = ""
	end
end

local function aimPoint(): Vector3?
	local ray = InputController.aimRay()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { me.Character :: Instance }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction.Unit * 280, params)
	if hit then
		return hit.Position
	end
	return myPos()
end

local function buildWheel()
	wheel = Kit.frame({
		Position = UDim2.fromOffset(U.safe + SIZE + 12, U.safe + 150),
		Size = UDim2.fromOffset(130, 3 * (U.touchTarget - 6) + 16),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.2,
		Visible = false,
	})
	wheel.Parent = gui
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 4)
	l.Parent = wheel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
	pad.Parent = wheel
	for kind, row in
		{
			{ "HELP", Color3.fromRGB(255, 220, 90), "help" },
			{ "HERE", Color3.fromRGB(120, 220, 255), "here" },
			{ "▲ DANGER", Color3.fromRGB(255, 90, 80), "danger" },
		}
	do
		local b = Kit.button({
			Text = row[1],
			Size = UDim2.new(1, 0, 0, U.touchTarget - 6),
			BackgroundColor3 = row[2],
		}, function()
			wheel.Visible = false
			local at = if kind == 1 then myPos() else aimPoint()
			if at then
				PvpClient.ping(kind, at)
			end
		end)
		b.Parent = wheel
		-- gap-icons2: the ping's icon leads its row (the danger row then drops its text triangle)
		if Kit.lead(b, "marker", row[3], U.touchTarget - 20) and kind == 3 then
			b.Text = "DANGER"
		end
	end
end

function Radar.init()
	gui = Kit.screen("Radar", 2)
	disc = Instance.new("TextButton")
	disc.Name = "Radar"
	disc.Text = ""
	disc.AutoButtonColor = false
	disc.BackgroundColor3 = Kit.color.night
	disc.BackgroundTransparency = 0.1
	disc.Size = UDim2.fromOffset(SIZE, SIZE)
	disc.Position = UDim2.fromOffset(U.safe, U.safe + 150)
	Kit.round(disc, SIZE // 2)
	-- the comic radar (2026-11-18): a heavy ink ring and a round drop shadow
	Kit.ink(disc)
	Kit.stroke(disc, Kit.color.ink, 4)
	disc.Parent = gui
	disc.Activated:Connect(function()
		MapScreen.open()
	end)
	local you = Kit.label({
		Text = "▲",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18), -- phone pass: still readable on the 88 px phone radar
		TextColor3 = Kit.color.gold,
		ZIndex = 4,
		maxText = 18,
	})
	you.Parent = disc
	clockText = Kit.label({
		Text = "",
		Size = UDim2.fromOffset(SIZE, 18),
		Position = UDim2.fromOffset(U.safe, U.safe + 150 + SIZE + 2),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.3,
		Font = Kit.bodyFont,
		maxText = 13,
	})
	clockText.Parent = gui
	bossText = Kit.label({
		Text = "",
		Size = UDim2.fromOffset(SIZE + 40, 18),
		Position = UDim2.fromOffset(U.safe, U.safe + 150 + SIZE + 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.3,
		Font = Kit.bodyFont,
		maxText = 13,
	})
	bossText.Parent = gui
	boostText = Kit.label({
		Text = "",
		Size = UDim2.fromOffset(SIZE + 40, 18),
		Position = UDim2.fromOffset(U.safe, U.safe + 150 + SIZE + 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		TextStrokeTransparency = 0.3,
		Font = Kit.bodyFont,
		maxText = 13,
	})
	boostText.Parent = gui
	local ping = Kit.button({
		Text = "PING",
		Size = UDim2.fromOffset(64, 36),
		Position = UDim2.fromOffset(U.safe + SIZE + 12, U.safe + 150 + SIZE - 78),
		BackgroundColor3 = Kit.color.paper,
		maxText = 16,
	}, function()
		wheel.Visible = not wheel.Visible
	end)
	ping.Parent = gui
	local squad = Kit.button({
		Text = "SQUAD",
		Size = UDim2.fromOffset(64, 36),
		Position = UDim2.fromOffset(U.safe + SIZE + 12, U.safe + 150 + SIZE - 36),
		BackgroundColor3 = Kit.color.paper,
		maxText = 16,
	}, function()
		SquadHud.toggle()
	end)
	squad.Parent = gui
	buildWheel()
	-- phone pass: PING and SQUAD join the top row; the radar and its lines take their box from the HUD plan
	-- (smaller on a phone, where it sits over the move stick and so does not take taps: MAP opens the map)
	Kit.dock(ping, "Ping", 5)
	Kit.dock(squad, "Squad", 8)
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = disc
	Kit.discInk(disc) -- its round shadow, scaled with the fit
	local function place()
		local hb = Kit.hudBoxes()
		local r, t = hb.radar, hb.radarText
		disc.Position = UDim2.fromOffset(r.x, r.y)
		fit.Scale = r.w / SIZE
		disc:SetAttribute("FitScale", fit.Scale)
		disc.Interactable = hb.radarTaps
		disc.Active = hb.radarTaps
		for i, l in { clockText, bossText, boostText } do
			l.Position = UDim2.fromOffset(t.x, t.y + (i - 1) * t.h)
			l.Size = UDim2.fromOffset(t.w + (if i == 1 then 0 else 40), t.h)
		end
		-- the ping wheel opens beside the radar; on a phone under the top row's middle, clear of the stick
		if hb.compact then
			local a = Kit.area()
			wheel.Position = UDim2.fromOffset(
				math.floor(a.X * 0.5 - wheel.Size.X.Offset / 2),
				U.safe + Config.Ui.phone.rowCompact + Config.Ui.phone.gap
			)
		else
			wheel.Position = UDim2.fromOffset(r.x + r.w + 12, r.y)
		end
	end
	place()
	Kit.LayoutChanged:Connect(place)
	PvpClient.Ping:Connect(function(p)
		if p.kind == 3 then
			table.insert(dangers, { pos = Vector3.new(p.x, p.y, p.z), untilT = os.clock() + (p.life or 8) })
		end
	end)
	local acc = 0
	RunService.RenderStepped:Connect(FrameProf.wrap("Radar", function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			draw()
		end
	end))
end

return Radar
