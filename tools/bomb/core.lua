if _G.RocketSystem then
	warn("[RocketSystem] ❌ ДУБЛЬ ЯДРА! Уже запущено. Этот скрипт отключён: " .. script:GetFullName())
	return
end
_G.RocketSystem = { Ready = false, booting = true }

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

print("[RocketSystem] Запуск ядра...")

-- ===================== КОНФИГ =====================
local Config = {
	INCOME_MULT = 1,          -- множитель дохода ракет
	MAX_ROCKETS = 12,
	COOLDOWN_TIME = 45,
	PICKUP_DISTANCE = 6,
	MIN_SPACING = 4,
	PAD_MARGIN = 1.5,
	PLACE_EXTRA_RADIUS = 10,
	REPAIR_COOLDOWN = 30,
	REPAIR_SPEED = 5,
	StartMoney = 800,
	-- ===== НОВАЯ ЭКОНОМИКА: ЭНЕРГИЯ / ЗАВОДЫ / СТРОИТЕЛЬСТВО =====
	Power = {
		plantCost = 200,     -- электростанция
		plantPower = 2,      -- энергии от одной станции
		plantIncome = 6,     -- доход одной станции, $/с
		factoryCost = 400,   -- ракетный завод
		factoryPower = 1,    -- энергии ест один завод
		factorySpeed = 0.25, -- +25% к скорости строительства за каждый лишний завод
		satelliteCost = 500, -- спутник: сигнал для запуска ракет
		buildTime = 30,      -- базовое время строительства ракеты, сек
		upgradeBase = 400,   -- улучшение завода: upgradeBase * номер новой версии
	},
	Tiers = {
		{ name = "RocketShip",     short = "Mk.I",   display = "Rocket Ship",      price = 200, income = 5,   speed = 1.00, damage = 25,  radius = 25, hp = 100, resist = 0.00, armor = 1, evasion = 0.00 },
		{ name = "RocketShip1",    short = "Mk.II",  display = "Rocket Ship Mk.I", price = 300, income = 12,  speed = 1.15, damage = 35,  radius = 30, hp = 150, resist = 0.10, armor = 1, evasion = 0.10 },
		{ name = "rocketpick",     short = "Mk.III", display = "Rocket Pick",      price = 400, income = 25,  speed = 1.35, damage = 45,  radius = 34, hp = 250, resist = 0.25, armor = 2, evasion = 0.15 },
		{ name = "rocketpick2",    short = "Mk.IV",  display = "Rocket Pick II",   price = 500, income = 45,  speed = 1.50, damage = 60,  radius = 38, hp = 350, resist = 0.35, armor = 2, evasion = 0.25 },
		{ name = "rocketguns",     short = "Mk.V",   display = "Rocket Guns",      price = 600, income = 80,  speed = 1.70, damage = 90,  radius = 44, hp = 550, resist = 0.45, armor = 3, evasion = 0.30 },
		{ name = "rocketguns3000", short = "Mk.VI",  display = "Rocket Guns 3000", price = 700, income = 140, speed = 1.95, damage = 130, radius = 50, hp = 800, resist = 0.55, armor = 4, evasion = 0.40 },
	},
	Turret = {
		modelName = "Rocket Turret",
		price = 1500,
		maxCount = 3,
		extraPrice = 1000,
		footprint = 3,
		range = 220,
		missileSpeed = 180,
		levels = {
			{ reaction = 1.50, reload = 120, upgradePrice = 0 },
			{ reaction = 1.20, reload = 108, upgradePrice = 2000 },
			{ reaction = 0.95, reload = 97,  upgradePrice = 3500 },
			{ reaction = 0.70, reload = 86,  upgradePrice = 5500 },
			{ reaction = 0.45, reload = 75,  upgradePrice = 8000 },
		},
	},
	Reward = {
		perDamage = 1,
		killPerTier = 100,
		shootdownRocket = 30,
		heliHit = 100,
		heliKill = 300,
	},
	HELI_FUSE_RADIUS = 12,
}

-- цена ракеты версии: фиксирована после разблокировки (не растёт от количества)
function Config.getRocketPrice(tierIndex)
	return Config.Tiers[tierIndex].price
end

-- улучшение заводa: разблокирует следующую версию ракет
function Config.getFactoryUpgradePrice(tierIndex)
	local nxt = Config.Tiers[tierIndex + 1]
	if not nxt then return nil end
	return Config.Power.upgradeBase * (tierIndex + 1)
end

-- устаревшие алиасы (на случай внешних вызовов)
function Config.getExtraRocketPrice(tierIndex, owned)
	return Config.getRocketPrice(tierIndex)
end

function Config.getUpgradePrice(tierIndex, count)
	return Config.getFactoryUpgradePrice(tierIndex)
end

local RS = { 
	Config = Config, 
	players = {}, 
	flying = {}, 
	billboards = {}, 
	Ready = false, 
	services = {}, 
	roundResetHooks = {},
	repairCooldowns = {},
	territories = {},
	alliances = {},
	wars = {},
}
_G.RocketSystem = RS

