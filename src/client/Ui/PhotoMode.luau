-- PhotoMode: take a picture of your hero (spec: Social table "Photo Mode | Pose button, hide-UI toggle,
-- backdrop. Nothing is recorded"; juice row Photo "Shutter | Hero pose | Flash only if reduce flashing is
-- off"). PHOTO (top left, or N; K is the Task Force board) opens it anywhere but the opening, a cutscene or
-- Downed (and a cutscene or going Downed closes it):
-- * the hero holds still and the camera orbits them: drag (or the right stick) to turn, scroll, pinch or
--   the triggers to zoom;
-- * POSE steps through the free photo poses (only on your screen) and the emotes you own (everyone sees);
-- * LOOK steps through backdrops: none, a comic frame, speed lines, sunset, noir and neon pop;
-- * HIDE UI hides every button (tap anywhere to bring them back) so the screenshot is clean;
-- * SNAP plays the shutter (and a flash unless reduce flashing is on). Nothing is saved or uploaded: the
--   player takes the screenshot with their device.
-- PLACEHOLDER ART: Kit buttons and flat overlay frames until the art pass.

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Kit = require(script.Parent.Kit)
local Thumb = require(script.Parent.Thumb)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local EmoteFx = require(script.Parent.Parent.Fx.EmoteFx)
local Juice = require(script.Parent.Parent.Fx.Juice)
local Telemetry = require(script.Parent.Parent.Controllers.Telemetry)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local PvpClient = require(script.Parent.Parent.Controllers.PvpClient)

local PhotoMode = {}

PhotoMode.reduce = false -- Settings: reduce flashing (no SNAP flash)
-- The keyboard key that opens and closes it (K was the Task Force board too: InputController)
PhotoMode.KEY = Enum.KeyCode.N

local U = Config.Ui
local T = U.touchTarget
local player = Players.LocalPlayer

local BACKDROPS = { "NONE", "COMIC", "SPEED", "SUNSET", "NOIR", "NEON" }

local gui: ScreenGui
local openButton: TextButton
local bar: Frame
local overlay: Frame
local flash: Frame
local poseButton: TextButton
local lookButton: TextButton
local open = false
local hidden: { ScreenGui } = {}
local yaw, pitch, dist = 0, 0.15, 12
local poseAt = 0
local lookAt = 1
local grade: ColorCorrectionEffect? = nil
local dragging: InputObject? = nil
local lastPinch: number? = nil

local function root(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function poses(): { number }
	local list = table.clone(EmoteFx.PHOTO_POSES)
	for _, id in EmoteFx.ownedEmotes() do
		table.insert(list, id)
	end
	return list
end

local function poseName(id: number): string
	local row = Config.Shop.emotes[id]
	return EmoteFx.POSE_NAMES[id] or (row and row.name) or ("Pose " .. id)
end

local function clearOverlay()
	for _, c in overlay:GetChildren() do
		c:Destroy()
	end
	if grade then
		grade:Destroy()
		grade = nil
	end
end

local function colour(brightness: number, contrast: number, saturation: number, tint: Color3)
	local g = Instance.new("ColorCorrectionEffect")
	g.Name = "PhotoGrade"
	g.Brightness = brightness
	g.Contrast = contrast
	g.Saturation = saturation
	g.TintColor = tint
	g.Parent = Lighting
	grade = g
end

local function backdrop(name: string)
	clearOverlay()
	if name == "COMIC" then
		-- a thick comic-page frame with a caption box
		local frameEdge = Kit.frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			round = false,
		})
		Kit.stroke(frameEdge, Kit.color.ink, 18)
		frameEdge.Parent = overlay
		local cap = Kit.label({
			Text = string.upper(tostring(player:GetAttribute("HeroName") or player.DisplayName)),
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(28, 28),
			Size = UDim2.fromOffset(260, 46),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(255, 236, 140),
			TextColor3 = Kit.color.ink,
			maxText = 34,
		})
		Kit.stroke(cap, Kit.color.ink, 3)
		cap.Parent = overlay
		colour(0.02, 0.2, 0.25, Color3.new(1, 1, 1))
	elseif name == "SPEED" then
		-- anime speed lines from the edges toward the hero
		for i = 1, 28 do
			local a = i / 28 * math.pi * 2
			local l = Kit.frame({
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0.5 + math.cos(a) * 0.36, 0.5 + math.sin(a) * 0.36),
				Size = UDim2.fromOffset(500, if i % 3 == 0 then 4 else 2),
				Rotation = math.deg(a),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.35,
				round = false,
			})
			l.Parent = overlay
		end
	elseif name == "SUNSET" then
		colour(0.03, 0.1, 0.15, Color3.fromRGB(255, 205, 170))
	elseif name == "NOIR" then
		colour(-0.02, 0.35, -1, Color3.new(1, 1, 1))
	elseif name == "NEON" then
		colour(0.05, 0.25, 0.7, Color3.fromRGB(220, 230, 255))
	end
