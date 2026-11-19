-- UiSim: a headless screen for the game's own UI code, so Lune can check every screen at phone sizes without
-- Studio (overhaul plan step 8, the phone pass). It runs the real client modules from a built place
-- (ModuleScript sources) with stand-in services: GUI objects are plain Lua stand-ins with the engine's
-- property defaults (from Lune's reflection database), events that can be fired, and a layout pass that
-- works out every object's on-screen box the way Roblox does for the parts our UI uses (UDim2 size and
-- position, AnchorPoint, UIScale, UIPadding, UISizeConstraint, UIAspectRatioConstraint, UIListLayout,
-- UIGridLayout, AutomaticSize, ScrollingFrame canvases, ScreenGui safe insets). Text sizes are estimated from
-- the box (TextScaled) or TextSize, with an average glyph width per font.
-- Not modelled: rich text, rotation, UIFlexItem, real glyph widths. Studio's Device Emulator is still the
-- final check (notes/Tasks.md "Phone pass").
--
--   local sim = UiSim.new(placeGame, device)  -- device: { name, w, h, top, left, right, bottom, touch }
--   local Hud = sim:require("Client.Ui.Hud")    -- a path under StarterPlayerScripts (or "Shared.X")
--   sim:boxes()                                 -- every visible GuiObject with its box
--   sim:issues(opts)                            -- off-screen, overlap, tiny tap targets and tiny text
--   sim:deepIssues(screen, opts, skip)          -- the same for every hidden part of a screen, one at a time
--   sim:advance(seconds)                        -- time passes: task.delay callbacks that come due run

local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local UDim2, UDim, Vector2, Vector3, CFrame, Color3 =
	roblox.UDim2, roblox.UDim, roblox.Vector2, roblox.Vector3, roblox.CFrame, roblox.Color3
local Enum = roblox.Enum

local DB = roblox.getReflectionDatabase()

local UiSim = {}
UiSim.__index = UiSim

---------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
Signal.__type = "RBXScriptSignal"

local function newSignal()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local conn = { Connected = true }
	local handlers = self.handlers
	table.insert(handlers, fn)
	function conn.Disconnect()
		conn.Connected = false
		local i = table.find(handlers, fn)
		if i then
			table.remove(handlers, i)
		end
	end
	return setmetatable(conn, { __type = "RBXScriptConnection" })
end
Signal.connect = Signal.Connect

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn.Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Wait()
	return coroutine.yield() -- never resumed: time does not pass in the sim
end

-- The sim fires events itself (a tap is Activated)
function Signal:Fire(...)
	for _, fn in table.clone(self.handlers) do
		local ok, err = pcall(fn, ...)
		if not ok then
			error(err, 0)
		end
	end
end

---------------------------------------------------------------------------
-- Stand-in instances
---------------------------------------------------------------------------
local FAKE = {} -- marks stand-ins
local CLASS_CHAIN: { [string]: { string } } = {}

local function chainOf(className: string): { string }
	local c = CLASS_CHAIN[className]
	if c then
		return c
	end
	c = {}
	local name: string? = className
	while name do
		table.insert(c, name)
		local info = DB:GetClass(name)
		name = info and info.Superclass or nil
	end
	if #c == 1 and className ~= "Instance" then
		table.insert(c, "Instance") -- unknown classes still are instances
	end
	CLASS_CHAIN[className] = c
	return c
end

-- Studio's Instance.new defaults where the file-format defaults in the database differ
local DEFAULTS: { [string]: { [string]: any } } = {
	GuiObject = {
		Size = UDim2.fromOffset(100, 100),
		Position = UDim2.new(),
		AnchorPoint = Vector2.zero,
		Visible = true,
		ZIndex = 1,
		LayoutOrder = 0,
		BackgroundTransparency = 0,
		Rotation = 0,
		AutomaticSize = Enum.AutomaticSize.None,
		ClipsDescendants = false,
		Active = false,
		Interactable = true,
	},
	GuiButton = { Active = true, AutoButtonColor = true },
	TextLabel = {
		Text = "Label",
		TextSize = 14,
		TextScaled = false,
		TextWrapped = false,
		Font = Enum.Font.Legacy,
	},
	TextButton = {
		Text = "Button",
		TextSize = 14,
		TextScaled = false,
		TextWrapped = false,
		Font = Enum.Font.Legacy,
	},
	TextBox = { Text = "", TextSize = 14, TextScaled = false, TextWrapped = false, Font = Enum.Font.Legacy },
	ImageLabel = { Image = "" },
	ImageButton = { Image = "" },
	ScrollingFrame = {
		ClipsDescendants = true,
		CanvasSize = UDim2.new(0, 0, 2, 0),
		CanvasPosition = Vector2.zero,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		ScrollBarThickness = 12,
		ScrollingEnabled = true,
	},
	CanvasGroup = { ClipsDescendants = true },
	ViewportFrame = {},
	LayerCollector = { Enabled = true, ResetOnSpawn = true },
	ScreenGui = {
		DisplayOrder = 0,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	},
	UIListLayout = {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Wraps = false,
	},
	UIGridLayout = {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		CellSize = UDim2.fromOffset(100, 100),
		CellPadding = UDim2.fromOffset(5, 5),
		FillDirectionMaxCells = 0,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		StartCorner = Enum.StartCorner.TopLeft,
	},
	UIPadding = {
		PaddingTop = UDim.new(0, 0),
		PaddingBottom = UDim.new(0, 0),
		PaddingLeft = UDim.new(0, 0),
		PaddingRight = UDim.new(0, 0),
	},
	UIScale = { Scale = 1 },
	UISizeConstraint = { MinSize = Vector2.zero, MaxSize = Vector2.new(math.huge, math.huge) },
	UITextSizeConstraint = { MinTextSize = 1, MaxTextSize = 100 },
	UIAspectRatioConstraint = {
		AspectRatio = 1,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
	},
	Camera = { FieldOfView = 70, CFrame = CFrame.new() },
	BasePart = {
		Size = Vector3.new(4, 1, 2),
		CFrame = CFrame.new(),
		Position = Vector3.zero,
		Transparency = 0,
		Anchored = false,
		CanCollide = true,
	},
	Model = { PrimaryPart = nil },
	Player = { UserId = 1, Name = "Tester", DisplayName = "Tester", AccountAge = 30, Character = nil },
	Humanoid = { Health = 100, MaxHealth = 100 },
	Sound = { Volume = 0.5, Playing = false, TimeLength = 1 },
	Instance = { Archivable = true },
}

local function defaultOf(className: string, key: string): (boolean, any)
	for _, cname in chainOf(className) do
		local d = DEFAULTS[cname]
		if d and d[key] ~= nil then
			return true, d[key]
		end
	end
	for _, cname in chainOf(className) do
		local info = DB:GetClass(cname)
		if info and info.Properties[key] then
			local dp = DB:GetClass(className)
			local v = dp and dp.DefaultProperties[key]
			return true, v
		end
	end
	return false, nil
end