-- ===================== REMOTES =====================
local remotes = ReplicatedStorage:FindFirstChild("RocketRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "RocketRemotes"
	remotes.Parent = ReplicatedStorage
end

local remoteNames = {
	"RequestLaunch", "RequestThrow", "SetTarget", "RocketStateChanged",
	"CameraFollowStart", "CameraFollowUpdate", "CameraFollowEnd",
	"BuyRocket", "UpgradeRocket", "BuyTurret", "UpgradeTurret", "ShopMessage",
	"PlaceRocket", "PlaceTurret",
	"BuyHelicopter", "SendHelicopter", "RecallHelicopter",
	"RoundResult", "UltraFlash", "StartMutation", "ChargeUltra", "BuyEnergySun",
	"StartRepair", "DeclareWar", "CreateAlliance", "BetrayAlliance", "GetPlayersList",
	"GetConfig", "GetHeliConfig",
	-- новая экономика
	"BuyPowerPlant", "BuyFactory", "UpgradeFactory", "BuySatellite",
}

for _, n in ipairs(remoteNames) do
	if not remotes:FindFirstChild(n) then
		local r = Instance.new(n:find("Config") and "RemoteFunction" or "RemoteEvent")
		r.Name = n
		r.Parent = remotes
	end
end

remotes.GetConfig.OnServerInvoke = function()
	return {
		MAX_ROCKETS = Config.MAX_ROCKETS,
		Tiers = Config.Tiers,
		Turret = Config.Turret,
		Reward = Config.Reward,
		PAD_MARGIN = Config.PAD_MARGIN,
		MIN_SPACING = Config.MIN_SPACING,
		PLACE_EXTRA_RADIUS = Config.PLACE_EXTRA_RADIUS,
		HELI_FUSE_RADIUS = Config.HELI_FUSE_RADIUS,
		INCOME_MULT = Config.INCOME_MULT,
		REPAIR_COOLDOWN = Config.REPAIR_COOLDOWN,
		StartMoney = Config.StartMoney,
		Power = Config.Power,
	}
end

RS.remotes = remotes

-- ===================== БЕЗОПАСНАЯ ОТПРАВКА =====================
function RS.isBot(data)
	return data ~= nil and data.bot == true
end

function RS.fire(remote, data, ...)
	local p = data and data.player
	if not p or typeof(p) ~= "Instance" or not p.Parent then return end
	remote:FireClient(p, ...)
end

function RS.msg(data, text, ok)
	RS.fire(remotes.ShopMessage, data, text, ok)
end

function RS.broadcast(text, ok)
	for _, d in pairs(RS.players) do
		RS.msg(d, text, ok)
	end
end

-- ===================== СПАВНЫ =====================
RS.spawnLocations = {}
for i = 1, 4 do
	local s = Workspace:WaitForChild("SpawnLocation" .. i, 10)
	if not s then warn("[RocketSystem] ❌ SpawnLocation" .. i .. " не найден!") end
	RS.spawnLocations[i] = s
end

local occupied = {}
RS.occupied = occupied

function RS.getFreeSpawnIndex()
	for i = 1, 4 do
		if RS.spawnLocations[i] and not occupied[i] then return i end
	end
	return nil
end

-- ===================== УТИЛИТЫ =====================
function RS.findTemplate(name)
	local lname = string.lower(name)
	for _, obj in ipairs(ServerStorage:GetDescendants()) do
		if string.lower(obj.Name) == lname and (obj:IsA("Model") or obj:IsA("BasePart")) then
			return obj
		end
	end
end

function RS.makeStatic(model, canCollide)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = canCollide
			p.Massless = true
		end
	end
end

function RS.prepareModel(model)
	if model:IsA("BasePart") then
		local wrap = Instance.new("Model")
		model.Parent = wrap
		wrap.PrimaryPart = model
		model = wrap
	end
	if not model.PrimaryPart then
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				model.PrimaryPart = p
				break
			end
		end
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			if p:GetAttribute("OrigColor") == nil then
				p:SetAttribute("OrigColor", p.Color)
			end
			if p:GetAttribute("OrigTrans") == nil then
				p:SetAttribute("OrigTrans", p.Transparency)
			end
		end
	end
	return model
end

function RS.setVisible(model, visible)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency = visible and (p:GetAttribute("OrigTrans") or 0) or 1
		end
	end
	local bb = RS.billboards[model]
	if bb then bb.gui.Enabled = visible end
end

function RS.placeAtRest(model, groundPos)
	model:PivotTo(CFrame.new(groundPos))
	local cf, size = model:GetBoundingBox()
	local bottomY = cf.Position.Y - size.Y / 2
	model:PivotTo(CFrame.new(groundPos + Vector3.new(0, groundPos.Y - bottomY, 0)))
end

function RS.getHome(model)
	return Vector3.new(
		model:GetAttribute("HomeX") or 0,
		model:GetAttribute("HomeY") or 0,
		model:GetAttribute("HomeZ") or 0
	)
end

function RS.setHome(model, pos)
	model:SetAttribute("HomeX", pos.X)
	model:SetAttribute("HomeY", pos.Y)
	model:SetAttribute("HomeZ", pos.Z)
end

function RS.isReady(m)
	if not m or not m.Parent then return false end
	return not m:GetAttribute("Flying") and (m:GetAttribute("CooldownEnd") or 0) <= tick()
end

-- ===================== ПЛОЩАДКА / РАССТАНОВКА =====================
local SPACING = 7

function RS.clampToArea(part, worldPos, extra)
	local l = part.CFrame:PointToObjectSpace(worldPos)
	local hx = part.Size.X / 2 + extra
	local hz = part.Size.Z / 2 + extra
	local w = part.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(l.X, -hx, hx),
		0,
		math.clamp(l.Z, -hz, hz)
		))
	return Vector3.new(w.X, part.Position.Y + part.Size.Y / 2, w.Z)
end

