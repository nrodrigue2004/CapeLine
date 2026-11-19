-- Popups: the one line every transient popup waits in on this device (pt-ui, nate's playtest 2026-11-19: "too
-- many popups on the screen at once"). The rules are Shared.PopupQueue's (Config.Ui.popups): at most 1 big card
-- and 2 small toasts at a time (1 toast on a phone), higher priority first, a burst merged ("+3 more"), non-urgent
-- cards held while fighting (at most combatHold s), offers only after offerCalm s of calm, nothing over the
-- loading screen, menu, creator, prologue or a cutscene but the answer to a tap, and every popup taken down at
-- the end of its life.
-- * Popups.toast(spec, draw): spec = { pri, group, life, urgent, stale, data, merge }; draw(data, count) builds the
--   toast and returns its GuiObject (destroyed at the end of its life).
-- * Popups.card(name, spec, show, isOpen?, hide?): spec = { pri, life, urgent, offer, fightOk, stale, expires };
--   show() puts the card up (and may return its GuiObject); the slot stays taken while isOpen() (else while the
--   returned object is in the game and Visible); hide() takes it down at the end of its life.
-- * Popups.fought(): a hit given or taken (also read from CinemaClient.lastHit every tick).
-- * Popups.busy: set by Ui.PopupGate (loading, menu, creator, prologue, cutscene).
-- * Popups.chip: the "+N more" note under the toasts for what was folded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PopupQueue = require(Shared:WaitForChild("PopupQueue"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))

local Kit = require(script.Parent.Kit)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)

local Popups = {}

local P = Config.Ui.popups
local q = PopupQueue.new(P)
Popups.queue = q -- (tests read it)
Popups.PRI = P.pri

type Handle = {
	show: () -> any,
	isOpen: (() -> boolean)?,
	hide: (() -> ())?,
	obj: any,
	draw: ((any, number) -> any)?,
}
local handles: { [number]: Handle } = {}

local clock = 0 -- seconds this device has run (Heartbeat), the queue's clock
local lastFight = -math.huge
local seenHit = 0
local blockedAt = -math.huge
local started = false

Popups.busy = function(): boolean
	return false
end
Popups.chip = nil :: TextLabel?

function Popups.now(): number
	return clock
end

function Popups.fought()
	lastFight = clock
end

function Popups.fighting(): boolean
	return clock - lastFight < P.calm
end

-- Is a card up (any, or this one)?
function Popups.cardUp(name: string?): boolean
	return PopupQueue.up(q, name)
end

local function ctx(): PopupQueue.Ctx
	local blocked = Popups.busy()
	if blocked then
		blockedAt = clock
	end
	return {
		fighting = Popups.fighting(),
		calmFor = clock - lastFight,
		blocked = blocked,
		freeFor = clock - blockedAt,
		phone = Kit.compact(),
	}
end

local function gone(h: Handle): boolean
	if h.isOpen then
		local ok, open = pcall(h.isOpen)
		return ok and not open
	end
	local o = h.obj
	if typeof(o) == "Instance" then
		return o.Parent == nil or (o:IsA("GuiObject") and not o.Visible)
	end
	return false
end

local function takeDown(item: PopupQueue.Item)
	local h = handles[item.id]
	handles[item.id] = nil
	if not h then
		return
	end
	if h.hide then
		pcall(h.hide)
	elseif typeof(h.obj) == "Instance" then
		h.obj:Destroy()
	end
end

local function more(n: number)
	local chip = Popups.chip
	if n <= 0 or not chip then
		return
	end
	local was = tonumber(chip:GetAttribute("More")) or 0
	chip:SetAttribute("More", was + n)
	chip.Text = string.format("+%d more", was + n)
	chip.Visible = true
	local token = clock
	chip:SetAttribute("At", token)
	task.delay(P.moreLife, function()
		if chip:GetAttribute("At") == token then
			chip.Visible = false
			chip:SetAttribute("More", 0)
		end
	end)
end

-- One pass of the queue: free what closed by itself, take down what had its time, put up what may show
function Popups.tick()
	if CinemaClient.lastHit ~= seenHit then
		seenHit = CinemaClient.lastHit
		Popups.fought() -- a hit taken
	end
	for i = #q.showing, 1, -1 do
		local s = q.showing[i]
		local h = handles[s.id]
		if not h or gone(h) then
			handles[s.id] = nil
			table.remove(q.showing, i)
		end
	end
	local out = PopupQueue.step(q, clock, ctx())
	for _, item in out.close do
		takeDown(item)
	end
	for _, item in out.show do
		local h = handles[item.id]
		if h then
			local ok, obj
			if h.draw then
				ok, obj = pcall(h.draw, item.data, item.count)
			else
				ok, obj = pcall(h.show)
			end
			if ok then
				h.obj = obj
			else
				warn("[Popups] " .. item.name .. ": " .. tostring(obj))
				handles[item.id] = nil
				PopupQueue.closed(q, item.id)
			end
		end
	end
	more(PopupQueue.takeMore(q))
end

local function start()
	if started then
		return
	end
	started = true
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("Popups", function(dt)
		clock += dt
		acc += dt
		if acc < P.tick then
			return
		end
		acc = 0
		Popups.tick()
	end))
end

-- A small toast; draw(data, count) builds it when its turn comes
function Popups.toast(spec: { [string]: any }, draw: (any, number) -> any): PopupQueue.Item
	start()
	local s = table.clone(spec)
	s.kind = "toast"
	s.life = s.life or 3.5
	local item, merged = PopupQueue.push(q, s, clock)
	if not merged then
		handles[item.id] = {
			show = function() end,
			draw = draw,
			obj = nil,
		}
	end
	Popups.tick()
	return item
end

-- A big card; show() puts it up when its turn comes
function Popups.card(
	name: string,
	spec: { [string]: any },
	show: () -> any,
	isOpen: (() -> boolean)?,
	hide: (() -> ())?
): PopupQueue.Item
	start()
	local s = table.clone(spec)
	s.kind = "card"
	s.name = name
	-- a card of the same name waiting: the newer one takes its place
	for _, w in q.waiting do
		if w.kind == "card" and w.name == name then
			handles[w.id] = nil
		end
	end
	local item = PopupQueue.push(q, s, clock)
	handles[item.id] = { show = show, isOpen = isOpen, hide = hide, obj = nil }
	Popups.tick()
	return item
end

-- Every card kind's own rules (Config.Ui.popups.cards[name]) as a spec
function Popups.spec(name: string): { [string]: any }
	local c = P.cards[name]
	assert(c, "no popup card " .. name)
	return {
		pri = P.pri[c.pri] or 0,
		life = c.life,
		urgent = c.urgent,
		offer = c.offer,
		fightOk = c.fightOk,
		stale = c.stale,
	}
end

-- Shorthand: a card from Config.Ui.popups.cards
function Popups.show(
	name: string,
	show: () -> any,
	isOpen: (() -> boolean)?,
	hide: (() -> ())?
): PopupQueue.Item
	return Popups.card(name, Popups.spec(name), show, isOpen, hide)
end

-- (tests) move this device's popup clock on, as the Heartbeat would
function Popups.advance(dt: number)
	clock += dt
	Popups.tick()
end

return Popups
