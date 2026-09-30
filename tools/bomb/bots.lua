local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

repeat task.wait() until _G.RocketSystem and _G.RocketSystem.Ready
local RS = _G.RocketSystem
RS.services = RS.services or {}
if RS.services.Bots then
	warn("[Bots] ❌ ДУБЛЬ! Отключён: " .. script:GetFullName())
	return
end
RS.services.Bots = script:GetFullName()
local Config = RS.Config

do
	local t0 = tick()
	while (not RS.launchSalvo or not RS.spawnTurret or not RS.spawnHeli or not RS.spawnEnergySun) and tick() - t0 < 20 do
		task.wait(0.5)
	end
	if not RS.launchSalvo then warn("[Bots] ⚠ FlightService не запустился") end
	if not RS.spawnTurret then warn("[Bots] ⚠ TurretService не запустился") end
	if not RS.spawnHeli then warn("[Bots] ⚠ HelicopterService не запустился") end
	if not RS.spawnEnergySun then warn("[Bots] ⚠ EnergySunService не запустился") end
end

-- ===================== КОНФИГ =====================
local BC = {
	FILL_TO = 4,
	MAX_BOTS = 3,
	SPAWN_DELAY = 6,
	THINK = 4,
	NEWBIE_GRACE = 120,
	ROUND_GRACE = 90,
	FIRST_BUY_DELAY = { 20, 40 },
	TURRET_MIN_TIME = 120,
	HELI_MIN_TIME = 240,
	HELI_MIN_ROCKETS = 4,
	HELI_SORTIE = { 50, 90 },
	HELI_REST = { 25, 60 },
	names = { "Альфа", "Браво", "Чарли", "Дельта", "Эхо", "Фокстрот" },
	difficulties = {
		{ name = "Новичок", emoji = "🟢", moneyMult = 0.8, income = 0.90, buyCooldown = { 30, 50 }, lead = 0, tierLead = 0, turretLead = 0,
			attackMin = 90, attackMax = 150, scatter = 14, maxRockets = 4, buyChance = 0.6, turretChance = 0.2, heliChance = 0.10, salvoMax = 2 },
		{ name = "Солдат",  emoji = "🟡", moneyMult = 1.0, income = 1.00, buyCooldown = { 20, 35 }, lead = 1, tierLead = 0, turretLead = 1,
			attackMin = 60, attackMax = 110, scatter = 9,  maxRockets = 6, buyChance = 0.75, turretChance = 0.5, heliChance = 0.30, salvoMax = 3 },
		{ name = "Ветеран", emoji = "🔴", moneyMult = 1.0, income = 1.15, buyCooldown = { 12, 25 }, lead = 2, tierLead = 1, turretLead = 1,
			attackMin = 45, attackMax = 80,  scatter = 5,  maxRockets = 8, buyChance = 0.9,  turretChance = 0.8, heliChance = 0.50, salvoMax = 4 },
	},
}

local botsFolder = ReplicatedStorage:FindFirstChild("RocketBots")
if not botsFolder then
	botsFolder = Instance.new("Folder")
	botsFolder.Name = "RocketBots"
	botsFolder.Parent = ReplicatedStorage
end

local bots = {}
local nextBotId = -1
local usedNames = {}
local roundStartedAt = tick()
local primeActive = false

-- ===================== ПСЕВДО-ИГРОК =====================
local function makeBotPlayer(name, userId)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder:SetAttribute("UserId", userId)
	folder:SetAttribute("IsBot", true)
	folder.Parent = botsFolder

	local proxy = setmetatable({}, {
		__index = function(_, k)
			if k == "Name" then return name
			elseif k == "UserId" then return userId
			elseif k == "Parent" then return folder.Parent
			elseif k == "Character" then return nil
			elseif k == "GetAttribute" then 
				return function(_, a) return folder:GetAttribute(a) end
			elseif k == "SetAttribute" then 
				return function(_, a, v) folder:SetAttribute(a, v) end
			end
			return nil
		end,
	})
	return proxy, folder
end

local function money(data)
	return data.player:GetAttribute("Money") or 0
end

local function setMoney(data, v)
	data.player:SetAttribute("Money", math.max(0, math.floor(v)))
end

local function rnd(range)
	return math.random(range[1], range[2])
end

