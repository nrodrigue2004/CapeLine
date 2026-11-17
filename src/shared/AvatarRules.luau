--!strict
-- AvatarRules: heroes are the player's own Roblox avatar plus hero gear (nate, 2026-11-17: "Own avatar plus hero
-- gear", like Blox Fruits). The avatar's clothes, face, hair, skin colour and accessories go on the classic
-- blocky R15 body (every hero the same shape, so gear fits and hitboxes stay fair); the creator's pieces go on
-- top, and a piece in a slot hides the avatar's own item there (a suit hides the shirt and pants, creator hair
-- hides the avatar's hair, a cape hides big back items). Pure (no Instances), so Lune tests it: AvatarService
-- applies the description, LookKit hides and shows the avatar's items.

local AvatarRules = {}

-- HumanoidDescription fields set to 0: the avatar's body parts (the classic blocky body stays) and its
-- animation pack (the heroes' own animations stay)
AvatarRules.CLEAR = {
	"Head",
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
	"ClimbAnimation",
	"FallAnimation",
	"IdleAnimation",
	"JumpAnimation",
	"MoodAnimation",
	"RunAnimation",
	"SwimAnimation",
	"WalkAnimation",
}
-- the standard size and proportions for every hero (no Rthro or slim stretch)
AvatarRules.SCALES = {
	HeightScale = 1,
	WidthScale = 1,
	DepthScale = 1,
	HeadScale = 1,
	BodyTypeScale = 0,
	ProportionScale = 0,
}

-- An accessory's kind from the attachment its handle uses, for older items whose AccessoryType is Unknown
AvatarRules.BY_ATTACHMENT = {
	HairAttachment = "Hair",
	HatAttachment = "Hat",
	FaceFrontAttachment = "Face",
	FaceCenterAttachment = "Face",
	NeckAttachment = "Neck",
	LeftShoulderAttachment = "Shoulder",
	RightShoulderAttachment = "Shoulder",
	LeftCollarAttachment = "Shoulder",
	RightCollarAttachment = "Shoulder",
	BodyFrontAttachment = "Front",
	BodyBackAttachment = "Back",
	WaistFrontAttachment = "Waist",
	WaistCenterAttachment = "Waist",
	WaistBackAttachment = "Waist",
}

-- layered clothing kinds (Enum.AccessoryType names)
local TOPS = { "TShirt", "Shirt", "Sweater", "Jacket" }
local BOTTOMS = { "Pants", "Shorts", "DressSkirt" }

export type Hides = {
	shirt: boolean, -- the classic Shirt and T-shirt (ShirtGraphic)
	pants: boolean, -- the classic Pants
	face: boolean, -- the face decal
	types: { [string]: boolean }, -- accessory kinds to hide (Enum.AccessoryType names)
}

-- What a look hides of the avatar. pieces: slot -> piece index (0 or missing = none, the avatar's own shows).
-- hidesHair / hidesFace: the look's mask or headwear covers the hair / the whole face (LookKit knows the kits).
function AvatarRules.hides(pieces: { [string]: number }, hidesHair: boolean?, hidesFace: boolean?): Hides
	local function on(slot: string): boolean
		return (pieces[slot] or 0) ~= 0
	end
	local types: { [string]: boolean } = {}
	local function hide(list: { string })
		for _, t in list do
			types[t] = true
		end
	end
	local suit, legs = on("suit"), on("legs")
	if suit then
		hide(TOPS) -- a suit is a bodysuit: it also colours the legs while Legs is empty
		hide(BOTTOMS)
	end
	if legs then
		hide(BOTTOMS)
	end
	if on("feet") then
		hide({ "LeftShoe", "RightShoe" })
	end
	if on("hair") or hidesHair then
		hide({ "Hair" })
	end
	if on("hat") or hidesHair then
		hide({ "Hat" })
	end
	if on("head") or on("beard") or hidesFace then
		hide({ "Face" }) -- glasses and beards under a mask or the creator's beard
	end
	if on("face") or on("eyes") or hidesFace then
		hide({ "Eyebrow", "Eyelash" })
	end
	if on("back") or on("backpack") then
		hide({ "Back" }) -- wings and big back items under a cape
	end
	if on("shoulders") then
		hide({ "Shoulder" })
	end
	if on("neck") then
		hide({ "Neck" })
	end
	if on("belt") then
		hide({ "Waist" })
	end
	if on("emblem") or suit then
		hide({ "Front" }) -- necklaces and badges over the chest symbol
	end
	return {
		shirt = suit,
		pants = suit or legs,
		face = on("face") or hidesFace == true, -- as before: a Face piece or a closed helm (eyes go on top)
		types = types,
	}
end

-- The accessory kind to judge an accessory by: its AccessoryType, or (Unknown) its handle's attachment
function AvatarRules.kind(accessoryType: string, attachmentName: string?): string
	if accessoryType ~= "Unknown" then
		return accessoryType
	end
	return AvatarRules.BY_ATTACHMENT[attachmentName or ""] or "Unknown"
end

return AvatarRules