function RS.groundAt(x, z, fallbackY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(filter, p.Character) end
	end
	for _, c in ipairs(Workspace:GetChildren()) do
		if c:GetAttribute("OwnerId") then table.insert(filter, c) end
	end
	params.FilterDescendantsInstances = filter
	local r = Workspace:Raycast(Vector3.new(x, fallbackY + 40, z), Vector3.new(0, -140, 0), params)
	return r and r.Position.Y or fallbackY
end

function RS.padGrid(part)
	local hx = math.max(part.Size.X / 2 - Config.PAD_MARGIN - 1, 0)
	local hz = math.max(part.Size.Z / 2 - Config.PAD_MARGIN - 1, 0)
	local cols = math.max(math.floor(hx * 2 / SPACING) + 1, 1)
	local rows = math.max(math.floor(hz * 2 / SPACING) + 1, 1)
	local grid = {}
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local x = math.clamp(-hx + c * SPACING, -hx, hx)
			local z = math.clamp(-hz + r * SPACING, -hz, hz)
			table.insert(grid, (part.CFrame * CFrame.new(x, part.Size.Y / 2, z)).Position)
		end
	end
	return grid
end

function RS.occupiedPositions(data, ignore)
	local list = {}
	for _, m in ipairs(data.rockets) do
		if m.Parent and m ~= ignore then
			table.insert(list, { pos = RS.getHome(m), pad = 0 })
		end
	end
	for _, T in ipairs(data.turrets or {}) do
		if T ~= ignore and T.home and T.model.Parent then
			table.insert(list, { pos = T.home, pad = Config.Turret.footprint })
		end
	end
	-- здания (электростанции, заводы, спутник)
	for _, b in ipairs(data.buildings or {}) do
		if b.model.Parent and b.model ~= ignore then
			table.insert(list, { pos = b.home, pad = b.footprint })
		end
	end
	-- Energy Sun занимает центр площадки
	if data.energySun and data.energySun.model and data.energySun.model.Parent then
		table.insert(list, { pos = data.energySun.model:GetPivot().Position, pad = 4 })
	end
	return list
end

function RS.isSpotFree(data, pos, minDist, ignore)
	for _, o in ipairs(RS.occupiedPositions(data, ignore)) do
		if (o.pos - pos).Magnitude < minDist + o.pad then return false end
	end
	return true
end

function RS.findFreePosition(data, fromEnd, minDist)
	local grid = RS.padGrid(RS.spawnLocations[data.spawnIndex])
	local n = #grid
	for k = 1, n do
		local p = grid[fromEnd and (n - k + 1) or k]
		if RS.isSpotFree(data, p, minDist) then return p end
	end
	return grid[fromEnd and n or 1]
end

function RS.resolvePlacement(data, worldPos, ignore, extraSpacing)
	local pad = RS.spawnLocations[data.spawnIndex]
	if not pad then return worldPos, false end
	local extra = Config.PLACE_EXTRA_RADIUS - Config.PAD_MARGIN
	local minDist = Config.MIN_SPACING + (extraSpacing or 0)
	local function fix(p)
		p = RS.clampToArea(pad, p, extra)
		return Vector3.new(p.X, RS.groundAt(p.X, p.Z, p.Y), p.Z)
	end
	local base = fix(worldPos)
	if RS.isSpotFree(data, base, minDist, ignore) then return base, true end
	for ring = 1, 4 do
		local r = ring * minDist
		local steps = 8 * ring
		for s = 0, steps - 1 do
			local a = s / steps * math.pi * 2
			local p = fix(base + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
			if RS.isSpotFree(data, p, minDist, ignore) then return p, true end
		end
	end
	return base, false
end

-- ===================== БИЛБОРД =====================
function RS.updateLabels(model)
	local bb = RS.billboards[model]
	if not bb then return end
	local short = Config.Tiers[model:GetAttribute("Tier") or 1].short
	local mut = model:GetAttribute("Mutation")
	local mark = ""
	if mut == "nuclear" then
		mark = " 💥"
	elseif mut == "electric" then
		mark = " ⚡"
	elseif mut == "tank" then
		mark = " 🛡"
	elseif mut == "speed" then
		mark = " 💨"
	end
	bb.hp.Text = ("❤ %d/%d · %s%s"):format(
		model:GetAttribute("HP") or 0,
		model:GetAttribute("MaxHP") or 0,
		short,
		mark
	)
	local left = (model:GetAttribute("CooldownEnd") or 0) - tick()
	if model:GetAttribute("Flying") then
		bb.cd.Text = "🚀 в полёте"
		bb.cd.TextColor3 = Color3.fromRGB(255, 200, 80)
	elseif left > 0 then
		bb.cd.Text = ("⏳ %dс"):format(math.ceil(left))
		bb.cd.TextColor3 = Color3.fromRGB(255, 140, 60)
	else
		bb.cd.Text = "✅ готова"
		bb.cd.TextColor3 = Color3.fromRGB(120, 255, 140)
	end
end

function RS.attachBillboard(model)
	if not model or not model.PrimaryPart then return end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RocketInfo"
	gui.Size = UDim2.new(0, 160, 0, 84)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = model.PrimaryPart
	gui.Parent = model.PrimaryPart

	local function lbl(y, h, color)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, h, 0)
		l.Position = UDim2.new(0, 0, y, 0)
		l.TextColor3 = color
		l.TextStrokeTransparency = 0
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.Parent = gui
		return l
	end

	local pop = lbl(0, 0.34, Color3.fromRGB(85, 255, 127))
	pop.TextTransparency = 1
	pop.TextStrokeTransparency = 1
	local hp = lbl(0.34, 0.33, Color3.fromRGB(255, 120, 120))
	local cd = lbl(0.67, 0.33, Color3.fromRGB(120, 255, 140))
	RS.billboards[model] = { gui = gui, hp = hp, cd = cd, pop = pop }
	RS.updateLabels(model)
end

function RS.popupMoney(model, amount)
	local bb = RS.billboards[model]
	if not bb or not bb.gui.Parent then return end
	bb.pop.Text = "+" .. amount .. "$"
	task.spawn(function()
		for t = 0, 1, 0.1 do
			if not bb.gui.Parent then return end
			bb.pop.Position = UDim2.new(0, 0, -t * 0.5, 0)
			bb.pop.TextTransparency = t
			bb.pop.TextStrokeTransparency = t
			task.wait(0.05)
		end
	end)
end

-- ===================== НАГРАДЫ =====================
function RS.floatText(pos, text, color)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Position = pos + Vector3.new(0, 6, 0)
	p.Parent = Workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 180, 0, 44)
	gui.AlwaysOnTop = true
	gui.Parent = p

	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 1, 0)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextStrokeTransparency = 0
	l.TextColor3 = color or Color3.fromRGB(255, 220, 80)
	l.Text = text
	l.Parent = gui

	task.spawn(function()
		for t = 0, 1, 0.05 do
			if not p.Parent then return end
			p.Position = p.Position + Vector3.new(0, 0.12, 0)
			l.TextTransparency = t
			l.TextStrokeTransparency = t
			task.wait(0.05)
		end
		p:Destroy()
	end)
	Debris:AddItem(p, 3)
end

function RS.giveMoney(userId, amount, pos, label)
	amount = math.floor((amount or 0) + 0.5)
	local d = RS.players[userId]
	if amount <= 0 or not d or not d.player.Parent then return 0 end
	d.player:SetAttribute("Money", (d.player:GetAttribute("Money") or 0) + amount)
	d.earned = (d.earned or 0) + amount
	if pos then RS.floatText(pos, "+" .. amount .. "$") end
	if label then RS.msg(d, ("💰 +%d$ — %s"):format(amount, label), true) end
	return amount
end

function RS.rewardCombat(attackerId, stats, label, pos, quiet)
	local r = Config.Reward
	local amount = math.floor(
		stats.damage * r.perDamage + 
			stats.killTierSum * r.killPerTier + 
			0.5
	)
	local d = RS.players[attackerId]
	if not d or not d.player.Parent then return 0 end
	d.kills = (d.kills or 0) + (stats.kills or 0)
	if amount <= 0 then return 0 end
	d.player:SetAttribute("Money", (d.player:GetAttribute("Money") or 0) + amount)
	d.earned = (d.earned or 0) + amount
	if pos then RS.floatText(pos, "+" .. amount .. "$") end
	if not quiet then
		local txt = ("💰 +%d$ — %s: урон %d"):format(amount, label, stats.damage or 0)
		if stats.kills and stats.kills > 0 then
			txt = txt .. (", уничтожено ракет: %d"):format(stats.kills)
		end
		RS.msg(d, txt, true)
	end
	return amount
end

-- ===================== УРОН / УНИЧТОЖЕНИЕ =====================
local DARK = Color3.fromRGB(45, 45, 45)

local function updateTint(model)
	local hp = model:GetAttribute("HP") or 1
	local maxHp = model:GetAttribute("MaxHP") or 1
	local frac = hp / math.max(maxHp, 1)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("OrigColor") then
			p.Color = p:GetAttribute("OrigColor"):Lerp(DARK, (1 - frac) * 0.8)
		end
	end
end