local function humanStats()
	local any = false
	local maxR, maxTier, maxTur = 0, 0, 0
	for _, o in pairs(RS.players) do
		if not o.bot and o.player.Parent then
			any = true
			maxR = math.max(maxR, #o.rockets)
			maxTier = math.max(maxTier, o.tier or 0)
			maxTur = math.max(maxTur, #(o.turrets or {}))
		end
	end
	if not any then maxR = 1 end
	return maxR, maxTier, maxTur
end

-- ===================== ТАБЛИЧКА НАД БАЗОЙ =====================
local function makeSign(pad)
	local part = Instance.new("Part")
	part.Name = "BotSign"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = pad.Position + Vector3.new(0, 16, 0)
	part.Parent = Workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 300, 0, 64)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 600
	gui.Parent = part

	local function lbl(y, color)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0.5, 0)
		l.Position = UDim2.new(0, 0, y, 0)
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.TextStrokeTransparency = 0
		l.TextColor3 = color
		l.Parent = gui
		return l
	end

	return part, lbl(0, Color3.fromRGB(255, 170, 80)), lbl(0.5, Color3.fromRGB(230, 230, 230))
end

-- ===================== СПАВН / УДАЛЕНИЕ =====================
local function spawnBot()
	local idx = RS.getFreeSpawnIndex()
	if not idx then return end

	local diff = BC.difficulties[math.random(#BC.difficulties)]
	local shortName
	for _, n in ipairs(BC.names) do
		if not usedNames[n] then
			shortName = n
			break
		end
	end
	shortName = shortName or ("№" .. math.random(10, 99))
	usedNames[shortName] = true

	local uid = nextBotId
	nextBotId = nextBotId - 1
	local proxy, folder = makeBotPlayer("Наёмник " .. shortName, uid)
	folder:SetAttribute("Difficulty", diff.name)

	local data = RS.createData(proxy, idx, true)
	data.incomeMult = diff.income
	data.spawnedOnce = true

	local base = money(data)
	if base <= 0 then base = Config.StartMoney or 300 end
	local startMoney = math.floor(base * diff.moneyMult)

	local now = tick()
	local sign, l1, l2 = makeSign(RS.spawnLocations[idx])
	data.ai = {
		diff = diff,
		shortName = shortName,
		folder = folder,
		sign = sign,
		l1 = l1,
		l2 = l2,
		startMoney = startMoney,
		nextThink = now + math.random() * BC.THINK,
		nextBuy = now + rnd(BC.FIRST_BUY_DELAY),
		nextAttack = now + math.max(BC.ROUND_GRACE, math.random(diff.attackMin, diff.attackMax)),
		nextHeli = now + BC.HELI_MIN_TIME,
		heliRecallAt = 0,
		heliVictim = nil,
		prime = false,
		revengeTarget = nil,
	}
	setMoney(data, startMoney)
	-- как и у людей: бот начинает с нуля — сначала станция, потом завод

	bots[uid] = data
	l1.Text = ("🤖 %s"):format(proxy.Name)
	print(("[Bots] %s (%s) занял базу №%d"):format(proxy.Name, diff.name, idx))
	RS.broadcast(("🤖 %s (%s %s) занял базу №%d"):format(proxy.Name, diff.emoji, diff.name, idx), true)
end

function RS.removeBot(data)
	if not data or not data.bot then return end
	bots[data.userId] = nil
	if data.ai then
		if data.ai.sign then data.ai.sign:Destroy() end
		usedNames[data.ai.shortName] = nil
	end
	local folder = data.ai and data.ai.folder
	RS.removeData(data)
	if folder then folder:Destroy() end
	print("[Bots] Бот удалён:", data.player.Name)
end

local function occupiedCount()
	local n = 0
	for i = 1, 4 do
		if RS.occupied[i] then n = n + 1 end
	end
	return n
end

local function botCount()
	local n = 0
	for _ in pairs(bots) do n = n + 1 end
	return n
end

local function fill()
	while occupiedCount() < BC.FILL_TO and botCount() < BC.MAX_BOTS and RS.getFreeSpawnIndex() do
		spawnBot()
	end
end

-- ===================== ЭКОНОМИКА =====================
local function anyFlying(data)
	for _, m in ipairs(data.rockets) do
		if m:GetAttribute("Flying") then return true end
	end
	return false
end

local function economy(data, now)
	local ai = data.ai
	local d = data.ai.diff
	if now < ai.nextBuy then return end

	local function refreshBuy(delay)
		if type(delay) == "table" then
			ai.nextBuy = now + rnd(delay)
		else
			ai.nextBuy = now + (delay or rnd(d.buyCooldown))
		end
	end

	-- прайм-режим: ускоряем покупки
	if ai.prime then
		ai.nextBuy = now + 5
	end

	-- 1) энергия: если блэкаут или нет станций — строим электростанцию
	if data.blackout or RS.powerCountOf(data) == 0 then
		if (data.player:GetAttribute("Money") or 0) >= Config.Power.plantCost then
			local ok, err = RS.buyBuilding(data, "power")
			if ok then
				refreshBuy(d.buyCooldown)
				return
			end
		end
		if data.blackout then
			refreshBuy(4)
			return
		end
	end

	-- 2) завод
	if RS.factoryCountOf(data) == 0 then
		if (data.player:GetAttribute("Money") or 0) >= Config.Power.factoryCost then
			local ok = RS.buyBuilding(data, "factory")
			if ok then
				refreshBuy(d.buyCooldown)
				return
			end
		end
		refreshBuy(5)
		return
	end

	-- 3) строительство ракет
	local owned = #data.rockets
	local hR, hTier, hTur = humanStats()
	local sinceRound = now - roundStartedAt
	local rocketCap = math.min(d.maxRockets, hR + d.lead)
	local tierCap = hTier + d.tierLead
	local turretCap = math.min(Config.Turret and Config.Turret.maxCount or 0, hTur + d.turretLead)

	local primeRocketCap = d.maxRockets
	if ai.prime then primeRocketCap = math.min(d.maxRockets + 2, 10) end
	rocketCap = math.min(rocketCap + (ai.prime and 2 or 0), primeRocketCap)

	local active = data.construction ~= nil
	if not active and owned < rocketCap then
		local ok = RS.buyConstruction(data)
		if ok then
			refreshBuy(ai.prime and 5 or rnd(d.buyCooldown))
			return
		end
	end

	-- 4) спутник (нужен для атак)
	if not data.hasSatellite and owned >= 1
		and (data.player:GetAttribute("Money") or 0) >= Config.Power.satelliteCost + 200
		and math.random() < d.buyChance then
		local ok = RS.buyBuilding(data, "satellite")
		if ok then
			refreshBuy(d.buyCooldown)
			return
		end
	end

	-- 5) улучшение завода (новая версия ракет)
	local nxt = Config.Tiers[data.tier + 1]
	if nxt and data.tier < tierCap and owned >= math.min(d.maxRockets, 3) then
		local price = Config.getFactoryUpgradePrice(data.tier)
		if price and (data.player:GetAttribute("Money") or 0) >= price * 1.3 and math.random() < d.buyChance then
			local ok = RS.upgradeFactory(data)
			if ok then
				refreshBuy(d.buyCooldown)
				return
			end
		end
	end

	-- 6) вертолёт
	local HCfg = Config.Helicopter
	if RS.spawnHeli and HCfg and not data.heli and sinceRound >= BC.HELI_MIN_TIME
		and owned >= BC.HELI_MIN_ROCKETS and (data.player:GetAttribute("Money") or 0) >= HCfg.price * 1.15
		and math.random() < d.heliChance then
		local H, err = RS.spawnHeli(data)
		if H then
			data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) - HCfg.price)
			RS.broadcast(("🚁 %s купил вертолёт!"):format(data.player.Name), false)
			refreshBuy(d.buyCooldown)
			return
		end
	end

	-- 7) ПВО
	if RS.spawnTurret and RS.turretPrice and sinceRound >= BC.TURRET_MIN_TIME then
		data.turrets = data.turrets or {}
		local tCount = #data.turrets
		if tCount < turretCap and owned >= 3 + tCount * 2 then
			local price = RS.turretPrice(tCount)
			if (data.player:GetAttribute("Money") or 0) >= price * 1.3 and math.random() < d.turretChance * 0.5 then
				if data.turretLevel == 0 then data.turretLevel = 1 end
				if RS.spawnTurret(data) then
					data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) - price)
					data.player:SetAttribute("TurretLevel", data.turretLevel)
					refreshBuy(d.buyCooldown)
					return
				elseif tCount == 0 then
					data.turretLevel = 0
				end
			end
		end
		if tCount > 0 then
			local up = RS.turretUpgradePrice(data.turretLevel, tCount)
			if up and (data.player:GetAttribute("Money") or 0) >= up * 1.5 and math.random() < d.turretChance * 0.3 then
				data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) - up)
				data.turretLevel = data.turretLevel + 1
				data.player:SetAttribute("TurretLevel", data.turretLevel)
				RS.updateTurretBillboard(data)
				refreshBuy(d.buyCooldown)
				return
			end
		end
	end

	-- 8) Energy Sun
	if RS.spawnEnergySun and not data.energySun and owned >= 3
		and (data.player:GetAttribute("Money") or 0) >= 3000 and math.random() < 0.2 then
		local ok, err = RS.spawnEnergySun(data)
		if ok then
			data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) - 3000)
			data.player:SetAttribute("HasEnergySun", true)
			refreshBuy(d.buyCooldown)
			return
		end
	end

	-- обычный тик покупок
	refreshBuy(ai.prime and 5 or nil)
