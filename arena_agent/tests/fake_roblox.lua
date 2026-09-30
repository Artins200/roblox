--[[
	fake_roblox.lua — минимальная заглушка Roblox API для запуска ArenaAgent.lua
	вне Studio (тестовый раннер tests/run_tests.py + lupa). Не используется в самой игре.
]]

-- warn, как в Roblox
function warn(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	print("[warn] " .. table.concat(parts, " "))
end

math.clamp = function(x, mn, mx)
	if x < mn then return mn end
	if x > mx then return mx end
	return x
end

---------------------------------------------------------------------
-- Сигналы (RBXScriptSignal-подобные)
---------------------------------------------------------------------
local function newSignal()
	local sig = { _handlers = {} }
	function sig:Connect(fn)
		table.insert(self._handlers, fn)
		return { Disconnect = function() end }
	end
	function sig:Fire(...)
		for _, fn in ipairs(self._handlers) do
			fn(...)
		end
	end
	return sig
end

---------------------------------------------------------------------
-- Типы данных
---------------------------------------------------------------------
local function simpleType(name, fields)
	local mt = {}
	mt.__index = function(v, k)
		if k == "__typeName" then return name end
		local f = rawget(v, "_f")
		if f and f[k] ~= nil then return f[k] end
		return nil
	end
	mt.__tostring = function(v) return name end
	mt.new = function(...)
		local args = { ... }
		local f = {}
		for i, fn in ipairs(fields) do
			f[fn] = tonumber(args[i]) or 0
		end
		return setmetatable({ _f = f }, mt)
	end
	return mt
end

Vector3 = simpleType("Vector3", { "X", "Y", "Z" })
Vector2 = simpleType("Vector2", { "X", "Y" })
UDim = simpleType("UDim", { "Scale", "Offset" })

local udim2mt = {}
udim2mt.__index = function(v, k)
	local f = rawget(v, "_f")
	if f and f[k] ~= nil then return f[k] end
	return nil
end
udim2mt.new = function(xs, xo, ys, yo)
	return setmetatable({ _f = { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) } }, udim2mt)
end
UDim2 = udim2mt

local color3mt = {}
color3mt.__index = function(v, k)
	if k == "R" or k == "G" or k == "B" then
		return rawget(v, "_" .. k) or 0
	end
	return nil
end
color3mt.new = function(r, g, b)
	return setmetatable({ _R = tonumber(r) or 0, _G = tonumber(g) or 0, _B = tonumber(b) or 0 }, color3mt)
end
function color3mt.fromRGB(r, g, b)
	return color3mt.new((tonumber(r) or 0) / 255, (tonumber(g) or 0) / 255, (tonumber(b) or 0) / 255)
end
function color3mt.fromHex(hex)
	local h = tostring(hex):gsub("#", "")
	local r = tonumber(h:sub(1, 2), 16) or 0
	local g = tonumber(h:sub(3, 4), 16) or 0
	local b = tonumber(h:sub(5, 6), 16) or 0
	return color3mt.new(r / 255, g / 255, b / 255)
end
Color3 = color3mt

local cframemt = {}
cframemt.__index = function(v, k)
	local f = rawget(v, "_list")
	if k == "Position" then
		return Vector3.new(f[1], f[2], f[3])
	end
	return nil
end
cframemt.new = function(...)
	return setmetatable({ _list = { ... } }, cframemt)
end
function cframemt:GetComponents()
	return unpack(rawget(self, "_list"))
end
CFrame = cframemt

local brickcolormt = {}
brickcolormt.__index = function(v, k)
	if k == "Name" then return rawget(v, "_name") end
	if k == "Number" then return rawget(v, "_num") end
	return nil
end
brickcolormt.new = function(what)
	if type(what) == "number" then
		return setmetatable({ _name = "Color" .. tostring(what), _num = what }, brickcolormt)
	end
	return setmetatable({ _name = tostring(what), _num = 0 }, brickcolormt)
end
BrickColor = brickcolormt

local numrangemt = {}
numrangemt.__index = function(v, k)
	if k == "Min" then return rawget(v, "_min") end
	if k == "Max" then return rawget(v, "_max") end
	return nil
end
numrangemt.new = function(mn, mx)
	return setmetatable({ _min = tonumber(mn) or 0, _max = tonumber(mx) or 0 }, numrangemt)
end
NumberRange = numrangemt

local rectmt = {}
rectmt.__index = function(v, k)
	if k == "Min" then return rawget(v, "_min") end
	if k == "Max" then return rawget(v, "_max") end
	return nil
end
rectmt.new = function(a, b, c, d)
	return setmetatable({
		_min = Vector2.new(a, b),
		_max = Vector2.new(c, d),
	}, rectmt)
end
Rect = rectmt

