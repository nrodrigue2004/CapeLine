-- WP10 (gap check G12): the group-join cosmetic and creator codes (Config.Promo, Shared.PromoRules,
-- PromoService, Settings > REWARDS). Called from tests/run.luau (ONLY=WP10 runs these):
--   require("./promo_test")({ test = test, check = check, Config = Config, placePath = process.args[1] })

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local PromoRules = require("../src/shared/PromoRules")
	local CreatorRules = require("../src/shared/CreatorRules")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local AnalyticsSchema = require("../src/shared/AnalyticsSchema")
	local NetSchema = require("../src/shared/NetSchema")
	local Remotes = require("../src/shared/Remotes")
	local P = Config.Promo
	local DAY = 20775 -- 2026-11-18

	-- A Config with a test code list (the real one ships empty)
	local function withCodes(codes: { any }, group: number?): any
		local promo = table.clone(P)
		promo.codes = codes
		promo.group = table.clone(P.group)
		promo.group.id = group or 0
		local c = table.clone(Config)
		c.Promo = promo
		return c
	end
	local function blank(): any
		return PromoRules.clean(nil)
	end

	test("WP10: Config.Promo ships off (group 0, no codes) and validates; rewards are drop pieces", function()
		check(P.group.id == 0, "the group id is 0 until nate sets it")
		check(#P.codes == 0, "the code list ships empty (the example is a comment)")
		local errs = PromoRules.validate(Config, CreatorRules.index(Config))
		for _, e in errs do
			check(false, e)
		end
		check(#errs == 0, "Config.Promo validates (studio codes included)")
		local idx = CreatorRules.index(Config)
		local gp = idx.byName[P.group.piece]
		check(gp ~= nil and gp.source.kind == "drop", "the group piece is an earnable drop piece")
		-- the Rogues File's milestone pieces stay that collection's own
		for _, m in Config.Rogues.milestones do
			check(m.piece ~= P.group.piece, "the group piece is not the Rogues milestone " .. m.piece)
		end
		local src = fs.readFile("src/config/Promo.luau")
		check(string.find(src, "-- { code = ", 1, true) ~= nil, "a commented example row for nate")
		local view = PromoRules.view(Config, blank(), DAY, false)
		check(view.on and view.group == nil and view.codes == 0, "live servers show no REWARDS rows yet")
		local sv = PromoRules.view(Config, blank(), DAY, true)
		check(sv.codes == 1, "Studio has its one live test code (the old one has ended)")
	end)

	test("WP10: the code box keeps upper-case letters and digits; the server's shape check", function()
		check(
			PromoRules.typed(Config, "sky-line 7!") == "SKYLINE7",
			"letters up, digits kept, the rest dropped"
		)
		check(PromoRules.typed(Config, "abcdefghijklmnopqrstuvwxyz") == "ABCDEFGHIJKL", "cut to maxLength")
		check(PromoRules.typed(Config, "héllo☺") == "HLLO", "no accents or symbols")
		check(PromoRules.typed(Config, "") == "", "empty stays empty")
		local n = PromoRules.normalize(Config, "  sky-line ")
		check(n == "SKYLINE", "spaces and dashes are forgiven on the server")
		for _, bad in { "AB", "ABCDEFGHIJKLM", "SKY!LINE", "SKY.LINE", "", string.rep("A", 21) } do
			local c, why = PromoRules.normalize(Config, bad)
			check(c == nil and why == "bad", "refused: " .. bad)
		end
		for _, bad in { 12, true, {} :: any } do
			check(PromoRules.normalize(Config, bad) == nil, "not a string: " .. typeof(bad))
		end
	end)

	test("WP10: UTC dates to day numbers, real dates only", function()
		check(PromoRules.dayOf("1970-01-01") == 0, "the epoch")
		check(PromoRules.dayOf("1969-12-31") == -1, "the day before")
		check(PromoRules.dayOf("2000-03-01") == 11017, "a century leap year")
		check(PromoRules.dayOf("2024-02-29") == 19782, "a leap day")
		check(PromoRules.dayOf("2026-11-18") == DAY, "today")
		check(PromoRules.dayOf("2027-01-31") == 20849, "next January")
		for _, bad in { "2026-02-29", "2026-13-01", "2026-00-10", "2026-04-31", "26-1-1", "2026/01/01", 5 } do
			check(PromoRules.dayOf(bad :: any) == nil, "not a date: " .. tostring(bad))
		end
	end)

	test("WP10: codes match the fixed list only, once per account, inside their dates", function()
		local C = withCodes({
			{ code = "SKYLINE", piece = "Fox Mask", tag = "launch" },
			{ code = "WINTER", piece = "Oni Mask", starts = "2026-12-01", ends = "2026-12-31" },
			{ code = "OLDNEWS", piece = "Moon Badge", ends = "2026-11-17" },
			{ code = "LASTDAY", piece = "Peak Badge", ends = "2026-11-18" },
		})
		check(#PromoRules.validate(C, CreatorRules.index(C)) == 0, "the test list validates")
		local promo = blank()
		-- near misses never match
		for _, miss in { "SKYLIN", "SKYLINES", "XSKYLINE", "SKYLINE1", "STUDIOTEST" } do
			local r = PromoRules.redeem(C, promo, miss, DAY, false)
			check(not r.ok and r.reason == "unknown" and r.row == nil, "no match: " .. miss)
		end
		check(next(promo.codes) == nil, "nothing was claimed by a miss")
		local r = PromoRules.redeem(C, promo, "skyline", DAY, false)
		check(r.ok and r.reason == "ok" and r.row and r.row.piece == "Fox Mask", "lower case still matches")
		check(promo.codes.SKYLINE == DAY, "the claim is saved with its day")
		r = PromoRules.redeem(C, promo, "SKYLINE", DAY + 3, false)
		check(not r.ok and r.reason == "used", "once per account")
		-- dates: notyet before starts, live through the whole of ends, expired after
		check(PromoRules.redeem(C, blank(), "WINTER", DAY, false).reason == "notyet", "not live yet")
		check(PromoRules.redeem(C, blank(), "WINTER", DAY + 13, false).reason == "ok", "live from starts")
		check(PromoRules.redeem(C, blank(), "WINTER", DAY + 43, false).reason == "ok", "live on ends")
		check(PromoRules.redeem(C, blank(), "WINTER", DAY + 44, false).reason == "expired", "ended")
		check(PromoRules.redeem(C, blank(), "OLDNEWS", DAY, false).reason == "expired", "ended yesterday")
		check(PromoRules.redeem(C, blank(), "LASTDAY", DAY, false).reason == "ok", "its last day")
		-- a removed code keeps its claim: putting it back never pays twice
		local gone = withCodes({})
		check(PromoRules.redeem(gone, promo, "SKYLINE", DAY, false).reason == "unknown", "a removed code")
		check(promo.codes.SKYLINE == DAY, "its claim stays on the save")
		check(PromoRules.redeem(C, promo, "SKYLINE", DAY, false).reason == "used", "back again: still used")
		-- Studio codes only in Studio
		check(PromoRules.redeem(Config, blank(), "STUDIOTEST", DAY, false).reason == "unknown", "not live")
		check(PromoRules.redeem(Config, blank(), "STUDIOTEST", DAY, true).ok, "in Studio")
		check(
			PromoRules.redeem(Config, blank(), "STUDIOOLD", DAY, true).reason == "expired",
			"Studio's old one"
		)
		-- off switch
		local off = withCodes({ { code = "SKYLINE", piece = "Fox Mask" } })
		off.Promo.on = false
		check(PromoRules.redeem(off, blank(), "SKYLINE", DAY, false).reason == "off", "Promo off")
	end)

	test("WP10: wrong codes wait after a few tries; only misses count", function()
		local t = {}
		for i = 1, P.tries.n do
			check(PromoRules.canTry(Config, t, i), "try " .. i)
			PromoRules.fail(t, i)
		end
		local can, left = PromoRules.canTry(Config, t, P.tries.n + 1)
		check(not can and left > 0, "the wait starts")
		check(
			PromoRules.canTry(Config, t, 1 + P.tries.window),
			"one slot opens when the oldest is old enough"
		)
		check(PromoRules.wrong("unknown") and PromoRules.wrong("bad"), "misses count")
		for _, r in { "ok", "used", "expired", "notyet", "off" } do
			check(not PromoRules.wrong(r), r .. " does not count")
		end
	end)

	test("WP10: the group piece: only with an id, only members, once per account", function()
		local promo = blank()
		check(not PromoRules.group(Config, promo, true), "id 0: nothing")
		local C = withCodes({}, 123456)
		check(not PromoRules.group(C, promo, false), "not a member: nothing")
		check(promo.group == 0, "still unpaid")
		check(PromoRules.group(C, promo, true), "a member: paid")
		check(promo.group == 1 and not PromoRules.group(C, promo, true), "once")
		local v = PromoRules.view(C, promo, DAY, false)
		check(v.group and v.group.claimed and v.group.piece == P.group.piece, "the row shows CLAIMED")
	end)

	test("WP10: validate refuses sold, gated or missing pieces, bad codes, repeats and bad dates", function()
		local idx = CreatorRules.index(Config)
		-- find a piece of each kind that must never be handed out by a code
		local sold, gated
		for _, p in idx.list do
			if
				not sold
				and (p.source.kind == "pack" or p.source.kind == "pass" or p.source.kind == "starter")
			then
				sold = p.name
			elseif not gated and p.source.kind == "lvl" then
				gated = p.name
			end
		end
		check(sold ~= nil and gated ~= nil, "the creator has sold and level pieces to test with")
		local cases = {
			{ { code = "SOLD", piece = sold }, "sold" },
			{ { code = "GATED", piece = gated }, "level piece" },
			{ { code = "NOPIECE", piece = "Not A Piece" }, "missing piece" },
			{ { code = "lower", piece = "Fox Mask" }, "lower case code" },
			{ { code = "AB", piece = "Fox Mask" }, "too short" },
			{ { code = "SKY LINE", piece = "Fox Mask" }, "a space" },
			{ { code = "DATES", piece = "Fox Mask", ends = "2026-02-30" }, "bad date" },
			{
				{ code = "BACKWARD", piece = "Fox Mask", starts = "2027-01-02", ends = "2027-01-01" },
				"backwards",
			},
			{ { code = "TAGGED", piece = "Fox Mask", tag = "no spaces!" }, "bad tag" },
		}
		for _, c in cases do
			local errs = PromoRules.validate(withCodes({ c[1] }), idx)
			check(#errs > 0, "refused: " .. c[2])
		end
		local dup =
			withCodes({ { code = "SAME", piece = "Fox Mask" }, { code = "SAME", piece = "Oni Mask" } })
		check(#PromoRules.validate(dup, idx) > 0, "a repeated code")
		local studioDup = withCodes({ { code = "STUDIOTEST", piece = "Fox Mask" } })
		check(#PromoRules.validate(studioDup, idx) > 0, "a live code that repeats a Studio code")
		local g = withCodes({}, 5)
		g.Promo.group.piece = sold
		check(#PromoRules.validate(g, idx) > 0, "a sold group piece")
	end)

	test("WP10: the save: a promo block on the account, repaired, never in the client view", function()
		local d = ProfileSchema.default()
		check(d.promo and d.promo.group == 0 and next(d.promo.codes) == nil, "a new save has an empty block")
		check(ProfileSchema.clientView(d).promo == nil, "the client view leaves it out")
		local raw = ProfileSchema.default()
		raw.promo = nil
		check(ProfileSchema.load(raw).promo.group == 0, "an older save gets the block (no version bump)")
		raw = ProfileSchema.default()
		raw.promo = {
			group = 7,
			codes = { SKYLINE = 20775.6, lower = 1, ["BAD KEY"] = 2, NUM = "x", [5] = 1, OK2 = 20000 },
		}
		local p = ProfileSchema.load(raw)
		check(p.promo.group == 0, "a junk group mark is unpaid")
		check(p.promo.codes.SKYLINE == 20775 and p.promo.codes.OK2 == 20000, "real claims are kept")
		local n = 0
		for _ in p.promo.codes do
			n += 1
		end
		check(n == 2, "junk claims are dropped")
		local again = ProfileSchema.load(ProfileSchema.deepCopy(p))
		check(again.promo.codes.SKYLINE == 20775 and again.promo.group == 0, "repair is stable")
		raw = ProfileSchema.default()
		raw.promo = { group = 1, codes = {} }
		for i = 1, 300 do
			raw.promo.codes["C" .. i] = i
		end
		n = 0
		for _ in ProfileSchema.load(raw).promo.codes do
			n += 1
		end
		check(n == 200 and ProfileSchema.load(raw).promo.group == 1, "capped at 200, the group mark kept")
	end)

	test("WP10: promo_claim analytics, the remotes, and the server source", function()
		local E = AnalyticsSchema.EVENTS
		check(E.promo_claim ~= nil and #E.promo_claim == 2, "promo_claim: kind, code")
		local value, fields =
			PromoRules.event("code", { code = "SKYLINE", piece = "Fox Mask", tag = "launch" })
		local ok, clean = AnalyticsSchema.check("promo_claim", fields)
		check(ok and value == 1 and clean[1] == "code" and clean[2] == "launch", "a code's tag")
		value, fields = PromoRules.event("code", { code = "SKYLINE", piece = "Fox Mask" })
		ok, clean = AnalyticsSchema.check("promo_claim", fields)
		check(ok and clean[2] == "SKYLINE", "no tag: the list's own code")
		ok, clean = AnalyticsSchema.check("promo_claim", select(2, PromoRules.event("group", nil)))
		check(ok and clean[1] == "group", "the group piece")
		-- remotes: one short string in, rate-limited; answers are server to client
		local R = Remotes.PromoRedeem
		check(R and R.dir == "C2S" and #R.schema == 1, "PromoRedeem takes one argument")
		check(R.schema[1].t == "string" and R.schema[1].max == P.rawMax, "a string of rawMax at most")
		check((R.rate :: number) <= 1 and (R.burst :: number) <= 3, "rate-limited")
		check(NetSchema.validate(R.schema, { "SKYLINE" }, 1), "a code passes the schema")
		check(
			not NetSchema.validate(R.schema, { string.rep("A", P.rawMax + 1) }, 1),
			"a long string is refused"
		)
		check(not NetSchema.validate(R.schema, { 5 }, 1), "a number is refused")
		for _, name in { "PromoOpen", "PromoGroup" } do
			check(
				Remotes[name] and Remotes[name].dir == "C2S" and #Remotes[name].schema == 0,
				name .. " takes nothing"
			)
		end
		for _, name in { "PromoState", "PromoResult" } do
			check(Remotes[name] and Remotes[name].dir == "S2C", name .. " is server to client")
		end
		local src = fs.readFile("src/server/Services/PromoService.luau")
		local function has(s: string): boolean
			return string.find(src, s, 1, true) ~= nil
		end
		check(has("pcall(player.IsInGroup"), "IsInGroup in a pcall")
		check(has("pcall(GroupService.GetGroupsAsync"), "GetGroupsAsync in a pcall")
		check(has("DataService.isSaving"), "no claim on a save that cannot save")
		check(has('Analytics.event(player, "promo_claim"'), "logs promo_claim")
		check(not has("fireAll") and not has("print(") and not has("warn("), "never broadcast or logged")
		-- the answer carries fixed fields only: never the raw text
		for line in string.gmatch(src, "[^\n]+") do
			if string.find(line, 'Net.fire("PromoResult"', 1, true) then
				check(not string.find(line, "raw", 1, true), "PromoResult never carries the typed text")
			end
		end
		local init = fs.readFile("src/server/init.server.luau")
		check(
			string.find(init, 'boot("PromoService", PromoService.init)', 1, true) ~= nil,
			"PromoService boots"
		)
		local bootAt = string.find(init, 'boot("PromoService"', 1, true) :: number
		check(bootAt < (string.find(init, 'boot("DataService"', 1, true) :: number), "before DataService")
		local menu = fs.readFile("src/client/Ui/SettingsMenu.luau")
		check(
			string.find(menu, "PromoRules.typed(Config, box.Text)", 1, true) ~= nil,
			"the box cleans as you type"
		)
		check(string.find(menu, "CodeBox", 1, true) ~= nil, "the code box is in Settings")
	end)

	local placePath = T.placePath
	if not placePath then
		return
	end

	test("WP10: Settings > REWARDS at phone, tablet and PC sizes: on screen, readable, tappable", function()
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local trees = UiSim.load(roblox.deserializePlace(fs.readFile(placePath)))
		local UP = Config.Ui.phone
		local DEVICES = {
			{ name = "iPhone SE", w = 667, h = 375, top = 58, left = 0, right = 0, bottom = 0, touch = true },
			{
				name = "Android 640",
				w = 640,
				h = 360,
				top = 58,
				left = 0,
				right = 0,
				bottom = 0,
				touch = true,
			},
			{
				name = "iPhone 14",
				w = 844,
				h = 390,
				top = 58,
				left = 47,
				right = 47,
				bottom = 0,
				touch = true,
			},
			{ name = "iPad", w = 1024, h = 768, top = 58, left = 0, right = 0, bottom = 0, touch = true },
			{
				name = "PC 1080p",
				w = 1920,
				h = 1080,
				top = 58,
				left = 0,
				right = 0,
				bottom = 0,
				touch = false,
			},
		}
		local results = {
			{ kind = "code", reason = "ok", piece = "Twin Tail Scarf" },
			{ kind = "code", reason = "unknown" },
			{ kind = "code", reason = "wait", wait = 42 },
			{ kind = "group", reason = "notMember" },
			{ kind = "group", reason = "owned", piece = "Spark Badge" },
		}
		for _, d in DEVICES do
			local sim = UiSim.new(trees, d)
			sim:run("InputController", sim:require("Client.Controllers.InputController").init)
			local Menu = sim:require("Client.Ui.SettingsMenu")
			sim:run("SettingsMenu", Menu.init)
			local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
			local function fire(name: string, data: any)
				sim:run(name, function()
					remotes:WaitForChild(name).OnClientEvent:Fire(data)
				end)
			end
			local function report(tag: string)
				for _, issue in
					sim:issues({
						minTap = UP.minTap,
						minText = UP.minText,
						safe = true,
						textOverlap = true,
						minList = 90,
						only = { Settings = true },
					})
				do
					check(false, d.name .. " " .. tag .. ": " .. issue)
				end
			end
			check(sim:run("open", Menu.open), d.name .. ": Settings opens")
			fire("PromoState", {
				on = true,
				group = {
					piece = "Spark Badge",
					name = "the Capeline group",
					claimed = false,
					member = false,
				},
				codes = 1,
				maxLength = P.maxLength,
			})
			local gui = sim.playerGui:FindFirstChild("Settings")
			local box = gui and gui:FindFirstChild("CodeBox", true)
			check(box ~= nil and box:IsA("TextBox"), d.name .. ": the code box shows while a code is live")
			check(gui ~= nil and gui:FindFirstChild("PromoGroup", true) ~= nil, d.name .. ": the group row")
			if box then
				box.Text = "sky-line!"
				check(box.Text == "SKYLINE", d.name .. ": the box keeps letters and digits, upper case")
				box.Text = "ABCDEFGHIJKLMNOP"
				check(#box.Text == P.maxLength, d.name .. ": the box stops at maxLength")
			end
			-- the REWARDS rows sit at the bottom of the list, past the fold on a phone, and the sim does not
			-- scroll: hide the rows above them (as scrolling down would) so they are laid out in view
			local body = gui and gui:FindFirstChildWhichIsA("ScrollingFrame", true)
			local function toRewards(): number
				local n = 0
				for _, c in body:GetChildren() do
					if c:IsA("GuiObject") then
						if string.sub(c.Name, 1, 5) == "Promo" then
							n += 1
						else
							c.Visible = false
						end
					end
				end
				return n
			end
			for _, r in results do
				fire("PromoResult", r)
				check(toRewards() == 4, d.name .. ": the heading, the group row, the code row and the answer")
				report("REWARDS " .. r.kind .. " " .. r.reason)
			end
			local note = gui and gui:FindFirstChild("PromoNote", true)
			check(note ~= nil, d.name .. ": the answer line shows")
			-- claimed, no live code: the group row alone; Promo off: no REWARDS rows at all
			fire("PromoState", { on = true, group = { piece = "Spark Badge", claimed = true }, codes = 0 })
			check(gui:FindFirstChild("CodeBox", true) == nil, d.name .. ": no box without a live code")
			check(toRewards() == 3, d.name .. ": the heading, the group row and the answer")
			report("REWARDS claimed")
			fire("PromoState", { on = true, codes = 0 })
			check(gui:FindFirstChild("PromoGroup", true) == nil, d.name .. ": no group row without an id")
			for _, e in sim.errors do
				check(false, d.name .. ": " .. tostring(e))
			end
		end
	end)
end
