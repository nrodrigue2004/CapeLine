-- GuideHud: the guides' line box (nate's lore, build plan step 6). Every line in the game plays here, one at
-- a time (Shared.GuidePlan's queue): the prologue's and the missions' camera beats (StoryHud feeds their
-- timed lines), a mission stage's radio lines and Patch's open-world radio (GuideClient), and Lodestar's
-- talk. Each line shows its speaker's portrait, name in their colour, a RADIO or ON AIR tag by style, and
-- plays the speaker's own blip as it starts (subtitles and a blip now, real voice lines later: nate).
-- * Never two at once; a tap (or click) on the box skips to the next line where the box is clear of the
--   move stick; open-world lines wait while a camera beat, the prologue or a mission runs.
-- * On a camera beat the box sits under the letterbox; in play it takes the free spot GuidePlan.box finds,
--   clear of the action buttons, the status corner, the top row and the story trackers (keepClear).
-- * Reduce flashing: no pop-in pulse and no radio static flicker on the portrait.
-- PLACEHOLDER ART: the portraits are drawn from frames until the art pass (Tasks.md "Placeholder art").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local GuidePlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GuidePlan"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local SettingsClient = require(script.Parent.Parent.Controllers.SettingsClient)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)

local GuideHud = {}

local G = Config.Story.guides

local Q = GuidePlan.queue()
local gui: ScreenGui
local box: Frame
local nameLabel: TextLabel
local tagLabel: TextLabel
local textLabel: TextLabel
local skipButton: TextButton
local portraitHolder: Frame
local portraits: { [string]: Frame } = {}
local statics: { [string]: Frame } = {}
local clear: { GuiObject } = {}
local shown: GuidePlan.Entry? = nil
local scene = { cinematic = false, hold = false, hidden = false }
local timeline: { key: any, said: number, tag: string } = { key = nil, said = 0, tag = "" }
local tags = 0

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function side(): string
	return if State.hero.side == "villain" then "villain" else "hero"
end

