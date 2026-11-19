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

local QtePlan = {}

export type Prompt = { action: string, word: string }
export type After = { go: string, wait: number, misses: number }

-- the keys a prompt listens for (any other action is ignored, never a miss)
QtePlan.KEYS = { Leap = true, Block = true, Basic = true }

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
		return out
	elseif step == "descend" then
		return { { action = "Leap", word = W.drop } }
	end
	return {}
end

function QtePlan.window(Config: any, misses: number): number
	local Q = Config.Story.opening.qte
	return if misses > 0 then Q.window * Q.ease else Q.window
end

function QtePlan.judge(Config: any, action: string, pressed: string, t: number, misses: number): string?
	if not QtePlan.KEYS[pressed] or t < 0 then
		return nil
	end
	if t > QtePlan.window(Config, misses) then
		return "miss"
	end
	return if pressed == action then "hit" else "miss"
end

function QtePlan.expired(Config: any, t: number, misses: number): boolean
	return t > QtePlan.window(Config, misses)
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
