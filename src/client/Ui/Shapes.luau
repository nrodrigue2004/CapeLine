-- Shapes: colorblind-safe marker shapes (spec: Accessibility "colorblind-safe markers (shapes plus color:
-- circle for incident, diamond for boss, triangle for danger)"). Every marker on the radar, the map and over
-- the world carries its shape as well as its colour. Events use a star, squadmates a square.

local Shapes = {}

Shapes.GLYPH = { triangle = "▲", star = "★" }

-- Turn a label into a shape marker: the background is the shape, or a glyph for triangle and star
function Shapes.apply(l: TextLabel, shape: string, color: Color3)
	local corner = l:FindFirstChildOfClass("UICorner")
	local stroke = l:FindFirstChildOfClass("UIStroke")
	l.Rotation = 0
	if shape == "triangle" or shape == "star" then
		l.BackgroundTransparency = 1
		l.Text = Shapes.GLYPH[shape]
		l.TextColor3 = color
		l.TextStrokeTransparency = 0
		l.TextStrokeColor3 = Color3.new(0, 0, 0)
		if stroke then
			stroke.Enabled = false
		end
		return
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
end

return Shapes
