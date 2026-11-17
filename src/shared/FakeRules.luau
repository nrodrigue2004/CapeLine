--!strict
-- FakeRules: the famous fakes and the evil twin as plain rules (nate's lore, build plan step 4). Silas Crane
-- replaces the city's famous heroes with robots; the public never ties them to him. Pure, so Lune tests it;
-- EnemySim, EnemyService and EnemyRenderer share it.
-- * look: a fake's fixed hero look (Config.Enemies.<Kind>.fake.look: piece names per creator slot, palette
--   colours, materials by name) as a LookCodec look, built from the hero creator's own pieces.
-- * cracked / shellHealth: a fake's face cracks once its health falls to Config.Enemies.fakes.crack (it is
--   unmasked); its shell stays whole until then and breaks off over the rest of its health after.
-- * plate: what its name plate shows: the hero name and title like a real hero's until unmasked, then FAKE.
-- * twinCfg: an evil twin's config for a power path: the twin's base with its path's fighting style on top.

local LookCodec = if script then require(script.Parent.LookCodec) else (require :: any)("./LookCodec")
local CreatorRules = if script
	then require(script.Parent.CreatorRules)
	else (require :: any)("./CreatorRules")

local FakeRules = {}

-- the LookCodec record (repeated here: the pure-module require pattern drops cross-module types)
export type Look = {
	pieces: { [string]: number },
	colors: { number },
	hair: number,
	skin: number,
	anime: boolean,
	gender: number,
	build: number,
	height: number,
	eyeColor: number,
	tints: { [string]: { number } },
	mats: { [string]: number },
}

export type Plate = { name: string, sub: string, red: boolean }

local looks: { [any]: { [string]: Look } } = {}
local twins: { [any]: { [string]: any } } = {}

-- A fixed hero look from a config def (piece names per creator slot, palette colours, materials by name).
-- Errors on a piece or material name the creator does not have, so a typo fails the tests, not the game.
local function fromDef(Config: any, def: any, label: string): Look
	local byTab = CreatorRules.index(Config).byTab
	local pieces: { [string]: number } = {}
	for _, slot in LookCodec.ALL do
		pieces[slot] = 0
	end
	for slot, name in def.pieces do
		local list = byTab[slot]
		local found = 0
		for i, p in list or {} do
			if p.name == name then
				found = i
				break
			end
		end
		assert(found > 0, string.format("FakeRules: %s has no %s piece %q", label, slot, name))
		pieces[slot] = found
	end
	local mats: { [string]: number } = {}
	for slot, name in def.mats or {} do
		local m = table.find(Config.Creator.materials, name)
		assert(m, string.format("FakeRules: %s has no material %q", label, name))
		mats[slot] = m
	end
	local tints: { [string]: { number } } = {}
	for slot, t in def.tints or {} do
		tints[slot] = table.clone(t)
	end
	return {
		pieces = pieces,
		colors = table.clone(def.colors),
		hair = def.hair,
		skin = def.skin,
		anime = false,
		gender = def.gender,
		build = def.build,
		height = def.height,
		eyeColor = def.eyeColor or 0,
		tints = tints,
		mats = mats,
	}
end

-- A fake's fixed look; a kind with no `fake.look` (the twin, before it knows its hero) wears the default look.
function FakeRules.look(Config: any, kind: string): Look
	local cache = looks[Config]
	if not cache then
		cache = {}
		looks[Config] = cache
	end
	local hit = cache[kind]
	if hit then
		return LookCodec.copy(hit :: any) :: any
	end
	local cfg = Config.Enemies[kind]
	local def = cfg and cfg.fake and cfg.fake.look
	local look: Look = if def then fromDef(Config, def, kind) else CreatorRules.defaultLook(Config) :: any
	cache[kind] = look
	return LookCodec.copy(look :: any) :: any
end

-- A story character's fixed hero look (lore step 3: Lodestar, Config.Story.opening.lodestar.look), built the
-- same way from earnable creator pieces
function FakeRules.lookFrom(Config: any, def: any, label: string): Look
	return fromDef(Config, def, label)
end

-- The health fraction at which a fake's face cracks
function FakeRules.crackAt(Config: any): number
	return Config.Enemies.fakes.crack
end

-- Is a fake at this health fraction (0 to 1) unmasked?
function FakeRules.cracked(Config: any, health: number): boolean
	return health <= Config.Enemies.fakes.crack + 1e-9
end

-- The health a fake's shell breaks by (RobotDamage.count): whole until the face cracks, then the shell breaks
-- off over the health that is left, so it is all metal near defeat like any robot
function FakeRules.shellHealth(Config: any, health: number, unmasked: boolean): number
	if not unmasked then
		return 1
	end
	local c = Config.Enemies.fakes.crack
	return math.clamp(health / c, 0, 1)
end

-- What a fake's plate shows. ident (an evil twin): the copied hero's name and title. Until unmasked it reads
-- like a real hero's plate (the name big, the title under it, no robot tag); then FAKE in red over the name.
function FakeRules.plate(Config: any, kind: string, unmasked: boolean, ident: { [string]: any }?): Plate
	local cfg = Config.Enemies[kind]
	local name = if ident and type(ident.name) == "string" and ident.name ~= "" then ident.name else cfg.name
	local title = if ident
		then (if type(ident.title) == "string" then ident.title else "")
		else cfg.fake.title
	if unmasked then
		return { name = Config.Enemies.fakes.word, sub = string.upper(name), red = true }
	end
	return { name = string.upper(name), sub = title or "", red = false }
end

-- The fighting style an evil twin takes for a power path (the default path's for an unknown one)
function FakeRules.styleOf(Config: any, path: string?): string
	local t = Config.Enemies.EvilTwin.twin
	return t.paths[path or ""] or t.paths[t.default]
end

-- An evil twin's config for a power path: the twin's base, then its style's fields on top (cached; treat it
-- as read-only). fake.path is the path, so its attacks are drawn in that path's look.
function FakeRules.twinCfg(Config: any, path: string?): any
	local base = Config.Enemies.EvilTwin
	local p = if path and base.twin.paths[path] then path else base.twin.default
	local cache = twins[Config]
	if not cache then
		cache = {}
		twins[Config] = cache
	end
	local hit = cache[p]
	if hit then
		return hit
	end
	local out = table.clone(base)
	for k, v in base.twin.styles[base.twin.paths[p]] do
		out[k] = v
	end
	out.fake = { title = base.fake.title, path = p }
	out.style = base.twin.paths[p]
	cache[p] = out
	return out
end

return FakeRules
