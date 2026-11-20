-- MeshFix: the turn each uploaded art set's MeshParts need so their geometry faces the way our Blender FBX drew it
-- (fix-weapons, nate's playtest 2026-11-19: "why are there just pieces floating around?"). Open Cloud's FBX import
-- turned every mesh 180 degrees about y inside its MeshPart (x and z flipped; the box size and centre unchanged),
-- so each piece sat in the right box but faced backwards: blades, hafts and handles drawn on a diagonal crossed the
-- wrong way and no longer met their guard or grip. Measured per mesh by art/upload/meshcheck.py (downloads each
-- MeshId, decodes Roblox's mesh file, compares with the FBX). A placed piece is part.CFrame * offset * MeshFix.turn(set).
-- Sets not verified as turned stay identity. Re-run meshcheck after any re-upload: a different importer may differ.
-- fix-models (nate, same playtest: "the leviathan engine's parts just aren't placed properly ... consistent
-- throughout the game with gear/weapons/etc."): every other set measured the same (2,303 more meshes in 39 sets, none as drawn;
-- the per-set tally is art/models/meshturns.json, written by art/upload/meshturns.py and checked against this
-- table by tests/model_fit_test.luau), so off-centre shapes (a jaw, a fin, a hood, a headlight) swung to the far
-- side of their boxes. Pieces cloned with MeshFix.clone carry their set as the MeshSet attribute, so code that
-- places a clone later (or a rig that joints it, Shared.NpcRig) finds its turn with MeshFix.of(part).

local MeshFix = {}

local TURN = CFrame.Angles(0, math.pi, 0)

-- every set measured turned (2026-11-19; art/models/meshturns.json has the counts). Hero is not listed: its 15
-- meshes are symmetric either way. Bodies (the fallback body sets, unused while Config.Creator.robloxBody is on) is
-- turned like the rest: NpcRig turns a rig built on them. LookKit.wearBodySet's in-place ApplyMesh cannot turn, so it
-- uses BodyTorsos (the torsos uploaded pre-turned, fix-bodies 2026-11-19), which is not listed: identity.
local TURNS: { [string]: CFrame } = {
	Weapons = TURN, -- 304 of 304 meshes match a 180 degree turn about y (2026-11-19; re-measured 2026-11-20 with the new style meshes and again with the baked textures)
}
for _, set in
	{
		"Activity",
		"Arms",
		"Backs",
		"Belts",
		"Board",
		"Bodies",
		"Boots",
		"Bosses",
		"Bosses2",
		"Bramblebeast",
		"Capes",
		"Coats",
		"Crater",
		"Deep",
		"Ears",
		"Eyes",
		"Finds", -- list-combat: the collection finds, 19 of 19 (2026-11-20)
		"Rings", -- list-combat: the PvP flag rings and the Downed ring, 3 of 3 (2026-11-20)
		"Guard", -- list-combat: the block shield, bubble, shard and flash, 6 of 6 (2026-11-20)
		"Juice", -- list-combat: the coin, dazed star, glow ring, tier beam and firework burst, 5 of 5 (2026-11-20)
		"NemParts", -- list-combat: the nemesis eyes, dome, cyclops eye, neck, plates, cannon, drone, antenna, 11 of 11 (2026-11-20)
		"Throwables", -- list-combat: the mailbox, sign, dumpster, slab and rubble, 14 of 14 (2026-11-20)
		"Gadget", -- list-combat: the Shield Drone body and rotor, 2 of 2 (2026-11-20)
		"Tether", -- list-combat: the rope and chain links, 2 of 2 (2026-11-20)
		"SideGear", -- list-combat: the side styles' crests, 16 of 16 (2026-11-20)
		"SiteProps", -- list-combat: the giver's mark, the relay giver and the cat, 8 of 8 (2026-11-20)
		"Stage", -- list-combat: the costume contest's stage, 11 of 11 (2026-11-20)
		"Foes", -- list-combat: the robots' gear and the foes' props, 28 of 28 (2026-11-20)
		"Gear",
		"Gloves",
		"Hair",
		"Hats",
		"Heads",
		"Hideout",
		"Hq",
		"Life", -- living-world: 32 of 32 match it (2026-11-19)
		"LoreBook", -- living-world: the lore book and shelf, 15 of 15 (2026-11-19)
		"Necks",
		"News",
		"Park", -- the city park: 67 of 67 match it (2026-11-20)
		"PocketProps",
		"PocketProps2",
		"Powers", -- list-combat: the power summons, rides and forms, 37 of 37 with the nemesis armour (2026-11-20)
		"Prologue",
		"Robots",
		"Rubble", -- list-combat: the rubble heaps, 8 of 8 (2026-11-20)
		"SetPieces",
		"Shapes", -- shapes-2: the living world's round 2, 59 of 59 match it (2026-11-19)
		"Shoulders",
		"Story",
		"Street",
		"Trooper",
		"Vehicles",
		"Voidhound",
		"WindupGiant",
		"Wrecks",
		"Wrists",
	}
do
	TURNS[set] = TURN
end

-- The correction for one set's meshes (identity for a set not measured turned)
function MeshFix.turn(set: string?): CFrame
	return if set then TURNS[set] or CFrame.identity else CFrame.identity
end

-- Every set in the table and its turn (tests)
function MeshFix.sets(): { [string]: CFrame }
	return table.clone(TURNS)
end

-- The art set a mesh comes from: its MeshSet attribute (a clone made by MeshFix.clone), else the folder under
-- ReplicatedStorage.Art it sits in; nil for anything else (Roblox's own body, catalog accessories, plain parts)
function MeshFix.setOf(inst: Instance): string?
	local tagged = inst:GetAttribute("MeshSet")
	if type(tagged) == "string" then
		return tagged
	end
	local node: Instance? = inst
	while node and node.Parent do
		local parent = node.Parent :: Instance
		if parent.Name == "Art" and parent.Parent and parent.Parent.ClassName == "ReplicatedStorage" then
			return node.Name
		end
		node = parent
	end
	return nil
end

-- The correction for this part's geometry (identity for anything not from a turned set)
function MeshFix.of(inst: Instance): CFrame
	return MeshFix.turn(MeshFix.setOf(inst))
end

-- A copy of an imported mesh that remembers its set (MeshFix.of works on it anywhere)
function MeshFix.clone<T>(src: T & Instance): T
	local set = MeshFix.setOf(src)
	local p = (src :: Instance):Clone()
	if set then
		p:SetAttribute("MeshSet", set)
	end
	return p :: any
end

return MeshFix
