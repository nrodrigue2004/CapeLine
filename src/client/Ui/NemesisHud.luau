-- NemesisHud: your nemesis on screen (spec: Hero MMO features > Nemesis; H5). The WANTED poster (the
-- WANTED button under TASK FORCE): its name, rank, traits, Intel and the SHOWDOWN button once your Intel is
-- complete. When it ambushes you a comic panel pops with its taunt (fixed lines with your hero name), and
-- again when it escapes or gloats.
-- PLACEHOLDER look until the UI pass; the poster on the HQ board waits on the HQ art pass (Tasks).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local NemesisMath = require(Shared:WaitForChild("NemesisMath"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Kit = require(script.Parent.Kit)

local NemesisHud = {}
-- WP7: the Journal's SHOWDOWN tab draws this poster (drawInto) and redraws when a new poster arrives
NemesisHud.Changed = Signal.new()
local last: { [string]: any }? = nil

local N = Config.Nemesis
local T = Config.Ui.touchTarget
local gui: ScreenGui
local poster: Frame
local nameL: TextLabel
local rankL: TextLabel
local traitsL: TextLabel
local intelL: TextLabel
local noteL: TextLabel
local showdown: TextButton
local panel: Frame
local panelName: TextLabel
local panelLine: TextLabel
local panelSeq = 0

local function label(
	parent: Instance,
	text: string,
	y: number,
	h: number,
	size: number,
	color: Color3?,
	body: boolean?
): TextLabel
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, -24, 0, h),
		Position = UDim2.fromOffset(12, y),
		TextColor3 = color or Kit.color.ink,
		Font = if body then Kit.bodyFont else Kit.font,
		maxText = size,
	})
	l.Parent = parent
	return l
end

local function traitNames(bits: number): string
	local out = {}
	for i, t in N.traits do
		if NemesisMath.hasTrait(bits, i) then
			table.insert(out, t.name)
		end
	end
	return if #out > 0 then table.concat(out, ", ") else "None yet"
end

-- The poster's note line
local function noteFor(d: { [string]: any }): string
	if d.locked then
		return "Your nemesis finds you from level " .. N.minLevel
	elseif (d.readyIn or 0) > 0 then
		return "A new one is on its way: " .. Kit.time(d.readyIn)
	elseif d.showdown then
		return "Its weak point is known: its back. Take it down."
	end
	return "It hunts you in the city. Each escape leaves Intel."
end

local function render(d: { [string]: any })
	last = d
	nameL.Text = string.upper(d.name or "")
	rankL.Text = "RANK " .. (d.rank or 1) .. "  " .. string.rep("★", d.rank or 1)
	traitsL.Text = "Traits: " .. traitNames(d.traits or 0)
	intelL.Text = string.format("Intel %d / %d", d.intel or 0, N.intelForShowdown)
	showdown.Visible = d.showdown == true
	noteL.Text = noteFor(d)
end

-- WP7: the WANTED poster in another screen's list (the Journal's SHOWDOWN tab, spec H5: "a mission in a
-- pocket, started from the Journal"); the caller cleared it. SHOWDOWN starts the fight and calls onStart
-- (the Journal closes). The poster's own panel is left as it is.
function NemesisHud.drawInto(container: Instance, onStart: (() -> ())?)
	local d = last
	if not d then
		Kit.stateNote(container, "loading", "Pinning up the poster...")
		return
	end
	local card = Kit.frame({
		Name = "Wanted",
		Size = UDim2.new(1, -8, 0, if d.showdown then 280 else 216),
		LayoutOrder = 1,
		BackgroundColor3 = Color3.fromRGB(236, 220, 180),
	})
	Kit.stroke(card, Kit.color.ink, 3)
	card.Parent = container
	label(card, "WANTED", 6, 44, 40, Color3.fromRGB(150, 30, 30))
	label(card, string.upper(d.name or ""), 50, 34, 30)
	label(card, "RANK " .. (d.rank or 1) .. "  " .. string.rep("★", d.rank or 1), 86, 24, 20)
	local traits = label(card, "Traits: " .. traitNames(d.traits or 0), 112, 34, 14, nil, true)
	traits.TextWrapped = true
	label(card, string.format("Intel %d / %d", d.intel or 0, N.intelForShowdown), 148, 22, 18)
	local note = label(card, noteFor(d), 172, 36, 14, nil, true)
	note.TextWrapped = true
	if d.showdown then
		local b = Kit.button({
			pending = true,
			Text = "SHOWDOWN",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.fromOffset(T * 4, T),
			BackgroundColor3 = Kit.color.gold,
		}, function()
			Net.send("NemesisShowdown")
			if onStart then
				onStart()
			end
		end)
		b.Parent = card
	end
	if (d.banes or 0) > 0 then
		local banes = Kit.label({
			Text = string.format("Nemeses beaten: %d", d.banes),
			Size = UDim2.new(1, -8, 0, 24),
			LayoutOrder = 2,
			TextColor3 = Kit.color.paper,
			Font = Kit.bodyFont,
			maxText = 15,
		})
		banes.Parent = container
	end
