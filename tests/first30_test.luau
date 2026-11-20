-- first-30 (2026-11-20, nate: "the first 30 seconds and the first 30 minutes are the most important part of the
-- game"): the first session's polish, proven on the real client code where it can be (UiSim on the built place).
-- Called from tests/run.luau; ONLY="First 30" runs just these.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox")
	local NpcAnim = require("../src/shared/NpcAnim")
	local OpeningPlan = require("../src/shared/OpeningPlan")
	local Rng = require("../src/shared/Rng")

	local function newSim()
		local UiSim = require("./uisim")
		return UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		),
			UiSim
	end

	test(
		"First 30: the Ceremony crowd's cheers, the stage's wave and the gasp are whole-body clips",
		function()
			local C = NpcAnim.CLIPS
			for _, e in NpcAnim.crowd.cheer do
				check(C[e[1]] ~= nil and C[e[1]].loop == true, e[1] .. " is a looping clip")
			end
			for _, name in { NpcAnim.crowd.stage, NpcAnim.crowd.crane, NpcAnim.crowd.scan } do
				check(C[name] ~= nil and C[name].loop == true, name .. " is a looping clip")
			end
			-- loops close on themselves (no pop at the wrap) and the cheers move the legs and the hop, not just arms
			for name, clip in C do
				if clip.loop then
					for joint, keys in clip.joints do
						local a, b = keys[1], keys[#keys]
						if #keys > 1 then
							check(
								b[1] == clip.dur
									and a[2] == b[2]
									and a[3] == b[3]
									and a[4] == b[4]
									and a[5] == b[5],
								name .. "'s " .. joint .. " loops cleanly"
							)
						end
					end
				end
			end
			check(
				C.cheer.joints.Root ~= nil and C.cheer.joints.LeftKnee ~= nil,
				"the cheer hops on bent knees"
			)
			local seen = {}
			for i = 0, 29 do
				seen[NpcAnim.pick(NpcAnim.crowd.cheer, (i * 0.37) % 1)] = true
			end
			local kinds = 0
			for _ in seen do
				kinds += 1
			end
			check(kinds == #NpcAnim.crowd.cheer, "a crowd of 30 mixes every cheer (" .. kinds .. ")")
			local fx = fs.readFile("src/client/Fx/PrologueFx.luau")
			check(not string.find(fx, "local function poseCheer", 1, true), "the shoulder-sine cheer is gone")
			check(not string.find(fx, "local function poseWave", 1, true), "the shoulder-sine wave is gone")
		end
	)

	test(
		"First 30: the real PrologueFx poses the crowd from the clips on the ceremony and the scan",
		function()
			if not T.placePath then
				return
			end
			local sim = newSim()
			local route
			for k = 1, 20 do
				route = OpeningPlan.route(Config, world, Rng.new(k * 17))
				if route then
					break
				end
			end
			check(route ~= nil, "a prologue route")
			if not route then
				return
			end
			local StoryClient = sim:require("Client.Controllers.StoryClient")
			local PrologueFx = sim:require("Client.Fx.PrologueFx")
			sim:run("StoryClient", StoryClient.init)
			sim:run("PrologueFx", PrologueFx.init)
			local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
			local function state(step: string, t: number)
				sim:run("state " .. step, function()
					remotes:WaitForChild("OpeningState").OnClientEvent:Fire({
						step = OpeningPlan.CODE[step],
						t = t,
						side = "hero",
						hall = route.hall,
						face = route.face,
						stage = route.stage,
						crane = route.crane,
						fakes = route.fakes,
						scanner = route.scanner,
						crowd = route.crowd,
						start = route.start,
						spark = route.spark,
						kid = route.kid,
						roofs = route.roofs,
						entrance = route.entrance,
						billboard = route.billboard,
					})
				end)
				-- real time passes (the crowd's crossfade runs on os.clock)
				local stop = os.clock() + NpcAnim.crowd.blend + 0.05
				repeat
					sim:run("frame", function()
						sim.service("RunService").RenderStepped:Fire(1 / 60)
					end)
				until os.clock() >= stop
			end
			local function elbows(): ({ number }, number)
				local out, lifted = {}, 0
				for _, d in sim.workspace:GetDescendants() do
					if d:IsA("Motor6D") and d.Name == "RightElbow" and d.Transform then
						local x = d.Transform:ToEulerAnglesXYZ()
						table.insert(out, math.deg(x))
					elseif
						d:IsA("Motor6D")
						and d.Name == "Root"
						and d.Transform
						and math.abs(d.Transform.Position.Y) > 0.01
					then
						lifted += 1
					end
				end
				return out, lifted
			end
			state("ceremony", 1)
			local e, lifted = elbows()
			check(#e >= 10, "the crowd stands in the plaza (" .. #e .. " elbows)")
			local bent = 0
			for _, a in e do
				if math.abs(a) > 3 then
					bent += 1
				end
			end
			check(bent >= #e * 0.6, "the cheering crowd bends its elbows (" .. bent .. " of " .. #e .. ")")
			check(lifted >= 5, "and hops (" .. lifted .. " roots lifted)")
			state("scan", Config.Story.opening.beats.scan * 0.8)
			e = elbows()
			local gasp = 0
			for _, a in e do
				if math.abs(a) > 60 then
					gasp += 1
				end
			end
			check(
				gasp >= #e * 0.6,
				"on the scan the crowd gasps, hands to the chest (" .. gasp .. " of " .. #e .. ")"
			)
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)
end
