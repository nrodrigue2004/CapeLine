--!strict
-- QtePlan: the prologue's rooftop chase as quick-time prompts (fix-flow, nate's playtest 2026-11-19: "It should be a
-- cutscene with QTE's"; Config.Story.opening.qte). Pure, so Lune checks the timing and every branch.
-- * prompts(Config, step, hop): the prompts for one hop of a beat, in order: { action, word } (action is an
--   InputController action: "Leap" to JUMP, "Block" to DODGE). The leap beat's one hop, each chase hop (DODGE first
--   on Config's dodge roofs), and the drop to the subway.
-- * window(Config, misses): how long a prompt stays open (longer after a miss).
-- * judge(Config, action, pressed, t, misses): one press `t` s after the prompt showed: "hit", "miss" (a wrong
--   prompt key, or too late) or nil (not a prompt key, or before the prompt showed: ignored).
-- * expired(Config, t, misses): no press in time (a miss).
-- * after(Config, result, misses): what comes next: { go = "next" | "retry" | "assist", wait = seconds, misses }.
--   A hit moves on; a miss retries after `retry` s; the `assist`-th miss in a row does the move by itself, so the
--   story always goes on (no dead ends).
-- prologue-cine (nate, 2026-11-20: "whole prologue needs to be cutscene with qtes until subway"): every beat to the
-- subway fight has prompts now (Shared.PrologueCine authors which and where). A prompt has a kind: "press" (one
-- press: JUMP, DODGE, GRAB, SHIELD, SMASH), "mash" (Config's mash.count presses inside mash.window s: a struggle)
-- or "hold" (the key held hold.seconds inside hold.window s: the suit snap). mashStep and holdStep are its rules;
-- worst(prompt) is the longest it can take (every try missed to the help), which the stuck timers must outlast.

local QtePlan = {}

export type Prompt = { action: string, word: string, kind: string?, count: number?, hold: number? }
export type After = { go: string, wait: number, misses: number }

-- the keys a prompt listens for (any other action is ignored, never a miss)
-- (prologue-cine: Catch is GRAB: B, the pad's X, or a tap)
QtePlan.KEYS = { Leap = true, Block = true, Basic = true, Catch = true }

function QtePlan.on(Config: any, step: string?): boolean
	return step ~= nil and Config.Story.opening.qte.beats[step] == true
end

function QtePlan.camera(Config: any, step: string?): boolean
	return step ~= nil and Config.Story.opening.qte.camera[step] == true
end

function QtePlan.prompts(Config: any, step: string, hop: number?): { Prompt }
	local Q = Config.Story.opening.qte
	local W = Q.words
	if step == "leap" then
		return { { action = "Leap", word = W.Leap } }
	elseif step == "chase" then
		local out = {}
		if Q.dodge[hop or 0] then
			table.insert(out, { action = "Block", word = W.Block })
		end
		table.insert(out, { action = "Leap", word = W.Leap })
		if Q.grab == hop then
			-- (prologue-cine) the long hop falls short: GRAB the ledge, then climb
			table.insert(out, { action = "Catch", word = W.Catch })
		end
		return out
	elseif step == "descend" then
		return { { action = "Leap", word = W.drop } }
	end
	return {}
end

-- first-30 (nate 2026-11-20: "Qtes shouldn't be timed in prologue"): while the device says a prompt waits for
-- its press (OpeningAct 8, `r.qteUp`), the server's prologue run holds its clocks: the beat's start (the stuck
-- timer and the Spark's backstop count from it) and the whole prologue's start (its timeout), up to Config's
-- qte.waitMax s in all, so an away player's prologue still ends. Returns true while it holds.
function QtePlan.holdClocks(Config: any, r: any, dt: number): boolean
	local Q = Config.Story.opening.qte
	if not (Q.wait and r.qteUp and (r.qteWaited or 0) < Q.waitMax) then
		return false
	end
	r.qteWaited = (r.qteWaited or 0) + dt
	r.qteStep = (r.qteStep or 0) + dt
	r.stepAt += dt
	r.startedAt += dt
	return true
end

-- How long a prompt stays open: a press's window, a mash's or a hold's (each `ease` times longer after a miss);
-- forever when prompts wait for their press (Config's `wait`, first-30 2026-11-20)
function QtePlan.window(Config: any, misses: number, kind: string?): number
	local Q = Config.Story.opening.qte
	if Q.wait then
		return math.huge
	end
	local w = if kind == "mash" then Q.mash.window elseif kind == "hold" then Q.hold.window else Q.window
	return if misses > 0 then w * Q.ease else w
end

-- A mash prompt: one more press of the right key (or a tap on the prompt). Returns the presses so far and whether
-- that is enough (Config's mash.count, or the prompt's own count)
function QtePlan.mashStep(Config: any, p: Prompt, presses: number): (number, boolean)
	local need = p.count or Config.Story.opening.qte.mash.count
	local n = presses + 1
	return n, n >= need
end

-- A hold prompt: how full it is after `held` s of the key held down (0 to 1), and whether it is done. Letting go
-- before it fills empties it again (the caller passes 0 held), which is never a miss by itself.
function QtePlan.holdStep(Config: any, p: Prompt, held: number): (number, boolean)
	local need = p.hold or Config.Story.opening.qte.hold.seconds
	local f = math.clamp(held / math.max(0.05, need), 0, 1)
	return f, f >= 1
end

-- The longest one prompt can take: shown `lead` s in, then every try missed (each window run out) until the
-- `assist`-th miss does it by itself
function QtePlan.worst(Config: any, kind: string?): number
	local Q = Config.Story.opening.qte
	if Q.wait then
		return Q.lead -- a waiting prompt holds the server's clocks, so only its lead counts
	end
	local t = Q.lead
	for k = 0, Q.assist - 1 do
		t += QtePlan.window(Config, k, kind) + (if k < Q.assist - 1 then Q.retry else 0)
	end
	return t
end

function QtePlan.judge(
	Config: any,
	action: string,
	pressed: string,
	t: number,
	misses: number,
	kind: string?
): string?
	if not QtePlan.KEYS[pressed] or t < 0 then
		return nil
	end
	if Config.Story.opening.qte.wait and pressed ~= action then
		return nil -- a waiting prompt ignores the wrong key (nothing is missed)
	end
	if t > QtePlan.window(Config, misses, kind) then
		return "miss"
	end
	return if pressed == action then "hit" else "miss"
end

function QtePlan.expired(Config: any, t: number, misses: number, kind: string?): boolean
	return t > QtePlan.window(Config, misses, kind)
end

function QtePlan.after(Config: any, result: string, misses: number): After
	local Q = Config.Story.opening.qte
	if result == "hit" then
		return { go = "next", wait = Q.lead, misses = 0 }
	end
	local m = misses + 1
	if m >= Q.assist then
		return { go = "assist", wait = 0, misses = 0 }
	end
	return { go = "retry", wait = Q.retry, misses = m }
end

-- The chase camera for a hop from `p` toward `to` (both { x, y, z }): its position and look point, out to the
-- side of the hop, up and a little behind, so the hero, the next roof and Skylance behind all show
function QtePlan.camera3(Config: any, p: { number }, to: { number }): ({ number }, { number })
	local Q = Config.Story.opening.qte
	local dx, dz = to[1] - p[1], to[3] - p[3]
	local l = math.sqrt(dx * dx + dz * dz)
	if l < 0.01 then
		dx, dz, l = 0, -1, 1
	end
	dx, dz = dx / l, dz / l
	local sx, sz = -dz, dx -- the hop's right-hand side
	local cam = {
		p[1] + sx * Q.camSide - dx * Q.camBack,
		p[2] + Q.camUp,
		p[3] + sz * Q.camSide - dz * Q.camBack,
	}
	local look =
		{ p[1] + (to[1] - p[1]) * 0.35, p[2] + 2 + (to[2] - p[2]) * 0.35, p[3] + (to[3] - p[3]) * 0.35 }
	return cam, look
end

return QtePlan
