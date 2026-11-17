--!strict
-- TouchLayout: where the HUD's buttons go on any screen (overhaul plan step 8, the phone pass). Pure, so
-- Lune tests it. Screen numbers are in Roblox GUI pixels (points on phones) inside a ScreenGui's safe area.
-- * compact(w, h): a phone-sized screen (landscape height under Config.Ui.phone.compactBelow).
-- * stickZone(w, h, mode): the move stick's touch area as a box (Roblox's dynamic thumbstick on the left;
--   our own on the right for left-handed and one-hand play), so no button lands in it.
-- * clusterScale(Config, w, h, opts): the action cluster's size: as big as Config.Ui.phone wants on this
--   device times the player's Button size setting, but never bigger than fits under the top row.
-- * cluster(Config, w, h, opts): every action button's centre and size (mirrored for left-handed).
-- * dock(Config, items, lo, hi, w, h, fromLo): the top row of screen buttons, from one end by order; the
--   ones that do not fit go in the MORE drawer.
-- * hud(Config, w, h, opts): the display parts' boxes (status card, wallet, buffs, radar, tracker, squad
--   list) and the top row's span, phone or not, left-handed or not.
-- * panelScale(Config, w, h, designW, designH): the UIScale for a panel drawn at a design size, so it fits the
--   screen (text never shrinks under Config.Ui.phone.minPanelScale; the panel scrolls instead).

local TouchLayout = {}

export type Slot = { x: number, y: number, d: number, optional: boolean? }
export type Placed = { x: number, y: number, size: number }
export type Box = { x: number, y: number, w: number, h: number }

-- The action cluster at design size: each button's centre from the Basic button's centre (x left is
-- negative, y up is negative) and its diameter. Rings of 4 skills around the basic, the super outside them,
-- movement to the left, the rarer buttons (swap, gadget, Awaken, Down) at the edges. Catch (the opening's
-- verb) shares the super's spot (they never show together). Block is kept for the Hero MMO features (H1):
-- a button named Block in the cluster takes it, and the cluster sizes for it only once it exists.
TouchLayout.SLOTS = {
	Basic = { x = 0, y = 0, d = 84 },
	Skill1 = { x = -126, y = 0, d = 60 },
	Skill2 = { x = -109, y = -63, d = 60 },
	Skill3 = { x = -63, y = -109, d = 60 },
	Skill4 = { x = 0, y = -126, d = 60 },
	Super = { x = -160, y = -160, d = 64 },
	Catch = { x = -160, y = -160, d = 84 },
	Swap = { x = 0, y = -200, d = 54 },
	Awaken = { x = -74, y = -200, d = 54 },
	Leap = { x = -224, y = 0, d = 66 },
	Fly = { x = -224, y = -84, d = 58 },
	Gadget = { x = -236, y = -164, d = 54 },
	Boost = { x = -304, y = -42, d = 58 },
	Down = { x = -304, y = -126, d = 54 },
	Block = { x = -384, y = -42, d = 58, optional = true },
} :: { [string]: Slot }

-- Pairs that share a spot on purpose
TouchLayout.SHARED = { Catch = "Super" }

-- The stamina dots ring the Boost button this far out (design pixels) and count as part of it
TouchLayout.RING = 10

-- The buttons players press most: these never shrink under Config.Ui.phone.minPrimary
TouchLayout.PRIMARY = { "Basic", "Skill1", "Skill2", "Skill3", "Skill4", "Super", "Leap", "Fly", "Boost" }

function TouchLayout.compact(Config: any, w: number, h: number): boolean
	return math.min(w, h) < Config.Ui.phone.compactBelow
end

-- The move stick's touch area. "default" is Roblox's dynamic thumbstick (the left 40%, the lower two
-- thirds); "left" and "oneHand" are InputController's own stick (the right 45%, the lower 60%).
function TouchLayout.stickZone(w: number, h: number, mode: string?): Box
	if mode == "left" or mode == "oneHand" then
		return { x = w * 0.55, y = h * 0.4, w = w * 0.45, h = h * 0.6 }
	end
	return { x = 0, y = h / 3, w = w * 0.4, h = h * 2 / 3 }
