-- Shapes: colorblind-safe marker shapes (spec: Accessibility "colorblind-safe markers (shapes plus color:
-- circle for incident, diamond for boss, triangle for danger)"). Every marker on the radar, the map and over
-- the world carries its shape as well as its colour. Events use a star, squadmates a square.
-- gap-icons2 (2026-11-19): with a symbol (group and key in Config.Icons) the shape is drawn as the icon set's
-- comic backing in the marker's colour with the symbol on it (Kit.showMark); without uploaded sheets it stays
-- today's frame or glyph.

local Kit = require(script.Parent.Kit)

local Shapes = {}

Shapes.GLYPH = { triangle = "▲", star = "★" }

-- Turn a label (or a map dot's button) into a shape marker: the background is the shape, or a glyph for
-- triangle and star; with a symbol (group, key) and the sheets uploaded, the comic shape and its symbol
function Shapes.apply(l: any, shape: string, color: Color3, group: string?, key: any): boolean
	local corner = l:FindFirstChildOfClass("UICorner")
	local stroke = l:FindFirstChildOfClass("UIStroke")
	l.Rotation = 0
	if Kit.showMark(l, shape, color, group, key) then
		l.BackgroundTransparency = 1
		l.Text = ""
		if stroke then
			stroke.Enabled = false
		end
		return true
	end
	if shape == "triangle" or shape == "star" then
		l.BackgroundTransparency = 1
		l.Text = Shapes.GLYPH[shape]
		l.TextColor3 = color
		l.TextStrokeTransparency = 0
		l.TextStrokeColor3 = Color3.new(0, 0, 0)
		if stroke then
			stroke.Enabled = false
		end
		return false
	end
	l.BackgroundTransparency = 0
	l.BackgroundColor3 = color
	if l.Text == "▲" or l.Text == "★" then
		l.Text = ""
	end
	if stroke then
		stroke.Enabled = true
	end
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = l
	end
	local c = corner :: UICorner
	if shape == "circle" then
		c.CornerRadius = UDim.new(0.5, 0)
	elseif shape == "diamond" then
		c.CornerRadius = UDim.new(0, 2)
		l.Rotation = 45
	else
		c.CornerRadius = UDim.new(0, 3)
	end
	return false
end

return Shapes
