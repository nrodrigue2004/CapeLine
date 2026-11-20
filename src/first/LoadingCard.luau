-- LoadingCard (ReplicatedFirst): the comic splash the loading screen shows (gap polish 2026-11-19; it was a title
-- on a night gradient). The PURE COMIC UI look of Kit (Config.Ui.ink: 3 px ink outlines, hard 4 px ink drop
-- shadows, cream paper and navy panels, faint halftone dots, Bangers display text outlined in ink) drawn here
-- with plain instances, because ReplicatedFirst runs before ReplicatedStorage is there: no requires at all,
-- the few colours and numbers copied from Config.Ui (keep them in step). Built by LoadingScreen; tests/uishot
-- renders it ("loading" scene).
-- The card: a navy page with halftone dots and a gold sunburst, the CAPELINE logo (gold Bangers with a thick ink
-- outline and an ink drop shadow, a little tilted), a red caption box, the spinning volt spark, the status line
-- and a cream TIP panel whose tip changes every few seconds.

local LoadingCard = {}

-- copied from Config.Ui (colors, ink) so ReplicatedFirst needs nothing else
local INK = Color3.fromRGB(17, 17, 17)
local PAPER = Color3.fromRGB(255, 247, 224)
local NIGHT = Color3.fromRGB(31, 42, 68)
local GOLD = Color3.fromRGB(255, 210, 60)
local RED = Color3.fromRGB(255, 77, 77)
local VOLT = Color3.fromRGB(120, 210, 255)
local STROKE = 3
local SHADOW = 4
local HALFTONE = "rbxassetid://89303571654854"

-- the music that starts the moment the card shows (list-combat 2026-11-20, nate: loading "that doesn't feel like
-- waiting": the city and sound at once): the day patrol from the Music atlas (copied from Config.AudioClips,
-- tests/intro_film_test keeps it in step), at the default music level (Config.Settings music 2 of 10) until the
-- saved setting takes over; LoadingScreen fades it out as the game's own music starts
-- the drawn CAPELINE logo (Everything Left 85; art/ui/logo.py, preview art/preview/logo.png, DRAFT until nate OKs
-- it): shown over the typed Bangers title once the image has loaded (the typed one stays if it never does).
-- Config.Ui.logo holds the same id for the main menu.
LoadingCard.LOGO = 138065040749947

LoadingCard.MUSIC = { atlas = 112969623640373, start = 0.05, length = 34.2857, volume = 0.35, group = 0.2 }

-- the skyline along the foot of the card: Brightharbor's towers in two layers drifting past (heights as a share
-- of the strip, widths as a share of one screen; each layer is two copies side by side so it loops)
LoadingCard.SKYLINE = {
	far = { 0.55, 0.8, 0.45, 0.95, 0.6, 0.7, 1, 0.5, 0.75, 0.62, 0.88, 0.48 },
	near = { 0.4, 0.62, 0.3, 0.78, 0.5, 0.36, 0.7, 0.44, 0.58, 0.34 },
}

-- short, true tips about the game (no free text; one at a time on the TIP panel)
LoadingCard.TIPS = {
	"Touch a beacon to find it. Found beacons let you fly across the city from the map.",
	"Hold Leap after the top of a jump to glide.",
	"Every building can come down. Hit hard enough and the wall gives way.",
	"PvP is your choice: raise the PVP flag only when you want a fight.",
	"A world boss wakes every 20 to 30 minutes. Everyone who helps gets a reward.",
	"Your gadget slot holds a Grappling Hook, Smoke Bomb, Shield Drone or Decoy.",
	"Bank your Credits at a safehouse so they are safe from a PvP defeat.",
	"Fill your Awakening meter in a fight, then let it loose.",
	"A Downed friend can be revived. Get to them before they give up!",
	"Side quests start from the people with a gold marker over their heads.",
}