end

local function setBar(visible: boolean)
	bar.Visible = visible
end

local function close()
	if not open then
		return
	end
	open = false
	RunService:UnbindFromRenderStep("CapelinePhoto")
	ContextActionService:UnbindAction("CapelinePhotoZoom")
	InputController.freeze(false)
	clearOverlay()
	overlay.Visible = false
	bar.Visible = false
	openButton.Visible = true
	for _, g in hidden do
		if g.Parent then
			g.Enabled = true
		end
	end
	hidden = {}
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
end
PhotoMode.close = close

function PhotoMode.open()
	local r = root()
	-- never during a cutscene (it owns the camera) or while Downed (the Downed screen must stay up)
	if
		open
		or not r
		or StoryClient.inOpening()
		or CinemaClient.playing()
		or PvpClient.downed()
		or PvpClient.down.downed
	then
		return
	end
	open = true
	InputController.freeze(true)
	-- hide every other screen (kept to bring back the same ones)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	for _, g in if pg then pg:GetChildren() else {} do
		if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
	openButton.Visible = false
	overlay.Visible = true
	bar.Visible = true
	local cam = Workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	-- start in front of the hero, looking back at them
	yaw = math.atan2(-look.X, -look.Z) + math.pi
	pitch, dist = 0.15, 12
	cam.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(
		"CapelinePhoto",
		Enum.RenderPriority.Camera.Value + 3,
		FrameProf.wrap("PhotoMode", function(dt)
			local rr = root()
			if not rr then
				close()
				return
			end
			-- the gamepad's right stick turns; the triggers zoom
			for _, st in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
				if st.KeyCode == Enum.KeyCode.Thumbstick2 and st.Position.Magnitude > 0.15 then
					yaw -= st.Position.X * dt * 2.4
					pitch = math.clamp(pitch + st.Position.Y * dt * 1.6, -0.6, 1.2)
				elseif st.KeyCode == Enum.KeyCode.ButtonR2 and st.Position.Z > 0.1 then
					dist = math.clamp(dist - dt * 14 * st.Position.Z, 4, 40)
				elseif st.KeyCode == Enum.KeyCode.ButtonL2 and st.Position.Z > 0.1 then
					dist = math.clamp(dist + dt * 14 * st.Position.Z, 4, 40)
				end
			end
			local focus = rr.Position + Vector3.new(0, 1.5, 0)
			local offset = CFrame.Angles(0, yaw, 0) * CFrame.Angles(-pitch, 0, 0) * Vector3.new(0, 0, dist)
			cam.CFrame = CFrame.lookAt(focus + offset, focus)
		end)
	)
	ContextActionService:BindAction("CapelinePhotoZoom", function(_, state, input)
		if state == Enum.UserInputState.Change and input.UserInputType == Enum.UserInputType.MouseWheel then
			dist = math.clamp(dist - input.Position.Z * 1.5, 4, 40)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseWheel)
	backdrop(BACKDROPS[lookAt])
end

local function snap()
	Juice.fire("photo")
	Telemetry.note("photo", lookAt)
	if not PhotoMode.reduce then
		flash.BackgroundTransparency = 0.1
		flash.Visible = true
		TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		task.delay(0.36, function()
			flash.Visible = false
		end)
	end
end

local function nextPose()
	local list = poses()
	poseAt = poseAt % #list + 1
	local id = list[poseAt]
	-- the pose's picture at the button's left (2026-11-19), words only while its sheet is not uploaded
	-- (beside its picture the name alone, so it stays readable in the 150 px button)
	local pic = Thumb.emote(id)
	Thumb.side(poseButton, pic, (if pic then "" else "POSE: ") .. string.upper(poseName(id)), 14)
	if id >= 100 then
		EmoteFx.poseLocal(id, 8)
	else
		Net.send("EmotePlay", id) -- an owned emote: everyone sees it
	end
