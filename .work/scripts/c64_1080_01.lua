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

-- ===================== ПОКУПКА РАКЕТ =====================
remotes.BuyRocket.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end

	local owned = #data.rockets
	if owned >= Config.MAX_ROCKETS then
		msg(player, "Максимум ракет!", false)
		return
	end

	local price = Config.getExtraRocketPrice(data.tier, owned)
	if money(player) < price then
		msg(player, "Не хватает денег", false)
		return
	end

	player:SetAttribute("Money", money(player) - price)
	RS.addRocket(data)
	msg(player, "Куплена ракета №" .. #data.rockets, true)
end)

-- ===================== УЛУЧШЕНИЕ РАКЕТ =====================
remotes.UpgradeRocket.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end

	local nxt = Config.Tiers[data.tier + 1]
	if not nxt then
		msg(player, "Максимальный уровень!", false)
		return
	end

	if data.held then
		msg(player, "Сначала положите ракету", false)
		return
	end

	for _, m in ipairs(data.rockets) do
		if m:GetAttribute("Flying") then
			msg(player, "Дождитесь возвращения ракет", false)
			return
		end
	end

	local price = Config.getUpgradePrice(data.tier, #data.rockets)
	if money(player) < price then
		msg(player, "Не хватает денег", false)
		return
	end

	player:SetAttribute("Money", money(player) - price)
	data.tier = data.tier + 1
	player:SetAttribute("RocketTier", data.tier)
	RS.rebuildFleet(data)
	RS.refreshReady(data)
	msg(player, "Улучшено до " .. nxt.display .. "!", true)
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

print("[Shop] ✅ Магазин готов")