end

-- The cluster's extent at design size (left, top, right, bottom from the Basic centre), counting the
-- Boost ring and leaving out optional slots nobody uses
function TouchLayout.extent(present: { [string]: boolean }?): (number, number, number, number)
	local l, t, r, b = 0, 0, 0, 0
	for id, s in TouchLayout.SLOTS do
		if not s.optional or (present and present[id]) then
			local rad = s.d / 2 + (if id == "Boost" then TouchLayout.RING else 0)
			l = math.min(l, s.x - rad)
			t = math.min(t, s.y - rad)
			r = math.max(r, s.x + rad)
			b = math.max(b, s.y + rad)
		end
	end
	return l, t, r, b
end

-- The height the top row takes (its margin, its buttons and a gap under it)
function TouchLayout.topReserve(Config: any, w: number, h: number): number
	local P = Config.Ui.phone
	local row = if TouchLayout.compact(Config, w, h) then P.rowCompact else P.row
	return Config.Ui.safe + row + P.gap
end

export type ClusterOpts = {
	user: number?, -- the Button size setting (1 = 100%)
	touch: boolean?, -- touch draws full size; mouse and gamepad a little smaller
	leftHanded: boolean?,
	present: { [string]: boolean }?, -- optional slots in use (Block)
}

function TouchLayout.clusterScale(Config: any, w: number, h: number, opts: ClusterOpts?): number
	local o: ClusterOpts = opts or {}
	local P = Config.Ui.phone
	local l, t, r, b = TouchLayout.extent(o.present)
	local m = Config.Ui.safe
	local fitH = (h - TouchLayout.topReserve(Config, w, h) - m) / (b - t)
	local fitW = (w * P.clusterWidth - m) / (r - l)
	local want = (if o.touch == false then P.desktopScale else 1) * (o.user or 1)
	return math.clamp(math.min(fitH, fitW, want, P.maxScale), P.minScale, P.maxScale)
end

-- Every slot placed on a w x h safe area: centre and diameter in pixels
function TouchLayout.cluster(
	Config: any,
	w: number,
	h: number,
	opts: ClusterOpts?
): ({ [string]: Placed }, number)
	local o: ClusterOpts = opts or {}
	local s = TouchLayout.clusterScale(Config, w, h, o)
	local m = Config.Ui.safe
	local _, _, r, b = TouchLayout.extent(o.present)
	-- the Basic centre: the cluster's right and bottom edges sit on the safe margin
	local cx = w - m - r * s
	local cy = h - m - b * s
	local out: { [string]: Placed } = {}
	for id, slot in TouchLayout.SLOTS do
		local x = cx + slot.x * s
		if o.leftHanded then
			x = w - x
		end
		out[id] = { x = x, y = cy + slot.y * s, size = slot.d * s }
	end
	return out, s
end

-- The cluster's bounding box on screen
function TouchLayout.clusterBox(Config: any, w: number, h: number, opts: ClusterOpts?): Box
	local o: ClusterOpts = opts or {}
	local placed, s = TouchLayout.cluster(Config, w, h, o)
	local l, t, r, b = TouchLayout.extent(o.present)
	local basic = placed.Basic
	local x0 = basic.x + l * s
	local x1 = basic.x + r * s
	if o.leftHanded then
		x0, x1 = basic.x - r * s, basic.x - l * s
	end
	return { x = x0, y = basic.y + t * s, w = x1 - x0, h = (b - t) * s }
end

-- A button's width in the top row for its label at row height
function TouchLayout.labelWidth(Config: any, text: string, row: number): number
	local P = Config.Ui.phone
	local n = utf8.len(text) or #text
	return math.max(row, math.floor(n * row * P.glyph + P.padX + 0.5))