function RS.refreshReady(data)
	local n = 0
	for _, m in ipairs(data.rockets) do
		if RS.isReady(m) then n = n + 1 end
	end
	if data.player.Parent then
		data.player:SetAttribute("ReadyRockets", n)
		data.player:SetAttribute("RocketCount", #data.rockets)
	end
end

function RS.ensureHasRocket(data)
	-- ИГРА СТРОИТСЯ С НУЛЯ: бесплатных ракет больше нет —
	-- сначала электростанция, потом завод, потом строительство ракеты.
	return false
end

function RS.destroyRocket(model)
	local data = RS.players[model:GetAttribute("OwnerId")]
	local pos = model:GetPivot().Position

	local ex = Instance.new("Explosion")
	ex.Position = pos
	ex.BlastRadius = 8
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.Parent = Workspace

	RS.flying[model] = nil
	RS.billboards[model] = nil

	if data then
		for i, m in ipairs(data.rockets) do
			if m == model then
				table.remove(data.rockets, i)
				break
			end
		end
		if data.held == model then
			data.held = nil
			RS.fire(remotes.RocketStateChanged, data, "Held", false)
		end
		if data.noPickup == model then data.noPickup = nil end
	end
	model:Destroy()

	if data and data.player.Parent then
		if #data.rockets == 0 then
			RS.msg(data, "💥 Последняя ракета уничтожена! Купите новую в разделе «🚀 РАКЕТЫ»", false)
		else
			RS.msg(data, "💥 Ракета уничтожена!", false)
		end
		RS.refreshReady(data)
	end
end

function RS.applyDamage(model, dmg)
	if not model or not model.Parent then return 0, false end
	local hpBefore = model:GetAttribute("HP") or 0
	local hp = math.max(0, hpBefore - dmg)
	model:SetAttribute("HP", hp)
	updateTint(model)
	RS.updateLabels(model)
	local killed = hp <= 0
	if killed then RS.destroyRocket(model) end
	return hpBefore - hp, killed
end

-- ===================== РЕМОНТ =====================
function RS.startRepair(data, model)
	if not model or not model.Parent then 
		return false, "Ракета не найдена" 
	end
	if model:GetAttribute("Flying") then 
		return false, "Ракета в полете" 
	end
	if model:GetAttribute("HP") >= model:GetAttribute("MaxHP") then 
		return false, "Ракета уже цела" 
	end

	local key = tostring(data.userId) .. "_" .. model.Name
	if RS.repairCooldowns[key] and RS.repairCooldowns[key] > tick() then
		return false, "Ремонт на перезарядке: " .. math.ceil(RS.repairCooldowns[key] - tick()) .. "с"
	end

	RS.repairCooldowns[key] = tick() + Config.REPAIR_COOLDOWN
	model:SetAttribute("Repairing", true)

	task.spawn(function()
		while model.Parent and model:GetAttribute("Repairing") do
			local hp = model:GetAttribute("HP") or 0
			local maxHp = model:GetAttribute("MaxHP") or 1
			if hp >= maxHp then break end
			local newHp = math.min(hp + Config.REPAIR_SPEED, maxHp)
			model:SetAttribute("HP", newHp)
			RS.updateLabels(model)
			task.wait(1)
		end
		model:SetAttribute("Repairing", false)
	end)

	RS.msg(data, "🔧 Ремонт ракеты начат!", true)
	return true
end

-- ===================== СПАВН РАКЕТ =====================
function RS.spawnRocketModel(data, homePos, version)
	version = math.clamp(math.floor(tonumber(version) or data.tier or 1), 1, #Config.Tiers)
	local tier = Config.Tiers[version]
	local template = RS.findTemplate(tier.name)
	if not template then
		warn("[RocketSystem] ❌ Модель '" .. tier.name .. "' не найдена, использую базовую")
		template = RS.findTemplate(Config.Tiers[1].name)
	end
	if not template then 
		warn("[RocketSystem] ❌ Нет ни одной модели ракеты!") 
		return 
	end

	local pad = RS.spawnLocations[data.spawnIndex]
	if not pad then return end

	local model = RS.prepareModel(template:Clone())
	if not model.PrimaryPart then 
		model:Destroy() 
		return 
	end

	model.Name = "Rocket_" .. data.player.Name
	RS.makeStatic(model, true)

	local home = homePos or RS.findFreePosition(data, false, Config.MIN_SPACING)
	model:SetAttribute("OwnerId", data.userId)
	model:SetAttribute("Tier", version)
	model:SetAttribute("HP", tier.hp)
	model:SetAttribute("MaxHP", tier.hp)
	model:SetAttribute("Flying", false)
	model:SetAttribute("Held", false)
	model:SetAttribute("CooldownEnd", 0)
	model:SetAttribute("Mutated", false)
	model:SetAttribute("Mutation", nil)
	RS.setHome(model, home)

	model.Parent = Workspace
	RS.placeAtRest(model, home)
	RS.attachBillboard(model)
	table.insert(data.rockets, model)
	RS.refreshReady(data)
	return model
end

function RS.addRocket(data)
	return RS.spawnRocketModel(data, nil, data.tier)
end

-- ===================== ЗДАНИЯ: ЭЛЕКТРОСТАНЦИЯ / ЗАВОД / СПУТНИК =====================
-- Модели строятся из простых деталей прямо на сервере (авторские, не ассеты).

local BUILDING_FOOTPRINT = { power = 3, factory = 4, satellite = 2.5 }

local function mkPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function markLamp(p)
	p:SetAttribute("Lamp", true)
	p:SetAttribute("LampColor", p.Color)
	return p
end

-- вертикальный цилиндр (ось Y)
local function vCylinder(height, dia, props)
	props = props or {}
	props.Size = Vector3.new(height, dia, dia)
	props.CFrame = CFrame.new(props.Position or Vector3.zero) * CFrame.Angles(0, 0, math.rad(90))
	props.Position = nil
	return mkPart(props)
end

local function newModel(name, primary)
	local m = Instance.new("Model")
	m.Name = name
	m.PrimaryPart = primary
	return m
end

-- ---------- ЭЛЕКТРОСТАНЦИЯ ----------
local function put(m, p)
	p.Parent = m
	return p
end

local function buildPowerPlantModel()
	local slab = mkPart({
		Size = Vector3.new(6, 0.5, 6),
		Color = Color3.fromRGB(88, 90, 96),
		Material = Enum.Material.Concrete,
	})
	local m = newModel("PowerPlant", slab)
	put(m, slab)

	put(m, mkPart({
		Size = Vector3.new(3.8, 2.6, 3.2),
		CFrame = CFrame.new(-0.7, 1.55, 0.3),
		Color = Color3.fromRGB(178, 184, 194),
		Material = Enum.Material.Metal,
	}))

	-- светящиеся окна
	for _, dz in ipairs({ -0.9, 0, 0.9 }) do
		put(m, markLamp(mkPart({
			Size = Vector3.new(0.12, 0.8, 0.6),
			CFrame = CFrame.new(1.25, 1.7, 0.3 + dz),
			Color = Color3.fromRGB(120, 225, 255),
			Material = Enum.Material.Neon,
		})))
	end

	-- труба с красными полосами
	put(m, vCylinder(5.2, 1.1, {
		Position = Vector3.new(2.1, 2.85, -1.9),
		Color = Color3.fromRGB(205, 205, 210),
		Material = Enum.Material.Metal,
	}))
	for _, y in ipairs({ 3.6, 4.7 }) do
		put(m, vCylinder(0.5, 1.2, {
			Position = Vector3.new(2.1, y, -1.9),
			Color = Color3.fromRGB(225, 70, 60),
			Material = Enum.Material.Metal,
			CanCollide = false,
		}))
	end

	-- трансформатор
	put(m, mkPart({
		Size = Vector3.new(1.3, 1.1, 0.9),
		CFrame = CFrame.new(1.6, 0.8, 1.7),
		Color = Color3.fromRGB(45, 48, 55),
		Material = Enum.Material.Metal,
	}))
	put(m, markLamp(mkPart({
		Size = Vector3.new(0.35, 0.12, 0.35),
		CFrame = CFrame.new(1.6, 1.41, 1.7),
		Color = Color3.fromRGB(255, 230, 90),
		Material = Enum.Material.Neon,
	})))

	-- маяк
	local beacon = put(m, mkPart({
		Size = Vector3.new(0.3, 0.3, 0.3),
		Shape = Enum.PartType.Ball,
		CFrame = CFrame.new(-0.7, 3.05, 0.3),
		Color = Color3.fromRGB(90, 255, 160),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(90, 255, 160)
	light.Range = 14
	light.Brightness = 1.2
	light.Parent = beacon
	return m
end

-- ---------- РАКЕТНЫЙ ЗАВОД ----------
local function buildFactoryModel()
	local slab = mkPart({
		Size = Vector3.new(7, 0.5, 7),
		Color = Color3.fromRGB(72, 74, 80),
		Material = Enum.Material.Concrete,
	})
	local m = newModel("RocketFactory", slab)
	put(m, slab)

	put(m, mkPart({
		Size = Vector3.new(5, 2.8, 3.6),
		CFrame = CFrame.new(-0.4, 1.65, -0.7),
		Color = Color3.fromRGB(118, 128, 142),
		Material = Enum.Material.Metal,
	}))

	-- оранжевый карниз
	put(m, markLamp(mkPart({
		Size = Vector3.new(5.1, 0.2, 3.7),
		CFrame = CFrame.new(-0.4, 3.15, -0.7),
		Color = Color3.fromRGB(255, 170, 60),
		Material = Enum.Material.Neon,
	})))

	-- фонари на крыше
	for _, dx in ipairs({ -1.6, 0, 1.6 }) do
		put(m, markLamp(mkPart({
			Size = Vector3.new(0.9, 0.1, 3.2),
			CFrame = CFrame.new(-0.4 + dx, 3.3, -0.7),
			Color = Color3.fromRGB(255, 235, 170),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})))
	end

	-- административный блок
	put(m, mkPart({
		Size = Vector3.new(1.8, 1.9, 1.7),
		CFrame = CFrame.new(2.3, 1.2, 2.1),
		Color = Color3.fromRGB(150, 155, 165),
		Material = Enum.Material.Concrete,
	}))
	put(m, markLamp(mkPart({
		Size = Vector3.new(0.7, 0.9, 0.1),
		CFrame = CFrame.new(2.3, 0.7, 3.0),
		Color = Color3.fromRGB(120, 225, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})))

	-- ворота-погрузка
	put(m, mkPart({
		Size = Vector3.new(2.2, 1.7, 0.15),
		CFrame = CFrame.new(-0.4, 1.1, 1.18),
		Color = Color3.fromRGB(48, 50, 56),
		Material = Enum.Material.DiamondPlate,
	}))

	-- труба с дымом
	local stack = put(m, vCylinder(3.4, 0.75, {
		Position = Vector3.new(-2.7, 1.95, -2.3),
		Color = Color3.fromRGB(160, 150, 140),
		Material = Enum.Material.Metal,
	}))
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "FactorySmoke"
	smoke.Texture = "rbxassetid://243660364"
	smoke.Rate = 7
	smoke.Speed = NumberRange.new(2, 4)
	smoke.Lifetime = NumberRange.new(2, 3.5)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 3.5),
	})
	smoke.Color = ColorSequence.new(Color3.fromRGB(170, 170, 175))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Parent = stack
	return m
end

-- ---------- СПУТНИКОВАЯ СТАНЦИЯ ----------
local function buildSatelliteModel()
	local slab = mkPart({
		Size = Vector3.new(3, 0.4, 3),
		Color = Color3.fromRGB(85, 88, 94),
		Material = Enum.Material.Concrete,
	})
	local m = newModel("SatelliteStation", slab)
	put(m, slab)

	put(m, mkPart({
		Size = Vector3.new(0.3, 2.2, 0.3),
		CFrame = CFrame.new(0, 1.3, 0),
		Color = Color3.fromRGB(165, 168, 175),
		Material = Enum.Material.Metal,
	}))

	-- тарелка: диск, повёрнутый вверх-вперёд
	local dir = Vector3.new(0, 0.72, 0.69).Unit
	local dishPos = Vector3.new(0, 2.4, 0)
	put(m, mkPart({
		Size = Vector3.new(0.22, 2.3, 2.3),
		CFrame = CFrame.lookAt(dishPos, dishPos + dir) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(225, 228, 235),
		Material = Enum.Material.Metal,
		CanCollide = false,
	}))
	put(m, mkPart({
		Size = Vector3.new(0.12, 0.9, 0.12),
		CFrame = CFrame.lookAt(dishPos + dir * 0.45, dishPos + dir * 1.1),
		Color = Color3.fromRGB(60, 62, 68),
		Material = Enum.Material.Metal,
		CanCollide = false,
	}))
	put(m, markLamp(mkPart({
		Size = Vector3.new(0.28, 0.28, 0.28),
		Shape = Enum.PartType.Ball,
		CFrame = CFrame.new(dishPos + dir * 1.15),
		Color = Color3.fromRGB(90, 255, 160),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})))

	-- мигающий маяк
	local beacon = put(m, mkPart({
		Size = Vector3.new(0.25, 0.25, 0.25),
		Shape = Enum.PartType.Ball,
		CFrame = CFrame.new(0, 3.05, 0),
		Color = Color3.fromRGB(80, 220, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(80, 220, 255)
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = beacon
	task.spawn(function()
		local on = false
		while m.Parent do
			on = not on
			light.Enabled = on
			beacon.Transparency = on and 0 or 0.35
			task.wait(0.5)
		end
	end)
	return m
end

-- ---------- БИЛБОРД ЗДАНИЯ ----------
function RS.attachBuildingBillboard(model, line1, line2, color1, color2)
	if not model.PrimaryPart then return end
	RS.attachBillboard(model)
	local bb = RS.billboards[model]
	if not bb then return end
	bb.hp.Text = line1
	bb.hp.TextColor3 = color1 or Color3.fromRGB(120, 225, 255)
	bb.cd.Text = line2
	bb.cd.TextColor3 = color2 or Color3.fromRGB(200, 205, 215)
	return bb
end

local function setFactoryLamps(b, on)
	for _, p in ipairs(b.model:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("Lamp") then
			local c = p:GetAttribute("LampColor")
			if on then
				p.Color = typeof(c) == "Color3" and c or Color3.new(1, 1, 1)
			else
				p.Color = Color3.fromRGB(255, 70, 60)
			end
		end
	end
end

function RS.updateBuildingBillboards(data)
	for _, b in ipairs(data.buildings) do
		local bb = RS.billboards[b.model]
		if bb and b.model.Parent then
			if b.kind == "factory" then
				if data.construction then
					local c = data.construction
					local pct = math.floor(math.min(c.elapsed / c.duration, 1) * 100)
					local left = math.max(0, math.ceil(c.duration - c.elapsed))
					if data.blackout then
						bb.cd.Text = ("🔴 Блэкаут! %d%% (стоит)"):format(pct)
						bb.cd.TextColor3 = Color3.fromRGB(255, 90, 90)
					else
						bb.cd.Text = ("🔨 Стройка %d%% (%dс)"):format(pct, left)
						bb.cd.TextColor3 = Color3.fromRGB(255, 210, 120)
					end
				elseif data.blackout then
					bb.cd.Text = "🔴 Нет энергии"
					bb.cd.TextColor3 = Color3.fromRGB(255, 90, 90)
				else
					bb.cd.Text = ("✅ Работает  ×%.2f"):format(RS.buildSpeedMult(data))
					bb.cd.TextColor3 = Color3.fromRGB(140, 255, 170)
				end
			elseif b.kind == "power" then
				bb.cd.Text = data.blackout
					and "⚡ Отдаёт энергию (авария!)"
					or ("⚡ +%d энергии · +%d$/с"):format(Config.Power.plantPower, Config.Power.plantIncome)
				bb.cd.TextColor3 = data.blackout and Color3.fromRGB(255, 200, 90) or Color3.fromRGB(200, 205, 215)
			end
		end
	end
end

function RS.factoryCountOf(data)
	local n = 0
	for _, b in ipairs(data.buildings) do
		if b.kind == "factory" then n = n + 1 end
	end
	return n
end

function RS.powerCountOf(data)
	local n = 0
	for _, b in ipairs(data.buildings) do
		if b.kind == "power" then n = n + 1 end
	end
	return n
end

function RS.buildSpeedMult(data)
	local n = RS.factoryCountOf(data)
	if n <= 0 then return 1 end
	return 1 + Config.Power.factorySpeed * (n - 1)
end

function RS.recalcEnergy(data)
	local power, draw = 0, 0
	for _, b in ipairs(data.buildings) do
		if b.kind == "power" then
			power = power + Config.Power.plantPower
		elseif b.kind == "factory" then
			draw = draw + Config.Power.factoryPower
		end
	end
	data.power = power
	data.powerDraw = draw
	local wasBlackout = data.blackout
	data.blackout = draw > power

	local p = data.player
	p:SetAttribute("Power", power)
	p:SetAttribute("PowerDraw", draw)
	p:SetAttribute("Blackout", data.blackout)
	p:SetAttribute("PowerCount", RS.powerCountOf(data))
	p:SetAttribute("FactoryCount", RS.factoryCountOf(data))

	for _, b in ipairs(data.buildings) do
		if b.kind == "factory" then
			setFactoryLamps(b, not data.blackout)
		end
	end

	if data.blackout and not wasBlackout then
		RS.msg(data, ("🔴 БЛЕКАУТ! Потребление %d⚡ больше мощности %d⚡ — постройте электростанцию"):format(draw, power), false)
	elseif wasBlackout and not data.blackout then
		RS.msg(data, "⚡ Энергия восстановлена — заводы снова работают!", true)
	end
	RS.updateBuildingBillboards(data)
end

local BUILDING_DEFS = {
	power = {
		label = "⚡ Электростанция",
		make = buildPowerPlantModel,
	},
	factory = {
		label = "🏭 Ракетный завод",
		make = buildFactoryModel,
	},
	satellite = {
		label = "📡 Спутниковая станция",
		make = buildSatelliteModel,
	},
}

function RS.buyBuilding(data, kind)
	local def = BUILDING_DEFS[kind]
	if not def then return false, "Неизвестное здание" end

	if kind == "power" then
		local cost = Config.Power.plantCost
		if (data.player:GetAttribute("Money") or 0) < cost then
			return false, ("Не хватает денег (нужно %d$)"):format(cost)
		end
		data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) - cost)
	elseif kind == "factory" then
		if RS.powerCountOf(data) < 1 then
			return false, "Сначала постройте электростанцию!"
		end
		local cost = Config.Power.factoryCost
		if (data.player:GetAttribute("Money") or 0) < cost then
			return false, ("Не хватает денег (нужно %d$)"):format(cost)
		end
		data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) - cost)
	elseif kind == "satellite" then
		if data.hasSatellite then
			return false, "Спутник уже на орбите"
		end
		local cost = Config.Power.satelliteCost
		if (data.player:GetAttribute("Money") or 0) < cost then
			return false, ("Не хватает денег (нужно %d$)"):format(cost)
		end
		data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) - cost)
	end

	local model = def.make()
	model:SetAttribute("OwnerId", data.userId)
	model:SetAttribute("BuildingKind", kind)
	RS.makeStatic(model, true)

	local footprint = BUILDING_FOOTPRINT[kind]
	local pos = RS.findFreePosition(data, false, Config.MIN_SPACING + footprint)
	model.Parent = Workspace
	RS.placeAtRest(model, pos)

	local b = { model = model, kind = kind, home = pos, footprint = footprint }
	table.insert(data.buildings, b)

	if kind == "power" then
		RS.attachBuildingBillboard(model, "⚡ Электростанция", "", Color3.fromRGB(120, 225, 255))
	elseif kind == "factory" then
		RS.attachBuildingBillboard(model, "🏭 Ракетный завод", "", Color3.fromRGB(255, 190, 90))
	else
		data.hasSatellite = true
		data.player:SetAttribute("HasSatellite", true)
		RS.attachBuildingBillboard(model, "📡 Спутник на орбите", "📡 Сигнал есть", Color3.fromRGB(90, 230, 255), Color3.fromRGB(140, 255, 170))
	end

	RS.recalcEnergy(data)
	RS.updateBuildingBillboards(data)

	if kind == "power" then
		RS.msg(data, ("⚡ Электростанция построена! +%d⚡ энергии, +%d$/с"):format(Config.Power.plantPower, Config.Power.plantIncome), true)
	elseif kind == "factory" then
		RS.msg(data, ("🏭 Завод построен! Скорость строительства ×%.2f (каждый следующий завод +25%%)"):format(RS.buildSpeedMult(data)), true)
	else
		RS.msg(data, "📡 Спутник вышел на орбиту — сигнал есть! Можно запускать ракеты и видеть базы врагов", true)
		RS.broadcast(("🛰 %s запустил спутник — теперь видит все базы"):format(data.player.Name), true)
	end
	return true
end

function RS.buyConstruction(data)
	if RS.factoryCountOf(data) < 1 then
		return false, "Сначала постройте ракетный завод!"
	end
	if data.construction then
		return false, "Ракета уже строится — дождитесь готовности"
	end
	if #data.rockets >= Config.MAX_ROCKETS then
		return false, "Максимум ракет!"
	end
	local price = Config.getRocketPrice(data.tier)
	if (data.player:GetAttribute("Money") or 0) < price then
		return false, ("Не хватает денег (нужно %d$)"):format(price)
	end
	data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) - price)

	local speed = RS.buildSpeedMult(data)
	local dur = Config.Power.buildTime / speed
	data.construction = { version = data.tier, startAt = tick(), duration = dur, elapsed = 0 }
	data.player:SetAttribute("ConstructionActive", true)
	data.player:SetAttribute("ConstructionVersion", data.tier)
	data.player:SetAttribute("ConstructionProgress", 0)
	data.player:SetAttribute("ConstructionLeft", math.ceil(dur))
	RS.msg(data, ("🔨 Строим ракету %s — %d сек (заводов: %d, ×%.2f)"):format(
		Config.Tiers[data.tier].short, math.ceil(dur), RS.factoryCountOf(data), speed), true)
	RS.updateBuildingBillboards(data)
	return true
