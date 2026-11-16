-- CreatorService: the hero creator, character slots and creator unlocks (spec: Hero creator; Character slots;
-- Faction reputation "a style unlock"; Hero.Create {side, classId, setId, look, colors, titleId, nounId}
-- 1/10s; Hero.Select {slot} 1/5s).
-- * The creator opens in three modes: "create" on the opening's Suit Up step (a new hero: side, class,
--   starting set, look and name), "first" once for a hero made before the creator (name and look), and
--   "edit" at HQ or a safehouse (look and name; the class changes only at HQ, the side and set never).
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
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
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

local CreatorService = {}
CreatorService.Saved = Signal.new() -- (player) a creator save landed (HqService refreshes the mannequins)
-- HqService sets these: is the hero in its HQ, and take it out before a character switch
CreatorService.inHq = function(_hero: any): boolean
	return false
end
CreatorService.leaveHq = function(_player: Player) end

local rng = Rng.new(os.time() % 100000 + 17)
local firstAsked: { [Player]: boolean } = {}

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
local function modeOf(player: Player, hero: any, c: any): (string?, string?)
	if OpeningService.atSuitUp(player) then
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
	nounId: number
)
	local profile, c = charOf(player)
	local hero = HeroService.get(player)
	if not profile or not c or not hero or not hero.loaded then
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
	local ok, reason = CreatorRules.validate(Config, profile, look)
	if not ok then
		result(player, false, reason)
		return
	end
	if not CreatorRules.nameOk(Config, titleId, nounId) then
		result(player, false, "name")
		return
	end
	local classId = Config.Classes.order[classIdx]
	local setId = Config.Creator.startSets[setIdx]
	local side = if sideIdx == 2 then "villain" else "hero"
	if not CreatorRules.pickOk(Config, classId, setId, side) then
		result(player, false, "pick")
		return
	end
	-- the look, the name and the effect style
	c.look = LookCodec.toWords(buf)
	c.titleId, c.nounId = titleId, nounId
	c.fxStyle = if look.anime then "Anime" else "Comic"
	HeroService.setFxStyle(hero, c.fxStyle)
	if mode == "create" then
		-- a new hero: the starting set opens from level 1 and its starter skills are learned
		c.startSet = setId
		hero.startSet = setId
		c.created = 1
		OpeningService.suitUp(player, classId, side)
		local active = hero.loadouts[hero.loadoutIndex]
		if active and active.set ~= setId then
			local ranks, loadout = AbilityRules.starter(Config, setId)
			for id, r in ranks do
				hero.ranks[id] = math.max(hero.ranks[id] or 0, r)
			end
			hero.loadouts = { loadout, table.clone(loadout) }
			hero.loadouts[2].skills = table.clone(loadout.skills)
			hero.loadoutIndex = 1
			hero.loadout = hero.loadouts[1]
			hero.setId = setId
			HeroService.refresh(hero)
		end
	else
		c.created = 1
		-- the class changes only at HQ (spec: Respec and class change at HQ); first-time heroes may pick it
		if classId ~= hero.classId and (mode == "first" or CreatorService.inHq(hero)) then
			HeroService.setClass(hero, classId)
			c.classId = classId
		end
	end
	GearService.refresh(player) -- the look on the body
	CreatorService.showName(player)
	HeroService.sendState(hero)
	DataService.changed(player)
	DataService.saveSoon(player)
	result(player, true, nil)
	Net.fire("Toast", player, { id = "heroSaved", name = CreatorRules.heroName(Config, titleId, nounId) })
	CreatorService.Saved:Fire(player)
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
	})
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
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		firstAsked[player] = nil
	end)
end

return CreatorService
