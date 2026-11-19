-- LoreClient: the lore pages on this device (side-content, 2026-11-19; Config.Lore, Shared.LorePlan, Shared.LoreBookKit).
-- * The server sends every page's spot and the pages this account has read (LoreState). A page you have not read
--   is drawn within Config.Lore.glow studs as a glowing open book (LoreBookKit's pieces: the very list the Blender
--   preview art/preview/lorebook.png renders), turning and bobbing, with a soft chime as you come near.
-- * The server picks it up (LoreService: within reach); LoreFound pops the juice (Juice "lorePage": the paper fan,
--   LORE n / N, the DISTRICT READ! stamp) and the page's comic caption card (Ui.LoreCard).
-- * The Journal's LORE tab draws from here (request, Changed, drawInto): each district's pages read of all, the
--   titles of the read ones (tap to read the card again) and ??? for the rest.
-- PLACEHOLDER ART: the book is parts until a sculpted Blender book mesh is uploaded (Tasks.md).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local LoreBookKit = require(Shared:WaitForChild("LoreBookKit"))
local LorePlan = require(Shared:WaitForChild("LorePlan"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Juice = require(script.Parent.Parent.Fx.Juice)
local LoreBooks = require(script.Parent.Parent.Fx.LoreBooks)
local Kit = require(script.Parent.Parent.Ui.Kit)
local LoreCard = require(script.Parent.Parent.Ui.LoreCard)
local AudioController = require(script.Parent.AudioController)

local LoreClient = {}
LoreClient.Changed = Signal.new()

local L = Config.Lore
local LOOK = L.look
local SCAN_EVERY = 0.4 -- seconds between the near-book checks (the spin and bob run every frame on the few shown)
local player = Players.LocalPlayer

type Spot = { bit: number, x: number, y: number, z: number }
type Shown = { model: Model, at: Vector3, phase: number }

local spots: { Spot } = {}
local read: { number } = { 0, 0 } -- the same two words as profile.lore (LorePlan.has / mark)
local loaded = false
local shown: { [number]: Shown } = {}
local chimed: { [number]: boolean } = {}
local folder: Folder? = nil

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function root(): BasePart?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function holder(): Folder
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "LorePages"
		f.Parent = Workspace
		folder = f
	end
	return folder :: Folder
end

-- The book's parts from LoreBookKit, in a model whose pivot is the book's middle
local function makeBook(s: Spot): Model
	local page = LorePlan.page(L, s.bit)
	local colors = LoreBookKit.colors(LOOK, page and page.district)
	local m = Instance.new("Model")
	m.Name = "LorePage" .. s.bit
	local base = CFrame.new()
	local core = LoreBooks.build(m, LoreBookKit.book(), colors, base).StarCore
	m.WorldPivot = base
	if core then
		local light = Instance.new("PointLight")
		light.Color = rgb(LOOK.glow)
		light.Range = LOOK.light.range
		light.Brightness = LOOK.light.brightness
		light.Shadows = false
		light.Parent = core
		local e = Instance.new("ParticleEmitter")
		e.Rate = 5
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(0.6, 1.6)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new(0.3, 0)
		e.Color = ColorSequence.new(rgb(LOOK.glow))
		e.LightEmission = 1
		e.Parent = core
	end
	m:PivotTo(CFrame.new(s.x, s.y, s.z))
	m.Parent = holder()
	return m
end

local function drop(bit: number)
	local sh = shown[bit]
	if sh then
		sh.model:Destroy()
		shown[bit] = nil
	end
end

-- Which books are near (every SCAN_EVERY): draw the missing ones in glow range, chime once as you come near
local function scan()
	local r = root()
	if not r then
		return
	end
	local pos = r.Position
	local g2, c2 = L.glow * L.glow, L.chime * L.chime
	for _, s in spots do
		local d = (s.x - pos.X) ^ 2 + (s.y - pos.Y) ^ 2 + (s.z - pos.Z) ^ 2
		local missing = not LorePlan.has(read, s.bit)
		if missing and d <= g2 then
			if not shown[s.bit] then
				shown[s.bit] =
					{ model = makeBook(s), at = Vector3.new(s.x, s.y, s.z), phase = (s.bit * 0.37) % 1 }
			end
			if d <= c2 and not chimed[s.bit] then
				chimed[s.bit] = true
				AudioController.play("loreNear", Vector3.new(s.x, s.y, s.z))
			elseif d > c2 * 1.5 then
				chimed[s.bit] = nil
			end
		elseif shown[s.bit] then
			drop(s.bit)
		end
	end
end

-- The spin and bob of the few books shown (every frame, FrameProf "LoreClient")
local scanAcc = 0
local function step(dt: number)
	scanAcc += dt
	if scanAcc >= SCAN_EVERY then
		scanAcc = 0
		scan()
	end
	if next(shown) == nil then
		return
	end
	local t = os.clock()
	local spin = math.rad(LOOK.spin)
	local per = LOOK.bob.period
	for _, sh in shown do
		local up = math.sin((t / per + sh.phase) * math.pi * 2) * LOOK.bob.height
		sh.model:PivotTo(
			CFrame.new(sh.at + Vector3.new(0, up, 0)) * CFrame.Angles(0, t * spin + sh.phase * 6.28, 0)
		)
	end
end

-- Show a page's caption card (Ui.LoreCard, in the popup line)
function LoreClient.showPage(bit: number)
	LoreCard.show(bit)
end

---------------------------------------------------------------------------
-- The Journal's LORE tab
---------------------------------------------------------------------------

function LoreClient.request()
	Net.send("LoreOpen")
end

function LoreClient.progress(): { any }
	return LorePlan.progress(L, read)
end

local function row(
	parent: Instance,
	text: string,
	h: number,
	size: number,
	color: Color3,
	order: number,
	font: Enum.Font?
)
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, 0, 0, h),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Font = font or Kit.bodyFont,
		TextWrapped = true,
		maxText = size,
	})
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

