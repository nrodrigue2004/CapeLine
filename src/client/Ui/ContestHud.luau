-- ContestHud: costume contests on screen (spec: Hero MMO features > Costume contests; H7).
-- * The call: a banner at the top with the theme and a countdown, and ENTER (near the stage) to step on.
-- * The show: the contestant in the spotlight gets a light over them on every device and, on their own
--   device, a slow camera spin round them; they pose with any emote they own.
-- * The vote: a card with every contestant and 1 to 5 big star buttons each (phone sized); you can vote from
--   anywhere on the server. Contestants do not get the card.
-- * The results: the top 3 with confetti (Juice "contestWin" for the winner), or a short "skipped" line.
-- PLACEHOLDER ART: Kit frames and an engine SpotLight until the UI and effects passes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Juice = require(script.Parent.Parent.Fx.Juice)
local Kit = require(script.Parent.Kit)
local Popups = require(script.Parent.Popups)
local Dismiss = require(script.Parent.Dismiss) -- fix-hud -- pt-ui: one line for every popup

local ContestHud = {}

local K = Config.Contest
local T = Config.Ui.touchTarget
local me = Players.LocalPlayer
local gui: ScreenGui
local banner: Frame
local bannerTitle: TextLabel
local bannerSub: TextLabel
local enterButton: TextButton
local card: Frame
local cardBody: ScrollingFrame
local state: { [string]: any } = {}
local clockOffset = 0 -- server os.time minus this device's
local myVotes: { [number]: number } = {}
local light: SpotLight? = nil
local spinning = false
-- pt-ui (2026-11-19, nate: "contest skipped stays on my screen"): the results and skipped banner close on this
-- device after Config.Contest.results s (or its X), whatever the server says next
-- fix-hud (nate, gaps7: popups stuck on screen): the call, show and vote banner folds away K.bannerLife s after
-- each new step (or at its X, a tap or Backspace) and comes back at the next step; ENTER waits on the radar's
-- star and the stage itself
local liveHidden = false
local liveAt = 0
local overShown = true -- the results or skipped banner is still up (cleared after Config.Contest.results s or the X)
local overToken = 0
local closeButton: TextButton
local voteAsked = false -- the stars card is waiting in Ui.Popups or up
local voteClosed = false -- its X was tapped this contest

local function now(): number
	return os.time() + clockOffset
end

local function isEntry(userId: number): boolean
	for _, e in state.entries or {} do
		if e.id == userId then
			return true
		end
	end
	return false
end

local function nearStage(): boolean
	local s = state.stage
	local char = me.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	if not s or not r or not r:IsA("BasePart") then
		return false
	end
	return (r.Position - Vector3.new(s[1], s[2], s[3])).Magnitude <= K.enterRange
end

local function spotlightOn(userId: number?)
	if light then
		light:Destroy()
		light = nil
	end
	local p = userId and Players:GetPlayerByUserId(userId)
	local head = p and p.Character and p.Character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Top
		l.Angle = 50
		l.Range = 24
		l.Brightness = 6
		l.Color = Color3.fromRGB(255, 240, 200)
		l.Parent = head
		light = l
	end
	-- the contestant's own camera turns slowly round them for the spotlight
	if userId == me.UserId and not spinning then
		spinning = true
		local t = 0
		RunService:BindToRenderStep("CapelineContestSpin", Enum.RenderPriority.Camera.Value - 2, function(dt)
			t += dt
			local char = me.Character
			local r = char and char:FindFirstChild("HumanoidRootPart")
			if t >= K.show or not r or not r:IsA("BasePart") then
				RunService:UnbindFromRenderStep("CapelineContestSpin")
				spinning = false
				return
			end
			local cam = Workspace.CurrentCamera
			local pivot = r.Position
			local yaw = math.pi * 2 / K.show * dt
			cam.CFrame = CFrame.new(pivot) * CFrame.Angles(0, yaw, 0) * CFrame.new(-pivot) * cam.CFrame
		end)
	end
end

