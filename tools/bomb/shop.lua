repeat task.wait() until _G.RocketSystem and _G.RocketSystem.Ready
local RS = _G.RocketSystem
RS.services = RS.services or {}
if RS.services.Shop then 
	warn("[Shop] ❌ ДУБЛЬ! Отключён: " .. script:GetFullName()) 
	return 
end
RS.services.Shop = script:GetFullName()

local Config = RS.Config
local remotes = RS.remotes

local function msg(player, text, ok)
	remotes.ShopMessage:FireClient(player, text, ok)
end

local function money(player)
	return player:GetAttribute("Money") or 0
end

-- ===================== ПОКУПКА РАКЕТЫ (СТРОИТЕЛЬСТВО) =====================
remotes.BuyRocket.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end

	local ok, err = RS.buyConstruction(data)
	if not ok then
		msg(player, "❌ " .. tostring(err), false)
	end
end)

-- ===================== УЛУЧШЕНИЕ ЗАВОДА (НОВАЯ ВЕРСИЯ РАКЕТ) =====================
local function handleUpgradeFactory(player)
	local data = RS.players[player.UserId]
	if not data then return end

	local ok, err = RS.upgradeFactory(data)
	if not ok then
		msg(player, "❌ " .. tostring(err), false)
	end
end

remotes.UpgradeRocket.OnServerEvent:Connect(handleUpgradeFactory)
if remotes:FindFirstChild("UpgradeFactory") then
	remotes.UpgradeFactory.OnServerEvent:Connect(handleUpgradeFactory)
end

-- ===================== ЭНЕРГИЯ: ЭЛЕКТРОСТАНЦИЯ / ЗАВОД / СПУТНИК =====================
remotes.BuyPowerPlant.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end
	local ok, err = RS.buyBuilding(data, "power")
	if not ok then msg(player, "❌ " .. tostring(err), false) end
end)

remotes.BuyFactory.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end
	local ok, err = RS.buyBuilding(data, "factory")
	if not ok then msg(player, "❌ " .. tostring(err), false) end
end)

remotes.BuySatellite.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end
	local ok, err = RS.buyBuilding(data, "satellite")
	if not ok then msg(player, "❌ " .. tostring(err), false) end
end)

-- ===================== ПОКУПКА ПВО =====================
remotes.BuyTurret.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end

	data.turrets = data.turrets or {}
	local owned = #data.turrets
	if owned >= Config.Turret.maxCount then
		msg(player, "Максимум ПВО!", false)
		return
	end

	local price = RS.turretPrice(owned)
	if money(player) < price then
		msg(player, "Не хватает денег", false)
		return
	end

	if data.turretLevel == 0 then data.turretLevel = 1 end

	if not RS.spawnTurret(data) then
		if owned == 0 then data.turretLevel = 0 end
		msg(player, "Модель ПВО не найдена", false)
		return
	end

	player:SetAttribute("Money", money(player) - price)
	player:SetAttribute("TurretLevel", data.turretLevel)
	msg(player, ("ПВО №%d установлено!"):format(#data.turrets), true)
end)

-- ===================== УЛУЧШЕНИЕ ПВО =====================
remotes.UpgradeTurret.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data or data.turretLevel == 0 or #(data.turrets or {}) == 0 then return end

	local price = RS.turretUpgradePrice(data.turretLevel, #data.turrets)
	if not price then
		msg(player, "ПВО прокачано максимально!", false)
		return
	end

	if money(player) < price then
		msg(player, "Не хватает денег", false)
		return
	end

	player:SetAttribute("Money", money(player) - price)
	data.turretLevel = data.turretLevel + 1
	player:SetAttribute("TurretLevel", data.turretLevel)
	RS.updateTurretBillboard(data)
	msg(player, ("Все ПВО улучшены до ур.%d"):format(data.turretLevel), true)
end)

-- ===================== ПОКУПКА ВЕРТОЛЁТА =====================
remotes.BuyHelicopter.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end

	if data.heli then
		msg(player, "Вертолёт уже куплен", false)
		return
	end

	if money(player) < 6000 then
		msg(player, "Не хватает денег (нужно 6000$)", false)
		return
	end

	if not RS.spawnHeli then
		msg(player, "❌ Сервис вертолёта не запущен", false)
		return
	end

	local H, err = RS.spawnHeli(data)
	if not H then
		msg(player, "❌ " .. tostring(err), false)
		return
	end

	player:SetAttribute("Money", money(player) - 6000)
	msg(player, "🚁 Вертолёт куплен! Нажмите «ОТПРАВИТЬ ВЕРТОЛЁТ» и выберите точку", true)
end)

