-- MeshFix: the turn each uploaded art set's MeshParts need so their geometry faces the way our Blender FBX drew it
-- (fix-weapons, nate's playtest 2026-11-19: "why are there just pieces floating around?"). Open Cloud's FBX import
-- turned every mesh 180 degrees about y inside its MeshPart (x and z flipped; the box size and centre unchanged),
-- so each piece sat in the right box but faced backwards: blades, hafts and handles drawn on a diagonal crossed the
-- wrong way and no longer met their guard or grip. Measured per mesh by art/upload/meshcheck.py (downloads each
-- MeshId, decodes Roblox's mesh file, compares with the FBX). A placed piece is part.CFrame * offset * MeshFix.turn(set).
-- Sets not verified as turned stay identity. Re-run meshcheck after any re-upload: a different importer may differ.

local MeshFix = {}

local TURNS: { [string]: CFrame } = {
	Weapons = CFrame.Angles(0, math.pi, 0), -- 259 of 259 meshes match a 180 degree turn about y (2026-11-19)
}

function MeshFix.turn(set: string): CFrame
	return TURNS[set] or CFrame.identity
end

return MeshFix