-- Event names seen in the game's client code (anything else ending in "ed" also reads as an event)
local EVENTS = {}
for _, n in
	string.split(
		"Activated InputBegan InputChanged InputEnded MouseEnter MouseLeave MouseMoved MouseButton1Click "
			.. "MouseButton1Down MouseButton1Up MouseButton2Click TouchTap TouchLongPress TouchPan TouchSwipe "
			.. "TouchPinch TouchStarted TouchMoved FocusLost Focused Changed ChildAdded ChildRemoved "
			.. "DescendantAdded DescendantRemoving AncestryChanged Destroying AttributeChanged Touched "
			.. "TouchEnded Triggered TriggerEnded PromptShown PromptHidden PromptButtonHoldBegan "
			.. "PromptButtonHoldEnded Ended Played Stopped Completed DidLoop Loaded OnClientEvent Event "
			.. "RenderStepped Heartbeat Stepped PreSimulation PostSimulation PreRender PreAnimation "
			.. "CharacterAdded CharacterRemoving CharacterAppearanceLoaded PlayerAdded PlayerRemoving Died "
			.. "HealthChanged StateChanged Running LastInputTypeChanged WindowFocused WindowFocusReleased "
			.. "JumpRequest GamepadConnected GamepadDisconnected MenuOpened MenuClosed "
			.. "PromptProductPurchaseFinished PromptGamePassPurchaseFinished PromptPurchaseFinished "
			.. "MessageReceived SendingMessage TextChannelAdded SelectionGained SelectionLost "
			.. "ReturnPressedFromOnScreenKeyboard KeyframeReached",
		" "
	)
do
	EVENTS[n] = true
end

local Inst = {}
local Methods = {}

local function isFake(x: any): boolean
	return type(x) == "table" and rawget(x, FAKE) == true
end

local nextId = 0
local function newInstance(className: string): any
	nextId += 1
	local self = {
		[FAKE] = true,
		_class = className,
		_props = { Name = className },
		_children = {},
		_attrs = {},
		_signals = {},
		_propSignals = {},
		_attrSignals = {},
		_id = nextId,
	}
	return setmetatable(self, Inst)
end
UiSim.newInstance = newInstance

local function signalOf(self, key: string)
	local s = self._signals[key]
	if not s then
		s = newSignal()
		self._signals[key] = s
	end
	return s
end

Inst.__type = "Instance"
Inst.__index = function(self, key)
	if type(key) == "string" and string.byte(key, 1) == 95 then
		return nil -- the stand-in's own fields ("_parent")
	end
	if key == "ClassName" then
		return self._class
	elseif key == "Parent" then
		return self._parent
	elseif key == "AbsoluteSize" or key == "AbsolutePosition" then
		local sim = UiSim.active
		return if sim then sim:_absolute(self, key) else Vector2.zero
	end
	local props = rawget(self, "_props")
	local v = props[key]
	if v ~= nil then
		return v
	end
	local m = Methods[key]
	if m then
		return m
	end
	local known, d = defaultOf(self._class, key)
	if known then
		return d
	end
	if EVENTS[key] then
		return signalOf(self, key)
	end
	for _, c in self._children do
		if c._props.Name == key then
			return c
		end
	end
	if type(key) == "string" and string.match(key, "^%u") and string.match(key, "ed$") then
		return signalOf(self, key)
	end
	error(string.format("%s is not a valid member of %s %q", tostring(key), self._class, props.Name), 2)
end

Inst.__newindex = function(self, key, value)
	if key == "Parent" then
		local old = self._parent
		if old == value then
			return
		end
		if old then
			local i = table.find(old._children, self)
			if i then
				table.remove(old._children, i)
			end
		end
		if value ~= nil then
			assert(isFake(value), "the sim cannot parent a stand-in to a real instance")
			table.insert(value._children, self)
		end
		rawset(self, "_parent", value)
		return
	end
	self._props[key] = value
	local ps = self._propSignals[key]
	if ps then
		pcall(ps.Fire, ps)
	end
end

Inst.__tostring = function(self)
	return self._props.Name
end

function Methods:IsA(className: string): boolean
	return table.find(chainOf(self._class), className) ~= nil
end
function Methods:GetChildren()
	return table.clone(self._children)
end
function Methods:GetDescendants()
	local out = {}
	local function walk(n)
		for _, c in n._children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function Methods:FindFirstChild(name: string, recursive: boolean?)
	for _, c in self._children do
		if c._props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in self._children do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function Methods:FindFirstChildOfClass(className: string)
	for _, c in self._children do
		if c._class == className then
			return c
		end
	end
	return nil
end
function Methods:FindFirstChildWhichIsA(className: string, recursive: boolean?)
	for _, c in self._children do
		if c:IsA(className) then
			return c
		end
	end
	if recursive then
		for _, c in self._children do
			local f = c:FindFirstChildWhichIsA(className, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function Methods:FindFirstAncestor(name: string)
	local p = self._parent
	while p do
		if p._props.Name == name then
			return p
		end
		p = p._parent
	end
	return nil
end
function Methods:FindFirstAncestorOfClass(className: string)
	local p = self._parent
	while p do
		if p._class == className then
			return p
		end
		p = p._parent
	end
	return nil
end
function Methods:FindFirstAncestorWhichIsA(className: string)
	local p = self._parent
	while p do
		if p:IsA(className) then
			return p
		end
		p = p._parent
	end
	return nil
end
-- A missing child is made on the spot (the server would have made it); it is a Folder unless named for a
-- remote
function Methods:WaitForChild(name: string)
	local c = self:FindFirstChild(name)
	if not c then
		c = newInstance("Folder")
		c.Name = name
		c.Parent = self
	end
	return c
end
function Methods:IsDescendantOf(other)
	local p = self._parent
	while p do
		if p == other then
			return true
		end
		p = p._parent
	end
	return false
end
function Methods:IsAncestorOf(other)
	return other:IsDescendantOf(self)
end
function Methods:GetFullName()
	local parts = {}
	local n = self
	while n do
		table.insert(parts, 1, n._props.Name)
		n = n._parent
	end
	return table.concat(parts, ".")
end
function Methods:Destroy()
	self.Parent = nil
	rawset(self, "_destroyed", true)
	for _, c in table.clone(self._children) do
		c:Destroy()
	end
end
function Methods:ClearAllChildren()
	for _, c in table.clone(self._children) do
		c:Destroy()
	end
end
function Methods:Clone()
	local c = newInstance(self._class)
	for k, v in self._props do
		c._props[k] = v
	end
	for k, v in self._attrs do
		c._attrs[k] = v
	end
	for _, child in self._children do
		child:Clone().Parent = c
	end
	return c
end
function Methods:GetAttribute(name: string)
	return self._attrs[name]
end
function Methods:SetAttribute(name: string, value: any)
	self._attrs[name] = value
	local s = self._attrSignals[name]
	if s then
		pcall(s.Fire, s, value)
	end
end
function Methods:GetAttributes()
	return table.clone(self._attrs)
end
function Methods:GetAttributeChangedSignal(name: string)
	local s = self._attrSignals[name]
	if not s then
		s = newSignal()
		self._attrSignals[name] = s
	end
	return s
end
function Methods:GetPropertyChangedSignal(name: string)
	local s = self._propSignals[name]
	if not s then
		s = newSignal()
		self._propSignals[name] = s
	end
	return s
end
function Methods:GetPivot()
	return self._props.CFrame or self._props.WorldPivot or CFrame.new()
end
function Methods:PivotTo(cf)
	self._props.CFrame = cf
end
function Methods:GetBoundingBox()
	return CFrame.new(), Vector3.new(4, 5, 2)
end
function Methods:GetExtentsSize()
	return Vector3.new(4, 5, 2)
end
function Methods:ScaleTo() end
function Methods:GetScale()
	return 1
end
function Methods:AddTag(tag: string)
	self._attrs["@tag:" .. tag] = true
end
function Methods:HasTag(tag: string)
	return self._attrs["@tag:" .. tag] == true
end
function Methods:RemoveTag(tag: string)
	self._attrs["@tag:" .. tag] = nil
end
for _, name in
	string.split(
		"Play Stop Pause Resume Emit Clear FireServer FireClient FireAllClients Kick SetMotor AdjustSpeed "
			.. "ChangeState BreakJoints MoveTo ApplyImpulse ApplyAngularImpulse SetNetworkOwner CaptureFocus "
			.. "ReleaseFocus LoadAnimation SetPrimaryPartCFrame TweenSize TweenPosition TweenSizeAndPosition "
			.. "Enable Disable Cancel BindAction UnbindAction BindToRenderStep UnbindFromRenderStep Fire "
			.. "ApplyMesh ApplyDescription SetCore SetCoreGuiEnabled PreloadAsync AddItem Invoke "
			.. "SetStateEnabled Move",
		" "
	)
do
	Methods[name] = Methods[name] or function() end
end
function Methods:GetState()
	return Enum.HumanoidStateType.Running
end
function Methods:GetPlayingAnimationTracks()
	return {}
end
function Methods:InvokeServer()
	return nil
end

---------------------------------------------------------------------------
-- A stand-in for anything the sim does not model: every member is a function returning another stand-in
---------------------------------------------------------------------------
local function permissive(name: string): any
	local p = {}
	return setmetatable(p, {
		__index = function(_, k)
			if k == "Connect" or k == "Once" then
				return function()
					return { Disconnect = function() end, Connected = true }
				end
			end
			return permissive(name .. "." .. tostring(k))
		end,
		__call = function()
			return permissive(name .. "()")
		end,
		__tostring = function()
			return name
		end,
	})
end

---------------------------------------------------------------------------
-- The sim
---------------------------------------------------------------------------
local REAL_SERVICES = { ReplicatedStorage = true, ReplicatedFirst = true, StarterPlayer = true }

-- The place's module trees as stand-ins (Lune's own instances cannot take stand-in children or events)
local function copyTree(real: any): any
	local f = newInstance(real.ClassName)
	f._props.Name = real.Name
	if real:IsA("LuaSourceContainer") then
		f._props.Source = real.Source
	end
	local ok, attrs = pcall(function()
		return real:GetAttributes()
	end)
	if ok then
		for k, v in attrs do
			f._attrs[k] = v
		end
	end
	for _, c in real:GetChildren() do
		copyTree(c).Parent = f
	end
	return f
