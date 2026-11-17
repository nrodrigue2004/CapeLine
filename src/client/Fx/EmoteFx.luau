-- EmoteFx: emotes and landing poses for everyone (spec: Robux Shop "Emotes"; Fame rank emotes; the landing
-- pose on a big fall). The server sets the player's Emote attribute (id x 1000 + a sequence) and every
-- device poses that hero for Config.Shop.emoteTime seconds.
-- * Poses are joint angles tweened onto the rig's Motor6D C0s (the Animator writes Transform, so walking
--   still blends underneath) and tweened back after. PLACEHOLDER ART: real animations in the M11 pass.
-- * EMOTE (H) opens a small picker of the emotes you own. A fall faster than LANDING_SPEED plays your
--   equipped landing pose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Kit = require(script.Parent.Parent.Ui.Kit)
local State = require(script.Parent.Parent.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local MoveController = require(script.Parent.Parent.Controllers.MoveController)

local EmoteFx = {}

local S = Config.Shop
local T = Config.Ui.touchTarget
local LANDING_SPEED = 70 -- studs per second of fall that counts as a big landing

-- joint -> { x, y, z } degrees; the joints are the R15 Motor6D names
type Pose = { [string]: { number } }
local POSES: { [number]: Pose } = {
	[1] = { RightShoulder = { 0, 0, 150 }, RightElbow = { 0, 0, 110 }, Neck = { -5, 0, 0 } }, -- Salute
	[2] = { Waist = { -45, 0, 0 }, Neck = { -20, 0, 0 }, RightShoulder = { -30, 0, 0 } }, -- Bow
	[3] = { RightShoulder = { 0, 0, 160 }, RightElbow = { 0, 0, 30 } }, -- Wave
	[4] = { RightShoulder = { 70, 0, 0 }, RightElbow = { 80, 0, 0 } }, -- Thumbs Up
	[5] = {
		RightShoulder = { 0, 0, 90 },
		LeftShoulder = { 0, 0, -90 },
		RightElbow = { 0, 0, 100 },
		LeftElbow = { 0, 0, -100 },
	}, -- Flex
	[6] = {
		RightShoulder = { 0, 0, 30 },
		LeftShoulder = { 0, 0, -30 },
		Neck = { 10, 20, 0 },
		RightHip = { 0, 0, 12 },
		LeftHip = { 0, 0, -12 },
	}, -- Hero Pose (fists on hips, chin up)
	[7] = { RightShoulder = { 0, 0, 175 }, Neck = { 25, 0, 0 } }, -- Point Up
	[8] = {
		RightShoulder = { 40, 0, 40 },
		LeftShoulder = { 40, 0, -40 },
		Waist = { -15, 0, 0 },
		RightKnee = { -30, 0, 0 },
		LeftKnee = { -30, 0, 0 },
	}, -- Power Up (a crouch, fists clenched)
	[9] = { Waist = { 20, 0, 0 }, Neck = { 30, 0, 0 }, RightShoulder = { 20, 0, 20 } }, -- Laugh
	[10] = { Waist = { 0, 50, 0 }, RightShoulder = { 0, 0, 100 }, LeftShoulder = { 0, 0, -40 } }, -- Cape Swish
	[11] = {
		RightShoulder = { 0, 0, 165 },
		LeftShoulder = { 0, 0, -165 },
		Neck = { 15, 0, 0 },
	}, -- Rookie Cheer
	[20] = {
		Waist = { -35, 0, 0 },
		RightShoulder = { 0, 0, 60 },
		LeftShoulder = { -40, 0, -20 },
		RightHip = { 70, 0, 0 },
		RightKnee = { -100, 0, 0 },
		LeftHip = { -20, 0, 0 },
		LeftKnee = { -60, 0, 0 },
	}, -- Super Landing (one knee, one fist down)
	[21] = {
		Waist = { -20, 0, 0 },
		RightHip = { 80, 0, 0 },
		RightKnee = { -90, 0, 0 },
		LeftKnee = { -80, 0, 0 },
		Neck = { -10, 0, 0 },
	}, -- Kneel Landing
	[22] = { Root = { 0, 180, 0 }, RightShoulder = { 0, 0, 90 }, LeftShoulder = { 0, 0, -90 } }, -- Spin Landing
	[23] = {
		Waist = { -50, 0, 0 },
		RightShoulder = { -60, 0, 20 },
		LeftShoulder = { -60, 0, -20 },
		RightKnee = { -110, 0, 0 },
		LeftKnee = { -110, 0, 0 },
	}, -- Crater Landing (both fists into the ground)
	[24] = {
		RightShoulder = { 0, 0, 45 },
		LeftShoulder = { 0, 0, -45 },
		RightKnee = { -20, 0, 0 },
		Neck = { 10, 0, 0 },
	}, -- Float Down
	-- H6: the mentors' emotes (Config.Mentors)
	[12] = {
		RightShoulder = { 0, 0, 160 },
		RightElbow = { 0, 0, 125 },
		Neck = { -8, 0, 0 },
		LeftShoulder = { 0, 0, -10 },
	}, -- Sharp Salute
	[13] = {
		RightShoulder = { 0, 0, 170 },
		LeftShoulder = { 0, 0, -170 },
		RightElbow = { 0, 0, 20 },
		LeftElbow = { 0, 0, -20 },
	}, -- Big Wave (both arms)
	[14] = {
		Waist = { -60, 0, 0 },
		Neck = { -15, 0, 0 },
		RightShoulder = { 40, 0, 20 },
		LeftShoulder = { -50, 0, -20 },
	}, -- Grand Bow (one arm across, one behind)
	[15] = {
		RightShoulder = { 0, 0, 40 },
		LeftShoulder = { 0, 0, -40 },
		RightElbow = { 0, 0, 90 },
		LeftElbow = { 0, 0, -90 },
		Neck = { 0, 0, 12 },
	}, -- Shrug
	-- Photo Mode's own poses (free, only on your screen while you take a photo; M11)
	[101] = {
		RightShoulder = { 80, 0, 20 },
		LeftShoulder = { 80, 0, -20 },
		RightElbow = { 90, 0, 0 },
		LeftElbow = { 90, 0, 0 },
		RightKnee = { -15, 0, 0 },
	}, -- Ready Stance (fists up)
	[102] = { RightShoulder = { 120, 0, 40 }, RightElbow = { 100, 0, 0 }, Neck = { 10, 15, 0 } }, -- Look Out
	[103] = {
		RightShoulder = { 0, 0, 170 },
		LeftShoulder = { 0, 0, -20 },
		LeftHip = { -25, 0, 0 },
		LeftKnee = { -50, 0, 0 },
	}, -- Take Off (one fist to the sky)
	[104] = { RightShoulder = { 100, 0, 30 }, RightElbow = { 130, 0, 0 }, Neck = { -10, -10, 0 } }, -- Thinking
}

EmoteFx.PHOTO_POSES = { 101, 102, 103, 104 }
EmoteFx.POSE_NAMES = { [101] = "Ready", [102] = "Look Out", [103] = "Take Off", [104] = "Thinking" }

local playing: { [Model]: { seq: number, base: { [Motor6D]: CFrame } } } = {}
local picker: Frame

local function motors(char: Model): { [string]: Motor6D }
	local out = {}
	for _, d in char:GetDescendants() do
		if d:IsA("Motor6D") then
			out[d.Name] = d
		end
	end
	return out
end

local function play(char: Model, id: number, hold: number?)
	local pose = POSES[id]
	if not pose then
		return
	end
	local cur = playing[char]
	local seq = (cur and cur.seq or 0) + 1
	local base = if cur then cur.base else {}
	playing[char] = { seq = seq, base = base }
	local joints = motors(char)
	local info = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for name, m in joints do
		if not base[m] then
			base[m] = m.C0
		end
		local a = pose[name]
		local goal = if a
			then base[m] * CFrame.Angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3]))
			else base[m]
		TweenService:Create(m, info, { C0 = goal }):Play()
	end
	task.delay(hold or S.emoteTime, function()
		local now = playing[char]
		if not now or now.seq ~= seq then
			return
		end
		for m, c0 in base do
			if m.Parent then
				TweenService:Create(m, TweenInfo.new(0.25), { C0 = c0 }):Play()
			end
		end
		playing[char] = nil
	end)