---------------------------------------------------------------------------
-- Portraits (PLACEHOLDER ART: frames in the speaker's colours)
---------------------------------------------------------------------------

local function piece(
	parent: Instance,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	round: number?
)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Active = false
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

local function buildPortrait(who: string, sp: any): Frame
	local p = sp.portrait
	local frame = Instance.new("Frame")
	frame.Name = "Portrait_" .. who
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = rgb(p.bg)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local skin, hair = rgb(p.skin), rgb(p.hair)
	local dark = Color3.fromRGB(24, 26, 34)
	-- shoulders in the speaker's colour, then the head
	piece(frame, 0.5, 1.02, 0.95, 0.36, rgb(sp.color), 0.3)
	if p.shape == "hood" then
		piece(frame, 0.5, 0.56, 0.78, 0.86, hair, 0.45)
	end
	piece(frame, 0.5, 0.55, 0.54, 0.58, if p.shape == "hood" then skin:Lerp(dark, 0.55) else skin, 0.45)
	-- hair
	if p.shape == "slick" then
		piece(frame, 0.5, 0.3, 0.58, 0.18, hair, 0.5)
	elseif p.shape == "messy" then
		piece(frame, 0.5, 0.3, 0.6, 0.2, hair, 0.5)
		piece(frame, 0.32, 0.24, 0.16, 0.14, hair, 0.5)
		piece(frame, 0.66, 0.23, 0.16, 0.14, hair, 0.5)
	elseif p.shape == "helmet" then
		piece(frame, 0.5, 0.36, 0.64, 0.36, hair, 0.35)
	end
	-- eyes
	piece(
		frame,
		0.4,
		0.55,
		0.07,
		0.07,
		if p.shape == "hood" then Color3.fromRGB(240, 240, 255) else dark,
		0.5
	)
	piece(
		frame,
		0.6,
		0.55,
		0.07,
		0.07,
		if p.shape == "hood" then Color3.fromRGB(240, 240, 255) else dark,
		0.5
	)
	for _, extra in p.extras do
		if extra == "beard" then
			piece(frame, 0.5, 0.76, 0.46, 0.18, hair, 0.45)
		elseif extra == "scar" then
			local s = piece(frame, 0.62, 0.52, 0.03, 0.18, Color3.fromRGB(170, 90, 80))
			s.Rotation = 20
		elseif extra == "star" then
			local s = piece(frame, 0.22, 0.9, 0.12, 0.12, Color3.fromRGB(255, 200, 60))
			s.Rotation = 45
		elseif extra == "cap" then
			piece(frame, 0.5, 0.26, 0.6, 0.14, rgb(sp.color):Lerp(dark, 0.3), 0.4)
			piece(frame, 0.7, 0.32, 0.34, 0.05, rgb(sp.color):Lerp(dark, 0.45), 0.5)
		elseif extra == "headset" then
			piece(frame, 0.22, 0.55, 0.08, 0.2, dark, 0.4)
			piece(frame, 0.32, 0.72, 0.2, 0.04, dark, 0.5)
		elseif extra == "tie" then
			piece(frame, 0.5, 0.92, 0.22, 0.14, Color3.fromRGB(245, 245, 245), 0.2)
			piece(frame, 0.5, 0.95, 0.07, 0.16, Color3.fromRGB(170, 30, 40))
		elseif extra == "mask" then
			piece(frame, 0.5, 0.55, 0.56, 0.12, Color3.fromRGB(230, 180, 40), 0.4)
		elseif extra == "visor" then
			piece(frame, 0.5, 0.55, 0.56, 0.1, Color3.fromRGB(255, 70, 70), 0.4)
		elseif extra == "crown" then
			-- the Harvest King's crown of wheat (chain 4): a gold band and three points
			local gold = Color3.fromRGB(230, 190, 60)
			piece(frame, 0.5, 0.24, 0.5, 0.08, gold, 0.2)
			for i = -1, 1 do
				local pt = piece(frame, 0.5 + i * 0.17, 0.17, 0.08, 0.1, gold)
				pt.Rotation = 45
			end
		elseif extra == "strawhat" then
			-- Farmer Dot's straw hat (chain 4): a wide brim and a crown with a band
			local straw = Color3.fromRGB(230, 200, 120)
			piece(frame, 0.5, 0.3, 0.86, 0.07, straw, 0.5)
			piece(frame, 0.5, 0.22, 0.46, 0.14, straw, 0.4)
			piece(frame, 0.5, 0.27, 0.46, 0.04, Color3.fromRGB(170, 50, 40))
		end
	end
	-- a radio voice's static: faint bars over the portrait (they flicker unless Reduce flashing is on)
	if sp.style == "radio" then
		local st = Instance.new("Frame")
		st.Name = "Static"
		st.Size = UDim2.fromScale(1, 1)
		st.BackgroundTransparency = 1
		st.Parent = frame
		for i = 0, 4 do
			local bar = piece(st, 0.5, 0.1 + i * 0.2, 1, 0.05, Color3.fromRGB(200, 240, 255))
			bar.BackgroundTransparency = 0.8
		end
		statics[who] = st
	end
	frame.Parent = portraitHolder
	return frame
end

local function portraitFor(who: string, sp: any): Frame
	local f = portraits[who]
	if not f then
		f = buildPortrait(who, sp)
		portraits[who] = f
	end
	return f
end

---------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------

local function build()
	gui = Kit.screen("GuideHud", 8)
	box = Kit.frame({
		Name = "Guide",
		Size = UDim2.fromOffset(G.box.maxW, G.box.h),
		BackgroundColor3 = Kit.color.ink,
		BackgroundTransparency = 0.18,
		Visible = false,
		ZIndex = 32,
	})
	box.Active = false
	box.Parent = gui
	portraitHolder = Instance.new("Frame")
	portraitHolder.Name = "Portrait"
	portraitHolder.BackgroundTransparency = 1
	portraitHolder.ZIndex = 33
	portraitHolder.Parent = box
	nameLabel = Kit.label({
		Name = "Speaker",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 18,
		ZIndex = 33,
	})
	nameLabel.Parent = box
	tagLabel = Kit.label({
		Name = "Tag",
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		maxText = 13,
		ZIndex = 33,
	})
	tagLabel.Parent = box
	textLabel = Kit.label({
		Name = "Line",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 17,
		ZIndex = 33,
	})
	textLabel.Parent = box
	-- the whole box skips to the next line (only where it is clear of the move stick)
	skipButton = Instance.new("TextButton")
	skipButton.Name = "Skip"
	skipButton.Text = ""
	skipButton.BackgroundTransparency = 1
	skipButton.AutoButtonColor = false
	skipButton.Size = UDim2.fromScale(1, 1)
	skipButton.ZIndex = 34
	skipButton.Parent = box
	skipButton.Activated:Connect(function()
		GuidePlan.skip(Q)
	end)
end

-- The story trackers and cards the box keeps clear of when they show
local function extras(): { any }
	local out = {}
	local origin = gui.AbsolutePosition
	for _, f in clear do
		if f.Visible and f.Parent then
			local p, s = f.AbsolutePosition - origin, f.AbsoluteSize
			table.insert(out, { x = p.X, y = p.Y, w = s.X, h = s.Y })
		end
	end
	return out
end

local function layout()
	local a = Kit.area()
	local b = GuidePlan.box(Config, a.X, a.Y, Kit.hudOptions(), scene.cinematic, extras())
	box.Position = UDim2.fromOffset(b.x, b.y)
	box.Size = UDim2.fromOffset(b.w, b.h)
	skipButton.Visible = b.tap
	skipButton.Active = b.tap
	local compact = Kit.compact()
	local ps = if compact then G.box.portrait - 12 else G.box.portrait
	portraitHolder.Position = UDim2.fromOffset(8, 8)
	portraitHolder.Size = UDim2.fromOffset(ps, ps)
	local left = ps + 16
	nameLabel.Position = UDim2.fromOffset(left, 5)
	nameLabel.Size = UDim2.new(1, -left - 74, 0, 20)
	tagLabel.Position = UDim2.new(1, -8, 0, 6)
	tagLabel.Size = UDim2.fromOffset(66, 16)
	textLabel.Position = UDim2.fromOffset(left, 27)
	textLabel.Size = UDim2.new(1, -left - 8, 1, -32)
end

local function show(e: GuidePlan.Entry)
	local sp = GuidePlan.speaker(Config, e.who) or G.speakers.crane
	shown = e
	for who, f in portraits do
		f.Visible = who == e.who
	end
	portraitFor(e.who, sp).Visible = true
	nameLabel.Text = sp.name
	nameLabel.TextColor3 = rgb(sp.color)
	local tag = G.tags[sp.style]
	tagLabel.Visible = tag ~= nil
	tagLabel.Text = tag or ""
	tagLabel.TextColor3 = if sp.style == "broadcast" then Color3.fromRGB(255, 90, 80) else rgb(sp.color)
	textLabel.Text = e.text
	local stroke = box:FindFirstChildOfClass("UIStroke")
	if not stroke then
		Kit.stroke(box, rgb(sp.color), 2)
	else
		stroke.Color = rgb(sp.color)
	end
	layout()
	box.Visible = true
	if not SettingsClient.on("reduceFlashing") then
		Kit.pulse(box, 0.12)
	end
	AudioController.play(sp.blip)
end

local function frame()
	local now = os.clock()
	local paused = scene.hold or scene.cinematic or scene.hidden
	local started = GuidePlan.tick(Config, Q, now, paused)
	if started then
		show(started)
	elseif not Q.current and shown then
		shown = nil
		box.Visible = false
	end
	box.Visible = shown ~= nil and not scene.hidden
	-- a radio voice's static flickers (steady with Reduce flashing)
	local cur = shown
	local st = cur and statics[cur.who]
	if st then
		local calm = SettingsClient.on("reduceFlashing")
		for i, bar in st:GetChildren() do
			if bar:IsA("Frame") then
				bar.BackgroundTransparency = if calm
					then 0.85
					else 0.72 + 0.2 * math.abs(math.sin(now * 9 + i * 1.7))
			end
		end
	end
end

---------------------------------------------------------------------------
-- The API
---------------------------------------------------------------------------

-- Queue a fixed line (text from Config.Story only). opts: world (Patch's open-world radio), cut (takes the
-- box at once), hold (seconds), tag. Returns whether it was queued.
function GuideHud.say(who: string, text: string, opts: { [string]: any }?): boolean
	if not GuidePlan.speaker(Config, who) or type(text) ~= "string" or text == "" then
		return false
	end
	local o = opts or {}
	return GuidePlan.push(
		Q,
		{ who = who, text = text, world = o.world, cut = o.cut, hold = o.hold, tag = o.tag },
		os.clock()
	)
end

-- A beat's timed lines ({ at, who, text }) at t seconds in, each frame while it runs; key names the beat
-- (any value; nil when no beat runs). A new beat drops the old one's line.
function GuideHud.timeline(key: any, list: { any }?, t: number)
	if key ~= timeline.key then
		if timeline.key ~= nil then
			GuidePlan.cancel(Q, timeline.tag)
		end
		tags += 1
		timeline = { key = key, said = 0, tag = "beat" .. tags }
	end
	if key == nil or not list then
		return
	end
	local items = list :: { any }
	local idx, hold = GuidePlan.due(Config, items, t, timeline.said)
	if idx then
		timeline.said = idx
		local l = items[idx]
		if hold then
			GuideHud.say(l.who, l.text, { cut = true, hold = hold, tag = timeline.tag })
		end
	end
end

-- What the story screens are doing: cinematic (a camera beat: the box goes under the letterbox), hold (the
-- prologue or a mission: open-world lines wait), hidden (a full-screen broadcast: the box steps away)
function GuideHud.setScene(cinematic: boolean, hold: boolean, hidden: boolean?)
	local h = hidden == true
	if scene.cinematic ~= cinematic or scene.hold ~= hold or scene.hidden ~= h then
		scene = { cinematic = cinematic, hold = hold, hidden = h }
		if shown then
			layout()
		end
	end
end

-- Keep the box clear of this frame while it shows (the story trackers)
function GuideHud.keepClear(f: GuiObject)
	table.insert(clear, f)
end

-- Drop a tag's lines (GuideClient's stage lines when a mission ends)
function GuideHud.cancel(tag: string)
	GuidePlan.cancel(Q, tag)
end

-- Skip the line showing
function GuideHud.skip()
	GuidePlan.skip(Q)
end

-- The line showing, or nil
function GuideHud.current(): GuidePlan.Entry?
	return Q.current
end

-- Dev panel: play the speaker's first line in the game for this side
function GuideHud.sample(who: string): boolean
	for _, e in GuidePlan.lines(Config) do
		if e.line.who == who then
			local text = GuidePlan.lineText(e.line, side())
			if text then
				return GuideHud.say(who, text, { cut = true })
			end
		end
	end
	return false
end

function GuideHud.init()
	build()
	Kit.LayoutChanged:Connect(function()
		if shown then
			layout()
		end
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("GuideHud", frame))
end

return GuideHud
