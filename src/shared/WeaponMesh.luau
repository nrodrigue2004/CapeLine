--!strict
-- WeaponMesh: the 36 weapons' Blender meshes (2026-11-18; art/blender/weapons.py, imported by nate as
-- ReplicatedStorage.Art.Weapons; each mesh's body part, colour role, flags and box is Config.WeaponArt, generated
-- by the same script). Pure, so Lune checks it; WeaponKit welds what it picks.
-- * ready(Config, id, has): a weapon is drawn in meshes only when every one of its meshes is found (has(name)),
--   its Broad and Jagged ones too, so a half import or a style switch never shows half a weapon (the same
--   all-or-nothing rule as Shared.SetPieceKit). Otherwise WeaponKit welds today's parts.
-- * pieces(Config, id, style): the meshes for a look's style: 1 Classic, 2 Broad and 3 Jagged swap in their own
--   mesh where the shape changes, 4 Energy marks the blade meshes (WeaponKit draws them as glowing light).
-- * hold(Config, id, at): how a weapon on that body part is turned from WeaponKit's parts frame (the same turn
--   the meshes were drawn with), so the part-built fallback sits in HeroAnim's stances the same way.
-- * check(Config): problems with the fit table (empty when fine). A fit's aim is where it points (dir, on body part
--   at) and, for shields and the bow, which way its face looks (face, on body part faceAt).

local WeaponMesh = {}

export type Piece = {
	mesh: string,
	at: string,
	role: string,
	offset: { number },
	size: { number },
	blade: boolean,
	glow: boolean,
	neon: boolean,
	emblem: boolean,
	energy: boolean,
	mat: string?,
}

WeaponMesh.ATS = {
	rhand = true,
	lhand = true,
	rlarm = true,
	llarm = true,
	rfoot = true,
	lfoot = true,
	rshin = true,
	lshin = true,
}
WeaponMesh.ROLES = { p = true, s = true, a = true, white = true, dark = true }
WeaponMesh.MATS = { Metal = true, Fabric = true, Wood = true, Leather = true, Glass = true }
WeaponMesh.budget = 2000 -- triangles a weapon, Classic, both hands (30 heroes on a phone)

-- A weapon's fit (nil for an unknown id)
function WeaponMesh.fit(Config: any, id: number?): any
	local art = Config.WeaponArt
	return if id and type(art) == "table" then art[id] else nil
end

-- Every mesh a weapon needs, its style meshes too
function WeaponMesh.names(Config: any, id: number?): { string }
	local out = {}
	local fit = WeaponMesh.fit(Config, id)
	for _, p in (fit and fit.pieces) or {} do
		table.insert(out, p.mesh)
		if p.broad then
			table.insert(out, p.broad.mesh)
		end
		if p.jag then
			table.insert(out, p.jag.mesh)
		end
	end
	return out
end

-- Is every mesh of this weapon found?
function WeaponMesh.ready(Config: any, id: number?, has: (string) -> boolean): boolean
	local names = WeaponMesh.names(Config, id)
	if #names == 0 then
		return false
	end
	for _, n in names do
		if not has(n) then
			return false
		end
	end
	return true
end

-- The meshes for a style (1 Classic, 2 Broad, 3 Jagged, 4 Energy)
function WeaponMesh.pieces(Config: any, id: number?, style: number?): { Piece }
	local out: { Piece } = {}
	local fit = WeaponMesh.fit(Config, id)
	local st = style or 1
	for _, p in (fit and fit.pieces) or {} do
		local v = if st == 2 then p.broad elseif st == 3 then p.jag else nil
		local src = v or p
		table.insert(out, {
			mesh = src.mesh,
			at = p.at,
			role = p.role,
			offset = src.offset,
			size = src.size,
			blade = p.blade == true,
			glow = p.glow == true,
			neon = p.neon == true,
			emblem = p.emblem == true,
			energy = st == 4 and p.blade == true,
			mat = p.mat,
		})
	end
	return out
end