end

local function watch(p: Player)
	p:GetAttributeChangedSignal("Emote"):Connect(function()
		local v = p:GetAttribute("Emote")
		local char = p.Character
		if typeof(v) == "number" and char then
			play(char, v // 1000)
		end
	end)
	p.CharacterRemoving:Connect(function(char)
		playing[char] = nil
	end)
end

local function owned(): { number }
	local out = {}
	for _, id in State.profile.emotes or {} do
		local row = S.emotes[id]
		if row and not row.landing then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- Photo Mode: your owned emotes (others see them) and the free photo poses (only on your screen)
function EmoteFx.ownedEmotes(): { number }
	return owned()
end

function EmoteFx.poseLocal(id: number, hold: number?)
	local char = Players.LocalPlayer.Character
	if char then
		play(char, id, hold)
	end
end

local function drawPicker()
	for _, c in picker:GetChildren() do
		if c:IsA("TextButton") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local list = owned()
	if #list == 0 then
		local l = Kit.label({
			Text = "No emotes yet: earn them with Fame or find them in the SHOP",
			Size = UDim2.new(1, 0, 0, 40),
			TextColor3 = Kit.color.paper,
			Font = Kit.bodyFont,
			TextWrapped = true,
			maxText = 14,
		})
		l.Parent = picker
		return
	end
	for i, id in list do
		local b = Kit.button({
			Text = string.upper(S.emotes[id].name),
			Size = UDim2.new(1, 0, 0, T - 10),
			LayoutOrder = i,
			BackgroundColor3 = Kit.color.paper,
		}, function()
			picker.Visible = false
			Net.send("EmotePlay", id)
		end)
		b.Parent = picker
	end
end

function EmoteFx.toggle()
	picker.Visible = not picker.Visible
	if picker.Visible then
		drawPicker()
	end
end

function EmoteFx.init()
	local gui = Kit.screen("Emotes", 6)
	picker = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -160),
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = picker
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = picker
	picker.Parent = gui
	InputController.Pressed:Connect(function(action)
		if action == "Emote" then
			EmoteFx.toggle()
		end
	end)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	MoveController.Landed:Connect(function(_, fallSpeed)
		local landing = State.profile.landing or 0
		if landing > 0 and (fallSpeed or 0) >= LANDING_SPEED then
			Net.send("EmotePlay", landing)
		end
	end)
end

return EmoteFx