end

-- Load a deserialized place once; every sim made from the result shares its module trees
function UiSim.load(place: any): { [string]: any }
	local out = {}
	for name in REAL_SERVICES do
		out[name] = copyTree(place:GetService(name))
	end
	return out
end

function UiSim.new(place: any, device: { [string]: any })
	local self = setmetatable({}, UiSim)
	self.place = place
	self.device = device
	self.cache = {}
	self.loading = {}
	self.errors = {}
	self.yields = {}
	self.now = 0 -- the sim's clock (sim:advance) and its task.delay callbacks
	self.timers = {}
	UiSim.active = self
	self:_services()
	return self
end

function UiSim:_services()
	local d = self.device
	local services = {}
	self.services = services
	local game = newInstance("DataModel")
	game.Name = "Game"
	self.game = game
	local function service(name: string): any
		if REAL_SERVICES[name] then
			local s = self.place[name]
			if s._parent ~= game then
				s._parent = nil
				s.Parent = game
			end
			return s
		end
		local s = services[name]
		if not s then
			local ok = pcall(function()
				return DB:GetClass(name)
			end)
			s = newInstance(if ok and DB:GetClass(name) then name else "Folder")
			s.Name = name
			s.Parent = game
			services[name] = s
		end
		return s
	end
	self.service = service
	game._props.GetService = function(_, name)
		return service(name)
	end
	game._props.FindService = game._props.GetService
	game._props.PlaceId = 0
	game._props.JobId = "sim"
	game._props.PlaceVersion = 1
	game._props.CreatorId = 0
	game._props.GameId = 0
	-- Workspace and the camera at the device's size
	local ws = service("Workspace")
	local cam = newInstance("Camera")
	cam.Name = "Camera"
	cam.ViewportSize = Vector2.new(d.w, d.h)
	cam.Parent = ws
	ws.CurrentCamera = cam
	ws.Gravity = 196.2
	ws.DistributedGameTime = 0
	ws._props.Raycast = function()
		return nil
	end
	ws._props.Spherecast = ws._props.Raycast
	ws._props.Blockcast = ws._props.Raycast
	ws._props.GetPartBoundsInRadius = function()
		return {}
	end
	ws._props.GetPartBoundsInBox = ws._props.GetPartBoundsInRadius
	ws._props.GetPartsInPart = ws._props.GetPartBoundsInRadius
	ws._props.GetServerTimeNow = function()
		return os.clock()
	end
	ws._props.BulkMoveTo = function() end
	cam._props.ViewportPointToRay = function(_, _x, _y)
		return roblox.Ray.new(Vector3.zero, Vector3.new(0, 0, -1))
	end
	cam._props.ScreenPointToRay = cam._props.ViewportPointToRay
	cam._props.WorldToViewportPoint = function()
		return Vector3.new(d.w / 2, d.h / 2, 10), true
	end
	cam._props.WorldToScreenPoint = cam._props.WorldToViewportPoint
	-- the player
	local players = service("Players")
	local me = newInstance("Player")
	me.Name = "Tester"
	me.Parent = players
	local pg = newInstance("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = me
	local ps = newInstance("PlayerScripts")
	ps.Name = "PlayerScripts"
	ps.Parent = me
	players.LocalPlayer = me
	players.MaxPlayers = 30
	players._props.GetPlayers = function()
		return { me }
	end
	players._props.GetPlayerByUserId = function(_, id)
		return if id == 1 then me else nil
	end
	players._props.GetPlayerFromCharacter = function()
		return nil
	end
	players._props.GetUserIdFromNameAsync = function()
		return 1
	end
	players._props.GetNameFromUserIdAsync = function()
		return "Tester"
	end
	me._props.GetMouse = function()
		return permissive("Mouse")
	end
	me._props.IsFriendsWith = function()
		return false
	end
	me._props.GetNetworkPing = function()
		return 0.05
	end
	self.player = me
	self.playerGui = pg
	-- input and GUI services for this device
	local uis = service("UserInputService")
	uis.TouchEnabled = d.touch == true
	uis.KeyboardEnabled = not d.touch and not d.gamepad
	uis.MouseEnabled = not d.touch and not d.gamepad
	uis.GamepadEnabled = d.gamepad == true
	uis.VREnabled = false
	uis.MouseBehavior = Enum.MouseBehavior.Default
	uis._props.GetMouseLocation = function()
		return Vector2.new(d.w / 2, d.h / 2)
	end
	uis._props.GetLastInputType = function()
		return if d.touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1
	end
	uis._props.GetConnectedGamepads = function()
		return {}
	end
	uis._props.GetFocusedTextBox = function()
		return nil
	end
	uis._props.GetGamepadState = function()
		return {}
	end
	uis._props.IsKeyDown = function()
		return false
	end
	uis._props.GetKeysPressed = function()
		return {}
	end
	local gs = service("GuiService")
	gs._props.IsTenFootInterface = function()
		return d.tenFoot == true
	end
	gs._props.GetGuiInset = function()
		return Vector2.new(0, d.top), Vector2.zero
	end
	gs.TopbarInset = roblox.Rect.new(0, 0, d.w, d.top)
	gs.SelectedObject = nil
	gs.MenuIsOpen = false
	local rs = service("RunService")
	rs._props.IsStudio = function()
		return false
	end
	rs._props.IsClient = function()
		return true
	end
	rs._props.IsServer = function()
		return false
	end
	rs._props.IsRunning = function()
		return true
	end
	local ts = service("TweenService")
	ts._props.Create = function(_, inst, _info, goals)
		local tw = newInstance("Tween")
		tw._props.Play = function()
			for k, v in goals do
				inst[k] = v -- the sim jumps to the end of every tween
			end
		end
		return tw
	end
	ts._props.GetValue = function(_, a)
		return a
	end
	local txt = service("TextService")
	txt._props.GetTextSize = function(_, text, size, _font, frame)
		local w = #text * size * 0.55
		return Vector2.new(math.min(w, frame and frame.X or w), size)
	end
	local http = service("HttpService")
	local n = 0
	http._props.GenerateGUID = function()
		n += 1
		return "guid-" .. n
	end
	local serde = require("@lune/serde")
	http._props.JSONEncode = function(_, v)
		return serde.encode("json", v)
	end
	http._props.JSONDecode = function(_, s)
		return serde.decode("json", s)
	end
	local cs = service("CollectionService")
	cs._props.GetTagged = function()
		return {}
	end
	cs._props.GetInstanceAddedSignal = function()
		return newSignal()
	end
	cs._props.GetInstanceRemovedSignal = cs._props.GetInstanceAddedSignal
	local hs = service("HapticService")
	hs._props.IsVibrationSupported = function()
		return false
	end
	hs._props.IsMotorSupported = hs._props.IsVibrationSupported
	local ms = service("MarketplaceService")
	ms._props.UserOwnsGamePassAsync = function()
		return false
	end
	ms._props.GetProductInfo = function()
		return { PriceInRobux = 0, Name = "" }
	end
	local sg = service("StarterGui")
	sg._props.GetCore = function()
		return nil
	end
	sg._props.GetCoreGuiEnabled = function()
		return true
	end
	local stats = service("Stats")
	stats._props.GetTotalMemoryUsageMb = function()
		return 500
	end
	local lighting = service("Lighting")
	lighting.ClockTime = 14
	lighting.GlobalShadows = true
	for _, e in
		{ { "Bloom", "BloomEffect" }, { "SunRays", "SunRaysEffect" }, { "Grade", "ColorCorrectionEffect" } }
	do
		local x = newInstance(e[2])
		x.Name = e[1]
		x.Enabled = true
		x.Parent = lighting
	end
	local atmo = newInstance("Atmosphere")
	atmo.Name = "Atmosphere"
	atmo.Parent = lighting
	local pps = service("ProximityPromptService")
	pps.Enabled = true
	local ss = service("SoundService")
	ss.Volume = 1
	local tcs = service("TextChatService")
	tcs._props.CanUsersChatAsync = function()
		return true
	end
	local vr = service("VRService")
	vr.VREnabled = false
	self.workspace = ws
	self.camera = cam
end

-- The globals a module sees
function UiSim:_env(script: any): { [string]: any }
	local sim = self
	local task = {
		spawn = function(f, ...)
			if type(f) ~= "function" then
				return nil
			end
			local co = coroutine.create(f)
			local ok, err = coroutine.resume(co, ...)
			if not ok then
				table.insert(sim.errors, "task.spawn: " .. tostring(err))
			end
			return co
		end,
		defer = nil :: any,
		delay = function(t, f, ...)
			-- time passes only when a test calls sim:advance
			if type(f) == "function" then
				table.insert(sim.timers, { at = sim.now + (tonumber(t) or 0), f = f, args = table.pack(...) })
			end
			return nil
		end,
		wait = function()
			if coroutine.isyieldable() then
				coroutine.yield()
			end
			return 0
		end,
		cancel = function() end,
		synchronize = function() end,
		desynchronize = function() end,
	}
	task.defer = task.spawn
	local function typeofX(v: any): string
		if isFake(v) then
			return "Instance"
		end
		local mt = getmetatable(v)
		if type(v) == "table" and type(mt) == "table" and rawget(mt, "__type") then
			return rawget(mt, "__type")
		end
		return typeof(v)
	end
	local randomMt = {}
	randomMt.__index = randomMt
	function randomMt:NextNumber(a, b)
		a, b = a or 0, b or 1
		return a + (b - a) * math.random()
	end
	function randomMt:NextInteger(a, b)
		return math.random(a, b)
	end
	function randomMt:Clone()
		return setmetatable({}, randomMt)
	end
	return {
		game = self.game,
		workspace = self.workspace,
		Workspace = self.workspace,
		script = script,
		require = function(m)
			return sim:_requireInstance(m)
		end,
		Instance = {
			new = function(className, parent)
				local i = newInstance(className)
				if parent then
					i.Parent = parent
				end
				return i
			end,
		},
		task = task,
		typeof = typeofX,
		wait = task.wait,
		delay = task.delay,
		spawn = task.spawn,
		tick = os.clock,
		time = os.clock,
		elapsedTime = os.clock,
		settings = function()
			return permissive("settings")
		end,
		UserSettings = function()
			return permissive("UserSettings")
		end,
		Enum = Enum,
		UDim2 = UDim2,
		UDim = UDim,
		Vector2 = Vector2,
		Vector3 = Vector3,
		CFrame = CFrame,
		Color3 = Color3,
		BrickColor = roblox.BrickColor,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		PhysicalProperties = roblox.PhysicalProperties,
		Rect = roblox.Rect,
		Ray = roblox.Ray,
		Region3 = roblox.Region3,
		Font = roblox.Font,
		Faces = roblox.Faces,
		Axes = roblox.Axes,
		Vector2int16 = roblox.Vector2int16,
		Vector3int16 = roblox.Vector3int16,
		TweenInfo = {
			new = function(...)
				return { ... }
			end,
		},
		RaycastParams = {
			new = function()
				return {}
			end,
		},
		OverlapParams = {
			new = function()
				return {}
			end,
		},
		Random = {
			new = function()
				return setmetatable({}, randomMt)
			end,
		},
		DateTime = {
			now = function()
				return { UnixTimestamp = os.time(), UnixTimestampMillis = os.time() * 1000 }
			end,
		},
		warn = function() end,
		print = function() end,
	}
end

-- require() of a ModuleScript from the place (cached per sim) or a stand-in
function UiSim:_requireInstance(m: any): any
	if not isFake(m) then
		error("require of a non-instance: " .. tostring(m), 2)
	end
	if m._props.Source == nil then
		return permissive("module " .. tostring(m)) -- made on the spot (a module the place does not have)
	end
	local key = m:GetFullName()
	local hit = self.cache[key]
	if hit ~= nil then
		return hit
	end
	local stub = self.stubs and self.stubs[m.Name]
	if stub then
		self.cache[key] = stub
		return stub
	end
	if self.loading[key] then
		error("require cycle at " .. key, 2)
	end
	self.loading[key] = true
	if UiSim.trace then
		print("load", key)
	end
	local fn = luau.load(m._props.Source, { debugName = key, environment = self:_env(m) })
	local co = coroutine.create(fn)
	local ok, result = coroutine.resume(co)
	self.loading[key] = nil
	if not ok then
		error(string.format("loading %s: %s", key, tostring(result)), 0)
	end
	if coroutine.status(co) ~= "dead" then
		error("module " .. key .. " yielded while loading", 0)
	end
	self.cache[key] = result
	return result
end

-- A module by dotted path: "Client.Ui.Hud" (under StarterPlayerScripts), "Shared.Net", "Config"
function UiSim:require(path: string): any
	local parts = string.split(path, ".")
	local node
	if parts[1] == "Client" then
		node = self.place.StarterPlayer:FindFirstChild("StarterPlayerScripts")
	else
		node = self.place.ReplicatedStorage
	end
	for _, p in parts do
		node = node:FindFirstChild(p)
		assert(node, "no module at " .. path)
	end
	return self:_requireInstance(node)
end

-- Run fn as the game would (in a coroutine, so a wait pauses it rather than failing). Returns ok, err.
-- Move the sim's clock on: every task.delay callback due by then runs, earliest first (one a callback
-- schedules runs too if it comes due in the same span)
function UiSim:advance(seconds: number)
	local stop = self.now + seconds
	while true do
		local best, at = nil, math.huge
		for i, t in self.timers do
			if t.at <= stop and t.at < at then
				best, at = i, t.at
			end
		end
		if not best then
			break
		end
		local t = table.remove(self.timers, best)
		self.now = t.at
		self:run("task.delay", function()
			t.f(table.unpack(t.args, 1, t.args.n))
		end)
	end
	self.now = stop