-- ===================== ПОКУПКА ENERGY SUN =====================
remotes.BuyEnergySun.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end

	if data.energySun then
		msg(player, "У вас уже есть Energy Sun", false)
		return
	end

	if money(player) < 10000 then
		msg(player, "Не хватает денег (нужно 10000$)", false)
		return
	end

	if not RS.spawnEnergySun then
		msg(player, "❌ Сервис Energy Sun не запущен", false)
		return
	end

	local ok, err = RS.spawnEnergySun(data)
	if not ok then
		msg(player, "❌ " .. tostring(err), false)
		return
	end

	player:SetAttribute("Money", money(player) - 10000)
	msg(player, "☀️ Energy Sun установлена! Цена: 10000$", true)
end)

-- ===================== РЕМОНТ =====================
remotes.StartRepair.OnServerEvent:Connect(function(player, model)
	if typeof(model) ~= "Instance" then return end
	local data = RS.players[player.UserId]
	if not data then return end

	local ok, err = RS.startRepair(data, model)
	if not ok then
		msg(player, "❌ " .. tostring(err), false)
	end
end)

-- ===================== МУТАЦИЯ =====================
remotes.StartMutation.OnServerEvent:Connect(function(player, rocketModel)
	if typeof(rocketModel) ~= "Instance" then return end
	local data = RS.players[player.UserId]
	if not data then return end

	local ok, err = RS.startMutation(data, rocketModel)
	if not ok then
		msg(player, "❌ " .. tostring(err), false)
	end
end)

-- ===================== УЛЬТРА-УДАР =====================
remotes.ChargeUltra.OnServerEvent:Connect(function(player, pos)
	if typeof(pos) ~= "Vector3" then return end
	local data = RS.players[player.UserId]
	if not data then return end

	local ok, err = RS.chargeUltra(data, pos)
	if not ok then
		msg(player, "❌ " .. tostring(err), false)
	end
end)

-- ===================== СОЮЗЫ И ВОЙНЫ (СЕРВЕР) =====================
-- Раньше этот код лежал в LocalScript и никогда не выполнялся — теперь он здесь.

local alliances = RS.alliances or {}
local wars = RS.wars or {}
RS.alliances = alliances
RS.wars = wars

local function allianceOf(userId)
	for id, a in pairs(alliances) do
		if a.members[userId] then return a, id end
	end
	return nil, nil
end

-- список игроков для окна союзов (игрок сам запрашивает через InvokeServer)
remotes.GetPlayersList.OnServerInvoke = function(player)
	local list = {}
	for _, d in pairs(RS.players) do
		if d.player.Parent then
			table.insert(list, {
				userId = d.userId,
				name = d.player.Name,
				isBot = d.bot or false,
				inAlliance = allianceOf(d.userId) ~= nil,
			})
		end
	end
	return list
end

remotes.CreateAlliance.OnServerEvent:Connect(function(player, targetId)
	local data = RS.players[player.UserId]
	local target = RS.players[targetId]
	if not data or not target then
		RS.msg(data, "Игрок не найден", false)
		return
	end

	if data.userId == target.userId then
		RS.msg(data, "Нельзя вступить в союз с самим собой", false)
		return
	end

	if allianceOf(data.userId) or allianceOf(target.userId) then
		RS.msg(data, "Кто-то уже состоит в союзе", false)
		return
	end

	local id = #alliances + 1
	alliances[id] = {
		members = {
			[data.userId] = true,
			[target.userId] = true,
		},
		leader = data.userId,
		created = tick(),
		betrayals = {},
	}

	data.allianceId = id
	target.allianceId = id

	RS.msg(data, "🤝 Союз создан с " .. target.player.Name, true)
	RS.msg(target, "🤝 " .. data.player.Name .. " создал союз с вами", true)
	RS.broadcast("🤝 " .. data.player.Name .. " и " .. target.player.Name .. " создали союз!", true)
end)

