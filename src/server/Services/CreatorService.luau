-- CreatorService: the hero creator, character slots and creator unlocks (spec: Hero creator; Character slots;
-- Faction reputation "a style unlock"; Hero.Create {side, classId, setId, look, colors, titleId, nounId}
-- 1/10s; Hero.Select {slot} 1/5s).
-- * The creator opens in three modes: "create" for a brand-new character before any story (nate's lore,
--   build plan step 2: creator first; side, origin, class, starting set, look and name; Done starts the
--   opening), "first" once for a hero made before the creator (name and look), and "edit" at HQ or a
--   safehouse (look, name and origin; the class changes only at HQ, the side and set never).
-- * Origins (lore step 2): picked in the creator, changed there free; a title and one look piece (the
--   origin's crest), never a stat. The street outfit (streetOutfit) is the prologue's plain clothes.
-- * HeroCreate checks everything on the server: every piece is unlocked, colours are on the palette, the
--   name pair is on the wheels and not blocked. The look is saved as 8 words; the hero's Comic or Anime pick
--   is the look's flag. Others see the look on the body (LookService) and the name on the plate.
-- * HeroSelect switches to another character slot at HQ or a safehouse (out of combat and unflagged), or
--   makes a new one when the slot is the next free one (slots 3 and 4 are bought): the new hero plays the
--   opening, which ends in the creator.
-- * Unlocks: after levels, story, Fame, boss rewards and Legacy, earned pieces are unlocked for the account
--   with a toast; an Epic or Legendary drop may unlock a random "drop" piece.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local LookCodec = require(Shared:WaitForChild("LookCodec"))
local WeaponRules = require(Shared:WaitForChild("WeaponRules"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local FlowPlan = require(Shared:WaitForChild("FlowPlan"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local SafehouseService = require(script.Parent.SafehouseService)
local StoryService = require(script.Parent.StoryService)
local OpeningService = require(script.Parent.OpeningService)
local BossService = require(script.Parent.BossService)
local FlagService = require(script.Parent.FlagService)
local Analytics = require(script.Parent.Analytics)
local CinemaService = require(script.Parent.CinemaService)

local CreatorService = {}
CreatorService.Saved = Signal.new() -- (player) a creator save landed (HqService refreshes the mannequins)
-- HqService sets these: is the hero in its HQ, and take it out before a character switch
CreatorService.inHq = function(_hero: any): boolean
	return false
end
CreatorService.leaveHq = function(_player: Player) end

local rng = Rng.new(os.time() % 100000 + 17)
local firstAsked: { [Player]: boolean } = {}
local createAsked: { [Player]: boolean } = {}
-- fix-flow (2026-11-19): a brand-new character's exposition is playing on its device (os.clock() it began)
local introAt: { [Player]: number } = {}

local function charOf(player: Player): (any?, any?)
	local profile = DataService.get(player)
	return profile, profile and ProfileSchema.active(profile)
end

-- Name and Legacy for everyone's plates
function CreatorService.showName(player: Player)
	local _, c = charOf(player)
	if not c then
		return
	end
	player:SetAttribute("HeroName", CreatorRules.heroName(Config, c.titleId, c.nounId) or "")
	player:SetAttribute("Legacy", c.legacy)
	-- lore step 2: the origin's title ("Lab-Born") under the hero's name
	local origin = Config.Creator.origins[c.origin or 0]
	player:SetAttribute("OriginTitle", if origin and c.created == 1 then origin.title else nil)
	player:SetAttribute("FxTint", if c.tint > 0 then c.tint else nil)
	player:SetAttribute("Landing", if c.landing > 0 then c.landing else nil)
	-- M11: the voice pack every device plays this hero's lines from (Config.Shop.voiceSounds)
	local look = LookCodec.read(c.look)
	local v = look and CreatorRules.piece(Config, "voice", look.pieces.voice or 0)
	player:SetAttribute("Voice", if v then v.kit else nil)
end

local function result(player: Player, ok: boolean, reason: string?)
	Net.fire("CreatorResult", player, { ok = ok, reason = reason })
end

-- Unlock whatever this account has earned and toast each new piece
function CreatorService.sweep(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local got = {}
	for _, p in CreatorRules.earned(Config, profile) do
		if CreatorRules.grant(profile, p) then
			table.insert(got, p.name)
		end
	end
	for _, name in got do
		Net.fire("Toast", player, { id = "piece", name = name })
	end
	if #got > 0 then
		DataService.changed(player)
		DataService.saveSoon(player)
	end
end

local function where(hero: any): string?
	if CreatorService.inHq(hero) then
		return "hq"
	end
	if SafehouseService.near(hero) then
		return "safehouse"
	end
	return nil
end

-- What the creator may change right now: "create", "first", "edit", or nil (and why)
-- A brand-new character (no creator yet, no opening yet) makes its hero first, before any story
local function isNew(c: any): boolean
	return c.created == 0 and c.story.opening == 0
end

local function modeOf(_player: Player, hero: any, c: any): (string?, string?)
	if isNew(c) then
		return "create", nil
	end
	if c.created == 0 and c.story.opening == 1 then
		return "first", nil
	end
	if hero.scene and hero.scene ~= "hq" then
		return nil, "scene"
	end
	if HeroService.inCombat(hero) then
		return nil, "combat"
	end
	if not where(hero) then
		return nil, "safehouse"
	end
	return "edit", nil
end

local function onCreate(
	player: Player,
	buf: buffer,
	sideIdx: number,
	classIdx: number,
	setIdx: number,
	titleId: number,
	nounId: number,
	mobilityIdx: number?,
	weaponBuf: buffer?,
	originIdx: number?
)
	local profile, c = charOf(player)
	local hero = HeroService.get(player)
	if not profile or not c or not hero or not hero.loaded then
		-- always answer (nate's playtest, 2026-11-18: DONE "dont work sometimes" when a tap got no reply)
		result(player, false, "loading")
		return
	end
	local mode, why = modeOf(player, hero, c)
	if not mode then
		result(player, false, why)
		return
	end
	local look = LookCodec.decode(buf)
	if not look then
		result(player, false, "look")
		return
	end
	-- the origin: a new hero picks one; anyone else may change theirs free (no pick keeps the saved one)
	local origin = if originIdx ~= nil then originIdx else c.origin
	if not CreatorRules.originOk(Config, origin) then
		result(player, false, "origin")
		return
	end
	local ok, reason = CreatorRules.validate(Config, profile, look, origin)
	if not ok then
		result(player, false, reason)
		return
	end
	if not CreatorRules.nameOk(Config, titleId, nounId) then
		result(player, false, "name")
		return
	end
	local classId = Config.Classes.order[classIdx]
	local class = classId and Config.Classes[classId]
	local setId = class and class.paths[setIdx]
	local mobility = Config.Move.mobilityOrder[mobilityIdx or 1] or "flight"
	local side = if sideIdx == 2 then "villain" else "hero"
	if not CreatorRules.pickOk(Config, classId, setId, side, mobility) then
		result(player, false, "pick")
		return
	end
	-- the weapon (2026-11-16 creator plan): a new hero (or one made before weapons) takes any Rack weapon
	-- free; otherwise only an owned weapon. Its look must be in range.
	local weaponLook = if weaponBuf then WeaponRules.decodeLook(weaponBuf) else nil
	local freeWeapon = false
	if weaponLook then
		local okLook, whyLook = WeaponRules.lookOk(Config, weaponLook)
		if not okLook then
			result(player, false, whyLook)
			return
		end
		if not WeaponRules.owned(Config, profile, weaponLook.id) then
			if (mode == "create" or mode == "first") and WeaponRules.freePickOk(Config, weaponLook.id) then
				freeWeapon = true
			else
				result(player, false, "weapon")
				return
			end
		end
	end
	if weaponLook then
		if freeWeapon then
			WeaponRules.grant(profile, weaponLook.id)
		end
		WeaponRules.setLook(profile, weaponLook)
		c.weapon = weaponLook.id
	end
	-- the origin (a title and one look piece; never a stat)
	if origin ~= c.origin or mode == "create" then
		Analytics.event(player, "origin_pick", hero.level, { Config.Creator.origins[origin].id, mode })
	end
	c.origin = origin
	-- the look, the name and the effect style
	c.look = LookCodec.toWords(buf)
	c.titleId, c.nounId = titleId, nounId
	c.fxStyle = if look.anime then "Anime" else "Comic"
	HeroService.setFxStyle(hero, c.fxStyle)
	-- the mobility: picked in the creator, swapped free whenever the creator opens (safehouse or HQ)
	if c.mobility ~= mobility then
		c.mobility = mobility
		HeroService.setMobility(hero, mobility)
	end
	local pathMoved = classId ~= hero.classId or setId ~= hero.startSet
	if mode == "create" then
		-- a new hero (creator first): its side, archetype and main path, open from level 1 with the path's
		-- starters learned; then the opening plays with this side (its Suit Up only finishes the run now)
		c.created = 1
		StoryService.setSide(player, side)
		Analytics.event(player, "creator_done", Analytics.since(player), { classId, side, setId })
		Analytics.step(player, "Opening", "creator_done")
		if pathMoved then
			CreatorService.setPath(player, hero, c, classId, setId, false)
		end
		if hero.scene == "creator" then
			hero.scene = nil
		end
		createAsked[player] = nil
		task.defer(OpeningService.start, player)
	else
		c.created = 1
		-- a hero made before the creator picks freely once; otherwise one free change before level 10
		if pathMoved then
			if mode == "first" then
				CreatorService.setPath(player, hero, c, classId, setId, false)
			elseif CreatorRules.pathChangeOk(Config, hero.level, c.pathChanged) then
				CreatorService.setPath(player, hero, c, classId, setId, true)
			else
				result(player, false, "path")
				return
			end
		end
	end
	GearService.refresh(player) -- the look on the body
	CreatorService.showName(player)
	HeroService.sendState(hero)
	DataService.changed(player)
	DataService.saveSoon(player)
	result(player, true, nil)
	Net.fire("Toast", player, { id = "heroSaved", name = CreatorRules.heroName(Config, titleId, nounId) })
	CreatorService.sweep(player) -- the origin's crest, unlocked for the account
	CreatorService.Saved:Fire(player)
end

-- Move a hero to another archetype and path: back to the path's starter skills (credits spent on ranks come
-- back, like a respec), both loadouts on the new path. `counts` uses up the one free change.
function CreatorService.setPath(
	player: Player,
	hero: any,
	c: any,
	classId: string,
	setId: string,
	counts: boolean
)
	local refund = AbilityRules.creditsSpent(Config, hero.ranks, hero.startSet)
	if refund > 0 then
		EconomyService.refund(hero, refund)
	end
	local ranks, loadout = AbilityRules.starter(Config, setId)
	hero.ranks = ranks
	hero.mods = {}
	hero.loadouts = { loadout, table.clone(loadout) }
	hero.loadouts[2].skills = table.clone(loadout.skills)
	hero.loadoutIndex = 1
	hero.loadout = hero.loadouts[1]
	hero.setId = setId
	hero.startSet = setId
	HeroService.setClass(hero, classId)
	c.classId = classId
	c.startSet = setId
	if counts then
		c.pathChanged = 1
	end
	HeroService.refresh(hero)
	Analytics.event(player, "path_change", hero.level, { classId, setId, if counts then "free" else "first" })
end

-- Open the creator on the client in a mode (the opening's Suit Up uses OpeningState; this is for the others)
function CreatorService.open(player: Player, mode: string)
	local _, c = charOf(player)
	if not c then
		return
	end
	Net.fire("CreatorOpen", player, {
		mode = mode,
		side = c.side,
		classIdx = table.find(Config.Classes.order, c.classId) or 1,
		hq = mode == "edit" and CreatorService.inHq(HeroService.get(player)),
		origin = c.origin,
		-- the archetype and path may change in this creator (a new or first-time hero, or the free change)
		pathOpen = mode ~= "edit" or CreatorRules.pathChangeOk(Config, c.level, c.pathChanged),
	})
end

-- Creator first (lore step 2): a brand-new character opens the creator before any story. The hero waits in
-- the "creator" scene (no incidents, events or robots find it) until PLAY starts the opening. Since fix-flow
-- (nate's playtest 2026-11-19: "The game should open with some sort of exposition ... get to the customization,
-- then prologue"), an account's first new hero sees the exposition comic page first (Shared.FlowPlan "intro");
-- the creator opens when the device says it is over (OpeningAct 5) or after Config.Story.opening.intro.timeout.
local function openCreate(player: Player)
	local _, c = charOf(player)
	local hero = HeroService.get(player)
	introAt[player] = nil
	if not c or not hero or not isNew(c) or OpeningService.running(player) then
		return
	end
	hero.scene = "creator"
	Analytics.step(player, "Opening", "creator_open")
	CreatorService.open(player, "create")
end

function CreatorService.createFirst(player: Player)
	local _, c = charOf(player)
	local hero = HeroService.get(player)
	if not c or not hero or not hero.loaded or not isNew(c) or createAsked[player] then
		return
	end
	if hero.scene and hero.scene ~= "creator" then
		return
	end
	createAsked[player] = true
	hero.scene = "creator" -- quiet from the first frame: the exposition and the creator are one waiting room
	local facts = {
		created = c.created,
		opening = c.story.opening,
		introSeen = CinemaService.seenScene(player, Config.Story.opening.intro.scene),
	}
	if FlowPlan.introFirst(facts) then
		local at = os.clock()
		introAt[player] = at
		Net.fire("OpeningIntro", player, {})
		task.delay(Config.Story.opening.intro.timeout, function()
			if introAt[player] == at then
				openCreate(player) -- the device never answered: the creator anyway (never a soft-lock)
			end
		end)
		return
	end
	openCreate(player)
end

-- The street outfit (lore step 2; the prologue in step 3 starts in it and the suit snaps on mid-chase): on
-- puts the hero in plain classic clothes with its own face and hair (Shared.CreatorRules.streetLook: no suit,
-- cape, gear look or weapon); off puts the designed look back. It survives a respawn and ends on a character
-- switch or leaving. Looks only: stats, gear and the weapon in play are unchanged.
function CreatorService.streetOutfit(player: Player, on: boolean)
	GearService.setStreet(player, on)
end

function CreatorService.inStreetOutfit(player: Player): boolean
	return GearService.street(player)
end

-- A hero made before the creator meets it once, a few seconds after joining (out of any scene)
local function maybeFirst(player: Player)
	local _, c = charOf(player)
	local hero = HeroService.get(player)
	if not c or not hero or firstAsked[player] then
		return
	end
	if c.created == 0 and c.story.opening == 1 and not hero.scene then
		firstAsked[player] = true
		CreatorService.open(player, "first")
	end
end

-- Switch to another character slot, or make a new one
local function onSelect(player: Player, slot: number)
	local profile = DataService.get(player)
	local hero = HeroService.get(player)
	if not profile or not hero or not hero.loaded then
		return
	end
	local function no(reason: string)
		Net.fire("Toast", player, { id = "slotRefused", reason = reason })
	end
	if slot == profile.active then
		return
	end
	if hero.scene and hero.scene ~= "hq" then
		no("scene")
		return
	end
	if HeroService.inCombat(hero) or FlagService.flagged(hero) or hero.downed then
		no("combat")
		return
	end
	if not where(hero) then
		no("safehouse")
		return
	end
	local count = #profile.characters
	if slot > count then
		if slot ~= count + 1 then
			no("slot")
			return
		end
		if slot > CreatorRules.maxSlots(profile) then
			no("locked")
			return
		end
	end
	-- write the live hero (and every service's live state) into the current character first
	CreatorService.leaveHq(player)
	DataService.save(player)
	if player.Parent == nil or DataService.get(player) ~= profile then
		return
	end
	if slot > #profile.characters then
		table.insert(profile.characters, ProfileSchema.newCharacter())
	end
	profile.active = slot
	firstAsked[player] = nil
	createAsked[player] = nil
	introAt[player] = nil
	GearService.setStreet(player, false)
	-- every service takes the new character as if it had just loaded
	DataService.Loaded:Fire(player, profile)
	CreatorService.showName(player)
	DataService.changed(player)
	DataService.saveSoon(player)
	Net.fire("Toast", player, { id = "slotSwitched", slot = slot })
end

function CreatorService.init()
	Net.on("HeroCreate", onCreate)
	Net.on("HeroSelect", onSelect)
	DataService.Loaded:Connect(function(player)
		CreatorService.showName(player)
		CreatorService.sweep(player)
		task.delay(4, maybeFirst, player)
		task.delay(1.5, CreatorService.createFirst, player)
	end)
	HeroService.Leveled:Connect(function(hero)
		if hero.player then
			CreatorService.sweep(hero.player)
		end
	end)
	StoryService.Changed:Connect(CreatorService.sweep)
	StoryService.Picked:Connect(function(player)
		CreatorService.sweep(player)
	end)
	EconomyService.Earned:Connect(function(player)
		task.defer(CreatorService.sweep, player) -- after FameService adds the Fame
	end)
	BossService.Rewarded:Connect(function(player)
		CreatorService.sweep(player)
	end)
	GearService.onRareDrop = function(player, profile)
		local p = CreatorRules.dropPick(Config, profile, rng)
		if p and CreatorRules.grant(profile, p) then
			Net.fire("Toast", player, { id = "piece", name = p.name })
		end
	end
	-- the opening ended: a skipped Suit Up (a stuck run) still gets a name and look later
	HeroService.Spawned:Connect(function(hero)
		if hero.player then
			task.delay(6, maybeFirst, hero.player)
			task.delay(1.5, CreatorService.createFirst, hero.player) -- a first body that loaded late
		end
	end)
	-- the exposition is over on the device: the creator (fix-flow)
	OpeningService.IntroDone:Connect(function(player)
		if introAt[player] then
			openCreate(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		introAt[player] = nil
		firstAsked[player] = nil
		createAsked[player] = nil
		GearService.setStreet(player, false)
	end)
end

return CreatorService
