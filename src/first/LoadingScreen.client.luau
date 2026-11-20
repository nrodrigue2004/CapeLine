-- LoadingScreen (ReplicatedFirst): the Capeline comic splash over loading. Removed once the game, the body and
-- the saved hero are loaded (the server's HeroLoaded attribute: a new player's creator opens about a second
-- later, so there is no wait on a bare HUD in between), or after 12 s. A fixed status line under the spark
-- says what is loading (onboarding check 2026-11-18).
-- The card itself is LoadingCard (gap polish 2026-11-19: the PURE COMIC look with the logo, a sunburst,
-- halftone dots and a TIP panel whose tip changes every 4 s); it requires nothing, so this stays light.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local LoadingCard = require(script.Parent:WaitForChild("LoadingCard"))

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ResetOnSpawn = false

local card = LoadingCard.build(gui)
local status = card.status
local spark = card.spark
local tipAt = math.random(1, #LoadingCard.TIPS)
card.setTip(tipAt)

gui.Parent = player:WaitForChild("PlayerGui")
-- sound at once: the day patrol in the Music group (list-combat 2026-11-20; LoadingCard.MUSIC)
local M = LoadingCard.MUSIC
local SoundService = game:GetService("SoundService")
local musicGroup = SoundService:FindFirstChild("Music") :: SoundGroup?
if not musicGroup then
	local g = Instance.new("SoundGroup")
	g.Name = "Music"
	g.Volume = M.group
	g.Parent = SoundService
	musicGroup = g
end
local music = Instance.new("Sound")
music.Name = "LoadingMusic"
music.SoundId = "rbxassetid://" .. string.format("%d", M.atlas)
music.PlaybackRegionsEnabled = true
music.PlaybackRegion = NumberRange.new(M.start, M.start + M.length)
music.Looped = true
music.Volume = M.volume
music.SoundGroup = musicGroup
music.Parent = SoundService
music:Play()
-- the skyline drifts by (near faster than far) and a hero streaks across the sky every few seconds
for i, layer in card.layers do
	TweenService:Create(
		layer,
		TweenInfo.new(if i == 1 then 60 else 34, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Position = UDim2.fromScale(-1, 1) }
	):Play()
end
TweenService:Create(
	card.streak,
	TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In, -1, false, 2.4),
	{ Position = UDim2.fromScale(1.4, 0.58) }
):Play()
TweenService:Create(
	spark,
	TweenInfo.new(0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
	{ Rotation = 405 }
):Play()
-- the logo pops in, then breathes
card.pop.Scale = 0.6
TweenService
	:Create(card.pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	:Play()
task.delay(0.5, function()
	TweenService:Create(
		card.pop,
		TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.04 }
	):Play()
end)
-- a new tip every 4 s while the card is up
task.spawn(function()
	while gui.Parent do
		task.wait(4)
		tipAt += 1
		card.setTip(tipAt)
	end
end)

local start = os.clock()
if not game:IsLoaded() then
	game.Loaded:Wait()
end
while not player.Character and os.clock() - start < 12 do
	task.wait(0.1)
end
status.Text = "LOADING YOUR HERO"
while player:GetAttribute("HeroLoaded") ~= true and os.clock() - start < 12 do
	task.wait(0.1)
end
-- Studio only: if the server hit an error, show it in a red box (tap to close) instead of an empty sky
local errors = game:GetService("RunService"):IsStudio()
	and game:GetService("ReplicatedStorage"):FindFirstChild("ServerErrors")
local function showErrors()
	if not errors or (errors :: StringValue).Value == "" then
		return
	end
	local eg = player.PlayerGui:FindFirstChild("ServerErrorsGui") or Instance.new("ScreenGui")
	eg.Name = "ServerErrorsGui"
	eg.ResetOnSpawn = false
	eg.DisplayOrder = 200
	local box = eg:FindFirstChild("Box") :: TextButton? or Instance.new("TextButton")
	box.Name = "Box"
	box.AutoButtonColor = false
	box.Position = UDim2.new(0, 16, 0, 60)
	box.Size = UDim2.new(1, -32, 0, 260)
	box.BackgroundColor3 = Color3.fromRGB(90, 10, 16)
	box.TextColor3 = Color3.new(1, 1, 1)
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.TextWrapped = true
	box.Font = Enum.Font.Code
	box.TextSize = 14
	box.Text = "SERVER ERROR (Studio only, tap to close)\n" .. (errors :: StringValue).Value
	box.Activated:Connect(function()
		eg:Destroy()
	end)
	box.Parent = eg
	eg.Parent = player.PlayerGui
end
if errors then
	(errors :: StringValue).Changed:Connect(showErrors)
	showErrors()
end
TweenService:Create(card.root, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
TweenService:Create(music, TweenInfo.new(1.5), { Volume = 0 }):Play() -- the game's own music takes over
task.wait(0.45)
gui:Destroy()
task.delay(1.2, function()
	music:Destroy()
end)