end

-- Ask the server for the poster (NemesisState answers)
function NemesisHud.request()
	Net.send("NemesisPoster")
end

local function comic(name: string, line: string)
	panelSeq += 1
	local seq = panelSeq
	panelName.Text = string.upper(name)
	panelLine.Text = line
	panel.Visible = true
	task.delay(N.panelTime, function()
		if panelSeq == seq then
			panel.Visible = false
		end
	end)
end

function NemesisHud.open()
	Kit.opening("NemesisHud", poster, NemesisHud.close, true)
	poster.Visible = true
	Net.send("NemesisPoster")
end

function NemesisHud.close()
	poster.Visible = false
end

function NemesisHud.init()
	gui = Kit.screen("NemesisHud", 6)
	poster = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 400),
		BackgroundColor3 = Color3.fromRGB(236, 220, 180),
		Visible = false,
	})
	Kit.stroke(poster, Kit.color.ink, 4)
	-- phone pass: the poster's design size draws smaller on a phone (it was a fixed 340 x 400, past a 375 px
	-- phone's safe area); its rows fit 370 px, SHOWDOWN at the bottom
	Kit.fit(poster, 340, 370, 340, 400)
	poster.Parent = gui
	local wanted = label(poster, "WANTED", 8, 50, 56, Color3.fromRGB(150, 30, 30))
	wanted.Size = UDim2.new(1, -2 * (T + 14), 0, 50) -- clear of X
	wanted.Position = UDim2.fromOffset(T + 14, 8)
	nameL = label(poster, "", 62, 40, 36)
	rankL = label(poster, "", 104, 26, 22)
	traitsL = label(poster, "", 136, 56, 15, nil, true)
	traitsL.TextWrapped = true
	intelL = label(poster, "", 198, 24, 20)
	noteL = label(poster, "", 226, 44, 14, nil, true)
	noteL.TextWrapped = true
	showdown = Kit.button({
		pending = true,
		Text = "SHOWDOWN",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(T * 4, T),
		BackgroundColor3 = Kit.color.gold,
		Visible = false,
	}, function()
		Net.send("NemesisShowdown")
		NemesisHud.close()
	end)
	showdown.Parent = poster
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(T, T - 6), -- still a full tap at the poster's phone scale
		Position = UDim2.new(1, -T - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, NemesisHud.close)
	close.Parent = poster
	local open = Kit.button({
		Name = "WantedButton",
		Text = "WANTED",
		Size = UDim2.fromOffset(T * 2 + 20, T - 10),
		Position = UDim2.fromOffset(Config.Ui.safe + 258, Config.Ui.safe + T * 2 - 4),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		if poster.Visible then
			NemesisHud.close()
		else
			NemesisHud.open()
		end
	end)
	Kit.dock(open, "Wanted", 13) -- the top row (or its MORE drawer), after SETTINGS
	-- the comic panel taunt (top of the screen)
	panel = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(460, 110),
		BackgroundColor3 = Color3.fromRGB(255, 250, 235),
		Visible = false,
	})
	Kit.stroke(panel, Kit.color.ink, 4)
	panel.Parent = gui
	panelName = label(panel, "", 6, 36, 30, Color3.fromRGB(180, 30, 30))
	panelLine = label(panel, "", 44, 56, 22)
	panelLine.TextWrapped = true

	Net.listen("NemesisState", function(d: any)
		if type(d) ~= "table" then
			return
		end
		if d.k == "poster" then
			render(d)
			NemesisHud.Changed:Fire()
		elseif (d.k == "taunt" or d.k == "escape" or d.k == "gloat") and d.line then
			comic(d.name or "", d.line)
		end
	end)
end

return NemesisHud
