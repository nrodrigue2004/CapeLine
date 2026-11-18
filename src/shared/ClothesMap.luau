--!strict
-- ClothesMap: Roblox's classic clothing template (the 585 x 559 Shirt and Pants layout) mapped onto the
-- blocky R15 body, so an NPC rig without a Humanoid can wear real Roblox-style clothes (nate, 2026-11-17: "i want
-- the characters to feel like roblox"). One clothes image, the Shirt and the Pants side by side (1170 x 559: the
-- shirt's template on the left, the pants' on the right, because a shirt's sleeves and the pants' legs use the
-- same slots), is shown on each part's faces with a Texture whose tile size and offset pick out that face's
-- rectangle, the way Roblox wraps a Shirt and Pants round an R15 body: the upper torso and arms read the shirt,
-- the lower torso and legs the pants. Pure (no Instances): NpcRig.dress makes the Textures.

local ClothesMap = {}

ClothesMap.W = 1170 -- the shirt (x 0 to 584) and the pants (x 585 to 1169)
ClothesMap.H = 559
ClothesMap.PANTS_X = 585
ClothesMap.TEMPLATE_W = 585 -- one classic Shirt or Pants image

export type Rect = { number } -- x, y, w, h in template pixels

-- the torso block's faces; the limbs' strips (the character's right limb on the image's left: an arm on the
-- Shirt, a leg on the Pants, the same slots). A strip wraps round the limb: the right limb reads L B R F.
local TORSO: { [string]: Rect } = {
	Front = { 231, 74, 128, 128 },
	Back = { 427, 74, 128, 128 },
	Right = { 165, 74, 64, 128 },
	Left = { 361, 74, 64, 128 },
	Top = { 231, 8, 128, 64 },
	Bottom = { 231, 204, 128, 64 },
}
local RIGHT: { [string]: Rect } = {
	Left = { 19, 355, 64, 128 },
	Back = { 85, 355, 64, 128 },
	Right = { 151, 355, 64, 128 },
	Front = { 217, 355, 64, 128 },
	Top = { 217, 289, 64, 64 },
	Bottom = { 217, 485, 64, 64 },
}
local LEFT: { [string]: Rect } = {
	Front = { 308, 355, 64, 128 },
	Left = { 374, 355, 64, 128 },
	Back = { 440, 355, 64, 128 },
	Right = { 506, 355, 64, 128 },
	Top = { 308, 289, 64, 64 },
	Bottom = { 308, 485, 64, 64 },
}
ClothesMap.TORSO = TORSO
ClothesMap.RIGHT = RIGHT
ClothesMap.LEFT = LEFT

-- the rows of a 128 px strip each R15 part shows (torso 1.6 over 0.4; a limb 0.85, 0.85 and 0.3 of 2)
ClothesMap.ROWS = {
	UpperTorso = { 0, 102 },
	LowerTorso = { 102, 128 },
	UpperArm = { 0, 54 },
	LowerArm = { 54, 108 },
	Hand = { 108, 128 },
	UpperLeg = { 0, 54 },
	LowerLeg = { 54, 108 },
	Foot = { 108, 128 },
}
-- the part that shows its strip's Top (the shoulder, the hip) or Bottom (the hand, the sole) square
local TOPS = { UpperTorso = true, UpperArm = true, UpperLeg = true }
local BOTTOMS = { LowerTorso = true, Hand = true, Foot = true }

-- every face a part shows, by Enum.NormalId name
ClothesMap.FACES = { "Front", "Back", "Right", "Left", "Top", "Bottom" }

local function short(part: string): string
	return (part:gsub("^Left", ""):gsub("^Right", ""))
end

-- Which half of the clothes image a part reads: 0 for the shirt (upper torso, arms), PANTS_X for the pants
function ClothesMap.half(part: string): number
	local s = short(part)
	return if s == "LowerTorso"
			or s == "UpperLeg"
			or s == "LowerLeg"
			or s == "Foot"
		then ClothesMap.PANTS_X
		else 0
end