remotes.DeclareWar.OnServerEvent:Connect(function(player, targetId)
	local data = RS.players[player.UserId]
	local target = RS.players[targetId]
	if not data or not target then
		RS.msg(data, "Игрок не найден", false)
		return
	end

	if data.userId == target.userId then
		RS.msg(data, "Нельзя объявлять войну самому себе", false)
		return
	end

	local a = allianceOf(data.userId)
	if a and a.members[target.userId] then
		RS.msg(data, "Нельзя объявлять войну союзнику! Сначала предайте союз", false)
		return
	end

	-- война может уже идти
	for _, w in pairs(wars) do
		if not w.ended and ((w.attacker == data.userId and w.defender == target.userId)
			or (w.attacker == target.userId and w.defender == data.userId)) then
			RS.msg(data, "Война с этим игроком уже идёт!", false)
			return
		end
	end

	local warId = #wars + 1
	wars[warId] = {
		attacker = data.userId,
		defender = target.userId,
		started = tick(),
		ended = false,
	}

	RS.msg(data, "⚔️ Вы объявили войну " .. target.player.Name, true)
	RS.msg(target, "⚔️ " .. data.player.Name .. " объявил вам войну!", false)
	RS.broadcast("⚔️ " .. data.player.Name .. " объявил войну " .. target.player.Name .. "!", false)

	if target.bot and target.ai then
		target.ai.nextAttack = tick() + 10
		target.ai.revengeTarget = data.userId
	end
end)

remotes.BetrayAlliance.OnServerEvent:Connect(function(player)
	local userId = player.UserId
	local data = RS.players[userId]
	local a, id = allianceOf(userId)

	if not a then
		RS.msg(data, "Вы не состоите в союзе", false)
		return
	end

	a.betrayals[userId] = (a.betrayals[userId] or 0) + 1
	a.members[userId] = nil
	if data then
		data.allianceId = nil
	end

	if a.leader == userId then
		alliances[id] = nil
		RS.broadcast("💔 Союз распался из-за предательства лидера!", false)
	else
		for uid, d in pairs(RS.players) do
			if d.bot and a.members[uid] and d.ai then
				d.ai.revengeTarget = userId
				d.ai.nextAttack = tick() + 5
				RS.msg(d, "😡 " .. player.Name .. " предал союз! Мстим!", false)
			end
		end
		RS.msg(data, "Вы предали союз! Боты-союзники будут мстить", false)
		RS.broadcast("💔 " .. player.Name .. " предал союз!", false)
	end
end)

-- проверка победы в войнах: у кого больше уничтоженных ракет
task.spawn(function()
	while true do
		task.wait(2)
		for _, war in pairs(wars) do
			if not war.ended then
				local attacker = RS.players[war.attacker]
				local defender = RS.players[war.defender]

				if not attacker or not defender then
					war.ended = true
				elseif attacker.kills - defender.kills > 5 then
					war.ended = true
					RS.broadcast("⚔️ " .. attacker.player.Name .. " победил в войне с " .. defender.player.Name, true)
					RS.msg(attacker, "🏆 Вы победили в войне!", true)
					RS.msg(defender, "💀 Вы проиграли войну!", false)
				elseif defender.kills - attacker.kills > 5 then
					war.ended = true
					RS.broadcast("⚔️ " .. defender.player.Name .. " победил в войне с " .. attacker.player.Name, true)
					RS.msg(defender, "🏆 Вы победили в войне!", true)
					RS.msg(attacker, "💀 Вы проиграли войну!", false)
				end
			end
		end
	end
end)

print("[Shop] ✅ Магазин готов")