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
local EmotePoses = require(Shared:WaitForChild("EmotePoses"))

local Kit = require(script.Parent.Parent.Ui.Kit)
local Thumb = require(script.Parent.Parent.Ui.Thumb)
local State = require(script.Parent.Parent.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local HeroAnimator = require(script.Parent.Parent.Controllers.HeroAnimator)

local EmoteFx = {}

local S = Config.Shop
local T = Config.Ui.touchTarget
local LANDING_SPEED = 70 -- studs per second of fall that counts as a big landing

-- joint -> { x, y, z } degrees; the joints are the R15 Motor6D names (Shared.EmotePoses: the picture tiles render
-- the same table)
type Pose = EmotePoses.Pose
local POSES: { [number]: Pose } = EmotePoses.POSES

EmoteFx.PHOTO_POSES = EmotePoses.PHOTO_POSES
EmoteFx.POSE_NAMES = EmotePoses.POSE_NAMES

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
			HeroAnimator.emote(p, S.emoteTime) -- it breathes and bounces under the held pose
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
		-- the pose's picture at the left (2026-11-19), words only while its sheet is not uploaded
		Thumb.side(b, Thumb.emote(id), string.upper(S.emotes[id].name))
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