end

function UiSim:run(label: string, fn: () -> ()): (boolean, string?)
	local co = coroutine.create(fn)
	local ok, err = coroutine.resume(co)
	if not ok then
		table.insert(self.errors, label .. ": " .. tostring(err))
		return false, tostring(err)
	end
	if coroutine.status(co) ~= "dead" then
		table.insert(self.yields, label)
	end
	return true, nil
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
export type Box = {
	inst: any,
	x: number,
	y: number,
	w: number,
	h: number,
	scale: number, -- every UIScale above and on it multiplied
	screen: any, -- its ScreenGui
	clip: { x: number, y: number, w: number, h: number }?, -- the clipping ancestor's box
	inScroll: any?, -- the ScrollingFrame it scrolls in
	text: number?, -- the estimated text size in pixels (text objects with text)
	textFits: boolean?, -- false when the text spills out of its box
	button: boolean,
	deco: boolean?, -- in a Kit ink Folder (shadow, halftone): drawn, never checked
}

local function udim(u: any, size: number): number
	return u.Scale * size + u.Offset
end

local function childOf(inst: any, className: string): any
	for _, c in inst._children do
		if c._class == className then
			return c
		end
	end
	return nil
end

local GLYPH = { [Enum.Font.Bangers] = 0.46, [Enum.Font.GothamBold] = 0.62, [Enum.Font.GothamBlack] = 0.64 }
local function glyph(font: any): number
	return GLYPH[font] or 0.56
