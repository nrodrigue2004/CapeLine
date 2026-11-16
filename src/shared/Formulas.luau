--!strict
-- Formulas: every stat and damage formula in the spec (Damage and stats formulas, Stats, Enemies). Pure, so
-- the server, the client's predicted numbers and the Lune tests all use the same maths.

local Formulas = {}

local function cfgOf(config: any): any
	return config
end

-- Power(L) = 30 + 6 x L + Might
function Formulas.power(config: any, level: number, might: number?): number
	local s = cfgOf(config).Stats.power
	return s.base + s.perLevel * level + (might or 0)
end

-- Health(L) = (400 + 25 x L + 5 x Vitality) x class HP mult
function Formulas.health(config: any, level: number, vitality: number?, classId: string?): number
	local s = config.Stats.health
	local class = config.Classes[classId or config.Classes.default]
	local mult = if class then class.healthMult else 1
	return math.floor((s.base + s.perLevel * level + s.perVitality * (vitality or 0)) * mult + 0.5)
end

-- Cooldown reduction = Focus / (Focus + 400), capped 40%
function Formulas.cooldownReduction(config: any, focus: number): number
	local s = config.Stats.focus
	if focus <= 0 then
		return 0
	end
	return math.min(s.cap, focus / (focus + s.k))
end

-- Crit chance = Precision / (Precision + 600), capped 50%
function Formulas.critChance(config: any, precision: number): number
	local s = config.Stats.precision
	if precision <= 0 then
		return 0
	end
	return math.min(s.cap, precision / (precision + s.k))
end

-- CC duration multiplier = 1 - Resolve / (Resolve + 500), minimum 0.5
function Formulas.ccMultiplier(config: any, resolve: number): number
	local s = config.Stats.resolve
	if resolve <= 0 then
		return 1
	end
	return math.max(s.floor, 1 - resolve / (resolve + s.k))
end

-- Damage = Power x ability coeff x class mult x (1 + 0.5 if crit) x (1 - mitigation)
function Formulas.damage(
	config: any,
	power: number,
	coeff: number,
	classId: string?,
	crit: boolean?,
	mitigation: number?
): number
	local class = config.Classes[classId or config.Classes.default]
	local classMult = if class then class.damageMult else 1
	local critMult = if crit then 1 + config.Stats.precision.critBonus else 1
	local mit = math.clamp(mitigation or 0, 0, 0.9)
	return power * coeff * classMult * critMult * (1 - mit)
end

-- Enemy HP x (1 + 0.1 x (zone level - 1))
function Formulas.enemyHealth(config: any, kind: string, zoneLevel: number): number
	local e = config.Enemies[kind]
	return math.floor(e.hp * (1 + config.Enemies.scale.hpPerLevel * (zoneLevel - 1)) + 0.5)
end

-- Enemy damage = (20 + 4 x level) x coeff
function Formulas.enemyDamage(config: any, kind: string, zoneLevel: number): number
	local e = config.Enemies[kind]
	local s = config.Enemies.scale
	return (s.dmgBase + s.dmgPerLevel * zoneLevel) * e.coeff
end

-- Effective cooldown after Focus and the class modifier
function Formulas.cooldown(config: any, base: number, focus: number, classId: string?): number
	if base <= 0.5 then
		return base -- basics keep their fire rate
	end
	local class = config.Classes[classId or config.Classes.default]
	local classMod = if class and class.cooldowns then class.cooldowns else 0
	return base * (1 - Formulas.cooldownReduction(config, focus)) * (1 + classMod)
end

return Formulas