end

function RS.upgradeFactory(data)
	if RS.factoryCountOf(data) < 1 then
		return false, "Сначала постройте ракетный завод!"
	end
	local price = Config.getFactoryUpgradePrice(data.tier)
	if not price then
		return false, "Достигнута максимальная версия ракет!"
	end
	if (data.player:GetAttribute("Money") or 0) < price then
		return false, ("Не хватает денег (нужно %d$)"):format(price)
	end
	data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) - price)
	data.tier = math.min(data.tier + 1, #Config.Tiers)
	data.player:SetAttribute("RocketTier", data.tier)
	RS.msg(data, ("🏭 Завод улучшен! Теперь строится %s (%d$). Старые ракеты остаются у вас"):format(
		Config.Tiers[data.tier].display, Config.getRocketPrice(data.tier)), true)
	RS.refreshReady(data)
	return true
end

function RS.hasSignal(data)
	return data.hasSatellite == true
end

function RS.signalRefused(data)
	RS.msg(data, "🚫 НЕТ СИГНАЛА! Ракеты не долетят до врага — купите спутник: МАГАЗИН → ⚡ ЭНЕРГИЯ", false)
end

local function destroyBuildings(data)
	for _, b in ipairs(data.buildings or {}) do
		RS.billboards[b.model] = nil
		if b.model.Parent then
			b.model:Destroy()
		end
	end
	data.buildings = {}
	data.hasSatellite = false
	data.construction = nil
end

-- ===================== ТИК: ДОХОД + КД =====================
task.spawn(function()
	local incomeAcc = 0
	while true do
		task.wait(0.5)
		incomeAcc = incomeAcc + 0.5
		local doIncome = incomeAcc >= 1
		if doIncome then incomeAcc = 0 end

		for _, data in pairs(RS.players) do
			if not data.player.Parent then
				RS.removeData(data)
			else
				-- ===== строительство ракеты на заводе =====
				if data.construction and not data.blackout then
					local c = data.construction
					c.elapsed = c.elapsed + 0.5
					if c.elapsed >= c.duration then
						local version = c.version
						data.construction = nil
						data.player:SetAttribute("ConstructionActive", false)
						data.player:SetAttribute("ConstructionProgress", 100)
						data.player:SetAttribute("ConstructionLeft", 0)
						local ok, err = pcall(RS.spawnRocketModel, data, nil, version)
						if ok then
							RS.msg(data, ("✅ Ракета %s построена! Подойдите к ней и запускайте (нужен спутник)"):format(Config.Tiers[version].short), true)
						else
							warn("[RocketSystem] спавн после стройки:", err)
						end
						RS.refreshReady(data)
					else
						local frac = c.elapsed / c.duration
						data.player:SetAttribute("ConstructionProgress", math.floor(frac * 100))
						data.player:SetAttribute("ConstructionLeft", math.ceil(c.duration - c.elapsed))
					end
					RS.updateBuildingBillboards(data)
				end

				-- ===== доход =====
				if doIncome then
					local im = data.incomeMult or 1
					local total = 0

					-- электростанции
					local plantIncome = math.floor(Config.Power.plantIncome * im + 0.5)
					for _, b in ipairs(data.buildings) do
						if b.kind == "power" and b.model.Parent then
							total = total + plantIncome
							RS.popupMoney(b.model, plantIncome)
						end
					end

					-- ракеты: доход своей версии
					for _, m in ipairs(data.rockets) do
						if m.Parent then
							local t = Config.Tiers[m:GetAttribute("Tier") or data.tier]
							local per = math.max(1, math.floor(t.income * (Config.INCOME_MULT or 1) * im + 0.5))
							total = total + per
							RS.popupMoney(m, per)
							RS.updateLabels(m)
						end
					end

					data.player:SetAttribute("Income", total)
					if total > 0 then
						data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) + total)
						data.earned = data.earned + total
					end
					RS.refreshReady(data)

					-- ===== пошаговые подсказки =====
					if data.hintStage then
						local joined = tick() - (data.joinedAt or tick())
						if data.hintStage == 1 and joined > 5 and RS.powerCountOf(data) == 0 then
							data.hintStage = 2
							RS.msg(data, "1️⃣ Откройте 🛒 МАГАЗИН → ⚡ ЭНЕРГИЯ и постройте электростанцию (200$)", true)
						elseif data.hintStage == 2 and RS.powerCountOf(data) > 0 and RS.factoryCountOf(data) == 0 then
							data.hintStage = 3
							RS.msg(data, "2️⃣ Купите ракетный завод (400$) — он потребляет энергию", true)
						elseif data.hintStage == 3 and RS.factoryCountOf(data) > 0 and #data.rockets == 0 and not data.construction then
							data.hintStage = 4
							RS.msg(data, "3️⃣ Купите ракету — она строится на заводе. Понадобится ещё и спутник", true)
						elseif data.hintStage == 4 and (#data.rockets > 0 or data.construction ~= nil) and not data.hasSatellite then
							data.hintStage = 5
							RS.msg(data, "4️⃣ Без спутника ракеты не стартуют («нет сигнала») — купите 📡 спутник (500$)", true)
						elseif data.hintStage == 5 and data.hasSatellite then
							data.hintStage = 6
							RS.msg(data, "5️⃣ Готово! Подходьте к ракете, нажмите 🚀 ЗАПУСТИТЬ и выберите цель", true)
						end
					end
				end
			end
		end
	end
end)