end

local function plainText(s: string): string
	s = string.gsub(s, "<[^>]+>", "")
	return s
end

-- The pixel size Roblox would draw a text object's text at, and whether it fits its box
local function textSize(inst: any, w: number, h: number, k: number): (number?, boolean)
	local ok, text = pcall(function()
		return inst.Text
	end)
	if not ok or type(text) ~= "string" then
		return nil, true
	end
	text = plainText(text)
	if text == "" or string.match(text, "^%s*$") then
		return nil, true
	end
	local pad = childOf(inst, "UIPadding")
	if pad then
		w -= (udim(pad.PaddingLeft, w) + udim(pad.PaddingRight, w)) * k
		h -= (udim(pad.PaddingTop, h) + udim(pad.PaddingBottom, h)) * k
	end
	w, h = math.max(1, w), math.max(1, h)
	local gw = glyph(inst.Font)
	local lines = string.split(text, "\n")
	local longest = 0
	local chars = 0
	for _, l in lines do
		longest = math.max(longest, utf8.len(l) or #l)
		chars += utf8.len(l) or #l
	end
	local wrapped = inst.TextWrapped == true
	local function fits(s: number): boolean
		if wrapped then
			local perLine = math.max(1, math.floor(w / (gw * s)))
			local n = 0
			for _, l in lines do
				n += math.max(1, math.ceil((utf8.len(l) or #l) / perLine))
			end
			return n * s * 1.1 <= h + 0.5
		end
		return longest * gw * s <= w + 0.5 and #lines * s * 1.05 <= h + 0.5
	end
	if inst.TextScaled then
		local limit = childOf(inst, "UITextSizeConstraint")
		local hi = math.min(100, if limit then limit.MaxTextSize else 100) * k
		local lo = (if limit then limit.MinTextSize else 1) * k
		local s = hi
		while s > lo and not fits(s) do
			s -= 0.5
		end
		return s, fits(s)
	end
	local s = (inst.TextSize or 14) * k
	return s, fits(s)
end

-- The safe area a ScreenGui lays out in
local function screenArea(sim, gui): (number, number, number, number)
	local d = sim.device
	local insets = gui.ScreenInsets
	local left, top, right, bottom = 0, 0, 0, 0
	if insets == Enum.ScreenInsets.CoreUISafeInsets or insets == Enum.ScreenInsets.DeviceSafeInsets then
		left, right, bottom = d.left or 0, d.right or 0, d.bottom or 0
	end
	if insets == Enum.ScreenInsets.CoreUISafeInsets or not gui.IgnoreGuiInset then
		top = d.top
	end
	return left, top, d.w - left - right, d.h - top - bottom
end

local function sorted(children: { any }, layout: any): { any }
	local list = {}
	for i, c in children do
		if c:IsA("GuiObject") and c.Visible then
			table.insert(list, { c = c, i = i })
		end
	end
	if layout.SortOrder == Enum.SortOrder.Name then
		table.sort(list, function(a, b)
			return a.c.Name < b.c.Name
		end)
	else
		table.sort(list, function(a, b)
			if a.c.LayoutOrder ~= b.c.LayoutOrder then
				return a.c.LayoutOrder < b.c.LayoutOrder
			end
			return a.i < b.i
		end)
	end
	local out = {}
	for _, e in list do
		table.insert(out, e.c)
	end
	return out
end

-- Size of an object in its parent's unscaled space (before its own UIScale), with constraints and the
-- automatic size from its content
local function baseSize(inst: any, pw: number, ph: number): (number, number)
	local s = inst.Size
	local w, h = udim(s.X, pw), udim(s.Y, ph)
	local ar = childOf(inst, "UIAspectRatioConstraint")
	if ar then
		local r = ar.AspectRatio
		if ar.AspectType == Enum.AspectType.ScaleWithParentSize then
			if ar.DominantAxis == Enum.DominantAxis.Width then
				h = w / r
			else
				w = h * r
			end
		else -- FitWithinMaxSize
			if w / math.max(h, 1e-6) > r then
				w = h * r
			else
				h = w / r
			end
		end
	end
	local sc = childOf(inst, "UISizeConstraint")
	if sc then
		w = math.clamp(w, sc.MinSize.X, math.max(sc.MinSize.X, sc.MaxSize.X))
		h = math.clamp(h, sc.MinSize.Y, math.max(sc.MinSize.Y, sc.MaxSize.Y))
	end
	return math.max(0, w), math.max(0, h)
end

function UiSim:_layoutChildren(parent: any, box: Box, out: { Box }, padFrom: any?)
	local k = box.scale
	-- content area (padding), in the parent's own unscaled pixels (a Folder's children: its GuiObject's)
	local cw, ch = box.w / k, box.h / k
	local ox, oy = 0, 0
	local pad = childOf(padFrom or parent, "UIPadding")
	if pad then
		local l, r = udim(pad.PaddingLeft, cw), udim(pad.PaddingRight, cw)
		local t, b = udim(pad.PaddingTop, ch), udim(pad.PaddingBottom, ch)
		ox, oy = l, t
		cw, ch = math.max(0, cw - l - r), math.max(0, ch - t - b)
	end
	local isScroll = parent:IsA("ScrollingFrame")
	local scroll = if isScroll then parent else box.inScroll
	local clip = box.clip
	if parent:IsA("GuiObject") and parent.ClipsDescendants then
		clip = { x = box.x, y = box.y, w = box.w, h = box.h }
	end
	-- a scrolling frame lays its children out on its canvas
	local areaW, areaH = cw, ch
	if isScroll then
		local cs = parent.CanvasSize
		areaW = math.max(cw, udim(cs.X, cw))
		areaH = math.max(ch, udim(cs.Y, ch))
		local auto = parent.AutomaticCanvasSize
		if auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY then
			areaH = ch -- children sized against the visible height; the canvas grows to fit them
		end
		if auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY then
			areaW = cw
		end
		local bar = parent.ScrollBarThickness or 12
		local dir = parent.ScrollingDirection
		if dir == Enum.ScrollingDirection.Y or dir == Enum.ScrollingDirection.XY then
			areaW -= 0 -- Roblox overlays the bar; content keeps the full width
		end
		local _ = bar
	end
	local list = childOf(parent, "UIListLayout")
	local grid = childOf(parent, "UIGridLayout")
	local placed: { [any]: { x: number, y: number } } = {}
	local sizes: { [any]: { w: number, h: number } } = {}
	local function sizeOf(c: any): (number, number)
		local s = sizes[c]
		if not s then
			local w, h = baseSize(c, areaW, areaH)
			w, h = self:_autoSize(c, w, h, areaW, areaH)
			s = { w = w, h = h }
			sizes[c] = s
		end
		return s.w, s.h
	end
	if list then
		local items = sorted(parent._children, list)
		local horizontal = list.FillDirection == Enum.FillDirection.Horizontal
		local gap = udim(list.Padding, if horizontal then areaW else areaH)
		local total = 0
		for i, c in items do
			local w, h = sizeOf(c)
			total += (if horizontal then w else h) + (if i > 1 then gap else 0)
		end
		local main = 0
		if horizontal then
			if list.HorizontalAlignment == Enum.HorizontalAlignment.Center then
				main = (areaW - total) / 2
			elseif list.HorizontalAlignment == Enum.HorizontalAlignment.Right then
				main = areaW - total
			end
		else
			if list.VerticalAlignment == Enum.VerticalAlignment.Center then
				main = (areaH - total) / 2
			elseif list.VerticalAlignment == Enum.VerticalAlignment.Bottom then
				main = areaH - total
			end
		end
		for _, c in items do
			local w, h = sizeOf(c)
			local cross
			if horizontal then
				cross = 0
				if list.VerticalAlignment == Enum.VerticalAlignment.Center then
					cross = (areaH - h) / 2
				elseif list.VerticalAlignment == Enum.VerticalAlignment.Bottom then
					cross = areaH - h
				end
				placed[c] = { x = main, y = cross }
				main += w + gap
			else
				cross = 0
				if list.HorizontalAlignment == Enum.HorizontalAlignment.Center then
					cross = (areaW - w) / 2
				elseif list.HorizontalAlignment == Enum.HorizontalAlignment.Right then
					cross = areaW - w
				end
				placed[c] = { x = cross, y = main }
				main += h + gap
			end
		end
	elseif grid then
		local items = sorted(parent._children, grid)
		local cellW, cellH = udim(grid.CellSize.X, areaW), udim(grid.CellSize.Y, areaH)
		local gx, gy = udim(grid.CellPadding.X, areaW), udim(grid.CellPadding.Y, areaH)
		local horizontal = grid.FillDirection == Enum.FillDirection.Horizontal
		local per
		if horizontal then
			per = math.max(1, math.floor((areaW + gx) / (cellW + gx)))
		else
			per = math.max(1, math.floor((areaH + gy) / (cellH + gy)))
		end
		if grid.FillDirectionMaxCells > 0 then
			per = math.min(per, grid.FillDirectionMaxCells)
		end
		local rowW = per * cellW + (per - 1) * gx
		local startX = 0
		if horizontal and grid.HorizontalAlignment == Enum.HorizontalAlignment.Center then
			startX = (areaW - rowW) / 2
		elseif horizontal and grid.HorizontalAlignment == Enum.HorizontalAlignment.Right then
			startX = areaW - rowW
		end
		for i, c in items do
			local a, b = (i - 1) % per, (i - 1) // per
			if horizontal then
				placed[c] = { x = startX + a * (cellW + gx), y = b * (cellH + gy) }
			else
				placed[c] = { x = b * (cellW + gx), y = a * (cellH + gy) }
			end
			sizes[c] = { w = cellW, h = cellH }
		end
	end
	for _, c in parent._children do
		if c:IsA("GuiObject") and c.Visible then
			local w, h = sizeOf(c)
			local ownScale = 1
			local us = childOf(c, "UIScale")
			if us then
				ownScale = us.Scale
			end
			local kc = k * ownScale
			local ax, ay -- top-left in the parent's unscaled content space
			local p = placed[c]
			if p then
				ax, ay = p.x, p.y
				-- a scale on a laid-out child grows it around its centre
				local gwx, ghy = w * (ownScale - 1), h * (ownScale - 1)
				ax -= gwx / 2
				ay -= ghy / 2
			else
				local pos = c.Position
				local px, py = udim(pos.X, areaW), udim(pos.Y, areaH)
				ax = px - c.AnchorPoint.X * w * ownScale
				ay = py - c.AnchorPoint.Y * h * ownScale
			end
			local cb: Box = {
				inst = c,
				x = box.x + (ox + ax) * k,
				y = box.y + (oy + ay) * k,
				w = w * kc,
				h = h * kc,
				scale = kc,
				screen = box.screen,
				clip = clip,
				inScroll = scroll,
				button = c:IsA("GuiButton") or c:IsA("TextBox"),
			}
			if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("TextBox") then
				cb.text, cb.textFits = textSize(c, cb.w, cb.h, kc)
			end
			table.insert(out, cb)
			self:_layoutChildren(c, cb, out)
		elseif c._class == "Folder" and c._props.Name == "Ink" then
			-- Kit's comic ink (drop shadow, halftone): Roblox draws a Folder's GuiObjects as the parent's
			-- own, outside its UIListLayout; marked deco so the checks skip them (they only decorate)
			local from = #out
			self:_layoutChildren(c, box, out, parent)
			for i = from + 1, #out do
				out[i].deco = true
			end
		end
	end
end

-- AutomaticSize: grow to the content (children boxes, or the text)
function UiSim:_autoSize(c: any, w: number, h: number, pw: number, ph: number): (number, number)
	local auto = c.AutomaticSize
	if auto == Enum.AutomaticSize.None then
		return w, h
	end
	local growX = auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY
	local growY = auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY
	local needW, needH = 0, 0
	if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("TextBox") then
		local text = plainText(c.Text or "")
		local size = c.TextSize or 14
		local gw = glyph(c.Font)
		if c.TextWrapped and not growX then
			local perLine = math.max(1, math.floor(w / (gw * size)))
			local lines = 0
			for _, l in string.split(text, "\n") do
				lines += math.max(1, math.ceil((utf8.len(l) or #l) / perLine))
			end
			needH = lines * size * 1.15
		else
			local longest, n = 0, 0
			for _, l in string.split(text, "\n") do
				longest = math.max(longest, utf8.len(l) or #l)
				n += 1
			end
			needW = longest * gw * size
			needH = n * size * 1.15
		end
	end
	-- children: lay them out in a scratch box and take their extent
	local scratch: { Box } = {}
	local probe: Box = {
		inst = c,
		x = 0,
		y = 0,
		w = w,
		h = h,
		scale = 1,
		screen = nil,
		button = false,
	}
	self:_layoutChildren(c, probe, scratch)
	for _, b in scratch do
		if b.inst._parent == c then
			needW = math.max(needW, b.x + b.w)
			needH = math.max(needH, b.y + b.h)
		end
	end
	local pad = childOf(c, "UIPadding")
	if pad then
		needW += udim(pad.PaddingRight, w)
		needH += udim(pad.PaddingBottom, h)
	end
	if growX then
		w = math.max(w, needW)
	end
	if growY then
		h = math.max(h, needH)
	end
	local _ = pw + ph
	return w, h
end

-- AbsoluteSize and AbsolutePosition: a ScreenGui's safe area, or a GuiObject's laid-out box
function UiSim:_absolute(inst: any, key: string): any
	if inst:IsA("ScreenGui") then
		local x, y, w, h = screenArea(self, inst)
		return if key == "AbsoluteSize" then Vector2.new(w, h) else Vector2.new(x, y)
	end
	for _, b in self:boxes() do
		if b.inst == inst then
			return if key == "AbsoluteSize" then Vector2.new(b.w, b.h) else Vector2.new(b.x, b.y)
		end
	end
	return Vector2.zero
end

-- Every visible GuiObject's box, for every enabled ScreenGui, in draw order
function UiSim:boxes(): { Box }
	local out: { Box } = {}
	local guis = {}
	for _, g in self.playerGui._children do
		if g:IsA("ScreenGui") and g.Enabled then
			table.insert(guis, g)
		end
	end
	table.sort(guis, function(a, b)
		return a.DisplayOrder < b.DisplayOrder
	end)
	for _, g in guis do
		local x, y, w, h = screenArea(self, g)
		local root: Box = { inst = g, x = x, y = y, w = w, h = h, scale = 1, screen = g, button = false }
		self:_layoutChildren(g, root, out)
	end
	return out
end

-- Shown on screen: it draws something (a fill, text, an image or a stroke)
local function draws(b: Box): boolean
	local i = b.inst
	if i.BackgroundTransparency < 0.99 then
		return true
	end
	if b.text then
		return true
	end
	if (i:IsA("ImageLabel") or i:IsA("ImageButton")) and i.Image ~= "" and i.ImageTransparency < 0.99 then
		return true
	end
	if i:IsA("ViewportFrame") then
		return true
	end
	return false
end
UiSim.draws = draws

local function overlap(a: Box, b: Box): number
	local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if w <= 0 or h <= 0 then
		return 0
	end
	return w * h
end
UiSim.overlap = overlap

local function related(a: any, b: any): boolean
	return a == b or a:IsDescendantOf(b) or b:IsDescendantOf(a)
end

-- Inside its clipping or scrolling ancestor (else it is cut off, so not shown)
local function shownPart(b: Box): Box?
	local c = b.clip
	if not c then
		return b
	end
	local x0, y0 = math.max(b.x, c.x), math.max(b.y, c.y)
	local x1, y1 = math.min(b.x + b.w, c.x + c.w), math.min(b.y + b.h, c.y + c.h)
	if x1 <= x0 or y1 <= y0 then
		return nil
	end
	return {
		inst = b.inst,
		x = x0,
		y = y0,
		w = x1 - x0,
		h = y1 - y0,
		scale = b.scale,
		screen = b.screen,
		button = b.button,
	}
end

-- What a player would trip over: opts { minTap = px, minText = px, thumb = {x0, y0, x1, y1} as screen
-- fractions (the move stick's zone), ignore = { [name] = true }, only = ScreenGui names or nil for all }
function UiSim:issues(opts: { [string]: any }): { string }
	local d = self.device
	local out = {}
	local boxes = self:boxes()
	local seen = {}
	local function say(s: string)
		if not seen[s] then
			seen[s] = true
			table.insert(out, s)
		end
	end
	local function name(b: Box): string
		local n = b.inst:GetFullName()
		n = string.gsub(n, "^Game%.Players%.Tester%.PlayerGui%.", "")
		local t = rawget(b.inst._props, "Text")
		if b.text and type(t) == "string" and #t > 0 then
			n ..= " '" .. string.sub(plainText(t), 1, 24) .. "'"
		end
		return n
	end
	local function wanted(b: Box): boolean
		if opts.only and not opts.only[b.screen.Name] then
			return false
		end
		if opts.minOrder and b.screen.DisplayOrder < opts.minOrder then
			return false -- under the panel being checked (it covers them)
		end
		local n = b.inst
		while n and n ~= b.screen do
			if opts.ignore and opts.ignore[n.Name] then
				return false
			end
			n = n._parent
		end
		return true
	end
	local taps: { Box } = {}
	local byInst = {}
	for _, b in boxes do
		byInst[b.inst] = b
	end
	-- the panel a box belongs to: its ScreenGui's direct child, when that draws (a card or panel)
	local function panelOf(b: Box): Box?
		local n = b.inst
		while n._parent and n._parent ~= b.screen do
			n = n._parent
		end
		local p = byInst[n]
		if p and p ~= b and draws(p) then
			return p
		end
		return nil
	end
	for _, b in boxes do
		if wanted(b) and draws(b) and not b.deco then
			local s = shownPart(b)
			if s then
				-- off the screen
				local slack = 2
				if s.x < -slack or s.y < -slack or s.x + s.w > d.w + slack or s.y + s.h > d.h + slack then
					say(string.format("off screen: %s at %d,%d %dx%d", name(b), s.x, s.y, s.w, s.h))
				elseif b.button and opts.safe then
					-- buttons stay in the safe area: out of the notch, the home bar and Roblox's top bar
					local l, r, bt = d.left or 0, d.right or 0, d.bottom or 0
					if s.x < l - slack or s.x + s.w > d.w - r + slack or s.y + s.h > d.h - bt + slack then
						say(string.format("in the notch or home bar: %s", name(b)))
					elseif s.y < d.top - slack then
						say(string.format("under Roblox's top bar: %s", name(b)))
					end
				end
				if b.button then
					-- cut off by a clipping parent (a list that does not scroll that way)
					if s.w < b.w - 2 and not b.inScroll then
						say(string.format("cut off: %s (%d of %d px wide)", name(b), s.w, b.w))
					end
					if opts.minTap and (b.w < opts.minTap - 0.5 or b.h < opts.minTap - 0.5) then
						say(string.format("small tap target: %s %dx%d", name(b), b.w, b.h))
					end
					if b.inst.Active ~= false and b.inst.Interactable ~= false then
						table.insert(taps, s)
					end
				end
				-- out of its panel (a row pushed past the panel's edge)
				local p = (b.button or b.text) and panelOf(b)
				if p and not b.inScroll then
					local e = 3
					if
						b.x < p.x - e
						or b.y < p.y - e
						or b.x + b.w > p.x + p.w + e
						or b.y + b.h > p.y + p.h + e
					then
						say(string.format("outside its panel: %s", name(b)))
					end
				end
				if b.text and opts.minText and b.text < opts.minText - 0.01 then
					say(string.format("tiny text: %s at %.1f px", name(b), b.text))
				end
				if b.text and b.textFits == false and opts.fit then
					say(string.format("text spills: %s", name(b)))
				end
				-- across a scrolling list sideways
				if b.inScroll and opts.listWidth then
					local sb = nil
					for _, x in boxes do
						if x.inst == b.inScroll then
							sb = x
							break
						end
					end
					if
						sb
						and b.x + b.w > sb.x + sb.w + 2
						and sb.inst.ScrollingDirection == Enum.ScrollingDirection.Y
					then
						say(string.format("wider than its list: %s", name(b)))
					end
				end
			end
		end
	end
	-- words on top of words (two texts in the same place)
	if opts.textOverlap then
		local texts = {}
		for _, b in boxes do
			if b.text and wanted(b) and not b.deco then
				local s = shownPart(b)
				if s then
					s.text = b.text
					table.insert(texts, s)
				end
			end
		end
		for i = 1, #texts do
			for j = i + 1, #texts do
				local a, b = texts[i], texts[j]
				if a.screen == b.screen and not related(a.inst, b.inst) then
					local o = overlap(a, b)
					-- compare against the text's own height band, not the whole box
					local small =
						math.min(a.w * math.min(a.h, a.text * 1.2), b.w * math.min(b.h, b.text * 1.2))
					if o > 0.25 * small then
						say(string.format("texts overlap: %s / %s", name(a), name(b)))
					end
				end
			end
		end
	end
	-- a scrolling list with no room to show a row
	for _, b in boxes do
		if opts.minList and wanted(b) and b.inst:IsA("ScrollingFrame") then
			local s = shownPart(b)
			local sw, sh = if s then s.w else 0, if s then s.h else 0
			if sh < opts.minList or sw < opts.minList then
				say(string.format("list too small: %s %dx%d", name(b), sw, sh))
			end
		end
	end
	-- buttons on top of buttons (overlap = false skips it: a deep walk shows parts that never show together)
	for i = 1, if opts.overlap == false then 0 else #taps do
		for j = i + 1, #taps do
			local a, b = taps[i], taps[j]
			if not related(a.inst, b.inst) then
				local o = overlap(a, b)
				local small = math.min(a.w * a.h, b.w * b.h)
				if o > 0.08 * small then
					local pair = {
						name({ inst = a.inst, text = 1 } :: any),
						name({
							inst = b.inst,
							text = 1,
						} :: any),
					}
					table.sort(pair)
					say(string.format("buttons overlap: %s / %s", pair[1], pair[2]))
				end
			end
		end
	end
	-- the move stick's zone
	if opts.thumb then
		local t = opts.thumb
		local zone = { x = t[1] * d.w, y = t[2] * d.h, w = (t[3] - t[1]) * d.w, h = (t[4] - t[2]) * d.h }
		for _, b in taps do
			if overlap(b :: any, zone :: any) > 0 then
				say(string.format("in the move stick's zone: %s", name({ inst = b.inst, text = 1 } :: any)))
			end
		end
	end
	return out
end

-- Every hidden GuiObject under a screen (the cards, rows, sub-panels and states a module shows later),
-- shown one at a time with its hidden ancestors and checked against the screen and its safe area: off
-- screen, under the top bar or in the notch, outside its panel, too small to tap, too small to read.
-- Overlaps are not checked (parts that take turns, like a menu's buttons and its report reasons, would
-- show together). skip lists name patterns ("Line%d+") of parts placed only while they show (a stick ring
-- at the finger, a scrolling ticker); a part under a skipped one is skipped too.
function UiSim:deepIssues(screen: any, opts: { [string]: any }, skip: { string }?): { string }
	local out, seen = {}, {}
	local ignore = {}
	for _, c in screen:GetDescendants() do
		for _, pattern in skip or {} do
			if string.match(c.Name, "^" .. pattern .. "$") then
				ignore[c.Name] = true
			end
		end
	end
	local o = table.clone(opts)
	o.only = { [screen.Name] = true }
	o.overlap = false
	o.textOverlap = false
	o.ignore = ignore
	local function skipped(c: any): boolean
		local n = c
		while n and n ~= screen do
			if ignore[n.Name] then
				return true
			end
			n = n._parent
		end
		return false
	end
	local was = screen.Enabled
	screen.Enabled = true
	for _, c in screen:GetDescendants() do
		if c:IsA("GuiObject") and not c.Visible and not skipped(c) then
			local chain = {}
			local n = c
			while n and n ~= screen do
				if n:IsA("GuiObject") and not n.Visible then
					table.insert(chain, n)
					n.Visible = true
				end
				n = n._parent
			end
			for _, issue in self:issues(o) do
				if not seen[issue] then
					seen[issue] = true
					table.insert(out, c.Name .. " shown: " .. issue)
				end
			end
			for _, x in chain do
				x.Visible = false
			end
		end
	end
	screen.Enabled = was
	return out
end

-- Draw order (button reliability, 2026-11-19): screens by DisplayOrder, then down the tree each level by
-- ZIndex (Sibling) and child order; a Folder (Kit's "Ink") lets its GuiObjects draw as its parent's children
local function drawKey(b: Box): { number }
	local path = {}
	local n = b.inst
	while n and not n:IsA("ScreenGui") do
		local p = n.Parent
		if not p then
			break
		end
		if n:IsA("GuiObject") then
			local idx = table.find(p._children, n) or 0
			if p._class == "Folder" and p.Parent then
				idx = table.find(p.Parent._children, p) or 0
			end
			table.insert(path, 1, idx)
			table.insert(path, 1, n.ZIndex)
		end
		n = p
	end
	table.insert(path, 1, b.screen.DisplayOrder)
	return path
end

local function drawsOver(a: Box, b: Box): boolean
	local ka, kb = drawKey(a), drawKey(b)
	for i = 1, math.min(#ka, #kb) do
		if ka[i] ~= kb[i] then
			return ka[i] > kb[i]
		end
	end
	return #ka > #kb -- a child draws over its parent
end

-- Takes input at a point (sinks it, so nothing under it gets the tap): a GuiButton, a TextBox, a
-- ScrollingFrame or any GuiObject made Active, and Interactable
local function sinks(i: any): boolean
	if i.Interactable == false then
		return false
	end
	return i:IsA("GuiButton") or i:IsA("TextBox") or i.Active == true
end
UiSim.sinks = sinks

-- The object a tap at (x, y) lands on: the top-drawn input-taking box there (its clip respected), or nil
function UiSim:hitAt(x: number, y: number, boxes: { Box }?): Box?
	local best: Box? = nil
	for _, b in boxes or self:boxes() do
		local part = shownPart(b)
		if
			part
			and sinks(b.inst)
			and x >= part.x
			and x <= part.x + part.w
			and y >= part.y
			and y <= part.y + part.h
			and (best == nil or drawsOver(b, best))
		then
			best = b
		end
	end
	return best
end

-- Every shown button whose middle a tap cannot reach: something else that takes input draws over it there.
-- Returns "button <- blocker" lines; only = ScreenGui names to check (nil for all).
function UiSim:blockedButtons(only: { [string]: boolean }?): { string }
	local out = {}
	local boxes = self:boxes()
	for _, b in boxes do
		if b.button and not b.deco and (not only or only[b.screen.Name]) then
			local part = shownPart(b)
			if part and part.w >= 4 and part.h >= 4 then
				local hit = self:hitAt(part.x + part.w / 2, part.y + part.h / 2, boxes)
				if hit and hit.inst ~= b.inst and not hit.inst:IsDescendantOf(b.inst) then
					table.insert(out, b.inst:GetFullName() .. " <- " .. hit.inst:GetFullName())
				end
			end
		end
	end
	return out
end

-- Tap a button: fires Activated and MouseButton1Click (and a touch press and release)
function UiSim:tap(button: any)
	local input = {
		UserInputType = if self.device.touch
			then Enum.UserInputType.Touch
			else Enum.UserInputType.MouseButton1,
		UserInputState = Enum.UserInputState.Begin,
		Position = Vector3.zero,
		KeyCode = Enum.KeyCode.Unknown,
	}
	for _, ev in { "InputBegan", "Activated", "MouseButton1Click", "InputEnded" } do
		local s = button._signals[ev]
		if s then
			s:Fire(input)
		end
	end
end

return UiSim
