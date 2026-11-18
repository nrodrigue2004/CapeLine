-- The text pass (overnight item 9, 2026-11-18): every player-visible string stays free of old names, the
-- typos and wordings the pass fixed, and lowercase game terms. Reads two places: every string in Config
-- (as data, Story and side quests included) and the string literals of the device's code (src/client and
-- src/first, comments stripped). Old names are also checked in the server and shared code's literals.
-- Called from tests/run.luau: require("./text_test")({ test = test, check = check, Config = Config })
-- ONLY="Text pass" runs just these.

local fs = require("@lune/fs")

-- Old names as players would read them (whole words, case-sensitive, so ids like CometCrater, NullSentinel
-- or SparkDrone that never reach the screen pass). Decisions.md records each rename.
local OLD_NAMES = {
	"Marlo", -- the Sunken City's diver is Dace (Marlo is a Mossbell Stand hero)
	"Captain Gleam", -- the Suspicious Hero's costume is Gleamheart
	"Shardfall", -- cut from the lore
	"Comet", -- the Comet Crater is the Crater; Comet pieces are Meteor
	"Null", -- Null Sentinel is the Warden, Null Echo the Echo Drone, the Null War-Frame Bulwark's Battle Form
	"League", -- the Vigil
	"War-Frame", -- Bulwark's Battle Form
	"Spark Trooper", -- the Crane Trooper
	"Spark Drone",
	"Crane Yard", -- Gantry Yard
	"Harbor Crane", -- the Harbour Gantry
	"Mayor's Sash", -- the Gold Sash
	"Seven League", -- Seven Strides
	"Shard Crate", -- the Tech crate
	"Shard Recovery", -- Core recovery
	"Hold the Line", -- the old Act 1's missions, replaced by nate's six
	"The Informant",
	"Under the Docks",
	"Bellweather", -- the retired side quest arcs' people
	"Maribel",
	"Tamsin",
	"Iron Dee",
	"Mossbell", -- nate's other games
	"Ragdoll",
}

-- Exact wordings the text pass replaced (a typo, a wrong tab name, an internal word), any case.
local FIXED = {
	"shard crate",
	"shard recovery",
	"mission pocket", -- players never see the word: "Too many missions running"
	"gear > show style", -- the tab is GEAR > STYLES
	"before it first", -- "Finish the mission before this one first"
	"the vigil win!",
	"the syndicate win!",
	"the syndicate want ",
	"harem",
	"harbor gantry",
}

-- Spellings: the game writes colour, harbour, honour, favourite, centre, theatre and tyre, but armor (the
-- established ability and creator names); Brightharbor is a proper name and one word, so it passes.
local SPELLING = {
	{ "%f[%a][Aa]rmour", "armor" },
	{ "%f[%a][Cc]olor%f[%A]", "colour" },
	{ "%f[%a][Cc]olors%f[%A]", "colours" },
	{ "%f[%a][Hh]arbor%f[%A]", "harbour" },
	{ "%f[%a][Hh]onor%f[%A]", "honour" },
	{ "%f[%a][Ff]avorite", "favourite" },
	{ "%f[%a][Tt]heater", "theatre" },
	{ "%f[%a][Cc]enter%f[%A]", "centre" },
	{ "%f[%a][Ff]lier", "flyer" },
	{ "%f[%a][Ff]liers", "flyers" },
}

-- Common English misspellings (whole words, lowercase).
local MISSPELT = {
	"teh",
	"recieve",
	"recieved",
	"seperate",
	"untill",
	"occured",
	"definately",
	"wich",
	"thier",
	"alot",
	"accross",
	"begining",
	"beleive",
	"wierd",
	"tommorow",
	"truely",
	"arguement",
	"neccessary",
	"sucess",
	"succesful",
	"independant",
	"noone",
	"everytime",
	"aswell",
	"incase",
	"eachother",
	"guage",
	"acheive",
	"calender",
	"commited",
	"knowlege",
	"millenium",
	"posession",
	"recomend",
	"refered",
	"relevent",
	"rythm",
	"threshhold",
	"writting",
	"loosing",
	"enviroment",
	"existance",
	"garentee",
	"grammer",
	"occurance",
	"persue",
	"publically",
	"suprise",
	"tounge",
	"wether",
}

