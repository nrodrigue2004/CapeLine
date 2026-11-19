--!strict
-- BoardArtKit: the plaza's weekly board (WP2) in art/blender/board.py's meshes (gap-props2, 2026-11-19; imported as
-- ReplicatedStorage.Art.Board, the look in the generated Config.BoardArt). Pure, so Lune checks it.
-- * BoardService builds the board's parts as before (the navy screen the SurfaceGui adorns, the frame, crest and
--   legs). Once every mesh of the look is imported (ready), it hides the frame, crest and legs (HIDES: kept, so
--   the collision is exactly as before), keeps the screen as it is and draws the meshes round it (meshes():
--   offsets from the screen's centre in its own axes; they never collide, take queries or touches).
-- * check(): the look was built for today's screen size (Config.Boards.prop.size) and never reaches in front of
--   the screen's face inside its rectangle, so every row stays readable.

local BoardArtKit = {}

BoardArtKit.LOOK = "PlazaBoard"
-- the board's parts the meshes stand in for (the Screen stays: the rows are drawn on it)
BoardArtKit.HIDES = { Frame = true, Crest = true, Leg = true }

export type Mesh = {
	name: string,
	size: { number },
	offset: { number },
	color: { number },
	mat: string,
	maps: boolean,
}

function BoardArtKit.fit(Config: any): any?
	local a = Config.BoardArt and Config.BoardArt[BoardArtKit.LOOK]
	return if type(a) == "table" and type(a.meshes) == "table" then a else nil
end

-- Is every mesh imported?
function BoardArtKit.ready(Config: any, has: (string) -> boolean): boolean
	local fit = BoardArtKit.fit(Config)
	if not fit or next(fit.meshes) == nil then
		return false
	end
	for name in fit.meshes do
		if not has(name) then
			return false
		end
	end
	return true
end

-- The look's meshes, sorted by name
function BoardArtKit.meshes(Config: any): { Mesh }
	local out: { Mesh } = {}
	local fit = BoardArtKit.fit(Config)
	for name, m in if fit then fit.meshes else {} do
		table.insert(out, {
			name = name,
			size = m.size,
			offset = m.offset,
			color = m.color,
			mat = m.mat or "SmoothPlastic",
			maps = m.maps == true,
		})
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

-- Problems (empty when fine)
function BoardArtKit.check(Config: any): { string }
	local bad = {}
	local fit = BoardArtKit.fit(Config)
	if not fit then
		return { "no Config.BoardArt (run art/blender/board.py)" }
	end
	local size = Config.Boards.prop.size
	if math.abs(fit.screen[1] - size[1]) > 1e-6 or math.abs(fit.screen[2] - size[2]) > 1e-6 then
		table.insert(bad, "built for a different screen size: rerun art/blender/board.py")
	end
	if fit.clear > 0 then
		table.insert(bad, string.format("a mesh covers the screen's rows by %.2f studs", fit.clear))
	end
	-- the legs stand on the plaza (the board's foot is the screen's bottom less its height above the plaza)
	local foot = -size[2] / 2 - Config.Boards.prop.height
	if math.abs(fit.lo[2] - foot) > 0.05 then
		table.insert(bad, string.format("the feet at %.2f, the plaza at %.2f", fit.lo[2], foot))
	end
	for _, m in BoardArtKit.meshes(Config) do
		for k = 1, 3 do
			if
				m.offset[k] - m.size[k] / 2 < fit.lo[k] - 0.01
				or m.offset[k] + m.size[k] / 2 > fit.hi[k] + 0.01
			then
				table.insert(bad, m.name .. " outside the look's bounds")
			end
		end
	end
	return bad
end

return BoardArtKit