end

export type DockItem = { id: string, text: string, order: number }
export type DockPlan = {
	row: { [string]: Box }, -- the buttons in the top row
	drawer: { string }, -- the rest, in order, for the MORE drawer
	more: Box?, -- the MORE button when the drawer has any
	height: number,
}

-- The top row between x = lo and x = hi: items by order from the hi end towards lo (from the lo end when
-- fromLo, for the left-handed phone layout). The ones that do not fit, and everything after the first that
-- does not, go in the drawer in order; MORE then takes the outer end.
function TouchLayout.dock(
	Config: any,
	items: { DockItem },
	lo: number,
	hi: number,
	w: number,
	h: number,
	fromLo: boolean?
): DockPlan
	local P = Config.Ui.phone
	local row = if TouchLayout.compact(Config, w, h) then P.rowCompact else P.row
	local m, gap = Config.Ui.safe, P.gap
	local list = table.clone(items)
	table.sort(list, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.id < b.id
	end)
	local function at(dist: number, bw: number): Box
		return if fromLo
			then { x = lo + dist, y = m, w = bw, h = row }
			else { x = hi - dist - bw, y = m, w = bw, h = row }
	end
	local function place(withMore: boolean): ({ [string]: Box }, { string }, Box?)
		local cursor = 0 -- distance used from the outer end
		local more: Box? = nil
		if withMore then
			local mw = TouchLayout.labelWidth(Config, "MORE", row)
			more = at(0, mw)
			cursor = mw + gap
		end
		local placed: { [string]: Box } = {}
		local rest: { string } = {}
		for _, it in list do
			local bw = TouchLayout.labelWidth(Config, it.text, row)
			if #rest == 0 and cursor + bw <= hi - lo then
				placed[it.id] = at(cursor, bw)
				cursor += bw + gap
			else
				table.insert(rest, it.id)
			end
		end
		return placed, rest, more
	end
	local placed, rest, more = place(false)
	if #rest > 0 then
		placed, rest, more = place(true)
	end
	return { row = placed, drawer = rest, more = more, height = row }
end

export type HudBoxes = {
	status: Box,
	buffs: Box,
	wallet: Box,
	radar: Box,
	radarText: Box, -- the first of three text lines under the radar (clock, boss timer, friend boost)
	tracker: Box, -- the incident tracker; its height fits whole rows
	trackerRows: number,
	squad: Box, -- the squad list
	dockLo: number, -- the top row's span
	dockHi: number,
	dockFromLo: boolean,
	compact: boolean,
	radarTaps: boolean, -- false when the radar sits in the move stick's zone (MAP opens the map instead)
}