-- The template rectangle one face of one R15 part shows, or nil for a face the body hides (a joint's inside).
-- `single`: the part's own image is just its Shirt or its Pants (585 wide, NpcRig.dressPair), so no half offset.
function ClothesMap.rect(part: string, face: string, single: boolean?): Rect?
	local s = short(part)
	local rows = ClothesMap.ROWS[s]
	if not rows then
		return nil -- the head (skin, the face decal) and anything else
	end
	local slots = if s == "UpperTorso" or s == "LowerTorso"
		then TORSO
		elseif part:sub(1, 5) == "Right" then RIGHT
		else LEFT
	local x = if single then 0 else ClothesMap.half(part)
	local slot: Rect
	if face == "Top" then
		if not TOPS[s] then
			return nil
		end
		slot = slots.Top
		return { slot[1] + x, slot[2], slot[3], slot[4] }
	elseif face == "Bottom" then
		if not BOTTOMS[s] then
			return nil
		end
		slot = slots.Bottom
		return { slot[1] + x, slot[2], slot[3], slot[4] }
	end
	local r = (slots :: { [string]: Rect })[face]
	return { r[1] + x, r[2] + rows[1], r[3], rows[2] - rows[1] }
end

-- Perf pass (2026-11-18): the faces the blocky body hides at rest, which a rig draws only up close: the hip
-- squares under the lower torso and the torso's own underside, the soles and the palms' ends, the legs'
-- inner sides (they stand against each other), the arms' inner sides and the upper torso's sides (arm against
-- torso). A dressed rig has 66 clothes Textures; 21 are tucked. From farther off a tucked face shows the
-- part's colour, which matches its clothes.
function ClothesMap.tucked(part: string, face: string): boolean
	local s = short(part)
	if face == "Top" then
		return s == "UpperLeg"
	elseif face == "Bottom" then
		return s == "LowerTorso" or s == "Foot" or s == "Hand"
	elseif s == "UpperTorso" then
		return face == "Left" or face == "Right"
	elseif s == "LowerTorso" then
		return false
	end
	-- a left limb's inner side faces +x (Right), a right limb's faces -x (Left)
	local inner = if part:sub(1, 4) == "Left" then "Right" else "Left"
	return face == inner
end

-- How much of a rig's clothes to draw `dist` studs from the camera (perf pass 2026-11-18; near and far from
-- the preset: Config.Presets clothesNear and clothesFar): 2 every face, 1 all but the tucked ones, 0 none (the
-- body colours match the clothes from that far). `now`, the level drawn now, is kept 10% past its edge so a
-- rig standing on one never flickers.
function ClothesMap.level(dist: number, near: number, far: number, now: number?): number
	local held = now or 0
	if dist <= near * (if held >= 2 then 1.1 else 1) then
		return 2
	elseif dist <= far * (if held >= 1 then 1.1 else 1) then
		return 1
	end
	return 0
end

-- A face's size in studs on a part of `size` (Vector3 as x, y, z): Front and Back show x by y, the sides z by
-- y, Top and Bottom x by z
function ClothesMap.faceSize(size: { number }, face: string): (number, number)
	if face == "Front" or face == "Back" then
		return size[1], size[2]
	elseif face == "Left" or face == "Right" then
		return size[3], size[2]
	end
	return size[1], size[3]
end

-- A Texture's settings that show exactly `rect` of the template across a face fw by fh studs: the whole image
-- is one tile, scaled so the rectangle fills the face, and shifted so the rectangle starts at the face's corner.
-- `sign` flips the offset direction (Config.NpcLooks.offsetSign, in case Studio shows the image the other way).
-- `width`: the image's width (ClothesMap.W for the side-by-side image, TEMPLATE_W for a lone Shirt or Pants).
function ClothesMap.texture(
	rect: Rect,
	fw: number,
	fh: number,
	sign: number?,
	width: number?
): (number, number, number, number)
	local s = sign or 1
	local su = fw * (width or ClothesMap.W) / rect[3]
	local sv = fh * ClothesMap.H / rect[4]
	local ou = -s * rect[1] * fw / rect[3]
	local ov = -s * rect[2] * fh / rect[4]
	return su, sv, ou, ov
end

return ClothesMap
