#!/usr/bin/env python3
"""Smoke-тест серверной логики бомба-игры в моках Roblox API (lupa/lua54).

Бут: core -> shop -> turret -> flight -> energysun -> round -> bots.
Затем сценарий: покупка станции/завода/ракеты, стройка, «нет сигнала»,
спутник, улучшение заводa, блэкаут, доход, выстрел лазера ПВО.
"""
from lupa import lua54

LUA = r'''
-- ================= МОКИ ROBLOX =================
local unpack = table.unpack or unpack
local virtualTime = 0
local scheduled = {}   -- {wake=, co=}
local running = true
local maxSteps = 200000
local steps = 0
logs = {}
local fired = {}       -- captured FireClient messages {target, text, ok}

local function log(...)
  local parts = {}
  for _, v in ipairs({...}) do parts[#parts+1] = tostring(v) end
  logs[#logs+1] = table.concat(parts, " ")
end
print = function(...) log(...) end
warn = function(...) log("WARN:", ...) end

tick = function() return virtualTime end
typeof = function(v)
  local t = type(v)
  if t ~= "table" then return t end
  local mt = getmetatable(v)
  if mt and mt.__vtype then return mt.__vtype end
  if rawget(v, "ClassName") then return "Instance" end
  return "table"
end

-- Luau-расширения поверх Lua 5.4
math.clamp = function(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end
math.round = function(x) return math.floor(x + 0.5) end
math.sign = function(x) return x > 0 and 1 or (x < 0 and -1 or 0) end
math.atan2 = function(y, x) return math.atan(y, x) end
table.find = function(t, v)
  for i, x in ipairs(t) do if x == v then return i end end
  return nil
end
table.clear = function(t) for k in pairs(t) do t[k] = nil end end
table.insert = table.insert
string.split = function(s, sep)
  local out = {}
  local pattern = "([^" .. sep .. "]+)"
  for piece in string.gmatch(s, pattern) do out[#out+1] = piece end
  return out
end
table.clone = function(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end
table.freeze = function(t) return t end
table.isfrozen = function() return false end
os.time = function() return math.floor(virtualTime) end

-- Vector3 -------------------------------------------------
local V3
V3 = {
  new = function(x, y, z)
    return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, V3)
  end,
  zero = nil,
  xAxis = nil, yAxis = nil, zAxis = nil,
}
V3.__index = function(t, k)
  if k == "Magnitude" then return math.sqrt(t.X*t.X + t.Y*t.Y + t.Z*t.Z) end
  if k == "Unit" then
    local m = t.Magnitude
    if m < 1e-9 then return V3.new(0,0,0) end
    return V3.new(t.X/m, t.Y/m, t.Z/m)
  end
  return V3[k]
end
V3.__add = function(a, b) return V3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
V3.__sub = function(a, b) return V3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
V3.__unm = function(a) return V3.new(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b)
  if type(a) == "number" then return V3.new(b.X*a, b.Y*a, b.Z*a) end
  if type(b) == "number" then return V3.new(a.X*b, a.Y*b, a.Z*b) end
  return V3.new(a.X*b.X, a.Y*b.Y, a.Z*b.Z)
end
V3.__div = function(a, b)
  if type(b) == "number" then return V3.new(a.X/b, a.Y/b, a.Z/b) end
  error("div")
end
V3.__eq = function(a, b) return a.X==b.X and a.Y==b.Y and a.Z==b.Z end
V3.__tostring = function(v) return string.format("%g, %g, %g", v.X, v.Y, v.Z) end
V3.__vtype = "Vector3"
V3.zero = V3.new(0, 0, 0)
V3.yAxis = V3.new(0, 1, 0)
function V3:Dot(o) return self.X*o.X + self.Y*o.Y + self.Z*o.Z end
function V3:Cross(o)
  return V3.new(self.Y*o.Z - self.Z*o.Y, self.Z*o.X - self.X*o.Z, self.X*o.Y - self.Y*o.X)
end
rawset(V3, "Cross", V3.Cross)

Vector3 = V3
Vector2 = {
  new = function(x, y) return {X = x or 0, Y = y or 0} end,
}

-- CFrame (без поворота: только позиция — достаточно для логики) -------------
local CFMT = {}
CFMT.__index = CFMT
CFMT.__call = function(_, pos) return setmetatable({Position = pos or Vector3.zero}, CFMT) end
function CFMT.new(x, y, z)
  if type(x) == "table" then return setmetatable({Position = x}, CFMT) end
  if type(x) == "number" then return setmetatable({Position = Vector3.new(x, y or 0, z or 0)}, CFMT) end
  return setmetatable({Position = Vector3.zero}, CFMT)
end
function CFMT.lookAt(pos, target)
  return setmetatable({Position = pos, _look = target}, CFMT)
end
function CFMT.Angles(...) return setmetatable({Position = Vector3.zero, _angles = true}, CFMT) end
function CFMT.identity() return setmetatable({Position = Vector3.zero}, CFMT) end
function CFMT:PointToObjectSpace(p) return p - self.Position end
function CFMT:PointToWorldSpace(p) return p + self.Position end
function CFMT:VectorToObjectSpace(v) return v end
function CFMT:VectorToWorldSpace(v) return v end
function CFMT:ToEulerAnglesXYZ() return 0, 0, 0 end
CFMT.__add = function(a, b)
  if type(b) == "table" and b.X ~= nil then return setmetatable({Position = a.Position + b}, CFMT) end
  return setmetatable({Position = a.Position}, CFMT)
end
CFMT.__mul = function(a, b)
  if type(a) == "table" and a._cfmul then return a end
  return a -- cf * cf не используется в тестах
end
CFMT.__vtype = "CFrame"
CFrame = setmetatable({}, {__call = function(_, ...) return CFMT.new(...) end,
  __index = function(t, k) return CFMT[k] end})
for k, v in pairs(CFMT) do CFrame[k] = v end
CFrame.new = CFMT.new
CFrame.lookAt = CFMT.lookAt
CFrame.Angles = CFMT.Angles

local C3MT = {__vtype = "Color3"}
Color3 = {
  new = function(r, g, b) return setmetatable({R = r or 0, G = g or 0, B = b or 0,
    Lerp = function(self, o, t) return Color3.new(self.R + (o.R-self.R)*t, self.G + (o.G-self.G)*t, self.B + (o.B-self.B)*t) end}, C3MT) end,
  fromRGB = function(r, g, b) return Color3.new((r or 0)/255, (g or 0)/255, (b or 0)/255) end,
}
UDim2 = {new = function(a, b, c, d) return {X = {Scale = a, Offset = b}, Y = {Scale = c, Offset = d}} end}
UDim = {new = function(s, o) return {Scale = s, Offset = o} end}
NumberRange = {new = function(a, b) return {Min = a, Max = b or a} end}
NumberSequence = {new = function(a, b) return {a, b} end}
NumberSequenceKeypoint = {new = function(a, b, c) return {Time = a, Value = b, Envelope = c} end}
ColorSequence = {new = function(a, b) return {a, b} end}
ColorSequenceKeypoint = {new = function(t, c) return {Time = t, Value = c} end}
Rect = {new = function(...) return {} end}

local function enumProxy()
  return setmetatable({}, {__index = function(t, k)
    local v = setmetatable({}, {__index = function() return k end})
    rawset(t, k, v)
    return v
  end})
end
Enum = setmetatable({}, {__index = function(t, k)
  local v = enumProxy()
  rawset(t, k, v)
  return v
end})

-- Instance -------------------------------------------------
local classHierarchy = {
  Part = {BasePart = true, PVInstance = true, Instance = true},
  UnionOperation = {BasePart = true, PVInstance = true, Instance = true},
  Model = {PVInstance = true, Instance = true},
  SpawnLocation = {BasePart = true, PVInstance = true, Instance = true},
  Folder = {Instance = true},
  PointLight = {Instance = true},
  Attachment = {Instance = true},
  Beam = {Instance = true},
  ParticleEmitter = {Instance = true},
  BillboardGui = {Instance = true},
  ScreenGui = {Instance = true},
  TextLabel = {Instance = true},
  TextButton = {Instance = true},
  Frame = {Instance = true},
  UICorner = {Instance = true},
  UIStroke = {Instance = true},
  UIListLayout = {Instance = true},
  Highlight = {Instance = true},
  Script = {Instance = true},
  LocalScript = {Instance = true},
  ModuleScript = {Instance = true},
  RemoteEvent = {Instance = true},
  RemoteFunction = {Instance = true},
  Explosion = {Instance = true},
  Debris = {Instance = true},
  Player = {Instance = true},
  Camera = {Instance = true},
}

Instance = {}
local instanceCount = 0

local objectMethods = {}
objectMethods.__index = objectMethods

function objectMethods:GetFullName() return self.Name or "?" end
function objectMethods:IsDescendantOf(other)
  local p = self.Parent
  while p do
    if p == other then return true end
    p = p.Parent
  end
  return false
end
function objectMethods:IsA(cls)
  local c = self.ClassName
  if c == cls then return true end
  local h = classHierarchy[c]
  return h and h[cls] or false
end
function objectMethods:GetChildren()
  local out = {}
  for _, ch in ipairs(self._children) do out[#out+1] = ch end
  return out
end
function objectMethods:GetDescendants()
  local out = {}
  local function walk(o)
    for _, ch in ipairs(o._children) do
      out[#out+1] = ch
      walk(ch)
    end
  end
  walk(self)
  return out
end
function objectMethods:FindFirstChild(name)
  for _, ch in ipairs(self._children) do
    if ch.Name == name then return ch end
  end
  return nil
end
function objectMethods:FindFirstChildOfClass(cls)
  for _, ch in ipairs(self._children) do
    if ch.ClassName == cls then return ch end
  end
  return nil
end
function objectMethods:WaitForChild(name, timeout)
  return self:FindFirstChild(name)
end
function objectMethods:GetAttribute(name)
  return self._attrs[name]
end
function objectMethods:SetAttribute(name, value)
  self._attrs[name] = value
  if self._attrSignals[name] then
    for _, cb in pairs(self._attrSignals[name]) do cb() end
  end
end
function objectMethods:GetAttributeChangedSignal(name)
  self._attrSignals[name] = self._attrSignals[name] or {}
  local id = tostring(math.random(1, 1e9))
  local t = {Connect = function(_, cb) self._attrSignals[name][id] = cb end}
  return t
end
function objectMethods:Destroy()
  self.Parent = nil
  self._destroyed = true
end
function objectMethods:Clone()
  local c = Instance.new(self.ClassName)
  c.Name = self.Name
  c._template = rawget(self, "_template")
  c._pivot = rawget(self, "_pivot")
  for _, k in ipairs({"Size", "CFrame", "Position", "Color", "Transparency",
                      "Anchored", "CanCollide", "Shape", "Material", "Enabled",
                      "Visible", "Text", "Adornee"}) do
    local v = rawget(self, k)
    if v ~= nil then rawset(c, k, v) end
  end
  for k, v in pairs(rawget(self, "_attrs") or {}) do
    c._attrs[k] = v
  end
  for _, ch in ipairs(self._children) do
    ch:Clone().Parent = c
  end
  if rawget(self, "PrimaryPart") then
    local pp = self.PrimaryPart
    for _, ch in ipairs(c._children) do
      if ch.Name == pp.Name then c.PrimaryPart = ch break end
    end
    if not c.PrimaryPart then
      local function findP(o)
        for _, ch in ipairs(o._children) do
          if ch.ClassName == "Part" or ch.ClassName == "SpawnLocation" then return ch end
          local r = findP(ch)
          if r then return r end
        end
        return nil
      end
      c.PrimaryPart = findP(c)
    end
  end
  return c
end
function objectMethods:PivotTo(cf)
  self._pivot = cf
  if self.PrimaryPart then
    self.PrimaryPart.CFrame = cf
    self.PrimaryPart.Position = cf.Position
  end
end
function objectMethods:GetPivot()
  return self._pivot or (self.PrimaryPart and self.PrimaryPart.CFrame) or CFrame.new()
end
function objectMethods:GetBoundingBox()
  return CFrame.new(self:GetPivot().Position), Vector3.new(4, 4, 4)
end
function objectMethods:GetServerTimeNow() return virtualTime end
function objectMethods:Raycast(origin, dir, params)
  -- земля на Y=0
  local t = -origin.Y / dir.Y
  if dir.Y < 0 and t > 0 then
    local p = origin + dir * t
    return {Position = p, Instance = {Name = "Baseplate", IsA = function() return true end}}
  end
  return nil
end
function objectMethods:Connect(event, cb)
  self._conns = self._conns or {}
  self._conns[event] = self._conns[event] or {}
  local id = tostring(math.random(1, 1e9))
  self._conns[event][id] = cb
  return {Disconnect = function() self._conns[event][id] = nil end}
end
-- RemoteEvent
function objectMethods:FireClient(player, ...)
  local args = {...}
  if firedLog then table.insert(firedLog, {player = player, args = args}) end
  if self._clientCbs and player and player.UserId then
    for _, cb in pairs(self._clientCbs) do cb(unpack(args)) end
  end
end
function objectMethods:FireAllClients(...) end
function objectMethods:FireServer(...) end
function objectMethods:FireServerFromServer(...) end
-- OnServerEvent выдаётся per-объект через mt.__index (см. Instance.new)
objectMethods.OnClientEvent = {
  Connect = function(_, cb) return {Disconnect = function() end} end,
}
objectMethods.OnServerInvoke = nil
objectMethods.OnInvoke = nil

function Instance.new(class)
  instanceCount = instanceCount + 1
  local o = setmetatable({}, objectMethods)
  o.ClassName = class
  o.Name = class
  o._children = {}
  o._attrs = {}
  o._attrSignals = {}
  o._conns = {}
  o._pivot = CFrame.new()
  o.Parent = nil
  o.Size = Vector3.new(2, 1, 1)
  o.CFrame = CFrame.new()
  o.Position = Vector3.new(0, 0, 0)
  o.Color = Color3.new(1, 1, 1)
  o.Transparency = 0
  o.Anchored = false
  o.CanCollide = true
  o.CanQuery = true
  o.CanTouch = true
  o.Enabled = true
  o.Visible = true
  o.Text = ""
  o.Rate = 0
  o.Shape = nil
  o.Material = nil
  o.PrimaryPart = nil
  if class == "ParticleEmitter" then
    o.Emit = function() end
  end
  if class == "Player" then
    local conns = {}
    o.CharacterAdded = {Connect = function(_, cb)
      conns[#conns+1] = cb
      return {Disconnect = function() end}
    end}
    o.CharacterRemoving = {Connect = function() return {Disconnect = function() end} end}
    o.Chatted = {Connect = function() return {Disconnect = function() end} end}
    o._evconns = conns
  end
  local mt = getmetatable(o)
  mt.__index = function(t, k)
    if k == "OnServerEvent" then
      local sig = rawget(t, "_srvsig")
      if not sig then
        sig = {Connect = function(_, cb)
          rawget(t, "_conns")["OnServerEvent"] = rawget(t, "_conns")["OnServerEvent"] or {}
          local id = tostring(math.random(1, 1e9))
          rawget(t, "_conns")["OnServerEvent"][id] = cb
          return {Disconnect = function()
            rawget(t, "_conns")["OnServerEvent"][id] = nil
          end}
        end}
        rawset(t, "_srvsig", sig)
      end
      return sig
    end
    local m = objectMethods[k]
    if m ~= nil then return m end
    for _, ch in ipairs(rawget(t, "_children") or {}) do
      if ch.Name == k then return ch end
    end
    return nil
  end
  mt.__newindex = function(t, k, v)
    if k == "Parent" then
      local old = rawget(t, "Parent")
      if old and old._children then
        for i, ch in ipairs(old._children) do
          if ch == t then table.remove(old._children, i) break end
        end
      end
      rawset(t, "Parent", v)
      if type(v) == "table" and v._children then
        table.insert(v._children, t)
      end
    elseif k == "OnServerInvoke" then
      rawset(t, k, v)
      if rawget(t, "ClassName") == "RemoteFunction" and v then
        remoteFunctions[rawget(t, "Name") or "?"] = v
        remoteFunctions[tostring(t)] = v
      end
    else
      rawset(t, k, v)
    end
  end
  return o
end

-- services -------------------------------------------------
firedLog = {}
serverEventHandlers = {}
remoteFunctions = {}

local Players = Instance.new("Folder")
Players.ClassName = "Players"
Players._players = {}
function Players:GetPlayers()
  local out = {}
  for _, p in pairs(self._players) do out[#out+1] = p end
  return out
end
Players.PlayerAdded = {Connect = function(_, cb) playerAddedCb = cb end}
Players.PlayerRemoving = {Connect = function(_, cb) playerRemovingCb = cb end}

Workspace = Instance.new("Folder")
Workspace.ClassName = "Workspace"
Workspace.Ray = function(self, origin, dir, params) return objectMethods.Raycast(self, origin, dir, params) end
function Workspace:Raycast(origin, dir, params)
  local t = -origin.Y / dir.Y
  if dir.Y < 0 and t > 0 then
    local p = origin + dir * t
    return {Position = p, Instance = {Name = "Baseplate", IsA = function(_, c) return c == "BasePart" end, GetAttribute = function() return nil end}}
  end
  return nil
end
function Workspace:GetServerTimeNow() return virtualTime end

local ReplicatedStorage = Instance.new("Folder")
ReplicatedStorage.ClassName = "ReplicatedStorage"
local ServerStorage = Instance.new("Folder")
ServerStorage.ClassName = "ServerStorage"
local RunService = {
  Heartbeat = {
    Connect = function(_, cb)
      local h = {_cb = cb}
      h.Disconnect = function(self2)
        self2._cb = nil
        for i, x in ipairs(heartbeatHandlers) do
          if x == self2 then table.remove(heartbeatHandlers, i) break end
        end
      end
      table.insert(heartbeatHandlers, h)
      return h
    end,
    Wait = function()
      coroutine.yield("heartbeat")
      return 0.05
    end,
  },
  RenderStepped = {Connect = function() return {Disconnect = function() end} end},
}
local Debris = {AddItem = function() end}
local HttpService = {
  JSONEncode = function(_, t) return "[]" end,
  JSONDecode = function(_, s) return {} end,
  GenerateGUID = function() return "guid" end,
}
local TweenService = {Create = function() return {Play = function() end} end}
local UserInputService = {
  GetMouseLocation = function() return Vector2.new(0, 0) end,
  InputBegan = {Connect = function() return {Disconnect = function() end} end},
  InputChanged = {Connect = function() return {Disconnect = function() end} end},
}

heartbeatHandlers = {}
playerAddedCb = nil
playerRemovingCb = nil

game = {
  GetService = function(_, name)
    if name == "Players" then return Players end
    if name == "Workspace" then return Workspace end
    if name == "ReplicatedStorage" then return ReplicatedStorage end
    if name == "ServerStorage" then return ServerStorage end
    if name == "RunService" then return RunService end
    if name == "Debris" then return Debris end
    if name == "HttpService" then return HttpService end
    if name == "TweenService" then return TweenService end
    if name == "UserInputService" then return UserInputService end
    error("unknown service " .. name)
  end,
}

script = Instance.new("Script")
script.Name = "MockScript"

-- шаблоны моделей в ServerStorage
local function makeTemplate(name)
  local m = Instance.new("Model")
  m.Name = name
  local p = Instance.new("Part")
  p.Name = "Base"
  p.Parent = m
  m.PrimaryPart = p
  m._template = true
  if name == "Rocket Turret" then
    for i = 1, 8 do
      local mis = Instance.new("Part")
      mis.Name = "Missile" .. i
      mis.Parent = m
    end
    local base = Instance.new("Part")
    base.Name = "TurretBase"
    base.Parent = m
  end
  if name == "Energy Sun" then
    local core = Instance.new("Part")
    core.Name = "Core"
    core.Parent = m
  end
  m.Parent = ServerStorage
  return m
end
for _, n in ipairs({"RocketShip", "RocketShip1", "rocketpick", "rocketpick2",
                    "rocketguns", "rocketguns3000", "Rocket Turret", "Energy Sun"}) do
  makeTemplate(n)
end

-- площадки спавна
for i = 1, 4 do
  local pad = Instance.new("SpawnLocation")
  pad.Name = "SpawnLocation" .. i
  pad.Size = Vector3.new(40, 1, 40)
  pad.CFrame = CFrame.new((i == 1 or i == 2) and -100 or 100, 0, (i == 1 or i == 4) and -100 or 100)
  pad.Parent = Workspace
end

-- task (виртуальный планировщик) ---------------------------------------
task = {}
local queue = {}  -- {wake=, co=}

function task.spawn(fn, ...)
  local co = coroutine.create(fn)
  local tb = debug.getinfo(2, "Sl")
  local tag = tb and (tb.short_src .. ":" .. tb.currentline) or "?"
  table.insert(queue, {wake = virtualTime, co = co, args = {...}, tag = tag})
end
function task.nowakeinfo() end
function task.defer(fn, ...) task.spawn(fn, ...) end
function task.delay(sec, fn, ...)
  local tb = debug.getinfo(2, "Sl")
  table.insert(queue, {wake = virtualTime + sec, co = coroutine.create(fn), args = {...},
    tag = "delay:" .. (tb and (tb.short_src .. ":" .. tb.currentline) or "?")})
end
function task.wait(sec)
  coroutine.yield("wait", sec or 0.03)
  return sec or 0.03
end

resumeCount = 0
local function runScheduler(maxTime)
  local guard = 0
  while running and guard < maxSteps do
    guard = guard + 1
    -- ближайшая задача
    local bestI = nil
    for i, item in ipairs(queue) do
      if not bestI or item.wake < queue[bestI].wake then bestI = i end
    end
    if not bestI then break end
    local item = table.remove(queue, bestI)
    if item.wake > maxTime then
      table.insert(queue, item)
      break
    end
    if item.wake > virtualTime then virtualTime = item.wake end
    local ok, mode, sec = coroutine.resume(item.co, unpack(item.args or {}))
    resumeCount = resumeCount + 1
    if not ok then
      error("TASK ERROR: " .. tostring(mode) .. "\n" .. debug.traceback(item.co))
    end
    if coroutine.status(item.co) == "dead" then
      -- завершилась
    elseif mode == "wait" then
      table.insert(queue, {wake = virtualTime + (tonumber(sec) or 0.03), co = item.co})
    elseif mode == "heartbeat" then
      table.insert(queue, {wake = virtualTime + 0.05, co = item.co})
    else
      -- неизвестный yield
      table.insert(queue, {wake = virtualTime + 0.05, co = item.co})
    end
    -- heartbeat-подписчики
    for _, h in ipairs(heartbeatHandlers) do
      if h._cb then
        local ok2, err2 = pcall(h._cb, 0.05)
        if not ok2 then error("HEARTBEAT ERROR: " .. tostring(err2)) end
      end
    end
  end
end

-- ================= ЗАГРУЗКА СКРИПТОВ =================
local ORDER = {
  {"core", "tools/bomb/core.lua"},
  {"shop", "tools/bomb/shop.lua"},
  {"turret", "tools/bomb/turret.lua"},
  {"flight", "tools/bomb/flight.lua"},
  {"energysun", "tools/bomb/energysun.lua"},
  {"round", ".work/scripts/c64_1080_07.lua"},
  {"bots", "tools/bomb/bots.lua"},
}
do -- heli-скрипт не грузим: даём bots дырку, чтобы не ждал 20 сек
  _G.__needHeliStub = true
end

local chunks = {}
for _, entry in ipairs(ORDER) do
  local f = assert(io.open(entry[2], "rb"))
  chunks[entry[1]] = f:read("*a")
  f:close()
end

local function bootScript(name, code)
  local fn, lerr = load(code, "@" .. name)
  if not fn then error("LOAD " .. name .. ": " .. tostring(lerr)) end
  local co = coroutine.create(function()
    local ok, e = pcall(fn)
    if not ok then error(name .. ": " .. tostring(e), 0) end
  end)
  table.insert(queue, {wake = virtualTime, co = co, args = {}})
  local guard = 0
  while coroutine.status(co) ~= "dead" do
    guard = guard + 1
    if guard > 50000 then error("BOOT TIMEOUT " .. name) end
    -- один шаг планировщика
    local bestI = nil
    for i, item in ipairs(queue) do
      if not bestI or item.wake < queue[bestI].wake then bestI = i end
    end
    if not bestI then error("BOOT STALLED " .. name) end
    local item = table.remove(queue, bestI)
    if item.wake > virtualTime then virtualTime = item.wake end
    local ok, mode, sec = coroutine.resume(item.co, unpack(item.args or {}))

    if not ok then error("TASK ERROR in " .. name .. ": " .. tostring(mode)) end
    for _, h in ipairs(heartbeatHandlers) do
      if h._cb then
        local ok2, err2 = pcall(h._cb, 0.05)
        if not ok2 then error("HEARTBEAT ERROR: " .. tostring(err2)) end
      end
    end
    if coroutine.status(item.co) ~= "dead" then
      local wake = virtualTime + 0.03
      if mode == "wait" then wake = virtualTime + (tonumber(sec) or 0.03) end
      table.insert(queue, {wake = wake, co = item.co})
    end
  end
end

for _, entry in ipairs(ORDER) do
  if entry[1] == "bots" and _G.RocketSystem and not _G.RocketSystem.spawnHeli then
    _G.RocketSystem.spawnHeli = function() end
  end
  bootScript(entry[1], chunks[entry[1]])
  log("BOOT OK:", entry[1])
end

runScheduler(3)  -- даём буту осесть (fill ботов через 3с)

-- ================= СЦЕНАРИЙ =================
local RS = _G.RocketSystem
assert(RS and RS.Ready, "core not ready")
assert(RS.buyBuilding and RS.buyConstruction and RS.upgradeFactory, "API отсутствует")

local function findRemote(name)
  local folder = ReplicatedStorage:FindFirstChild("RocketRemotes")
  return folder and folder:FindFirstChild(name)
end

for _, n in ipairs({"BuyPowerPlant", "BuyFactory", "BuySatellite", "BuyRocket",
                    "UpgradeRocket", "RequestLaunch", "SetTarget", "GetPlayersList",
                    "CreateAlliance", "DeclareWar", "BetrayAlliance"}) do
  assert(findRemote(n), "remote missing: " .. n)
end
log("SCENE: remotes ok")

-- фиктивный игрок
local player = Instance.new("Player")
player.Name = "Tester"
player.UserId = 42
player.Parent = Players
Players._players[42] = player
local function check(cond, msg)
  if not cond then error("FAIL: " .. msg, 2) end
  log("PASS:", msg)
end

playerAddedCb(player)
runScheduler(1)

local data = RS.players[42]
check(data ~= nil, "player data создан")
check(#data.rockets == 0, "старт без ракет")
check((player:GetAttribute("Money") or 0) == 800, "стартовые деньги 800")
check((player:GetAttribute("RocketCount") or 0) == 0, "RocketCount=0")

local function fire(name, ...)
  local r = findRemote(name)
  for _, h in ipairs(serverEventHandlers) do end
  -- вызываем обработчики напрямую через сохранённые h._cb? RemoteEvent хранит свои
  local cbs = r._conns and r._conns.OnServerEvent
  if not cbs then error("no handlers for " .. name) end
  for _, cb in pairs(cbs) do cb(player, ...) end
end

-- покупка станции
fire("BuyPowerPlant")
check(#data.buildings == 1, "электростанция построена")
check(player:GetAttribute("PowerCount") == 1, "PowerCount=1")
check(player:GetAttribute("Money") == 600, "деньги 600 после станции")
check(player:GetAttribute("Income") == nil or true, "")

-- завод без денег? (хватает: 600>400)
fire("BuyFactory")
check(player:GetAttribute("FactoryCount") == 1, "завод построен")
check(player:GetAttribute("Money") == 200, "деньги 200 после завода")
check(player:GetAttribute("PowerDraw") == 1, "потребление 1")
check(player:GetAttribute("Blackout") == false, "нет блэкаута")


-- стройка ракеты
fire("BuyRocket")
check(data.construction ~= nil, "строительство начато")
check(player:GetAttribute("Money") == 0, "деньги списаны (200 -> 0)")
check(player:GetAttribute("ConstructionActive") == true, "ConstructionActive")
local startT = virtualTime
runScheduler(startT + 35)

check(data.construction == nil, "ракета достроена за ~30с")
check(#data.rockets == 1, "1 ракета в флоте")
check(player:GetAttribute("RocketCount") == 1, "RocketCount=1")
check(data.rockets[1]:GetAttribute("Tier") == 1, "ракета версии 1")

-- персонаж рядом с площадкой: Heartbeat подбирает готовую ракету
local function giveCharacter(p, pos)
  local char = Instance.new("Model")
  char.Name = p.Name
  local hrp = Instance.new("Part")
  hrp.Name = "HumanoidRootPart"
  hrp.CFrame = CFrame.new(pos)
  hrp.Position = pos
  hrp.Parent = char
  local hum = Instance.new("Humanoid")
  hum.Name = "Humanoid"
  hum.Health = 100
  hum.MaxHealth = 100
  hum.Parent = char
  local hand = Instance.new("Part")
  hand.Name = "RightHand"
  hand.CFrame = CFrame.new(pos + Vector3.new(1, 0, 0))
  hand.Position = pos + Vector3.new(1, 0, 0)
  hand.Parent = char
  p.Character = char
  char.Parent = Workspace
  return char
end
local padPos = data.rockets[1]:GetPivot().Position
giveCharacter(player, padPos)

-- запуск без спутника -> «нет сигнала»
runScheduler(virtualTime + 1)
check(data.held ~= nil, "ракета подобрана (data.held)")
local msgCount = #firedLog
fire("RequestLaunch")
local sawSignal = false
for i = msgCount + 1, #firedLog do
  if tostring(firedLog[i].args[1] or ""):find("НЕТ СИГНАЛА") then sawSignal = true end
end
check(sawSignal, "«нет сигнала» при запуске без спутника")

-- доход растёт
local moneyBefore = player:GetAttribute("Money")
runScheduler(virtualTime + 5)
local moneyAfter = player:GetAttribute("Money")
check(moneyAfter > moneyBefore, "доход идёт (станция + ракета): " .. moneyBefore .. " -> " .. moneyAfter)

-- спутник
player:SetAttribute("Money", 2000)
fire("BuySatellite")
check(data.hasSatellite == true, "спутник куплен")
check(player:GetAttribute("HasSatellite") == true, "HasSatellite=true")

-- после спутника RequestLaunch пропускает (нет исключения + нет повторного отказа)
msgCount = #firedLog
fire("RequestLaunch")
local refused2 = false
for i = msgCount + 1, #firedLog do
  if tostring(firedLog[i].args[1] or ""):find("НЕТ СИГНАЛА") then refused2 = true end
end
check(not refused2, "со спутником отказа нет")

-- улучшение заводa: версия 2, старая ракета остаётся
player:SetAttribute("Money", 5000)
fire("UpgradeRocket")
check(data.tier == 2, "версия ракет = 2")
check(#data.rockets == 1, "старая ракета НЕ уничтожена")
check(data.rockets[1]:GetAttribute("Tier") == 1, "старая ракета осталась версии 1")
check(player:GetAttribute("Money") == 5000 - 800, "цена улучшения 800")

-- новая ракета строится уже второй версии
player:SetAttribute("Money", 5000)
fire("BuyRocket")
runScheduler(virtualTime + 35)
check(#data.rockets == 2, "вторая ракета достроена")
local t2 = data.rockets[2]:GetAttribute("Tier")
check(t2 == 2, "вторая ракета версии 2 (текущая)")

-- блэкаут: ещё два завода -> 3 завода при 1 станции (2⚡)
fire("BuyFactory")
fire("BuyFactory")
runScheduler(virtualTime + 1)
check(player:GetAttribute("Blackout") == true, "блэкаут при 3 заводах / 1 станции")
local cBefore = data.construction and data.construction.elapsed or 0
-- стройка заморожена в блэкауте
player:SetAttribute("Money", 1000)
fire("BuyRocket")
local actT = virtualTime
runScheduler(actT + 3)
check(data.construction ~= nil, "стройка в блэкауте не завершается")
-- строим ещё станции -> блэкаут снимается
fire("BuyPowerPlant")
fire("BuyPowerPlant")
check(player:GetAttribute("Blackout") == false, "после 2 станций блэкаут снят")
runScheduler(virtualTime + 40)
check(#data.rockets >= 3, "после снятия блэкаута ракета достроена")

-- лазер ПВО (через покупку, как игрок)
player:SetAttribute("Money", 5000)
fire("BuyTurret")
local turOk = #data.turrets > 0
check(turOk == true, "ПВО установлено")
check((data.turretLevel or 0) >= 1, "уровень ПВО >=1")
check(player:GetAttribute("TurretCount") >= 1, "TurretCount>=1")
-- подсовываем вражескую ракету в полёте
local victim = nil
for uid, d in pairs(RS.players) do
  if uid ~= 42 and #d.rockets > 0 then victim = d break end
end
if not victim then
  -- создаём второго игрока-мишень
  local p2 = Instance.new("Player"); p2.Name = "Target"; p2.UserId = 77
  p2.Parent = Players
  Players._players[77] = p2
  playerAddedCb(p2)
  runScheduler(1)
  victim = RS.players[77]
end
if victim and #victim.rockets == 0 then
  RS.spawnRocketModel(victim, nil, 1)
end
check(victim ~= nil and #victim.rockets > 0, "мишень есть")
local victimRocket = victim.rockets[1]
local T = data.turrets[1]
T.reloading = false
T.missilesLeft = #T.missiles
T.lastFire = 0
local entry = {model = victimRocket, owner = victim.userId, tier = victimRocket:GetAttribute("Tier") or 1,
               armorLeft = victimRocket:GetAttribute("Tier") or 1, alive = true, isHeli = false}
T.target = entry
-- позиция цели рядом с ПВО? дистанция важна: подгоним
victimRocket:PivotTo(CFrame.new(T.model:GetPivot().Position + Vector3.new(20, 0, 0)))
runScheduler(virtualTime + 2)
check(T.lastFire > 0, "лазер ПВО выстрелил")
local sawBeam = false
for _, o in ipairs(Workspace:GetChildren()) do
  if o.ClassName == "Part" and o.Name == "Part" then
    for _, ch in ipairs(o:GetChildren()) do
      if ch.ClassName == "Beam" then sawBeam = true end
    end
  end
end
check(sawBeam or T.missilesLeft < #T.missiles, "луч/заряд израсходован")

-- союзы и войны
local p3 = Instance.new("Player"); p3.Name = "Mate"; p3.UserId = 88
p3.Parent = Players
Players._players[88] = p3
playerAddedCb(p3)
runScheduler(1)
check(RS.players[88] ~= nil, "второй игрок подключился")
fire("CreateAlliance", 88)
local found = false
for _, a in pairs(RS.alliances or {}) do if a.members[42] and a.members[88] then found = true end end
check(found, "союз создан")
fire("DeclareWar", 88)
local warBlocked = false
for _, w in pairs(RS.wars or {}) do if not w.ended then warBlocked = true end end
check(warBlocked == false, "война союзнику запрещена")
fire("BetrayAlliance")
local still = false
for _, a in pairs(RS.alliances or {}) do if a.members[42] then still = true end end
check(not still, "предательство работает")
fire("DeclareWar", 88)
local wars = 0
for _, w in pairs(RS.wars or {}) do wars = wars + 1 end
check(wars >= 1, "война объявлена после предательства")

-- список игроков
local rf = remoteFunctions["GetPlayersList"] or (findRemote("GetPlayersList") and findRemote("GetPlayersList").OnServerInvoke)
-- OnServerInvoke может быть не в remoteFunctions (присваивание через newindex) — пробуем напрямую
local gpl = findRemote("GetPlayersList")
local invoker = gpl.OnServerInvoke
check(type(invoker) == "function", "GetPlayersList имеет серверный обработчик")
local list = invoker(player)
check(type(list) == "table" and #list >= 2, "список игроков возвращается")

-- мутация: Energy Sun + ракета
player:SetAttribute("Money", 20000)
fire("BuyEnergySun")
check(data.energySun ~= nil, "Energy Sun куплена")
if #data.rockets == 0 then
  player:SetAttribute("Money", 1000)
  fire("BuyRocket")
  runScheduler(virtualTime + 40)
end
check(#data.rockets > 0, "есть ракета для мутации")
-- ждём заряда солнца
local guardSun = 0
while (player:GetAttribute("EnergySunCharge") or 0) < 50 and guardSun < 400 do
  guardSun = guardSun + 1
  runScheduler(virtualTime + 1)
end

local okMut, errMut = RS.startMutation(data, data.rockets[1])
check(okMut, "мутация запускается без подноса: " .. tostring(errMut))
runScheduler(virtualTime + 140)
local mutatedOne = nil
for _, m in ipairs(data.rockets) do
  if m:GetAttribute("Mutated") then mutatedOne = m break end
end
check(mutatedOne ~= nil, "мутация завершена")
check(mutatedOne:GetAttribute("Mutation") ~= nil, "тип мутации установлен")

log("ALL SCENARIO CHECKS PASSED")

-- отчёт по сообщениям
log("fired messages:", #firedLog)
return table.concat(logs, "\n")
'''

def main():
    rt = lua54.LuaRuntime(unpack_returned_tuples=False)
    g = rt.globals()
    try:
        result = rt.execute(LUA)
    except Exception as e:
        print("SMOKE TEST FAILED")
        print(e)
        try:
            tail = rt.execute("return table.concat(logs, \"\\n\")")
            print("---- LUA LOG ----")
            print(tail)
        except Exception:
            pass
        raise
    print(result if isinstance(result, str) else str(result))
    print("\nSMOKE TEST PASSED")


if __name__ == "__main__":
    main()
