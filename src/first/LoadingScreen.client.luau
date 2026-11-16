-- LoadingScreen (ReplicatedFirst): the Capeline title card over loading. The opening cinematic plays here
-- from M7 (spec: The opening). Removed once the game and the hero are loaded, or after 12 s.
-- PLACEHOLDER ART: a title on a night sky gradient.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ResetOnSpawn = false

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(14, 18, 34)
bg.BorderSizePixel = 0
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.fromRGB(30, 50, 110), Color3.fromRGB(10, 12, 24))
grad.Rotation = 90
grad.Parent = bg
bg.Parent = gui

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.45)
title.Size = UDim2.fromScale(0.7, 0.18)
title.Font = Enum.Font.Bangers
title.Text = "CAPELINE"
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 214, 90)
title.TextStrokeTransparency = 0
title.Parent = bg

local spark = Instance.new("Frame")
spark.AnchorPoint = Vector2.new(0.5, 0.5)
spark.Position = UDim2.fromScale(0.5, 0.62)
spark.Size = UDim2.fromOffset(18, 18)
spark.BackgroundColor3 = Color3.fromRGB(120, 210, 255)
spark.BorderSizePixel = 0
spark.Rotation = 45
spark.Parent = bg

gui.Parent = player:WaitForChild("PlayerGui")
TweenService:Create(
	spark,
	TweenInfo.new(0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
	{ Rotation = 405 }
):Play()

local start = os.clock()
if not game:IsLoaded() then
	game.Loaded:Wait()
end
while not player.Character and os.clock() - start < 12 do
	task.wait(0.1)
end
TweenService:Create(bg, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
TweenService:Create(title, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
spark.Visible = false
task.wait(0.45)
gui:Destroy()