-- The turn for a weapon's pieces on one body part: rx, ry (degrees, CFrame.Angles(rx, ry, 0)) about pivot; nil
-- when that part's pieces are not turned
function WeaponMesh.hold(Config: any, id: number?, at: string): (number?, number?, { number }?)
	local fit = WeaponMesh.fit(Config, id)
	local h = fit and fit.hold and fit.hold[at]
	if not h or ((h.rx or 0) == 0 and (h.ry or 0) == 0) then
		return nil, nil, nil
	end
	return h.rx or 0, h.ry or 0, h.pivot or { 0, 0, 0 }
end

local function vec(t: any): boolean
	return type(t) == "table"
		and #t == 3
		and type(t[1]) == "number"
		and type(t[2]) == "number"
		and type(t[3]) == "number"
end

-- Problems with the fit table (empty when fine): every weapon in Config.Weapons has a fit with real body parts,
-- roles, materials and boxes, unique mesh names across the set, its triangles in the budget, a unit aim, and
-- style meshes only where they differ
function WeaponMesh.check(Config: any): { string }
	local bad = {}
	local seen: { [string]: string } = {}
	for _, w in Config.Weapons.list do
		local id = w[1]
		local fit = WeaponMesh.fit(Config, id)
		local name = string.format("%d %s", id, tostring(w[3]))
		if type(fit) ~= "table" then
			table.insert(bad, name .. ": no fit")
			continue
		end
		if fit.name ~= w[3] then
			table.insert(bad, name .. ": the fit is named " .. tostring(fit.name))
		end
		if type(fit.pieces) ~= "table" or #fit.pieces == 0 then
			table.insert(bad, name .. ": no pieces")
			continue
		end
		local tris = 0
		for _, p in fit.pieces do
			local pn = name .. " " .. tostring(p.mesh)
			if not WeaponMesh.ATS[p.at] then
				table.insert(bad, pn .. ": body part " .. tostring(p.at))
			end
			if not WeaponMesh.ROLES[p.role] then
				table.insert(bad, pn .. ": role " .. tostring(p.role))
			end
			if p.mat ~= nil and not WeaponMesh.MATS[p.mat] then
				table.insert(bad, pn .. ": material " .. tostring(p.mat))
			end
			for _, row in { p, p.broad or false, p.jag or false } do
				if row then
					if type(row.mesh) ~= "string" or seen[row.mesh] then
						table.insert(bad, pn .. ": mesh name used twice " .. tostring(row.mesh))
					else
						seen[row.mesh] = name
					end
					if not (vec(row.offset) and vec(row.size)) then
						table.insert(bad, pn .. ": no box")
					else
						for _, s in row.size do
							if s <= 0 then
								table.insert(bad, pn .. ": a size is not positive")
							end
						end
					end
					if type(row.tris) ~= "number" or row.tris <= 0 then
						table.insert(bad, pn .. ": no triangle count")
					end
				end
			end
			tris += p.tris or 0
		end
		if tris ~= fit.triangles then
			table.insert(bad, name .. ": the triangles do not add up")
		end
		if tris > WeaponMesh.budget then
			table.insert(bad, string.format("%s: %d triangles is over the budget", name, tris))
		end
		local aim = fit.aim
		if not (aim and WeaponMesh.ATS[aim.at] and vec(aim.dir)) then
			table.insert(bad, name .. ": no aim")
		else
			local d = aim.dir
			local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
			if math.abs(len - 1) > 0.01 then
				table.insert(bad, name .. ": the aim is not a unit direction")
			end
			if aim.face ~= nil and not (vec(aim.face) and WeaponMesh.ATS[aim.faceAt]) then
				table.insert(bad, name .. ": a face with no body part")
			end
		end
		if not (fit.grip and WeaponMesh.ATS[fit.grip.at] and vec(fit.grip.pos)) then
			table.insert(bad, name .. ": no grip")
		end
		for at, h in fit.hold or {} do
			if
				not WeaponMesh.ATS[at]
				or type(h.rx) ~= "number"
				or type(h.ry) ~= "number"
				or not vec(h.pivot)
			then
				table.insert(bad, name .. ": a bad hold on " .. tostring(at))
			end
		end
	end
	return bad
end

return WeaponMesh
