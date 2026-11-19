--!strict
-- SignKit: the comic sign boards' lettering (2026-11-19, the pocket kit pass): fixed text (never typed by a player)
-- in Bangers, the comic-book display face the HUD uses (Kit.font), in a bold ink colour with a thick dark stroke,
-- filling a board part's face. The pockets' boards (Shared.PocketDress, built by PocketArt) and the side quest
-- sites' signs and set piece signs (SideQuestService) letter through it. Instances: server and client.

local SignKit = {}

SignKit.font = Enum.Font.Bangers
SignKit.strokeColor = Color3.fromRGB(24, 22, 30)

-- Letter `text` on a board part's face(s): faces defaults to the front only; pixels a stud; stroke in pixels
function SignKit.letter(
	board: BasePart,
	text: string,
	ink: Color3,
	opts: {
		faces: { Enum.NormalId }?,
		pixels: number?,
		stroke: number?,
		strokeColor: Color3?,
	}?
)
	local o = opts or {}
	for _, face in o.faces or { Enum.NormalId.Front } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Sign"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = o.pixels or 40
		gui.LightInfluence = 0.6
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.94, 0.9)
		label.Position = UDim2.fromScale(0.03, 0.05)
		label.BackgroundTransparency = 1
		label.Font = SignKit.font
		label.TextScaled = true
		label.TextColor3 = ink
		label.Text = text -- fixed sign text from Config (never player text)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = o.stroke or 4
		stroke.Color = o.strokeColor or SignKit.strokeColor
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
		label.Parent = gui
		gui.Parent = board
	end
end

return SignKit