---------------------------------------------------------------------
-- Enum (автосоздание, как разрешено Luau-тесту)
---------------------------------------------------------------------
Enum = setmetatable({}, {
	__index = function(_, enumName)
		local et
		local itemMT = {
			__type = "EnumItem",
			__tostring = function(item)
				return "Enum." .. enumName .. "." .. rawget(item, "_itemName")
			end,
		}
		et = setmetatable({}, {
			__index = function(_, itemName)
				if type(itemName) ~= "string" then return nil end
				return setmetatable({ _itemName = itemName, EnumType = et }, itemMT)
			end,
		})
		-- кешируем
		rawset(Enum, enumName, et)
		return et
	end,
})

---------------------------------------------------------------------
-- Instance
---------------------------------------------------------------------
local FakeInstance = {}
local EVENT_NAMES = {
	FocusLost = true, FocusGained = true, MouseButton1Click = true,
	Activated = true, MouseEnter = true, MouseLeave = true,
}

FakeInstance.__index = function(self, key)
	if key == "ClassName" then return rawget(self, "__className") end
	if key == "Parent" then return rawget(self, "__parent") end
	if key == "AbsoluteCanvasSize" then return Vector3.new(0, 0, 0) end
	if EVENT_NAMES[key] then
		local sigs = rawget(self, "__signals")
		local s = sigs[key]
		if not s then
			s = newSignal()
			sigs[key] = s
		end
		return s
	end
	local m = FakeInstance[key]
	if m ~= nil then return m end
	local props = rawget(self, "__props")
	if props and props[key] ~= nil then return props[key] end
	-- как в Roblox: dot-доступ к детям (workspace.Part)
	local kids = rawget(self, "__children")
	if kids then
		for _, c in ipairs(kids) do
			if c.Name == key then return c end
		end
	end
	return nil
end
FakeInstance.__newindex = function(self, key, value)
	if key == "Parent" then
		local old = rawget(self, "__parent")
		local oldKids = old and type(old) == "table" and rawget(old, "__children") or nil
		if oldKids then
			for idx = #oldKids, 1, -1 do
				if oldKids[idx] == self then table.remove(oldKids, idx) end
			end
		end
		rawset(self, "__parent", value)
		local kids = type(value) == "table" and rawget(value, "__children") or nil
		if kids then
			table.insert(kids, self)
		end
		return
	end
	rawget(self, "__props")[key] = value
end

function FakeInstance.new(className)
	local self = setmetatable({}, FakeInstance)
	rawset(self, "__className", className or "Instance")
	rawset(self, "__children", {})
	rawset(self, "__props", {})
	rawset(self, "__attributes", {})
	rawset(self, "__signals", {})
	self.Name = className or "Instance"
	-- дефолты, как у настоящего BasePart
	if className == "Part" or className == "WedgePart" or className == "TrussPart" then
		self.Size = Vector3.new(4, 1, 2)
		self.Position = Vector3.new(0, 0, 0)
		self.CFrame = CFrame.new(0, 0, 0)
		self.Anchored = false
		self.CanCollide = true
		self.Material = Enum.Material.Plastic
		self.Color = Color3.fromRGB(163, 162, 165)
	end
	return self
end

function FakeInstance:FindFirstChild(name)
	for _, c in ipairs(rawget(self, "__children")) do
		if c.Name == name then return c end
	end
	return nil
end

function FakeInstance:FindFirstChildWhichIsA(cls)
	for _, c in ipairs(rawget(self, "__children")) do
		if c:IsA(cls) then return c end
	end
	return nil
end