local function stroke(g: GuiObject, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = thickness or STROKE
	s.ApplyStrokeMode = if g:IsA("TextLabel")
		then Enum.ApplyStrokeMode.Contextual
		else Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.Parent = g
	return s
end

-- a panel with its ink outline and hard ink drop shadow (the shadow is a sibling drawn just behind it)
local function panel(
	parent: Instance,
	color: Color3,
	pos: UDim2,
	size: UDim2,
	anchor: Vector2,
	z: number
): (Frame, Frame)
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = anchor
	shadow.Position = pos + UDim2.fromOffset(SHADOW + STROKE, SHADOW + STROKE)
	shadow.Size = size
	shadow.BackgroundColor3 = INK
	shadow.BorderSizePixel = 0
	shadow.ZIndex = z
	shadow.Parent = parent
	local f = Instance.new("Frame")
	f.AnchorPoint = anchor
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z + 1
	stroke(f)
	f.Parent = parent
	return f, shadow
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextScaled = true
	for k, v in props do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

export type Card = {
	root: CanvasGroup,
	logo: TextLabel,
	status: TextLabel,
	tip: TextLabel,
	spark: Frame,
	pop: UIScale,
	setTip: (i: number) -> (),
	layers: { Frame },
	streak: Frame,
}

-- One skyline layer: towers with lit windows, two copies wide so a pan of one screen loops seamlessly
local function skylineLayer(root: Instance, heights: { number }, color: Color3, lit: number, z: number): Frame
	local layer = Instance.new("Frame")
	layer.Name = "Skyline"
	layer.BackgroundTransparency = 1
	layer.AnchorPoint = Vector2.new(0, 1)
	layer.Position = UDim2.fromScale(0, 1)
	layer.Size = UDim2.fromScale(2, 0.42)
	layer.ZIndex = z
	layer.Parent = root
	local n = #heights
	local w = 0.5 / n
	for copy = 0, 1 do
		for i, h in heights do
			local b = Instance.new("Frame")
			b.Name = "Tower"
			b.AnchorPoint = Vector2.new(0, 1)
			b.Position = UDim2.fromScale(copy * 0.5 + (i - 1) * w, 1)
			b.Size = UDim2.fromScale(w * (0.82 + (i % 3) * 0.09), h)
			b.BackgroundColor3 = color
			b.BorderSizePixel = 0
			b.ZIndex = z
			b.Parent = layer
			-- a few lit windows (gold squares), the same on both copies
			for k = 1, lit do
				if (i * 7 + k * 3) % 4 ~= 0 then
					local win = Instance.new("Frame")
					win.Name = "Window"
					win.AnchorPoint = Vector2.new(0.5, 0.5)
					win.Position = UDim2.fromScale(0.25 + ((i + k) % 3) * 0.25, 0.12 + k * (0.8 / (lit + 1)))
					win.Size = UDim2.fromScale(0.14, 0.035)
					win.BackgroundColor3 = GOLD
					win.BackgroundTransparency = 0.25 + ((i + k) % 2) * 0.3
					win.BorderSizePixel = 0
					win.ZIndex = z
					win.Parent = b
				end
			end
		end
	end
	return layer
end

function LoadingCard.build(parent: Instance): Card
	local root = Instance.new("CanvasGroup")
	root.Name = "Card"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = NIGHT
	root.BorderSizePixel = 0
	root.Parent = parent

	-- halftone dots over the whole page
	local dots = Instance.new("ImageLabel")
	dots.Name = "Halftone"
	dots.BackgroundTransparency = 1
	dots.Size = UDim2.fromScale(1, 1)
	dots.Image = HALFTONE
	dots.ImageColor3 = Color3.new(1, 1, 1)
	dots.ImageTransparency = 0.9
	dots.ScaleType = Enum.ScaleType.Tile
	dots.TileSize = UDim2.fromOffset(14, 14)
	dots.ZIndex = 1
	dots.Parent = root

	-- a gold sunburst behind the logo: thin rays round the logo's centre, every other one ink
	local burst = Instance.new("Frame")
	burst.Name = "Burst"
	burst.BackgroundTransparency = 1
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.32)
	burst.Size = UDim2.fromScale(2.4, 2.4)
	burst.ZIndex = 2
	burst.Parent = root
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = burst
	for i = 0, 15 do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(0.035, 1)
		ray.Rotation = i * 11.25
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = if i % 2 == 0 then GOLD else VOLT
		ray.BackgroundTransparency = if i % 2 == 0 then 0.8 else 0.88
		ray.ZIndex = 2
		-- each ray fades out toward its ends, so the burst glows behind the logo and melts into the page
		local fadeOut = Instance.new("UIGradient")
		fadeOut.Rotation = 90
		fadeOut.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fadeOut.Parent = ray
		ray.Parent = burst
	end

	-- the city along the foot (behind the TIP panel): a far layer in dusk blue, a near one in ink, and a hero's
	-- gold streak across the sky (the cold open's first shot, in the comic's own style)
	local far = skylineLayer(root, LoadingCard.SKYLINE.far, Color3.fromRGB(52, 68, 106), 3, 2)
	local near = skylineLayer(root, LoadingCard.SKYLINE.near, Color3.fromRGB(20, 24, 38), 4, 2)
	near.Size = UDim2.fromScale(2, 0.3)
	local streak = Instance.new("Frame")
	streak.Name = "Streak"
	streak.AnchorPoint = Vector2.new(1, 0.5)
	streak.Position = UDim2.fromScale(-0.2, 0.66)
	streak.Size = UDim2.fromScale(0.22, 0.012)
	streak.Rotation = -6
	streak.BackgroundColor3 = GOLD
	streak.BorderSizePixel = 0
	streak.ZIndex = 2
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new(1, 0)
	fade.Parent = streak
	streak.Parent = root

	-- the logo: an ink drop-shadow copy behind the gold title, both tilted a little
	local logoBox = Instance.new("Frame")
	logoBox.Name = "Logo"
	logoBox.BackgroundTransparency = 1
	logoBox.AnchorPoint = Vector2.new(0.5, 0.5)
	logoBox.Position = UDim2.fromScale(0.5, 0.29)
	logoBox.Size = UDim2.fromScale(0.74, 0.2)
	logoBox.Rotation = -4
	logoBox.ZIndex = 3
	logoBox.Parent = root
	local pop = Instance.new("UIScale")
	pop.Scale = 1
	pop.Parent = logoBox
	local shade = text(logoBox, {
		Name = "LogoShadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(7, 7),
		Font = Enum.Font.Bangers,
		Text = "CAPELINE",
		TextColor3 = INK,
		ZIndex = 3,
	})
	stroke(shade, 6)
	local logo = text(logoBox, {
		Name = "LogoText",
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.Bangers,
		Text = "CAPELINE",
		TextColor3 = GOLD,
		ZIndex = 4,
	})
	stroke(logo, 6)
	if LoadingCard.LOGO ~= 0 then
		local drawn = Instance.new("ImageLabel")
		drawn.Name = "LogoImage"
		drawn.BackgroundTransparency = 1
		drawn.AnchorPoint = Vector2.new(0.5, 0.5)
		drawn.Position = UDim2.fromScale(0.5, 0.5)
		drawn.Size = UDim2.fromScale(1.15, 2.2) -- the word fills about 85% of the image's width
		drawn.ScaleType = Enum.ScaleType.Fit
		drawn.Image = "rbxassetid://" .. LoadingCard.LOGO
		drawn.ImageTransparency = 1
		drawn.ZIndex = 5
		drawn.Parent = logoBox
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({ drawn })
			end)
			if drawn.IsLoaded then
				drawn.ImageTransparency = 0
				shade.Visible = false
				logo.Visible = false
			end
		end)
	end

	-- the red caption box under it
	local cap, capShadow =
		panel(root, RED, UDim2.fromScale(0.5, 0.45), UDim2.fromScale(0.5, 0.07), Vector2.new(0.5, 0.5), 5)
	cap.Name = "Caption"
	cap.Rotation = 2
	text(cap, {
		Name = "CaptionText",
		Size = UDim2.new(1, -40, 1, -10),
		Position = UDim2.fromOffset(20, 5),
		Font = Enum.Font.Bangers,
		Text = "HEROES. VILLAINS. ONE CITY.",
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 7,
	})
	capShadow.Rotation = 2

	-- the spinning volt spark and the status line
	local spark = Instance.new("Frame")
	spark.Name = "Spark"
	spark.AnchorPoint = Vector2.new(0.5, 0.5)
	spark.Position = UDim2.fromScale(0.5, 0.575)
	spark.Size = UDim2.fromOffset(20, 20)
	spark.BackgroundColor3 = VOLT
	spark.BorderSizePixel = 0
	spark.Rotation = 45
	spark.ZIndex = 6
	stroke(spark)
	spark.Parent = root
	local status = text(root, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.61),
		Size = UDim2.fromScale(0.6, 0.045),
		Font = Enum.Font.Bangers,
		Text = "LOADING THE CITY",
		TextColor3 = PAPER,
		ZIndex = 6,
	})
	stroke(status, 2)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 24
	limit.MinTextSize = 10
	limit.Parent = status

	-- the cream TIP panel at the foot
	local tipBox, tipShadow =
		panel(root, PAPER, UDim2.new(0.5, 0, 1, -22), UDim2.new(0.8, 0, 0.18, 0), Vector2.new(0.5, 1), 5)
	tipBox.Name = "Tip"
	for _, f in { tipBox, tipShadow } do
		local size = Instance.new("UISizeConstraint")
		size.MaxSize = Vector2.new(720, 74)
		size.Parent = f
	end
	local tipDots = dots:Clone()
	tipDots.ImageColor3 = INK
	tipDots.ImageTransparency = 0.9
	tipDots.ZIndex = 6
	tipDots.Parent = tipBox
	local tag, tagShadow =
		panel(tipBox, RED, UDim2.fromOffset(12, -14), UDim2.fromOffset(58, 28), Vector2.zero, 7)
	tag.Name = "TipTag"
	tag.Rotation = -3
	tagShadow.Rotation = -3
	text(tag, {
		Name = "TipTagText",
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.Bangers,
		Text = "TIP!",
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 9,
	})
	local tip = text(tipBox, {
		Name = "TipText",
		Position = UDim2.fromOffset(16, 18),
		Size = UDim2.new(1, -32, 1, -26),
		Font = Enum.Font.GothamBold,
		Text = LoadingCard.TIPS[1],
		TextColor3 = INK,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 8,
	})
	local tipLimit = Instance.new("UITextSizeConstraint")
	tipLimit.MaxTextSize = 20
	tipLimit.MinTextSize = 9
	tipLimit.Parent = tip

	local card: Card = {
		root = root,
		logo = logo,
		status = status,
		tip = tip,
		spark = spark,
		pop = pop,
		layers = { far, near },
		streak = streak,
		setTip = function(i: number)
			local n = #LoadingCard.TIPS
			tip.Text = LoadingCard.TIPS[(i - 1) % n + 1]
		end,
	}
	return card
end

return LoadingCard