end

-- ===================== ЦЕЛИ =====================
local function pickVictim(data)
	local pool = {}
	for uid, other in pairs(RS.players) do
		if uid ~= data.userId and other.player.Parent and #other.rockets > 0
			and (other.bot or tick() - (other.joinedAt or 0) > BC.NEWBIE_GRACE) then

			-- Если есть цель мести — добавляем с большим весом
			if data.ai.revengeTarget and uid == data.ai.revengeTarget then
				for _ = 1, 5 do table.insert(pool, other) end
			else
				local w = other.bot and 1 or (#other.rockets <= 1 and 1 or 2)
				for _ = 1, w do table.insert(pool, other) end
			end
		end
	end
	if #pool == 0 then return nil end
	return pool[math.random(#pool)]
end

local function randomRocketHome(victim)
	local alive = {}
	for _, m in ipairs(victim.rockets) do
		if m.Parent then table.insert(alive, m) end
	end
	if #alive == 0 then return nil end
	return RS.getHome(alive[math.random(#alive)])
end

-- ===================== АТАКА РАКЕТАМИ =====================
local function readyRockets(data)
	local list = {}
	for _, m in ipairs(data.rockets) do
		if RS.isReady(m) then table.insert(list, m) end
	end
	return list
end

local function attack(data)
	if not RS.launchSalvo then return false end
	if not RS.hasSignal(data) then return false end -- нет спутника — нет сигнала
	if tick() - roundStartedAt < BC.ROUND_GRACE then return false end

	local ready = readyRockets(data)
	if #ready == 0 then return false end

	local victim = pickVictim(data)
	if not victim then return false end

	local d = data.ai.diff
	local aim

	-- В прайм-режиме бьем по самым слабым
	if data.ai.prime then
		local weakVictim
		local minRockets = 999
		for uid, other in pairs(RS.players) do
			if uid ~= data.userId and other.player.Parent and #other.rockets < minRockets then
				minRockets = #other.rockets
				weakVictim = other
			end
		end
		if weakVictim then victim = weakVictim end
	end

	local tHomes = {}
	for _, T in ipairs(victim.turrets or {}) do
		if T.model.Parent and T.home then table.insert(tHomes, T.home) end
	end

	if #tHomes > 0 and math.random() < 0.25 then
		aim = tHomes[math.random(#tHomes)]
	else
		aim = randomRocketHome(victim)
		if not aim then return false end
	end

	local a, r = math.random() * math.pi * 2, math.random() * d.scatter
	aim = aim + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)

	local maxSalvo = data.ai.prime and d.salvoMax + 2 or d.salvoMax
	if not victim.bot then
		maxSalvo = math.min(maxSalvo, math.max(1, #victim.rockets))
	end
	local count = math.random(1, math.min(#ready, maxSalvo))
	local list = {}
	for i = 1, count do list[i] = ready[i] end

	RS.msg(victim, ("⚠ %s запускает %d ракет по вашей базе!"):format(data.player.Name, count), false)
	task.spawn(RS.launchSalvo, data, list, aim)
	return true
end

-- ===================== ВЕРТОЛЁТ =================
local function heliLogic(data, now)
	local H = data.heli
	local ai = data.ai
	if not H or not RS.sendHeli then return end
	local st = H.state

	if st == "idle" then
		if now < ai.nextHeli or now - roundStartedAt < BC.ROUND_GRACE then return end
		local victim = pickVictim(data)
		local aim = victim and randomRocketHome(victim)
		if aim then
			aim = aim + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
			if RS.sendHeli(data, aim) then
				ai.heliVictim = victim
				ai.heliRecallAt = now + rnd(BC.HELI_SORTIE)
				RS.msg(victim, ("🚁 Вертолёт %s летит к вашей базе!"):format(data.player.Name), false)
			end
		end
		ai.nextHeli = now + 15
	elseif st == "hover" or st == "flying" then
		local v = ai.heliVictim
		local victimGone = not v or RS.players[v.userId] ~= v or #v.rockets == 0
		if now >= ai.heliRecallAt or victimGone then
			RS.recallHeli(data)
			ai.nextHeli = now + rnd(BC.HELI_REST)
			ai.heliVictim = nil
		elseif st == "hover" and math.random() < 0.15 then
			local aim = randomRocketHome(v)
			if aim then
				RS.sendHeli(data, aim + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8)))
			end
		end
	elseif st == "destroyed" then
		ai.nextHeli = now + 10
	end
end

-- ===================== ПРАЙМ-РЕЖИМ =====================
function RS.activatePrimeMode()
	if primeActive then return end
	primeActive = true
	for _, d in pairs(bots) do
		if d.ai then
			d.ai.prime = true
			d.ai.diff.attackMin = 20
			d.ai.diff.attackMax = 40
			d.ai.diff.buyChance = 1.0
			d.ai.diff.salvoMax = 6
			d.ai.nextBuy = tick()
			d.ai.nextAttack = tick() + 10
		end
	end
	RS.broadcast("🔥 Боты перешли в ПРАЙМ-РЕЖИМ!", true)
end

-- ===================== ГЛАВНЫЙ ЦИКЛ =====================
task.spawn(function()
	while true do
		task.wait(1)
		if #Players:GetPlayers() > 0 then
			local now = tick()

			-- Проверка на прайм-режим (последние 5 минут)
			local left = RS.round.endAt - now
			if left <= 300 and not primeActive then
				RS.activatePrimeMode()
			end

			for uid, data in pairs(bots) do
				if RS.players[uid] ~= data then
					bots[uid] = nil
				else
					local ai = data.ai
					if ai then
						if now >= ai.nextThink then
							ai.nextThink = now + BC.THINK + math.random() * 2
							local ok, err = pcall(economy, data, now)
							if not ok then warn("[Bots] economy:", err) end
						end

						if now >= ai.nextAttack then
							local ok, launched = pcall(attack, data)
							if not ok then warn("[Bots] attack:", launched) end
							ai.nextAttack = now + ((ok and launched) and math.random(ai.diff.attackMin, ai.diff.attackMax) or 10)
						end

						local okH, errH = pcall(heliLogic, data, now)
						if not okH then warn("[Bots] heli:", errH) end

						if ai.l2 then
							ai.l2.Text = ("%s %s  💰%d$  🚀%d  🛡%d  %s ⚔%d"):format(
								ai.diff.emoji,
								ai.diff.name,
								money(data),
								#data.rockets,
								#(data.turrets or {}),
								data.heli and "🚁" or "",
								data.kills or 0
							)
						end
					end
				end
			end
		end
	end
end)

table.insert(RS.roundResetHooks, function(data)
	roundStartedAt = tick()
	primeActive = false
	if not data.bot or not data.ai then return end
	local now = tick()
	local d = data.ai.diff
	setMoney(data, data.ai.startMoney)
	data.ai.nextBuy = now + rnd(BC.FIRST_BUY_DELAY)
	data.ai.nextAttack = now + math.max(BC.ROUND_GRACE, math.random(d.attackMin, d.attackMax))
	data.ai.nextHeli = now + BC.HELI_MIN_TIME
	data.ai.heliVictim = nil
	data.ai.prime = false
end)

task.delay(3, fill)
Players.PlayerRemoving:Connect(function()
	task.delay(BC.SPAWN_DELAY, fill)
end)

print("[Bots] ✅ Сервис наёмников готов")