-- The HUD's display parts for a w x h safe area. Elsewhere it is the M10 layout (status, buffs and radar
-- down the left; wallet and tracker under the top row on the right). On a phone the radar, status card,
-- wallet, buffs and tracker share the top-left corner (all display, so the move stick works under them),
-- mirrored to the right for left-handed, and the tracker shows only the rows that fit.
function TouchLayout.hud(Config: any, w: number, h: number, opts: ClusterOpts?): HudBoxes
	local o: ClusterOpts = opts or {}
	local P = Config.Ui.phone
	local m, gap = Config.Ui.safe, P.gap
	local compact = TouchLayout.compact(Config, w, h)
	local row = if compact then P.rowCompact else P.row
	local rowH = P.trackerRow
	local cb = TouchLayout.clusterBox(Config, w, h, o)
	-- the cluster's nearest edge to the corner group (the Boost ring counted), for the parts beside it
	local placed, s = TouchLayout.cluster(Config, w, h, o)
	local inner = w
	for id, p in placed do
		local slot = TouchLayout.SLOTS[id]
		if not slot.optional or (o.present and o.present[id]) then
			local rad = p.size / 2 + (if id == "Boost" then TouchLayout.RING * s else 0)
			inner = math.min(inner, if o.leftHanded then w - (p.x + rad) else p.x - rad)
		end
	end
	local out: HudBoxes
	if compact then
		local r = P.radarCompact
		local sw = P.statusCompactW
		local sx = m + r + gap
		local ty = m + 104 + 46
		local rows = math.clamp(math.floor((h - m - ty + 6) / rowH), 0, 2)
		out = {
			status = { x = sx, y = m, w = sw, h = 104 },
			wallet = { x = sx, y = m + 104 + 4, w = sw, h = 16 },
			buffs = { x = sx, y = m + 104 + 22, w = sw, h = 22 },
			radar = { x = m, y = m, w = r, h = r },
			radarText = { x = m, y = m + r + 2, w = r, h = 16 },
			tracker = { x = sx, y = ty, w = math.min(sw, inner - gap - sx), h = math.max(0, rows * rowH - 6) },
			trackerRows = rows,
			squad = { x = m, y = m + r + 54, w = r, h = 100 },
			dockLo = sx + sw + gap,
			dockHi = w - m,
			dockFromLo = false,
			compact = true,
			radarTaps = false,
		}
		if o.leftHanded then
			-- the cluster is on the left: the corner group moves to the right and the row fills from the left
			for _, key in { "status", "wallet", "buffs", "radar", "radarText", "tracker", "squad" } do
				local b = (out :: any)[key]
				b.x = w - b.x - b.w
			end
			out.dockLo, out.dockHi, out.dockFromLo = m, w - (sx + sw + gap), true
		end
	else
		local size = 132
		local ty = m + row + gap + 18 + 4
		-- whole rows that fit above the cluster when it is on the same side
		local bottom = if o.leftHanded then h - m else cb.y - gap
		local rows = math.clamp(math.floor((bottom - ty + 6) / rowH), 0, 6)
		out = {
			status = { x = m, y = m, w = 250, h = 104 },
			buffs = { x = m, y = m + 110, w = 250, h = 22 },
			wallet = { x = w - m - 260, y = m + row + 4, w = 260, h = 18 },
			radar = { x = m, y = m + 150, w = size, h = size },
			radarText = { x = m, y = m + 150 + size + 2, w = size + 40, h = 18 },
			tracker = { x = w - m - 250, y = ty, w = 250, h = math.max(0, rows * rowH - 6) },
			trackerRows = rows,
			squad = { x = m, y = m + 150 + size + 60, w = 200, h = 100 },
			dockLo = m + 250 + gap,
			dockHi = w - m,
			dockFromLo = false,
			compact = false,
			radarTaps = true,
		}
		-- the radar column beside the status card instead of under it, so the squad list sits higher
		local function besideStatus()
			local rx = m + 250 + gap
			out.radar = { x = rx, y = m, w = size, h = size }
			out.radarText = { x = rx, y = m + size + 2, w = size + 40, h = 18 }
			out.squad = { x = rx, y = m + size + 60, w = 200, h = 100 }
			out.dockLo = rx + size + gap
		end
		if o.leftHanded then
			-- the mirrored cluster takes the bottom left: the squad list stops above it
			local room = cb.y - gap
			if out.squad.y + out.squad.h > room then
				besideStatus()
				out.squad.h = math.max(40, math.min(out.squad.h, room - out.squad.y))
			end
		elseif o.touch then
			-- a tablet: the move stick owns the lower left, so the radar goes beside the status card
			local zone = TouchLayout.stickZone(w, h, "default")
			if out.squad.y + out.squad.h > zone.y then
				besideStatus()
			end
		end
	end
	return out
end

-- The UIScale for a panel drawn at designW x designH so it fits a w x h safe area with a margin
function TouchLayout.panelScale(Config: any, w: number, h: number, designW: number, designH: number): number
	local P = Config.Ui.phone
	local fit = math.min((w - 2 * P.panelMargin) / designW, (h - 2 * P.panelMargin) / designH)
	return math.clamp(fit, P.minPanelScale, 1)
end

return TouchLayout
