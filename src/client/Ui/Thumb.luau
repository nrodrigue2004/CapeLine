-- Thumb: a tile's picture (2026-11-19, the creator, shop and weapon thumbnails). Shared.ThumbMap says which
-- picture a tile shows (a cell of our packed sheets, Config.Thumbs, or a catalog face's own image); this draws it
-- inside a tile or row button. A tile with no picture (a sheet still at id 0, catalog hair, voices) keeps the text
-- tile it had. Pictures are ImageLabels under the button with Active = false, so a press always reaches the
-- button (DONE/NEXT and every pick keep answering).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local ThumbMap = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ThumbMap"))

local Kit = require(script.Parent.Kit)

local Thumb = {}

export type Pic = ThumbMap.Pic

function Thumb.creator(p: { tab: string, kit: string }): Pic?
	return ThumbMap.creator(Config, p)
end

function Thumb.key(key: string?): Pic?
	return ThumbMap.pic(Config, key)
end

function Thumb.weaponKey(id: number): string
	return ThumbMap.weaponKey(id)
end

-- a text tile's glyph where a piece has no picture of its own (catalog hair, voices), or nil
function Thumb.glyph(p: { tab: string, kit: string }): string?
	if ThumbMap.creator(Config, p) then
		return nil
	end
	return ThumbMap.GLYPHS[p.tab]
end

-- an ImageLabel showing pic, sized and placed by props
function Thumb.image(pic: Pic, props: { [string]: any }): ImageLabel
	local l = Instance.new("ImageLabel")
	l.Name = "Thumb"
	l.BackgroundTransparency = 1
	l.Active = false
	l.Image = pic.image
	if pic.w > 0 then
		l.ImageRectOffset = Vector2.new(pic.x, pic.y)
		l.ImageRectSize = Vector2.new(pic.w, pic.h)
	end
	l.ScaleType = Enum.ScaleType.Fit
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

-- A picture tile's insides: the picture over most of the button, the name as a caption under it and, for a
-- locked piece, how to get it on an ink strip over the picture (dimmed). caption: the cell's bottom text height.
function Thumb.fill(b: GuiButton, pic: Pic, name: string, sub: string?, locked: boolean, caption: number)
	local img = Thumb.image(pic, {
		Size = UDim2.new(1, -8, 1, -caption - 6),
		Position = UDim2.fromOffset(4, 4),
		ImageTransparency = if locked then 0.45 else 0,
		ZIndex = b.ZIndex + 1,
	})
	if pic.catalog then
		-- a catalog face is a decal on a clear background: show it on a skin-coloured head-shaped card
		img.BackgroundTransparency = 0
		img.BackgroundColor3 = Color3.fromRGB(240, 196, 150)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.2, 0)
		c.Parent = img
	end
	img.Parent = b
	local l = Kit.label({
		Text = name,
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(1, -6, 0, caption),
		Position = UDim2.new(0, 3, 1, -2),
		TextColor3 = if locked then Kit.color.paper else Kit.color.ink,
		Font = Kit.bodyFont,
		ZIndex = b.ZIndex + 2,
		maxText = 12,
	})
	l.Parent = b
	if sub then
		local s = Kit.label({
			Text = sub,
			Size = UDim2.new(1, -8, 0, 18),
			Position = UDim2.fromOffset(4, 4),
			BackgroundTransparency = 0.15,
			BackgroundColor3 = Kit.color.ink,
			TextColor3 = Kit.color.gold,
			Font = Kit.bodyFont,
			ZIndex = b.ZIndex + 3,
			maxText = 10,
		})
		s.Parent = b
	end
end

return Thumb
