-- Damage and stats formulas (spec: Damage and stats formulas, Stats). (tune)
return {
	power = { base = 30, perLevel = 6 }, -- Power(L) = 30 + 6 x L + Might
	health = { base = 400, perLevel = 25, perVitality = 5 }, -- Health(L) = (400 + 25 x L + 5 x Vit) x class mult
	focus = { k = 400, cap = 0.40 }, -- cooldown reduction = Focus / (Focus + 400)
	precision = { k = 600, cap = 0.50, critBonus = 0.5 },
	resolve = { k = 500, floor = 0.5 },
	levelCap = 40,
	-- Out-of-combat regen. Not in the spec (it has no PvE healing outside abilities); without it a solo hero
	-- slowly runs out of health between incidents. Logged in Decisions.md. (tune)
	regen = { delay = 6, perSecond = 0.04 },
	respawnTime = 5, -- spec: Defeated, respawn 5 s (the Downed state arrives in M8)
}