local function clearCard()
	for _, c in cardBody:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local function drawCard()
	clearCard()
	local order = 0
	for _, e in state.entries or {} do
		if e.id ~= me.UserId then
			order += 1
			local row = Kit.frame({ Size = UDim2.new(1, 0, 0, T + 30), BackgroundTransparency = 1 })
			row.LayoutOrder = order
			row.Parent = cardBody
			local name = Kit.label({
				Text = string.upper(e.name),
				Size = UDim2.new(1, 0, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if state.spot == e.id then Kit.color.gold else Kit.color.paper,
				maxText = 18,
			})
			name.Parent = row
			for s = 1, 5 do
				local on = (myVotes[e.id] or 0) >= s
				local b = Kit.button({
					Text = "★",
					Size = UDim2.new(0.2, -6, 0, T),
					Position = UDim2.new((s - 1) * 0.2, 0, 0, 28),
					BackgroundColor3 = if on then Kit.color.gold else Kit.color.paper,
				}, function()
					myVotes[e.id] = s
					Net.send("ContestVote", e.id, s)
					drawCard()
				end)
				b.Parent = row
			end
		end
	end
end

local function results()
	local top = state.top or {}
	local names = {}
	for place, u in top do
		local nm = "?"
		for _, e in state.entries or {} do
			if e.id == u then
				nm = e.name
			end
		end
		table.insert(names, string.format("%d. %s", place, string.upper(nm)))
	end
	bannerTitle.Text = "CONTEST RESULTS"
	bannerSub.Text = table.concat(names, "   ")
	if top[1] == me.UserId then
		Juice.fire("contestWin", nil, { mine = true })
	elseif #top > 0 then
		Juice.fire("contestWin", nil, { mine = false })
	end
end

local function render()
	local phase = state.phase
	local left = math.max(0, (state.endsAt or 0) - now())
	local over = phase == "results" or phase == "skipped"
	-- (and it steps aside while another big card is up: a result card, a name card)
	local otherCard = Popups.cardUp() and not Popups.cardUp("contestVote")
	local live = (phase == "call" or phase == "show" or phase == "vote")
		and not liveHidden
		and os.clock() - liveAt < K.bannerLife
	banner.Visible = (live or (over and overShown)) and not otherCard
	closeButton.Visible = true
	enterButton.Visible = phase == "call" and not isEntry(me.UserId) and #(state.entries or {}) < K.maxEntries
	local want = (phase == "show" or phase == "vote")
		and not isEntry(me.UserId)
		and #(state.entries or {}) > 0
		and not voteClosed
	if not want then
		card.Visible = false
		voteAsked = false
	elseif not card.Visible and not voteAsked then
		-- the stars card takes the big card slot through the show and the vote (Ui.Popups "contestVote")
		voteAsked = true
		Popups.panel("contestVote", function() -- fix-hud: its X, a tap and Backspace (Ui.Dismiss)
			return card
		end)
		Popups.show("contestVote", function()
			if voteAsked and not voteClosed then
				card.Visible = true
				drawCard()
			end
		end, function()
			return card.Visible
		end, function()
			card.Visible = false
		end)
	end
	if phase == "call" then
		bannerTitle.Text = "COSTUME CONTEST: " .. string.upper(state.theme or "")
		bannerSub.Text = string.format(
			"On the plaza stage in %d s  ·  %d / %d on stage",
			left,
			#(state.entries or {}),
			K.maxEntries
		)
		enterButton.Text = if nearStage() then "ENTER" else "GO TO THE STAGE"
	elseif phase == "show" then
		local nm = ""
		for _, e in state.entries or {} do
			if e.id == state.spot then
				nm = e.name
			end
		end
		bannerTitle.Text = "IN THE SPOTLIGHT: " .. string.upper(nm)
		bannerSub.Text = "Theme: " .. (state.theme or "") .. "  ·  rate them below"
	elseif phase == "vote" then
		bannerTitle.Text = "VOTE NOW"
		bannerSub.Text = string.format("%d s left  ·  Theme: %s", left, state.theme or "")
	elseif phase == "skipped" then
		bannerTitle.Text = "CONTEST SKIPPED"
		bannerSub.Text = "Not enough contestants or voters this time. See you in 30 minutes!"
	end
end

function ContestHud.init()
	gui = Kit.screen("ContestHud", 5)
	banner = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 190), -- under the toasts (pt-ui: it sat on them)
		Size = UDim2.new(0.9, 0, 0, 74),
		BackgroundColor3 = Color3.fromRGB(80, 40, 120),
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(520, 74)
	lim.Parent = banner
	Kit.stroke(banner, Kit.color.gold, 3)
	banner.Parent = gui
	bannerTitle = Kit.label({
		Text = "",
		Size = UDim2.new(1, -130, 0, 34),
		Position = UDim2.fromOffset(12, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 24,
	})
	bannerTitle.Parent = banner
	bannerSub = Kit.label({
		Text = "",
		Size = UDim2.new(1, -130, 0, 28),
		Position = UDim2.fromOffset(12, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 13,
	})
	bannerSub.Parent = banner
	enterButton = Kit.button({
		Text = "ENTER",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(110, T),
		BackgroundColor3 = Kit.color.gold,
		Visible = false,
	}, function()
		if nearStage() then
			Net.send("ContestEnter")
		end
	end)
	enterButton.Parent = banner
	closeButton = Kit.button({
		Text = "X",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(T, T),
		BackgroundColor3 = Kit.color.paper,
		Visible = false,
	}, function()
		overShown = false
		liveHidden = true
		render()
	end)
	closeButton.Name = "Close"
	closeButton.Parent = banner
	Dismiss.attach(banner, function()
		overShown = false
		liveHidden = true
		render()
	end, { x = false })
	card = Kit.frame({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0.42, 0, 0.6, 0),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	local clim = Instance.new("UISizeConstraint")
	clim.MaxSize = Vector2.new(340, 460)
	clim.MinSize = Vector2.new(220, 200)
	clim.Parent = card
	card.Parent = gui
	local x = Kit.button({
		Name = "Close",
		Text = "X",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(T - 8, T - 8),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		voteClosed = true
		render()
	end)
	x.Parent = card
	local head = Kit.label({
		Text = "RATE THE LOOKS",
		Size = UDim2.new(1, -20, 0, 28),
		Position = UDim2.fromOffset(10, 4),
		TextColor3 = Kit.color.gold,
		maxText = 20,
	})
	head.Parent = card
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(10, 34)
	scroll.Size = UDim2.new(1, -20, 1, -40)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.Parent = card
	cardBody = scroll
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = cardBody

	Net.listen("ContestState", function(d: any)
		if type(d) ~= "table" then
			return
		end
		if typeof(d.now) == "number" then
			clockOffset = d.now - os.time()
		end
		local was = state.phase
		state = d
		if d.phase ~= was then
			liveHidden = false -- a new step: the banner shows again for a moment
			liveAt = os.clock()
		end
		if (d.phase == "results" or d.phase == "skipped") and was ~= d.phase then
			overShown = true
			overToken += 1
			local token = overToken
			task.delay(K.results, function()
				if token == overToken then
					overShown = false
					render()
				end
			end)
		end
		if d.phase == "call" and was ~= "call" then
			myVotes = {}
			voteClosed = false
			Juice.fire("contestCall", nil, { mine = false })
		end
		spotlightOn(if d.phase == "show" then d.spot else nil)
		if d.phase == "results" and was ~= "results" then
			results()
		end
		if card.Visible or d.phase == "show" or d.phase == "vote" then
			drawCard()
		end
		render()
	end)
	task.defer(function()
		Net.send("ContestOpen")
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ph: string = state.phase or "idle"
			local live = ph == "call" or ph == "show" or ph == "vote"
			if live or (banner.Visible and ph ~= "results") then
				render()
			end
		end
	end)
end

return ContestHud
