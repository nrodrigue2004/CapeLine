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

-- an emote's, landing pose's or photo pose's picture (nil while its sheet is not uploaded: words only)
function Thumb.emote(id: number): Pic?
	return ThumbMap.pic(Config, ThumbMap.emoteKey(id))
end

-- a shop item's picture: its own cell, or an emote's pose
function Thumb.shop(key: string): Pic?
	return ThumbMap.shop(Config, key)
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

-- A row button's picture at its left and its words beside it (the emote picker, Photo Mode's POSE button):
-- b's own Text goes empty; a later call replaces the picture and words (a button that changes what it names).
-- pic nil: just the words, centred, as a plain button.
function Thumb.side(b: TextButton, pic: Pic?, text: string, maxText: number?)
	for _, c in b:GetChildren() do
		if c.Name == "Thumb" or c.Name == "ThumbText" then
			c:Destroy()
		end
	end
	if not pic then
		b.Text = text
		return
	end
	b.Text = ""
	local h = b.AbsoluteSize.Y > 0 and b.AbsoluteSize.Y or b.Size.Y.Offset
	local side = math.max(24, h - 8)
	local img = Thumb.image(pic, {
		Size = UDim2.new(0, side, 1, 4),
		Position = UDim2.fromOffset(-4, -2),
		ZIndex = b.ZIndex + 1,
	})
	img.Parent = b
	local l = Kit.label({
		Name = "ThumbText",
		Text = text,
		Size = UDim2.new(1, -side - 2, 1, 0),
		Position = UDim2.fromOffset(side + 2, 0),
		TextColor3 = b.TextColor3,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = b.ZIndex + 1,
		maxText = maxText or 16,
	})
	l.Parent = b
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