function FakeInstance:GetChildren()
	-- как в Roblox: возвращает ОДНО значение — таблицу-массив
	local out = {}
	for _, c in ipairs(rawget(self, "__children")) do
		out[#out + 1] = c
	end
	return out
end

function FakeInstance:GetDescendants()
	local out = {}
	local function walk(inst)
		for _, c in ipairs(rawget(inst, "__children")) do
			out[#out + 1] = c
			walk(c)
		end
	end
	walk(self)
	return out
end

function FakeInstance:GetFullName()
	local parts = {}
	local cur = self
	while cur and rawget(cur, "__parent") do
		table.insert(parts, 1, cur.Name)
		cur = rawget(cur, "__parent")
	end
	if #parts == 0 then return self.Name end
	return table.concat(parts, ".")
end

function FakeInstance:IsDescendantOf(other)
	local cur = rawget(self, "__parent")
	while cur do
		if cur == other then return true end
		cur = rawget(cur, "__parent")
	end
	return false
end

function FakeInstance:IsA(cls)
	if cls == "Instance" then return true end
	return self.ClassName == cls
end

function FakeInstance:Destroy()
	self.Parent = nil
	rawset(self, "__destroyed", true)
end

function FakeInstance:SetAttribute(k, v)
	if v ~= nil and type(v) ~= "string" and type(v) ~= "number" and type(v) ~= "boolean" and type(v) ~= "table" then
		error("атрибут должен быть string/number/boolean/table, а не " .. type(v))
	end
	rawget(self, "__attributes")[k] = v
end

function FakeInstance:GetAttribute(k)
	return rawget(self, "__attributes")[k]
end

function FakeInstance:GetAttributeChangedSignal()
	return newSignal()
end

Instance = {
	new = function(cls)
		if type(cls) ~= "string" then
			error("Instance.new: ожидается имя класса")
		end
		return FakeInstance.new(cls)
	end,
}

---------------------------------------------------------------------
-- Сервисы
---------------------------------------------------------------------
Selection = {
	_list = {},
	Get = function(self) return self._list end,
	Set = function(self, arr)
		self._list = {}
		for _, v in ipairs(arr) do self._list[#self._list + 1] = v end
	end,
	SelectionChanged = newSignal(),
}

ChangeHistoryService = {
	waypoints = {},
	SetWaypoint = function(self, name)
		self.waypoints[#self.waypoints + 1] = name
	end,
}

UserInputService = {
	IsKeyDown = function() return false end,
}

-- HttpService с JSON через Python-мосты (__py_json_encode/__py_json_decode)
HttpService = {
	_responder = nil,
	_requests = {},
}
function HttpService:JSONEncode(t)
	return __py_json_encode(t)
end
function HttpService:JSONDecode(s)
	return __py_json_decode(s)
end
function HttpService:RequestAsync(opts)
	self._requests[#self._requests + 1] = opts
	if self._responder then
		return self._responder(opts)
	end
	return { Success = false, StatusCode = 0, Body = "no responder configured" }
end

---------------------------------------------------------------------
-- game
---------------------------------------------------------------------
local services = {}

local function makeService(name)
	local s = FakeInstance.new(name)
	services[name] = s
	return s
end

Workspace = makeService("Workspace")
makeService("ReplicatedStorage")
makeService("ServerScriptService")
makeService("ServerStorage")
makeService("StarterGui")
makeService("StarterPack")
local starterPlayer = makeService("StarterPlayer")
starterPlayer.StarterPlayerScripts = FakeInstance.new("StarterPlayerScripts")
starterPlayer.StarterPlayerScripts.Name = "StarterPlayerScripts"
starterPlayer.StarterPlayerScripts.Parent = starterPlayer
makeService("Lighting")
makeService("SoundService")
makeService("Teams")
makeService("TextChatService")

game = setmetatable({}, {
	__index = function(_, name) return services[name] end,
})
function game:FindFirstChild(name) return services[name] end
function game:GetService(name)
	if name == "HttpService" then return HttpService end
	if name == "ChangeHistoryService" then return ChangeHistoryService end
	if name == "Selection" then return Selection end
	if name == "UserInputService" then return UserInputService end
	return services[name]
end

---------------------------------------------------------------------
-- plugin / UI
---------------------------------------------------------------------
DockWidgetPluginGuiInfo = {
	new = function(...) return { ... } end,
}

ColorSequenceKeypoint = {
	new = function(time, value) return { Time = time, Value = value } end,
}
ColorSequence = {
	new = function(...) return { keypoints = { ... } } end,
}


plugin = {
	_settings = {},
	Unloading = newSignal(),
}
function plugin:SetSetting(k, v)
	if v == nil then
		self._settings[k] = nil
		return
	end
	self._settings[k] = v
end
function plugin:GetSetting(k) return self._settings[k] end

function plugin:CreateToolbar(name)
	local tb = { _name = name }
	function tb:CreateButton(text, tooltip, icon)
		local btn = {
			Text = text,
			Click = newSignal(),
			Active = false,
		}
		function btn:SetActive(a) self.Active = a end
		return btn
	end
	return tb
end

function plugin:CreateDockWidgetPluginGui(id, info)
	local w = {
		Enabled = false,
		Title = "",
		Name = id,
		EnabledChanged = newSignal(),
	}
	function w:GetPropertyChangedSignal(prop)
		return newSignal()
	end
	w.BindingActivated = newSignal()
	return w
end

---------------------------------------------------------------------
-- task
---------------------------------------------------------------------
task = {
	spawn = function(fn, ...)
		local co = coroutine.create(fn)
		local args = { ... }
		local ok, e = coroutine.resume(co, unpack(args))
		if not ok then
			error("task.spawn упал: " .. tostring(e))
		end
	end,
	wait = function() end,
	delay = function() end,
}

---------------------------------------------------------------------
-- typeof (как в Luau)
---------------------------------------------------------------------
Vector3.__type = "Vector3"
Vector2.__type = "Vector2"
UDim.__type = "UDim"
UDim2.__type = "UDim2"
Color3.__type = "Color3"
CFrame.__type = "CFrame"
BrickColor.__type = "BrickColor"
NumberRange.__type = "NumberRange"
Rect.__type = "Rect"
FakeInstance.__type = "Instance"

typeof = function(v)
	if type(v) == "table" then
		local mt = getmetatable(v)
		if mt and rawget(mt, "__type") then
			return mt.__type
		end
		return "table"
	end
	return type(v)
end