-- Game terms are capitalised in running text (CAPS labels pass). Not "dust" or "fame": plain English uses them.
local TERMS = {
	"credits",
	"renown",
	"vigil",
	"syndicate",
	"foundry",
	"lumen dust",
	"skill point",
	"hero pass",
	"rogues file",
	"infamy",
}

-- Repeated words players are meant to read twice.
local REPEAT_OK: { [string]: boolean } = { ding = true, bravo = true, tick = true, knock = true, ho = true }

local MISSPELT_SET: { [string]: boolean } = {}
for _, w in MISSPELT do
	MISSPELT_SET[w] = true
end

-- Each problem in one piece of text, as short notes. Format holes (%d, %s, %.1f) and tokens ({Kind}) are
-- blanked first so "%d d" never reads as a repeated word.
local function problems(text: string, old: boolean, full: boolean): { string }
	local out = {}
	if old then
		for _, w in OLD_NAMES do
			if
				string.find(text, "%f[%w]" .. w .. "%f[%W]")
				or string.find(text, "%f[%w]" .. string.upper(w) .. "%f[%W]")
			then
				table.insert(out, "old name " .. w)
			end
		end
	end
	-- the full checks read running text only: no ids or keys (no space), no "[Service] ..." log lines
	if not full or not string.find(text, " ", 1, true) or string.find(text, "^%[%a+%]") then
		return out
	end
	local lower = string.lower(text)
	for _, w in FIXED do
		if string.find(lower, w, 1, true) then
			table.insert(out, 'fixed wording "' .. w .. '"')
		end
	end
	for _, s in SPELLING do
		if string.find(text, s[1]) then
			table.insert(out, "spelling (" .. s[2] .. ")")
		end
	end
	local plain = string.gsub(string.gsub(text, "%%[%-%+ #0]*%d*%.?%d*[%a%%]", "#"), "{%w+}", "#")
	local prevWord, prevEnd = nil, nil
	for at, word, stop in string.gmatch(plain, "()(%a+)()") do
		local lw = string.lower(word)
		if MISSPELT_SET[lw] then
			table.insert(out, "misspelt " .. word)
		end
		if
			prevWord
			and lw == prevWord
			and #lw > 1
			and not REPEAT_OK[lw]
			and string.sub(plain, prevEnd, at - 1) == " "
		then
			table.insert(out, "repeated word " .. word)
		end
		prevWord, prevEnd = lw, stop
	end
	for _, t in TERMS do
		if string.find(text, "%f[%a]" .. t .. "%f[%A]") then
			table.insert(out, "lowercase term " .. t)
		end
	end
	if string.find(plain, "%a [,%.!?;:]") and not string.find(plain, "%a %.%.%.") then
		table.insert(out, "space before punctuation")
	end
	if string.find(plain, "%l[,;!?]%a") then
		table.insert(out, "no space after punctuation")
	end
	if string.find(plain, "[!?,;:][!?,;:]") and not string.find(plain, "%?!") then
		table.insert(out, "doubled punctuation")
	end
	return out
end

