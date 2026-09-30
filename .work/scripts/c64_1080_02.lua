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
	PAYBACK_SECONDS = 120,
	INCOME_MULT = 2,
	MAX_ROCKETS = 12,
	COOLDOWN_TIME = 45,
	PICKUP_DISTANCE = 6,
	MIN_SPACING = 4,
	PAD_MARGIN = 1.5,
	PLACE_EXTRA_RADIUS = 10,
	REPAIR_COOLDOWN = 30,
	REPAIR_SPEED = 5,
	Tiers = {
		{ name = "RocketShip",     display = "Rocket Ship",      income = 5,   speed = 1.00, damage = 25,  radius = 25, hp = 100, resist = 0.00, armor = 1, evasion = 0.00 },
		{ name = "RocketShip1",    display = "Rocket Ship Mk.I", income = 12,  speed = 1.15, damage = 35,  radius = 30, hp = 150, resist = 0.10, armor = 1, evasion = 0.10 },
		{ name = "rocketpick",     display = "Rocket Pick",      income = 25,  speed = 1.35, damage = 45,  radius = 34, hp = 250, resist = 0.25, armor = 2, evasion = 0.15 },
		{ name = "rocketpick2",    display = "Rocket Pick II",   income = 45,  speed = 1.50, damage = 60,  radius = 38, hp = 350, resist = 0.35, armor = 2, evasion = 0.25 },
		{ name = "rocketguns",     display = "Rocket Guns",      income = 80,  speed = 1.70, damage = 90,  radius = 44, hp = 550, resist = 0.45, armor = 3, evasion = 0.30 },
		{ name = "rocketguns3000", display = "Rocket Guns 3000", income = 140, speed = 1.95, damage = 130, radius = 50, hp = 800, resist = 0.55, armor = 4, evasion = 0.40 },
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
	StartMoney = 300,
}

for _, t in ipairs(Config.Tiers) do 
	t.price = t.income * Config.PAYBACK_SECONDS 
end

function Config.getExtraRocketPrice(tierIndex, owned)
	return Config.Tiers[tierIndex].price + (owned - 1) * 150
end

function Config.getUpgradePrice(tierIndex, count)
	local nxt = Config.Tiers[tierIndex + 1]
	return nxt and nxt.price * count or nil
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
	"GetConfig", "GetHeliConfig"
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
	bb.hp.Text = ("❤ %d/%d"):format(
		model:GetAttribute("HP") or 0,
		model:GetAttribute("MaxHP") or 0
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
			p.Position += Vector3.new(0, 0.12, 0)
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
	if not data.player.Parent then return end
	for i = #data.rockets, 1, -1 do
		if not data.rockets[i].Parent then
			table.remove(data.rockets, i)
		end
	end
	if #data.rockets > 0 then return end

	data.tier = 1
	data.player:SetAttribute("RocketTier", 1)
	local ok, err = pcall(RS.spawnRocketModel, data)
	if ok and #data.rockets > 0 then
		RS.msg(data, "💥 Все ракеты уничтожены! Выдана базовая ракета", false)
	else
		warn("[RocketSystem] Не удалось выдать базовую ракету:", err)
	end
	RS.refreshReady(data)
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
			task.defer(RS.ensureHasRocket, data)
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
function RS.spawnRocketModel(data, homePos)
	local tier = Config.Tiers[data.tier]
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
	return RS.spawnRocketModel(data)
end

function RS.rebuildFleet(data)
	local homes = {}
	for _, m in ipairs(data.rockets) do
		table.insert(homes, RS.getHome(m))
		RS.flying[m] = nil
		RS.billboards[m] = nil
		m:Destroy()
	end
	data.rockets = {}
	for _, h in ipairs(homes) do
		RS.spawnRocketModel(data, h)
	end
end

-- ===================== ТИК: ДОХОД + КД =====================
task.spawn(function()
	while true do
		task.wait(1)
		for _, data in pairs(RS.players) do
			if not data.player.Parent then 
				RS.removeData(data)
				continue 
			end

			local tier = Config.Tiers[data.tier]
			local per = math.max(1, math.floor(
				tier.income * (Config.INCOME_MULT or 1) * (data.incomeMult or 1) + 0.5
				))
			local total = 0

			for _, m in ipairs(data.rockets) do
				if m.Parent then
					total = total + per
					RS.popupMoney(m, per)
					RS.updateLabels(m)
				end
			end

			data.player:SetAttribute("Income", total)
			if total > 0 then
				data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) + total)
				data.earned = (data.earned or 0) + total
			end
			RS.refreshReady(data)

			if #data.rockets == 0 and data.spawnedOnce then
				RS.ensureHasRocket(data)
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
	}
	RS.players[playerLike.UserId] = data
	occupied[spawnIndex] = data

	playerLike:SetAttribute("SpawnIndex", spawnIndex)
	playerLike:SetAttribute("Money", 0)
	playerLike:SetAttribute("Income", 0)
	playerLike:SetAttribute("RocketCount", 1)
	playerLike:SetAttribute("ReadyRockets", 1)
	playerLike:SetAttribute("RocketTier", 1)
	playerLike:SetAttribute("TurretLevel", 0)
	playerLike:SetAttribute("TurretCount", 0)
	playerLike:SetAttribute("HasEnergySun", false)
	playerLike:SetAttribute("EnergySunCharge", 0)

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

	data.tier = 1
	data.earned = 0
	data.kills = 0

	local p = data.player
	if p.Parent then
		p:SetAttribute("Money", 0)
		p:SetAttribute("Income", 0)
		p:SetAttribute("RocketTier", 1)
		p:SetAttribute("TurretLevel", 0)
		p:SetAttribute("TurretCount", 0)
	end

	if data.spawnedOnce or data.bot then
		data.spawnedOnce = true
		local ok, err = pcall(RS.spawnRocketModel, data)
		if not ok then warn("[RocketSystem] resetBase:", err) end
	end
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
		local first = not data.spawnedOnce
		data.spawnedOnce = true
		task.wait(0.2)
		pcall(function()
			if character:WaitForChild("HumanoidRootPart", 5) then
				character:PivotTo(RS.spawnLocations[spawnIndex].CFrame + Vector3.new(0, 5, 0))
			end
		end)
		if first then
			local ok, err = pcall(RS.spawnRocketModel, data)
			if not ok then warn("[RocketSystem] Ошибка спавна ракеты:", err) end
		end
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