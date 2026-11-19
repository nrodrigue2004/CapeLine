--!strict
-- BodyFit: where a creator piece, a gear look's fallback part or a weapon sits on the body it is worn on
-- (pt-fit, nate's playtest 2026-11-19: "a lot of weapons and just customization things aren't modeled properly or
-- aren't on the player properly"). Every piece's fit (Config.CapeArt, HeadArt, GloveArt, ... WeaponArt and
-- LookKit's and WeaponKit's part specs) is written against the classic blocks of Config.HeroRig: offsets from each
-- part's centre, in studs. Heroes, robots and citizens now stand on Roblox's own blocky R15 body
-- (Config.RobloxRig), which shows the same classic blocks but whose limb boxes are taller and overlap at the
-- joints (an upper arm is 1.169 tall, centred 0.206 lower than the block it shows). LookKit and WeaponKit used
-- to scale a piece by the part's box against HeroRig's (x1.375 on an upper arm, x1.40 on a shin), so pieces
-- on the arms and legs stretched and slid down the limb. BodyFit maps the fit's frame onto the body:
-- * on Roblox's body, a limb or torso piece keeps its place in the world at rest (the shown block is the same:
--   the fit's centre is shifted by HeroRig's centre minus Roblox's, nothing stretched); a head piece maps the
--   classic head's box onto Roblox's rounded head (its centre and size), as before;
-- * on the Blender body (the fallback) nothing changes: the box against HeroRig's.
-- Either way a bigger or smaller body part (the creator's builds, when the Body step is on) scales the piece with
-- it. frame(Config, partName, size) gives the shift (studs, in the part's frame) and the per-axis scale; a
-- piece's CFrame is part.CFrame * CFrame.new(shift) * CFrame.new(offset * scale), its size size * scale. Which
-- body it is comes from the part's own proportions (each limb box's height over its width), so a rig never has
-- to say. Pure, so Lune tests it.

local BodyFit = {}

export type Vec = { number }

local function v3(t: any): Vec
	return { t[1], t[2], t[3] }
end

-- Which rig a part's size is closest to, by its proportions (height over width and depth); "roblox" or "hero"
function BodyFit.kind(Config: any, name: string, size: Vec): string
	local r = Config.RobloxRig.parts[name]
	local h = Config.HeroRig.parts[name]
	if not (r and h) then
		return "hero"
	end
	local function off(ref: Vec): number
		local a = (size[2] / size[1]) / (ref[2] / ref[1])
		local b = (size[2] / size[3]) / (ref[2] / ref[3])
		return math.abs(math.log(a)) + math.abs(math.log(b))
	end
	return if off(r.size) < off(h.size) - 1e-6 then "roblox" else "hero"
end

-- The fit frame on a body part of this name and size: shift (in the part's frame) and scale
function BodyFit.frame(Config: any, name: string, size: Vec): (Vec, Vec)
	local h = Config.HeroRig.parts[name]
	if not h then
		return { 0, 0, 0 }, { 1, 1, 1 }
	end
	local hs = h.size
	if BodyFit.kind(Config, name, size) ~= "roblox" then
		return { 0, 0, 0 }, { size[1] / hs[1], size[2] / hs[2], size[3] / hs[3] }
	end
	local r = Config.RobloxRig.parts[name]
	local rs = r.size
	-- how much bigger this part is than Roblox's standard one (1 on the standard body)
	local k = { size[1] / rs[1], size[2] / rs[2], size[3] / rs[3] }
	if name == "Head" then
		-- the classic head's box onto Roblox's rounded head, centre on centre
		return { 0, 0, 0 }, { rs[1] / hs[1] * k[1], rs[2] / hs[2] * k[2], rs[3] / hs[3] * k[3] }
	end
	local hc, rc = h.centre, r.centre
	return { (hc[1] - rc[1]) * k[1], (hc[2] - rc[2]) * k[2], (hc[3] - rc[3]) * k[3] }, k
end

-- A fit's box (offset and size on HeroRig's part) on a body part of this name and size: its centre from the
-- part's centre and its size, both in the part's frame
function BodyFit.place(Config: any, name: string, size: Vec, offset: Vec, box: Vec): (Vec, Vec)
	local shift, f = BodyFit.frame(Config, name, size)
	return {
		shift[1] + offset[1] * f[1],
		shift[2] + offset[2] * f[2],
		shift[3] + offset[3] * f[3],
	}, { box[1] * f[1], box[2] * f[2], box[3] * f[3] }
end

-- Roblox's standard part size (for tests and the renders)
function BodyFit.robloxSize(Config: any, name: string): Vec?
	local r = Config.RobloxRig.parts[name]
	return if r then v3(r.size) else nil
end

return BodyFit