-- Every string literal in a Luau source, comments stripped: "..." and '...' with escapes, `...` and [[...]].
local function literals(src: string): { string }
	local out = {}
	local i, n = 1, #src
	while i <= n do
		local c = string.sub(src, i, i)
		if c == "-" and string.sub(src, i, i + 1) == "--" then
			local eq = string.match(src, "^%[(=*)%[", i + 2)
			if eq then
				local close = string.find(src, "]" .. eq .. "]", i, true)
				i = if close then close + #eq + 2 else n + 1
			else
				local nl = string.find(src, "\n", i, true)
				i = if nl then nl + 1 else n + 1
			end
		elseif c == '"' or c == "'" or c == "`" then
			local j = i + 1
			local buf = {}
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					table.insert(buf, string.sub(src, j, j + 1))
					j += 2
				elseif d == c or d == "\n" then
					break
				else
					table.insert(buf, d)
					j += 1
				end
			end
			table.insert(out, table.concat(buf))
			i = j + 1
		elseif c == "[" and string.match(src, "^%[=*%[", i) then
			local eq = string.match(src, "^%[(=*)%[", i) :: string
			local close = string.find(src, "]" .. eq .. "]", i, true)
			local stop = if close then close - 1 else n
			table.insert(out, string.sub(src, i + #eq + 2, stop))
			i = stop + #eq + 3
		else
			i += 1
		end
	end
	return out
end

local function luauFiles(dir: string, into: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			luauFiles(path, into)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(into, path)
		end
	end
	return into
end

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config

	test("Text pass: the checker finds what it should and passes what it should", function()
		local function has(text: string, what: string): boolean
			for _, p in problems(text, true, true) do
				if string.find(p, what, 1, true) then
					return true
				end
			end
			return false
		end
		check(has("Join the League today", "old name League"), "an old name")
		check(has("MARLO IS BACK", "old name Marlo"), "an old name in CAPS")
		check(#problems("CometCrater", true, true) == 0, "an id is no old name")
		check(has("Every mission pocket is busy", "mission pocket"), "a fixed wording")
		check(has("Heavy Armour", "armor"), "the house spelling")
		check(#problems("Welcome to Brightharbor, the harbour city", true, true) == 0, "Brightharbor passes")
		check(has("Find the the beacon", "repeated word"), "a repeated word")
		check(#problems("DING DING! %d d %d h", true, true) == 0, "meant repeats and format holes pass")
		check(has("Bank your credits first", "lowercase term credits"), "a lowercase term")
		check(#problems("+%s CREDITS   +%s RENOWN", true, true) == 0, "CAPS terms pass")
		check(has("We recieve a signal", "misspelt"), "a misspelling")
		check(has("Hold on , hero", "space before"), "a stray space")
		check(has("Wait,what now", "no space after"), "a missing space")
		check(#problems("Loading your journal...", true, true) == 0, "an ellipsis passes")
		check(#problems("Who took my ledger?! Somebody", true, true) == 0, "?! passes")
		check(#problems("[FavoritePrompt] shown to %s", true, true) == 0, "a log line is not read")
		check(has("Hurry up!! Go", "doubled punctuation"), "doubled punctuation")
		local lits = literals('local a = "one two" -- "not this"\n--[[ "nor this" ]]\nlocal b = `three {x}`')
		check(#lits == 2 and lits[1] == "one two" and lits[2] == "three {x}", "literals skip comments")
	end)

	test("Text pass: no old names, fixed typos or lowercase terms in Config's text", function()
		local hits = {}
		local count = 0
		local function walk(v: any, path: string, seen: { [any]: boolean })
			if type(v) == "string" then
				count += 1
				for _, p in problems(v, true, true) do
					table.insert(hits, path .. ": " .. p .. ' in "' .. v .. '"')
				end
			elseif type(v) == "table" and not seen[v] then
				seen[v] = true
				for k, x in v do
					walk(x, path .. "." .. tostring(k), seen)
				end
			end
		end
		for name, mod in Config do
			walk(mod, tostring(name), {})
		end
		check(count > 5000, "the walk read Config's strings (" .. count .. ")")
		for _, h in hits do
			check(false, h)
		end
	end)

	test("Text pass: no old names, fixed typos or lowercase terms in the device's code text", function()
		local hits = {}
		local files = luauFiles("src/first", luauFiles("src/client", {}))
		local count = 0
		for _, path in files do
			for _, lit in literals(fs.readFile(path)) do
				count += 1
				for _, p in problems(lit, true, true) do
					table.insert(hits, path .. ": " .. p .. " in " .. lit)
				end
			end
		end
		check(#files > 60 and count > 3000, string.format("read %d files, %d strings", #files, count))
		for _, h in hits do
			check(false, h)
		end
	end)

	test("Text pass: no old names in the server's and shared code's text (toasts, prompts, cards)", function()
		local hits = {}
		local files = luauFiles("src/shared", luauFiles("src/server", {}))
		for _, path in files do
			for _, lit in literals(fs.readFile(path)) do
				for _, p in problems(lit, true, false) do
					table.insert(hits, path .. ": " .. p .. " in " .. lit)
				end
			end
		end
		check(#files > 80, "read the server and shared files")
		for _, h in hits do
			check(false, h)
		end
	end)
end