-- ===================== ДАННЫЕ УЧАСТНИКА =====================
function RS.createData(playerLike, spawnIndex, isBot)
	local data = {
		player = playerLike,
		userId = playerLike.UserId,
		spawnIndex = spawnIndex,
		bot = isBot or false,
		tier = 1,
		rockets = {},
		held = nil,
		noPickup = nil,
		spawnedOnce = false,
		turrets = {},
		turretLevel = 0,
		heli = nil,
		earned = 0,
		kills = 0,
		incomeMult = 1,
		joinedAt = tick(),
		territories = {},
		energySun = nil,
		allianceId = nil,
		-- новая экономика
		buildings = {},
		construction = nil,
		hasSatellite = false,
		power = 0,
		powerDraw = 0,
		blackout = false,
		hintStage = (not isBot) and 1 or nil,
	}
	RS.players[playerLike.UserId] = data
	occupied[spawnIndex] = data

	playerLike:SetAttribute("SpawnIndex", spawnIndex)
	playerLike:SetAttribute("Money", Config.StartMoney)
	playerLike:SetAttribute("Income", 0)
	playerLike:SetAttribute("RocketCount", 0)
	playerLike:SetAttribute("ReadyRockets", 0)
	playerLike:SetAttribute("RocketTier", 1)
	playerLike:SetAttribute("TurretLevel", 0)
	playerLike:SetAttribute("TurretCount", 0)
	playerLike:SetAttribute("HasEnergySun", false)
	playerLike:SetAttribute("EnergySunCharge", 0)
	-- новая экономика
	playerLike:SetAttribute("Power", 0)
	playerLike:SetAttribute("PowerDraw", 0)
	playerLike:SetAttribute("PowerCount", 0)
	playerLike:SetAttribute("FactoryCount", 0)
	playerLike:SetAttribute("Blackout", false)
	playerLike:SetAttribute("HasSatellite", false)
	playerLike:SetAttribute("ConstructionActive", false)
	playerLike:SetAttribute("ConstructionProgress", 0)
	playerLike:SetAttribute("ConstructionLeft", 0)
	playerLike:SetAttribute("ConstructionVersion", 1)

	return data
