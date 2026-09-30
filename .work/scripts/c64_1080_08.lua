local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage")

repeat task.wait() until _G.RocketSystem and _G.RocketSystem.Ready
local RS = _G.RocketSystem
RS.services = RS.services or {}
if RS.services.EnergySun then
	warn("[EnergySun] ❌ ДУБЛЬ! Отключён: " .. script:GetFullName())
	return
end
RS.services.EnergySun = script:GetFullName()

local Config = RS.Config
local remotes = RS.remotes

-- ===================== КОНФИГ =====================
local ESC = {
	MODEL_NAME = "Energy Sun",
	MUTATE_TIME = 120,
	CHARGE_RATE = 1,
	MAX_CHARGE = 100,
	ULTRA_CHARGE_TIME = 60,
	ULTRA_RADIUS = 60,
	PRICE = 10000,
}

Config.EnergySun = ESC

-- ===================== ДАННЫЕ =====================
local suns = {}

-- ===================== УТИЛИТЫ =====================
local function msg(p, text, ok)
	if typeof(p) == "Instance" and p.Parent then
		remotes.ShopMessage:FireClient(p, text, ok)
	end
end

local function money(p)
	return p:GetAttribute("Money") or 0
end

-- ===================== ПОИСК МОДЕЛИ =====================
local function findEnergySunTemplate()
	print("[EnergySun] 🔍 Ищу модель 'Energy Sun' в ServerStorage...")

	for _, obj in ipairs(ServerStorage:GetDescendants()) do
		if obj:IsA("Model") or obj:IsA("BasePart") then
			if obj.Name == "Energy Sun" then
				print("[EnergySun] ✅ Найдена модель 'Energy Sun'!")
				return obj
			end
		end
	end

	warn("[EnergySun] ❌ Модель 'Energy Sun' не найдена в ServerStorage!")
	print("[EnergySun] 📋 Список моделей в ServerStorage:")
	for _, obj in ipairs(ServerStorage:GetDescendants()) do
		if obj:IsA("Model") then
			print("[EnergySun]   - " .. obj.Name)
		end
	end

	return nil
end

-- ===================== СПАВН ENERGY SUN =====================
function RS.spawnEnergySun(data)
	if suns[data.userId] then 
		return false, "У вас уже есть Energy Sun" 
	end

	local template = findEnergySunTemplate()
	if not template then 
		return false, "Модель 'Energy Sun' не найдена в ServerStorage!" 
	end

	print("[EnergySun] 🚀 Создаю Energy Sun для " .. data.player.Name)

	local model = RS.prepareModel(template:Clone())
	if not model or not model.PrimaryPart then
		if model then model:Destroy() end
		return false, "Модель Energy Sun повреждена"
	end

	model.Name = "EnergySun_" .. data.player.Name
	model:SetAttribute("OwnerId", data.userId)
	RS.makeStatic(model, true)
	model.Parent = Workspace

	local pad = RS.spawnLocations[data.spawnIndex]
	if not pad then
		model:Destroy()
		return false, "Площадка не найдена"
	end

	local pos = pad.Position + Vector3.new(0, pad.Size.Y / 2 + 2, 0)
	model:PivotTo(CFrame.new(pos))

	local sun = {
		model = model,
		owner = data,
		charge = 0,
		mutating = false,
		mutationType = nil,
		mutatingRocket = nil,
		mutateStart = 0,
		ultraCharge = 0,
		target = nil,
		gui = nil,
		chargeLabel = nil,
		statusLabel = nil,
	}
	suns[data.userId] = sun
	data.energySun = sun
	data.player:SetAttribute("HasEnergySun", true)
	data.player:SetAttribute("EnergySunCharge", 0)

	-- BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "EnergySunUI"
	gui.Size = UDim2.new(0, 300, 0, 80)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = model.PrimaryPart

	local chargeLabel = Instance.new("TextLabel")
	chargeLabel.BackgroundTransparency = 1
	chargeLabel.Size = UDim2.new(1, 0, 0.5, 0)
	chargeLabel.Position = UDim2.new(0, 0, 0, 0)
	chargeLabel.Text = "⚡ Заряд: 0%"
	chargeLabel.Font = Enum.Font.GothamBold
	chargeLabel.TextScaled = true
	chargeLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	chargeLabel.Parent = gui

	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, 0, 0.5, 0)
	statusLabel.Position = UDim2.new(0, 0, 0.5, 0)
	statusLabel.Text = "🔄 Готов к мутации"
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.TextColor3 = Color3.fromRGB(120, 200, 255)
	statusLabel.Parent = gui

	sun.gui = gui
	sun.chargeLabel = chargeLabel
	sun.statusLabel = statusLabel

	msg(data.player, "☀️ Energy Sun установлена! Положите ракету внутрь для мутации.", true)
	print("[EnergySun] ✅ Energy Sun создана для " .. data.player.Name)
	return true, nil