function LoreClient.drawInto(container: Instance)
	if not loaded then
		Kit.stateNote(container, "loading", "Opening the archive...")
		return
	end
	local have, total = LorePlan.count(L, read)
	local order = 1
	row(container, string.format("LORE PAGES  %d / %d", have, total), 30, 26, Kit.color.gold, order, Kit.font)
	order += 1
	row(
		container,
		"Glowing books lie by the city's landmarks. Read every page in a district for its title.",
		34,
		15,
		Kit.color.paper,
		order
	)
	for _, d in LorePlan.progress(L, read) do
		order += 1
		local head = row(
			container,
			string.format(
				"%s  %d / %d%s",
				string.upper(d.name),
				d.have,
				d.total,
				if d.done then "  ★ " .. d.title else ""
			),
			26,
			20,
			if d.done then Kit.color.gold else Kit.color.volt,
			order,
			Kit.font
		)
		head.Name = "District_" .. d.id
		for _, p in LorePlan.inDistrict(L, d.id) do
			order += 1
			if LorePlan.has(read, p.bit) then
				local b = Kit.button({
					Name = "Page_" .. p.id,
					Text = "  " .. p.title,
					Size = UDim2.new(1, 0, 0, Config.Ui.touchTarget - 8),
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundColor3 = Kit.color.paper,
					maxText = 18,
				}, function()
					LoreClient.showPage(p.bit)
				end)
				b.LayoutOrder = order
				b.Parent = container
			else
				row(container, "   A page still to find", 22, 15, Color3.fromRGB(150, 150, 170), order)
			end
		end
	end
end

function LoreClient.init()
	Net.listen("LoreState", function(d: any)
		if type(d) ~= "table" then
			return
		end
		spots = {}
		for _, r in d.spots or {} do
			if type(r) == "table" and type(r[1]) == "number" then
				table.insert(spots, { bit = r[1], x = r[2], y = r[3], z = r[4] })
			end
		end
		read = { 0, 0 }
		for _, b in d.read or {} do
			if type(b) == "number" and b >= 1 and b <= L.bits then
				LorePlan.mark(read, b)
			end
		end
		for bit in shown do
			if LorePlan.has(read, bit) then
				drop(bit)
			end
		end
		loaded = true
		LoreClient.Changed:Fire()
	end)
	Net.listen("LoreFound", function(d: any)
		if type(d) ~= "table" or type(d.bit) ~= "number" then
			return
		end
		LorePlan.mark(read, d.bit)
		local sh = shown[d.bit]
		local at = if sh then sh.at else nil
		drop(d.bit)
		Juice.fire("lorePage", at, {
			found = d.found,
			count = d.count,
			inDistrict = d.inDistrict,
			ofDistrict = d.ofDistrict,
			title = d.title,
			all = d.all,
			mine = true,
		})
		LoreClient.showPage(d.bit)
		LoreClient.Changed:Fire()
	end)
	RunService.Heartbeat:Connect(FrameProf.wrap("LoreClient", step))
	task.defer(LoreClient.request)
end

return LoreClient