end

function RS.removeData(data)
	if not data or RS.players[data.userId] ~= data then return end

	for _, m in ipairs(data.rockets) do
		RS.flying[m] = nil
		RS.billboards[m] = nil
		m:Destroy()
	end
	data.rockets = {}
	data.held = nil

	for _, b in ipairs(data.buildings or {}) do
		RS.billboards[b.model] = nil
		if b.model.Parent then b.model:Destroy() end
	end
	data.buildings = {}
	data.construction = nil
	data.hasSatellite = false

	if RS.clearTurrets then 
		RS.clearTurrets(data) 
	end

	if data.heli and RS.removeHeli then 
		pcall(RS.removeHeli, data) 
	end

	if occupied[data.spawnIndex] == data then
		occupied[data.spawnIndex] = nil
	end
	RS.players[data.userId] = nil
end

function RS.resetBase(data)
	if RS.players[data.userId] ~= data then return end

	if data.held then
		data.held = nil
		RS.fire(remotes.RocketStateChanged, data, "Held", false)
	end
	data.noPickup = nil

	for _, m in ipairs(data.rockets) do
		RS.flying[m] = nil
		RS.billboards[m] = nil
		m:Destroy()
	end
	data.rockets = {}

	if RS.clearTurrets then RS.clearTurrets(data) end
	data.turretLevel = 0

	if RS.removeHeli then pcall(RS.removeHeli, data) end

	-- здания и строительство нового раунда
	for _, b in ipairs(data.buildings or {}) do
		RS.billboards[b.model] = nil
		if b.model.Parent then b.model:Destroy() end
	end
	data.buildings = {}
	data.construction = nil
	data.hasSatellite = false
	data.blackout = false
	data.power = 0
	data.powerDraw = 0

	data.tier = 1
	data.earned = 0
	data.kills = 0

	local p = data.player
	if p.Parent then
		p:SetAttribute("Money", Config.StartMoney)
		p:SetAttribute("Income", 0)
		p:SetAttribute("RocketTier", 1)
		p:SetAttribute("TurretLevel", 0)
		p:SetAttribute("TurretCount", 0)
		p:SetAttribute("Power", 0)
		p:SetAttribute("PowerDraw", 0)
		p:SetAttribute("PowerCount", 0)
		p:SetAttribute("FactoryCount", 0)
		p:SetAttribute("Blackout", false)
		p:SetAttribute("HasSatellite", false)
		p:SetAttribute("ConstructionActive", false)
		p:SetAttribute("ConstructionProgress", 0)
		p:SetAttribute("ConstructionLeft", 0)
		p:SetAttribute("RocketCount", 0)
		p:SetAttribute("ReadyRockets", 0)
	end

	-- раунд начинается с нуля: сначала электростанция, потом завод
	RS.refreshReady(data)

	for _, hook in ipairs(RS.roundResetHooks) do
		task.spawn(hook, data)
	end
end

-- ===================== ИГРОКИ =====================
local function onPlayerAdded(player)
	if RS.players[player.UserId] then return end

	local spawnIndex = RS.getFreeSpawnIndex()
	if not spawnIndex and RS.removeBot then
		for i = 1, 4 do
			local occ = occupied[i]
			if occ and occ.bot then
				RS.removeBot(occ)
				break
			end
		end
		spawnIndex = RS.getFreeSpawnIndex()
	end

	if not spawnIndex then
		warn("[RocketSystem] ❌ Нет свободной базы для " .. player.Name)
		return
	end

	local data = RS.createData(player, spawnIndex, false)
	print("[RocketSystem] Игрок", player.Name, "→ база №", spawnIndex)

	local function onCharacter(character)
		data.spawnedOnce = true
		task.wait(0.2)
		pcall(function()
			if character:WaitForChild("HumanoidRootPart", 5) then
				character:PivotTo(RS.spawnLocations[spawnIndex].CFrame + Vector3.new(0, 5, 0))
			end
		end)
		-- первая ракета НЕ выдаётся: игра начинается со строительства
	end

	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	RS.removeData(RS.players[player.UserId])
end)

RS.Ready = true
print("[RocketSystem] ✅ Ядро готово")