end

local function nextLook()
	lookAt = lookAt % #BACKDROPS + 1
	lookButton.Text = "LOOK: " .. BACKDROPS[lookAt]
	backdrop(BACKDROPS[lookAt])
end

local function button(text: string, color: Color3, onClick: () -> ()): TextButton
	local b = Kit.button({
		Text = text,
		Size = UDim2.fromOffset(150, T),
		BackgroundColor3 = color,
		maxText = 20,
	}, onClick)
	b.Parent = bar
	return b
end

function PhotoMode.isOpen(): boolean
	return open
end

function PhotoMode.init()
	gui = Kit.screen("Photo", 30)
	openButton = Kit.button({
		Text = "PHOTO",
		Size = UDim2.fromOffset(84, T - 10),
		Position = UDim2.fromOffset(U.safe + 312, U.safe),
		BackgroundColor3 = Kit.color.paper,
		maxText = 16,
	}, PhotoMode.open)
	openButton.Parent = gui
	Kit.dock(openButton, "Photo", 10) -- phone pass: in the top row (or its MORE drawer)
	overlay = Instance.new("Frame")
	overlay.Name = "Backdrop"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Visible = false
	overlay.Parent = gui
	flash = Kit.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		round = false,
		Visible = false,
		ZIndex = 20,
	})
	flash.Parent = gui
	bar = Instance.new("Frame")
	bar.Name = "PhotoBar"
	bar.BackgroundTransparency = 1
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -U.safe)
	bar.Size = UDim2.new(1, -2 * U.safe, 0, T * 2 + 10)
	bar.Visible = false
	bar.Parent = gui
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(150, T)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.VerticalAlignment = Enum.VerticalAlignment.Bottom
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = bar
	local snapButton = button("SNAP", Kit.color.gold, snap)
	snapButton.LayoutOrder = 1
	poseButton = button("POSE", Kit.color.paper, nextPose)
	poseButton.LayoutOrder = 2
	lookButton = button("LOOK: NONE", Kit.color.paper, nextLook)
	lookButton.LayoutOrder = 3
	local hide = button("HIDE UI", Kit.color.paper, function()
		setBar(false)
	end)
	hide.LayoutOrder = 4
	local exit = button("EXIT", Kit.color.muted, close)
	exit.LayoutOrder = 5

	-- drag to orbit, pinch to zoom, tap anywhere to bring the buttons back after HIDE UI
	UserInputService.InputBegan:Connect(function(input, processed)
		if not open then
			if
				not processed
				and input.KeyCode == PhotoMode.KEY
				and not UserInputService:GetFocusedTextBox()
			then
				PhotoMode.open()
			end
			return
		end
		if input.KeyCode == PhotoMode.KEY or input.KeyCode == Enum.KeyCode.ButtonB then
			close()
			return
		end
		if processed then
			return
		end
		if not bar.Visible then
			setBar(true)
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = input
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not open then
			return
		end
		if
			dragging
			and lastPinch == nil
			and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragging)
		then
			yaw -= input.Delta.X * 0.008
			pitch = math.clamp(pitch + input.Delta.Y * 0.006, -0.6, 1.2)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = nil
		end
	end)
	UserInputService.TouchPinch:Connect(function(_, scale, _, state)
		if not open then
			return
		end
		if state == Enum.UserInputState.Begin then
			lastPinch = scale
		elseif state == Enum.UserInputState.Change and lastPinch then
			dist = math.clamp(dist / (scale / lastPinch), 4, 40)
			lastPinch = scale
		else
			lastPinch = nil
		end
	end)
	-- hidden during the opening; a death closes it
	RunService.Heartbeat:Connect(FrameProf.wrap("PhotoMode", function()
		openButton.Visible = not open and not StoryClient.inOpening()
	end))
	player.CharacterRemoving:Connect(close)
	-- a cutscene takes the camera and Downed shows its own screen: either closes Photo Mode
	CinemaClient.Changed:Connect(function(scene)
		if scene then
			close()
		end
	end)
	PvpClient.Changed:Connect(function(what)
		if what == "down" and (PvpClient.down.downed or PvpClient.downed()) then
			close()
		end
	end)
end

return PhotoMode