end

-- ===================== МУТАЦИЯ =====================
function RS.startMutation(data, rocketModel)
	local sun = suns[data.userId]
	if not sun then 
		return false, "Нет Energy Sun" 
	end
	if sun.mutating then 
		return false, "Уже идет мутация" 
	end
	if sun.charge < 50 then 
		return false, "Недостаточно заряда (нужно 50%)" 
	end

	local found = false
	for _, m in ipairs(data.rockets) do
		if m == rocketModel and m.Parent then
			found = true
			break
		end
	end
	if not found then 
		return false, "Ракета не ваша или не существует" 
	end

	local dist = (rocketModel:GetPivot().Position - sun.model:GetPivot().Position).Magnitude
	if dist > 15 then 
		return false, "Ракета слишком далеко от Energy Sun (нужно < 15 м)" 
	end

	sun.mutating = true
	sun.mutatingRocket = rocketModel
	sun.mutateStart = tick()
	sun.statusLabel.Text = "🔄 Мутация... " .. ESC.MUTATE_TIME .. "с"
	sun.charge = sun.charge - 50
	data.player:SetAttribute("EnergySunCharge", sun.charge)

	msg(data.player, "🔬 Мутация началась! Ждите " .. ESC.MUTATE_TIME .. " секунд.", true)
	print("[EnergySun] 🌀 Мутация началась для " .. data.player.Name)

	task.delay(ESC.MUTATE_TIME, function()
		if suns[data.userId] ~= sun then return end
		if not sun.mutatingRocket or not sun.mutatingRocket.Parent then
			sun.mutating = false
			sun.statusLabel.Text = "❌ Мутация прервана"
			return
		end

		sun.mutating = false

		local types = {
			{ name = "nuclear", chance = 0.1, label = "💥 ЯДЕРНАЯ" },
			{ name = "electric", chance = 0.3, label = "⚡ ЭЛЕКТРИЧЕСКАЯ" },
			{ name = "tank", chance = 0.3, label = "🛡️ БРОНИРОВАННАЯ" },
			{ name = "speed", chance = 0.3, label = "💨 СКОРОСТНАЯ" },
		}

		local r = math.random()
		local cum = 0
		local chosenType = nil
		for _, t in ipairs(types) do
			cum = cum + t.chance
			if r <= cum then
				chosenType = t
				break
			end
		end

		if not chosenType then chosenType = types[2] end

		sun.mutationType = chosenType.name
		sun.statusLabel.Text = "✅ Готово: " .. chosenType.label

		local rocket = sun.mutatingRocket
		rocket:SetAttribute("Mutation", chosenType.name)
		rocket:SetAttribute("Mutated", true)
		rocket:SetAttribute("MutatedTime", tick())

		if chosenType.name == "nuclear" then
			rocket:SetAttribute("MutatedDamage", 200)
			rocket:SetAttribute("MutatedRadius", 55)
			msg(data.player, "💥 ЯДЕРНАЯ мутация! Огромный урон и замедление врагов!", true)
		elseif chosenType.name == "electric" then
			rocket:SetAttribute("MutatedDamage", 80)
			rocket:SetAttribute("MutatedRadius", 45)
			msg(data.player, "⚡ ЭЛЕКТРИЧЕСКАЯ мутация! Сбивает ПВО!", true)
		elseif chosenType.name == "tank" then
			rocket:SetAttribute("MaxHP", 1500)
			rocket:SetAttribute("HP", 1500)
			rocket:SetAttribute("MutatedArmor", 8)
			msg(data.player, "🛡️ БРОНИРОВАННАЯ мутация! Огромная прочность!", true)
		elseif chosenType.name == "speed" then
			rocket:SetAttribute("MutatedSpeed", 3.0)
			msg(data.player, "💨 СКОРОСТНАЯ мутация! В 3 раза быстрее!", true)
		end

		print("[EnergySun] ✅ Мутация завершена: " .. chosenType.name .. " для " .. data.player.Name)
		sun.mutatingRocket = nil
	end)

	return true, nil
end

-- ===================== УЛЬТРА-УДАР =====================
function RS.chargeUltra(data, targetPos)
	local sun = suns[data.userId]
	if not sun then 
		return false, "Нет Energy Sun" 
	end
	if sun.charge < 100 then 
		return false, "Нужен 100% заряд" 
	end
	if sun.ultraCharge > 0 then 
		return false, "Ультра-удар уже заряжается" 
	end

	sun.target = targetPos
	sun.ultraCharge = tick()
	sun.statusLabel.Text = "⚡ УЛЬТРА-УДАР заряжается..."
	sun.charge = 0
	data.player:SetAttribute("EnergySunCharge", 0)

	msg(data.player, "💥 Ультра-удар начал зарядку! " .. ESC.ULTRA_CHARGE_TIME .. "с", true)
	print("[EnergySun] ⚡ Ультра-удар заряжается для " .. data.player.Name)

	task.delay(ESC.ULTRA_CHARGE_TIME, function()
		if suns[data.userId] ~= sun then return end
		if not sun.target then return end

		sun.ultraCharge = 0

		local marker = Instance.new("Part")
		marker.Name = "UltraMarker"
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.Transparency = 0.5
		marker.Color = Color3.fromRGB(255, 255, 255)
		marker.Material = Enum.Material.Neon
		marker.Size = Vector3.new(4, 1, 4)
		marker.Position = sun.target
		marker.Parent = Workspace
		Debris:AddItem(marker, 5)

		task.wait(2)
		RS.ultraStrike(data, sun.target)
		sun.statusLabel.Text = "✅ Ультра-удар готов"
		sun.target = nil
		msg(data.player, "💥 Ультра-удар нанесён!", true)
		print("[EnergySun] 💥 Ультра-удар нанесён для " .. data.player.Name)
	end)

	return true, nil
end

-- ===================== ULTRA STRIKE =====================
function RS.ultraStrike(data, pos)
	print("[EnergySun] 💥 УЛЬТРА-УДАР по позиции " .. tostring(pos))

	local ex = Instance.new("Explosion")
	ex.Position = pos
	ex.BlastRadius = ESC.ULTRA_RADIUS
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.Parent = Workspace

	for uid, d in pairs(RS.players) do
		if uid ~= data.userId and d.player.Parent then
			local dist = (pos - RS.spawnLocations[d.spawnIndex].Position).Magnitude
			if dist < ESC.ULTRA_RADIUS then
				print("[EnergySun] 🎯 Попадание по " .. d.player.Name)

				remotes.UltraFlash:FireClient(d.player)

				local toDestroy = math.ceil(#d.rockets / 2)
				for i = 1, toDestroy do
					local m = d.rockets[i]
					if m and m.Parent then
						RS.destroyRocket(m)
					end
				end

				for _, T in ipairs(d.turrets or {}) do
					if RS.disableTurret then
						RS.disableTurret(T, 60)
					end
				end

				for _, m in ipairs(d.rockets) do
					if m and m.Parent then
						m:SetAttribute("CooldownEnd", tick() + 45)
					end
				end

				RS.msg(d, "⚡ Ультра-удар! Половина ракет уничтожена, ПВО сломано!", false)
			end
		end
	end
end

-- ===================== ОБНОВЛЕНИЕ =====================
RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.1)
	for userId, sun in pairs(suns) do
		if not sun.model.Parent then
			suns[userId] = nil
			if sun.owner then
				sun.owner.energySun = nil
				sun.owner.player:SetAttribute("HasEnergySun", false)
			end
			continue
		end

		if sun.charge < ESC.MAX_CHARGE and not sun.mutating and sun.ultraCharge == 0 then
			sun.charge = math.min(sun.charge + ESC.CHARGE_RATE * dt, ESC.MAX_CHARGE)
			if sun.owner and sun.owner.player.Parent then
				sun.owner.player:SetAttribute("EnergySunCharge", math.floor(sun.charge))
			end
		end

		if sun.chargeLabel then
			sun.chargeLabel.Text = string.format("⚡ Заряд: %.0f%%", sun.charge)
		end

		if sun.statusLabel then
			if sun.mutating then
				local left = math.max(0, ESC.MUTATE_TIME - (tick() - sun.mutateStart))
				sun.statusLabel.Text = "🔄 Мутация... " .. math.ceil(left) .. "с"
			elseif sun.ultraCharge > 0 then
				local left = math.max(0, ESC.ULTRA_CHARGE_TIME - (tick() - sun.ultraCharge))
				sun.statusLabel.Text = "⚡ Ультра-удар: " .. math.ceil(left) .. "с"
			elseif sun.mutationType then
				local labels = {
					nuclear = "💥 ЯДЕРНАЯ",
					electric = "⚡ ЭЛЕКТРИЧЕСКАЯ",
					tank = "🛡️ БРОНИРОВАННАЯ",
					speed = "💨 СКОРОСТНАЯ",
				}
				sun.statusLabel.Text = "✅ " .. (labels[sun.mutationType] or "Готово")
			else
				sun.statusLabel.Text = sun.charge >= 50 and "🔄 Готов к мутации" or "⚡ Заряжается..."
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local data = RS.players[player.UserId]
	if data and data.energySun then
		if data.energySun.model then
			data.energySun.model:Destroy()
		end
		suns[player.UserId] = nil
		data.energySun = nil
	end
end)

print("[EnergySun] ✅ Energy Sun Service готов")