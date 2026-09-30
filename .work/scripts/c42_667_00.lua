local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function corner(o, r)
	mk("UICorner", { CornerRadius = UDim.new(0, r or 12) }, o)
end

local function label(parent, props)
	local base = {
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = ""
	}
	for k, v in pairs(props) do base[k] = v end
	return mk("TextLabel", base, parent)
end

local function button(parent, props)
	local base = {
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		BorderSizePixel = 0
	}
	for k, v in pairs(props) do base[k] = v end
	local b = mk("TextButton", base, parent)
	corner(b)
	return b
end

local function attr(n, d)
	local v = player:GetAttribute(n)
	if v == nil then return d end
	return v
end

local ACTIVE_TAB = Color3.fromRGB(60, 130, 220)
local INACTIVE_TAB = Color3.fromRGB(70, 70, 80)
local GREY = Color3.fromRGB(110, 110, 110)

-- ===================== 1. GUI =====================
local screenGui = mk("ScreenGui", { Name = "RocketGui", ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))

-- HUD
local hud = mk("Frame", {
	Size = UDim2.new(0, 290, 0, 228),
	Position = UDim2.new(0, 20, 0, 20),
	BackgroundColor3 = Color3.fromRGB(20, 20, 25),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0
}, screenGui)
corner(hud)
mk("UIStroke", { Color = Color3.fromRGB(85, 255, 127), Thickness = 2 }, hud)

local moneyLabel = label(hud, {
	Size = UDim2.new(1, -20, 0, 38),
	Position = UDim2.new(0, 10, 0, 5),
	TextColor3 = Color3.fromRGB(85, 255, 127),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "💰 0$"
})

local incomeLabel = label(hud, {
	Size = UDim2.new(1, -20, 0, 24),
	Position = UDim2.new(0, 10, 0, 43),
	TextColor3 = Color3.fromRGB(180, 255, 200),
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left
})

local fleetLabel = label(hud, {
	Size = UDim2.new(1, -20, 0, 28),
	Position = UDim2.new(0, 10, 0, 70),
	TextColor3 = Color3.fromRGB(255, 200, 80),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Загрузка..."
})

local readyLabel = label(hud, {
	Size = UDim2.new(1, -20, 0, 26),
	Position = UDim2.new(0, 10, 0, 100),
	TextColor3 = Color3.fromRGB(120, 255, 140),
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left
})

local turretLabel = label(hud, {
	Size = UDim2.new(1, -20, 0, 28),
	Position = UDim2.new(0, 10, 0, 130),
	TextColor3 = Color3.fromRGB(120, 200, 255),
	TextXAlignment = Enum.TextXAlignment.Left
})

local heliLabel = label(hud, {
	Size = UDim2.new(1, -20, 0, 28),
	Position = UDim2.new(0, 10, 0, 162),
	TextColor3 = Color3.fromRGB(150, 220, 255),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "🚁 Вертолёт: нет"
})

local sunStatusLabel = label(hud, {
	Size = UDim2.new(1, -20, 0, 28),
	Position = UDim2.new(0, 10, 0, 194),
	TextColor3 = Color3.fromRGB(255, 200, 50),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "☀️ Energy Sun: нет",
	Font = Enum.Font.Gotham,
	TextScaled = false,
	TextSize = 14
})

-- Кнопки слева
local shopButton = button(screenGui, {
	Size = UDim2.new(0, 180, 0, 50),
	Position = UDim2.new(0, 20, 0, 255),
	BackgroundColor3 = Color3.fromRGB(255, 170, 30),
	Text = "🛒 МАГАЗИН"
})

local turretPlaceButton = button(screenGui, {
	Size = UDim2.new(0, 180, 0, 44),
	Position = UDim2.new(0, 20, 0, 312),
	BackgroundColor3 = Color3.fromRGB(60, 130, 220),
	Text = "📍 ПЕРЕСТАВИТЬ ПВО",
	Visible = false
})

local heliSendButton = button(screenGui, {
	Size = UDim2.new(0, 180, 0, 44),
	Position = UDim2.new(0, 20, 0, 363),
	BackgroundColor3 = Color3.fromRGB(40, 160, 230),
	Text = "🚁 ОТПРАВИТЬ ВЕРТОЛЁТ",
	Visible = false
})

local heliRecallButton = button(screenGui, {
	Size = UDim2.new(0, 180, 0, 44),
	Position = UDim2.new(0, 20, 0, 414),
	BackgroundColor3 = Color3.fromRGB(120, 120, 140),
	Text = "🏠 ВЕРНУТЬ ВЕРТОЛЁТ",
	Visible = false
})

local sunButton = button(screenGui, {
	Size = UDim2.new(0, 180, 0, 44),
	Position = UDim2.new(0, 20, 0, 465),
	BackgroundColor3 = Color3.fromRGB(255, 200, 50),
	Text = "☀️ ENERGY SUN",
	Visible = false
})

local mutateButton = button(screenGui, {
	Size = UDim2.new(0, 180, 0, 40),
	Position = UDim2.new(0, 20, 0, 516),
	BackgroundColor3 = Color3.fromRGB(150, 80, 220),
	Text = "🌀 МУТИРОВАТЬ",
	Visible = false
})

local ultraButton = button(screenGui, {
	Size = UDim2.new(0, 180, 0, 40),
	Position = UDim2.new(0, 20, 0, 563),
	BackgroundColor3 = Color3.fromRGB(255, 60, 60),
	Text = "💥 УЛЬТРА-УДАР",
	Visible = false
})

local repairButton = button(screenGui, {
	Size = UDim2.new(0, 180, 0, 44),
	Position = UDim2.new(1, -200, 0, 20),
	BackgroundColor3 = Color3.fromRGB(60, 180, 60),
	Text = "🔧 ЧИНИТЬ",
	Visible = false
})

-- Кнопки СОЮЗОВ (справа сверху)
local allianceButton = button(screenGui, {
	Size = UDim2.new(0, 160, 0, 40),
	Position = UDim2.new(1, -180, 0, 20),
	BackgroundColor3 = Color3.fromRGB(60, 180, 220),
	Text = "🤝 СОЮЗЫ",
	Visible = true
})

local declareWarButton = button(screenGui, {
	Size = UDim2.new(0, 160, 0, 40),
	Position = UDim2.new(1, -180, 0, 70),
	BackgroundColor3 = Color3.fromRGB(220, 60, 60),
	Text = "⚔️ ВОЙНА",
	Visible = true
})

-- ===================== МАГАЗИН =====================
local shop = mk("Frame", {
	Size = UDim2.new(0, 580, 0, 520),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(20, 20, 25),
	Visible = false
}, screenGui)
corner(shop, 16)
mk("UIStroke", { Color = Color3.fromRGB(255, 170, 30), Thickness = 2 }, shop)

label(shop, {
	Size = UDim2.new(1, -60, 0, 45),
	Position = UDim2.new(0, 15, 0, 8),
	Text = "🛒 МАГАЗИН",
	TextColor3 = Color3.fromRGB(255, 170, 30),
	TextXAlignment = Enum.TextXAlignment.Left
})

local closeBtn = button(shop, {
	Size = UDim2.new(0, 34, 0, 34),
	Position = UDim2.new(1, -44, 0, 12),
	BackgroundColor3 = Color3.fromRGB(220, 60, 60),
	Text = "✕"
})

-- Вкладки (4 штуки)
local tabRockets = button(shop, {
	Size = UDim2.new(0, 130, 0, 40),
	Position = UDim2.new(0, 15, 0, 60),
	BackgroundColor3 = ACTIVE_TAB,
	Text = "🚀 РАКЕТЫ"
})

local tabTurret = button(shop, {
	Size = UDim2.new(0, 130, 0, 40),
	Position = UDim2.new(0, 155, 0, 60),
	BackgroundColor3 = INACTIVE_TAB,
	Text = "🛡 ПВО"
})

local tabHeli = button(shop, {
	Size = UDim2.new(0, 130, 0, 40),
	Position = UDim2.new(0, 295, 0, 60),
	BackgroundColor3 = INACTIVE_TAB,
	Text = "🚁 ВЕРТОЛЁТ"
})

local tabEnergy = button(shop, {
	Size = UDim2.new(0, 130, 0, 40),
	Position = UDim2.new(0, 435, 0, 60),
	BackgroundColor3 = INACTIVE_TAB,
	Text = "☀️ ENERGY"
})

-- Страницы
local pageRockets = mk("Frame", {
	Size = UDim2.new(1, -30, 1, -170),
	Position = UDim2.new(0, 15, 0, 110),
	BackgroundTransparency = 1
}, shop)

local pageTurret = mk("Frame", {
	Size = UDim2.new(1, -30, 1, -170),
	Position = UDim2.new(0, 15, 0, 110),
	BackgroundTransparency = 1,
	Visible = false
}, shop)

local pageHeli = mk("Frame", {
	Size = UDim2.new(1, -30, 1, -170),
	Position = UDim2.new(0, 15, 0, 110),
	BackgroundTransparency = 1,
	Visible = false
}, shop)

local pageEnergy = mk("Frame", {
	Size = UDim2.new(1, -30, 1, -170),
	Position = UDim2.new(0, 15, 0, 110),
	BackgroundTransparency = 1,
	Visible = false
}, shop)

-- Страница РАКЕТЫ
local curInfo = label(pageRockets, {
	Size = UDim2.new(1, 0, 0, 90),
	Font = Enum.Font.Gotham,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top
})

local buyRocketBtn = button(pageRockets, {
	Size = UDim2.new(1, 0, 0, 48),
	Position = UDim2.new(0, 0, 0, 95),
	BackgroundColor3 = Color3.fromRGB(60, 200, 90)
})

local nextInfo = label(pageRockets, {
	Size = UDim2.new(1, 0, 0, 90),
	Position = UDim2.new(0, 0, 0, 152),
	Font = Enum.Font.Gotham,
	TextWrapped = true,
	TextColor3 = Color3.fromRGB(255, 220, 140),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top
})

local upgradeBtn = button(pageRockets, {
	Size = UDim2.new(1, 0, 0, 48),
	Position = UDim2.new(0, 0, 0, 245),
	BackgroundColor3 = Color3.fromRGB(255, 170, 30)
})

-- Страница ПВО
local turretInfo = label(pageTurret, {
	Size = UDim2.new(1, 0, 0, 200),
	Font = Enum.Font.Gotham,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top
})

local turretBtn = button(pageTurret, {
	Size = UDim2.new(1, 0, 0, 48),
	Position = UDim2.new(0, 0, 0, 210),
	BackgroundColor3 = Color3.fromRGB(60, 130, 220)
})

local turretUpBtn = button(pageTurret, {
	Size = UDim2.new(1, 0, 0, 48),
	Position = UDim2.new(0, 0, 0, 266),
	BackgroundColor3 = Color3.fromRGB(255, 170, 30),
	Visible = false
})

-- Страница ВЕРТОЛЁТ
local heliInfo = label(pageHeli, {
	Size = UDim2.new(1, 0, 0, 240),
	Font = Enum.Font.Gotham,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top
})

local heliBtn = button(pageHeli, {
	Size = UDim2.new(1, 0, 0, 55),
	Position = UDim2.new(0, 0, 0, 250),
	BackgroundColor3 = Color3.fromRGB(40, 160, 230)
})

-- Страница ENERGY SUN
local energyInfo = label(pageEnergy, {
	Size = UDim2.new(1, 0, 0, 270),
	Font = Enum.Font.Gotham,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "☀️ ENERGY SUN\n\n" ..
		"💰 Цена: 10,000$\n\n" ..
		"⚡ Заряжает энергией до 100%\n\n" ..
		"🔄 МУТАЦИЯ РАКЕТ (4 типа):\n" ..
		"  • 💥 ЯДЕРНАЯ — мощный взрыв, замедляет доход врагов\n" ..
		"  • ⚡ ЭЛЕКТРИЧЕСКАЯ — сбивает ПВО\n" ..
		"  • 🛡️ БРОНИРОВАННАЯ — +HP и броня\n" ..
		"  • 💨 СКОРОСТНАЯ — в 3 раза быстрее\n\n" ..
		"💥 УЛЬТРА-УДАР при 100% заряде:\n" ..
		"  • Уничтожает половину ракет врага\n" ..
		"  • Отключает ПВО на 60 секунд\n" ..
		"  • Ставит КД на все ракеты\n\n" ..
		"📌 Чтобы использовать:\n" ..
		"  1. Подойдите к Energy Sun с ракетой\n" ..
		"  2. Нажмите «МУТИРОВАТЬ»\n" ..
		"  3. Ждите 2 минуты"
})

local energyBtn = button(pageEnergy, {
	Size = UDim2.new(1, 0, 0, 55),
	Position = UDim2.new(0, 0, 0, 280),
	BackgroundColor3 = Color3.fromRGB(255, 200, 50)
})

local shopMsg = label(shop, {
	Size = UDim2.new(1, -30, 0, 36),
	Position = UDim2.new(0, 15, 1, -48),
	Font = Enum.Font.Gotham
})

-- Переключение вкладок
local function setTab(idx)
	pageRockets.Visible = idx == 1
	pageTurret.Visible = idx == 2
	pageHeli.Visible = idx == 3
	pageEnergy.Visible = idx == 4
	tabRockets.BackgroundColor3 = idx == 1 and ACTIVE_TAB or INACTIVE_TAB
	tabTurret.BackgroundColor3 = idx == 2 and ACTIVE_TAB or INACTIVE_TAB
	tabHeli.BackgroundColor3 = idx == 3 and ACTIVE_TAB or INACTIVE_TAB
	tabEnergy.BackgroundColor3 = idx == 4 and ACTIVE_TAB or INACTIVE_TAB
end

tabRockets.MouseButton1Click:Connect(function() setTab(1) end)
tabTurret.MouseButton1Click:Connect(function() setTab(2) end)
tabHeli.MouseButton1Click:Connect(function() setTab(3) end)
tabEnergy.MouseButton1Click:Connect(function() setTab(4) end)

-- Нижняя панель
local buttonsFrame = mk("Frame", {
	Size = UDim2.new(0, 520, 0, 160),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -30),
	BackgroundTransparency = 1,
	Visible = false
}, screenGui)

local qFrame = mk("Frame", {
	Size = UDim2.new(0, 260, 0, 60),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	BackgroundColor3 = Color3.fromRGB(20, 20, 25),
	BackgroundTransparency = 0.1
}, buttonsFrame)
corner(qFrame)

local minusBtn = button(qFrame, {
	Size = UDim2.new(0, 50, 0, 50),
	Position = UDim2.new(0, 5, 0, 5),
	BackgroundColor3 = Color3.fromRGB(220, 60, 60),
	Text = "-"
})

local plusBtn = button(qFrame, {
	Size = UDim2.new(0, 50, 0, 50),
	Position = UDim2.new(0, 205, 0, 5),
	BackgroundColor3 = Color3.fromRGB(60, 200, 90),
	Text = "+"
})

local qLabel = label(qFrame, {
	Size = UDim2.new(0, 140, 0, 50),
	Position = UDim2.new(0, 60, 0, 5),
	Text = "1"
})

local selectedQuantity = 1
local function clampQ()
	local maxReady = math.max(attr("ReadyRockets", 1), 1)
	selectedQuantity = math.clamp(selectedQuantity, 1, maxReady)
	qLabel.Text = ("%d / %d"):format(selectedQuantity, maxReady)
end

minusBtn.MouseButton1Click:Connect(function()
	selectedQuantity = selectedQuantity - 1
	clampQ()
end)

plusBtn.MouseButton1Click:Connect(function()
	selectedQuantity = selectedQuantity + 1
	clampQ()
end)

local holder = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 80),
	Position = UDim2.new(0, 0, 0, 75),
	BackgroundTransparency = 1
}, buttonsFrame)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 15)
}, holder)

local function bigBtn(text, color)
	local b = button(holder, {
		Size = UDim2.new(0, 160, 0, 66),
		BackgroundColor3 = color,
		Text = text
	})
	mk("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.5 }, b)
	b.MouseEnter:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.15), { Size = UDim2.new(0, 168, 0, 72) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.15), { Size = UDim2.new(0, 160, 0, 66) }):Play()
	end)
	return b
end

local launchButton = bigBtn("🚀 ЗАПУСТИТЬ", Color3.fromRGB(220, 60, 60))
local placeButton = bigBtn("📍 ПОСТАВИТЬ", Color3.fromRGB(60, 200, 90))
local throwButton = bigBtn("📦 БРОСИТЬ", Color3.fromRGB(60, 130, 220))

shopButton.MouseButton1Click:Connect(function()
	shop.Visible = not shop.Visible
end)

closeBtn.MouseButton1Click:Connect(function()
	shop.Visible = false
end)

print("[RocketClient] GUI создан")

-- ===================== 2. РЕМОУТЫ + КОНФИГ =====================
local remotes = ReplicatedStorage:WaitForChild("RocketRemotes", 30)
if not remotes then
	fleetLabel.Text = "❌ Сервер не запустился"
	return
end

local R = {}
for _, n in ipairs({
	"RequestLaunch", "RequestThrow", "SetTarget", "RocketStateChanged",
	"CameraFollowStart", "CameraFollowUpdate", "CameraFollowEnd",
	"BuyRocket", "UpgradeRocket", "BuyTurret", "UpgradeTurret", "ShopMessage",
	"PlaceRocket", "PlaceTurret", "GetConfig",
	"BuyHelicopter", "SendHelicopter", "RecallHelicopter", "GetHeliConfig",
	"BuyEnergySun", "StartMutation", "ChargeUltra", "UltraFlash",
	"StartRepair", "CreateAlliance", "DeclareWar", "BetrayAlliance", "GetPlayersList"
	}) do
	R[n] = remotes:WaitForChild(n, 15)
	if not R[n] then
		warn("[RocketClient] ❌ Ремоут '" .. n .. "' не найден")
	end
end

local Config = R.GetConfig and R.GetConfig:InvokeServer()
if not Config then
	fleetLabel.Text = "❌ Конфиг не получен"
	return
end

local HC
if R.GetHeliConfig then
	for _ = 1, 10 do
		HC = R.GetHeliConfig:InvokeServer()
		if HC then break end
		task.wait(1)
	end
end

print("[RocketClient] Конфиг получен")

local INCOME_MULT = Config.INCOME_MULT or 1

local function getExtraRocketPrice(tierIndex, owned)
	return Config.Tiers[tierIndex].price + (owned - 1) * 150
end

local function getUpgradePrice(tierIndex, count)
	local nxt = Config.Tiers[tierIndex + 1]
	return nxt and nxt.price * count or nil
end

-- ===================== 3. ОБНОВЛЕНИЕ ИНТЕРФЕЙСА =====================
local function tierStats(t)
	local inc = math.floor(t.income * INCOME_MULT + 0.5)
	return ("Доход: %d$/с за ракету   Скорость: x%.2f\nУрон: %d   Радиус: %d\nHP: %d   Броня: %d%%   Уклонение от ПВО: %d%%")
		:format(inc, t.speed, t.damage, t.radius, t.hp, t.resist * 100, t.evasion * 100)
end

local function priceBtn(btn, text, price, okColor)
	btn.Text = text .. " — " .. price .. "$"
	btn.BackgroundColor3 = attr("Money", 0) >= price and okColor or GREY
end

local HELI_STATE = {
	none = "нет",
	idle = "на базе",
	takeoff = "взлетает",
	flying = "в полёте",
	hover = "на позиции",
	returning = "возвращается",
	falling = "падает!",
	destroyed = "сбит"
}

local function heliStatusText()
	if not attr("HeliOwned", false) then return "🚁 Вертолёт: нет" end
	local st = attr("HeliState", "idle")
	if st == "destroyed" then
		local left = math.max(0, math.ceil(attr("HeliCooldownEnd", 0) - Workspace:GetServerTimeNow()))
		return ("🚁 Сбит — ⏳ %d:%02d"):format(left // 60, left % 60)
	end
	return ("🚁 %s   🛡%d   🚀%d"):format(HELI_STATE[st] or st, attr("HeliArmor", 0), attr("HeliAmmo", 0))
end

local selectedRocket = nil
local selectedPlayer = nil

local function getSelectedRocket()
	return selectedRocket
end

-- Функция layoutSideButtons
local function layoutSideButtons()
	local y = 312
	for _, b in ipairs({ turretPlaceButton, heliSendButton, heliRecallButton, sunButton, mutateButton, ultraButton }) do
		if b.Visible then
			b.Position = UDim2.new(0, 20, 0, y)
			y = y + 51
		end
	end
end

-- ===================== ОКНО СОЮЗОВ =====================
local allianceGui = mk("Frame", {
	Size = UDim2.new(0, 400, 0, 350),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(20, 20, 25),
	Visible = false,
	ZIndex = 100
}, screenGui)
corner(allianceGui, 16)
mk("UIStroke", { Color = Color3.fromRGB(60, 180, 220), Thickness = 2 }, allianceGui)

label(allianceGui, {
	Size = UDim2.new(1, -40, 0, 40),
	Position = UDim2.new(0, 20, 0, 10),
	Text = "🤝 СОЮЗЫ",
	TextColor3 = Color3.fromRGB(60, 180, 220),
	TextXAlignment = Enum.TextXAlignment.Left
})

local closeAllianceBtn = button(allianceGui, {
	Size = UDim2.new(0, 34, 0, 34),
	Position = UDim2.new(1, -44, 0, 10),
	BackgroundColor3 = Color3.fromRGB(220, 60, 60),
	Text = "✕"
})

local playersList = mk("ScrollingFrame", {
	Size = UDim2.new(1, -20, 0, 200),
	Position = UDim2.new(0, 10, 0, 60),
	BackgroundColor3 = Color3.fromRGB(30, 30, 40),
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	ScrollBarThickness = 6,
	ZIndex = 101
}, allianceGui)
corner(playersList, 8)

local playersLayout = mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 4)
}, playersList)

local allianceStatus = label(allianceGui, {
	Size = UDim2.new(1, -20, 0, 30),
	Position = UDim2.new(0, 10, 0, 270),
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(200, 200, 200),
	Text = "Выберите игрока для действия"
})

local createAllianceBtn = button(allianceGui, {
	Size = UDim2.new(0, 160, 0, 40),
	Position = UDim2.new(0.5, -170, 0, 305),
	BackgroundColor3 = Color3.fromRGB(60, 180, 220),
	Text = "🤝 СОЗДАТЬ СОЮЗ"
})

local betrayAllianceBtn = button(allianceGui, {
	Size = UDim2.new(0, 160, 0, 40),
	Position = UDim2.new(0.5, 10, 0, 305),
	BackgroundColor3 = Color3.fromRGB(220, 60, 60),
	Text = "💔 ПРЕДАТЬ"
})

-- Обновление списка игроков
local function refreshPlayersList()
	R.GetPlayersList:InvokeServer()
end

R.GetPlayersList.OnClientEvent:Connect(function(players)
	for _, child in ipairs(playersList:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end

	for _, p in ipairs(players) do
		if p.userId ~= player.UserId then
			local btn = button(playersList, {
				Size = UDim2.new(0, 360, 0, 40),
				BackgroundColor3 = p.isBot and Color3.fromRGB(40, 40, 60) or Color3.fromRGB(50, 50, 70),
				Text = (p.isBot and "🤖 " or "") .. p.name .. (p.inAlliance and " [В СОЮЗЕ]" or ""),
				TextColor3 = p.inAlliance and Color3.fromRGB(120, 255, 140) or Color3.new(1, 1, 1),
				ZIndex = 102
			})
			btn.MouseButton1Click:Connect(function()
				selectedPlayer = p
				allianceStatus.Text = "Выбран: " .. p.name
				if p.inAlliance then
					createAllianceBtn.Text = "⚔️ ОБЪЯВИТЬ ВОЙНУ"
					createAllianceBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
				else
					createAllianceBtn.Text = "🤝 СОЗДАТЬ СОЮЗ"
					createAllianceBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 220)
				end
			end)
		end
	end

	playersList.CanvasSize = UDim2.new(0, 0, 0, #players * 44)
end)

-- Кнопки союзов
allianceButton.MouseButton1Click:Connect(function()
	allianceGui.Visible = not allianceGui.Visible
	if allianceGui.Visible then
		refreshPlayersList()
	end
end)

closeAllianceBtn.MouseButton1Click:Connect(function()
	allianceGui.Visible = false
end)

createAllianceBtn.MouseButton1Click:Connect(function()
	if not selectedPlayer then
		showToast("Выберите игрока из списка", false)
		return
	end

	if selectedPlayer.inAlliance then
		R.DeclareWar:FireServer(selectedPlayer.userId)
		showToast("⚔️ Война объявлена " .. selectedPlayer.name, true)
	else
		R.CreateAlliance:FireServer(selectedPlayer.userId)
		showToast("🤝 Союз создан с " .. selectedPlayer.name, true)
	end
	allianceGui.Visible = false
end)

betrayAllianceBtn.MouseButton1Click:Connect(function()
	R.BetrayAlliance:FireServer()
	showToast("💔 Вы предали союз!", false)
	allianceGui.Visible = false
end)

declareWarButton.MouseButton1Click:Connect(function()
	allianceGui.Visible = true
	refreshPlayersList()
	allianceStatus.Text = "Выберите игрока для войны"
end)

-- ===================== TOAST =====================
local toast = label(screenGui, {
	Size = UDim2.new(0, 600, 0, 40),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 80),
	BackgroundColor3 = Color3.fromRGB(20, 20, 25),
	BackgroundTransparency = 0.25,
	Visible = false
})
corner(toast, 10)

local function showToast(text, ok)
	toast.Text = text
	toast.TextColor3 = ok and Color3.fromRGB(85, 255, 127) or Color3.fromRGB(255, 110, 110)
	toast.Visible = true
	task.delay(3, function()
		if toast.Text == text then toast.Visible = false end
	end)
end

local function refresh()
	local money, income = attr("Money", 0), attr("Income", 0)
	local count, ready, tierIdx, tLvl, tCount = attr("RocketCount", 1), attr("ReadyRockets", 1), attr("RocketTier", 1), attr("TurretLevel", 0), attr("TurretCount", 0)
	local tier = Config.Tiers[tierIdx]
	local TC = Config.Turret

	-- HUD
	moneyLabel.Text = "💰 " .. money .. "$"
	incomeLabel.Text = "+" .. income .. "$/с"
	fleetLabel.Text = ("🚀 %s ×%d"):format(tier.display, count)
	readyLabel.Text = ("Готово к запуску: %d/%d"):format(ready, count)
	turretLabel.Text = tCount > 0 and ("🛡 ПВО ×%d  ур.%d/%d"):format(tCount, tLvl, #TC.levels) or "🛡 ПВО: нет"
	turretPlaceButton.Visible = tCount > 0

	-- Вертолёт
	local owned, hs = attr("HeliOwned", false), attr("HeliState", "none")
	heliLabel.Text = heliStatusText()
	heliSendButton.Visible = owned and hs ~= "destroyed" and hs ~= "falling"
	heliRecallButton.Visible = owned and (hs == "takeoff" or hs == "flying" or hs == "hover")

	-- Energy Sun
	local hasSun = attr("HasEnergySun", false)
	local charge = attr("EnergySunCharge", 0) or 0
	sunButton.Visible = not hasSun
	mutateButton.Visible = hasSun and charge >= 50
	ultraButton.Visible = hasSun and charge >= 100
	repairButton.Visible = selectedRocket ~= nil

	-- Статус Energy Sun в HUD
	if hasSun then
		sunStatusLabel.Text = string.format("☀️ Energy Sun: %d%% заряда", charge)
		sunStatusLabel.TextColor3 = charge >= 100 and Color3.fromRGB(85, 255, 127) or Color3.fromRGB(255, 200, 50)
	else
		sunStatusLabel.Text = "☀️ Energy Sun: нет"
		sunStatusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	end

	layoutSideButtons()
	if buttonsFrame.Visible then clampQ() end

	if not shop.Visible then return end

	-- === СТРАНИЦА РАКЕТЫ ===
	curInfo.Text = ("Сейчас: %s ×%d\n%s"):format(tier.display, count, tierStats(tier))
	if count >= Config.MAX_ROCKETS then
		buyRocketBtn.Text = "МАКСИМУМ РАКЕТ"
		buyRocketBtn.BackgroundColor3 = GREY
	else
		priceBtn(buyRocketBtn, "Купить ещё ракету (" .. (count + 1) .. ")", getExtraRocketPrice(tierIdx, count), Color3.fromRGB(60, 200, 90))
	end

	local nxt = Config.Tiers[tierIdx + 1]
	if nxt then
		nextInfo.Text = ("Следующая: %s\n%s"):format(nxt.display, tierStats(nxt))
		priceBtn(upgradeBtn, "Улучшить все ракеты", getUpgradePrice(tierIdx, count), Color3.fromRGB(255, 170, 30))
	else
		nextInfo.Text = "Это максимальный уровень ракет!"
		upgradeBtn.Text = "МАКС"
		upgradeBtn.BackgroundColor3 = GREY
	end

	-- === СТРАНИЦА ПВО ===
	if tCount == 0 then
		local l1 = TC.levels[1]
		turretInfo.Text = ("Система ПВО «%s»\nСбивает вражеские ракеты и вертолёты.\n💰 За сбитую ракету: %d$ × её уровень, за вертолёт: %d$\nМожно поставить до %d штук, каждая следующая дороже на %d$.\n\nУр.1: реакция %.2fс, перезарядка %dс, дальность %d"):format(
			TC.modelName, Config.Reward.shootdownRocket, Config.Reward.heliHit + Config.Reward.heliKill,
			TC.maxCount, TC.extraPrice, l1.reaction, l1.reload, TC.range
		)
		turretUpBtn.Visible = false
	else
		local cur, nxtL = TC.levels[tLvl], TC.levels[tLvl + 1]
		local txt = ("ПВО ×%d   ур.%d/%d\nРеакция: %.2fс   Перезарядка: %dс   Дальность: %d"):format(
			tCount, tLvl, #TC.levels, cur.reaction, cur.reload, TC.range
		)
		if nxtL then
			txt = txt .. ("\n\nСледующий ур.%d: реакция %.2fс, перезарядка %dс\n(улучшаются все ПВО сразу — цена × %d)"):format(
				tLvl + 1, nxtL.reaction, nxtL.reload, tCount
			)
			priceBtn(turretUpBtn, "Улучшить все ПВО", nxtL.upgradePrice * tCount, Color3.fromRGB(255, 170, 30))
		else
			txt = txt .. "\n\nМаксимальный уровень!"
			turretUpBtn.Text = "МАКС"
			turretUpBtn.BackgroundColor3 = GREY
		end
		turretInfo.Text = txt
		turretUpBtn.Visible = true
	end

	if tCount >= TC.maxCount then
		turretBtn.Text = "МАКСИМУМ ПВО"
		turretBtn.BackgroundColor3 = GREY
	else
		priceBtn(turretBtn, tCount == 0 and "Купить ПВО" or ("Купить ещё ПВО (%d/%d)"):format(tCount + 1, TC.maxCount),
			TC.price + tCount * TC.extraPrice, Color3.fromRGB(60, 130, 220))
	end

	-- === СТРАНИЦА ВЕРТОЛЁТ ===
	if HC then
		heliInfo.Text = ("🚁 Боевой вертолёт\n\n" ..
			"• Летит в указанную точку (цель можно менять в полёте)\n" ..
			"• Замечает врагов в радиусе %d: стреляет 1 ракетой раз в %dс (урон %d), всего %d ракет\n" ..
			"• Если видит вражеский вертолёт — атакует его в первую очередь\n" ..
			"• Выдерживает %d попадания (ПВО, ракеты, другой вертолёт), потом падает\n" ..
			"• Падение на базу врага: урон ракетам, ПВО отключается на %dс\n" ..
			"• Восстановление после крушения: %d мин\n" ..
			"💰 Деньги за весь нанесённый урон\n\n" ..
			"💰 Цена: 6,000$"):format(
				HC.detectRange, HC.fireInterval, HC.rocketDamage, #HC.rocketNames,
				HC.armor, HC.turretDisable, HC.respawn // 60
			)
		if owned then
			heliBtn.Text = "✅ ВЕРТОЛЁТ КУПЛЕН"
			heliBtn.BackgroundColor3 = GREY
		else
			priceBtn(heliBtn, "Купить вертолёт", 6000, Color3.fromRGB(40, 160, 230))
		end
	else
		heliInfo.Text = "❌ Сервис вертолёта не запущен"
		heliBtn.Text = "НЕДОСТУПНО"
		heliBtn.BackgroundColor3 = GREY
	end

	-- === СТРАНИЦА ENERGY SUN ===
	if hasSun then
		energyBtn.Text = "✅ ENERGY SUN УСТАНОВЛЕНА"
		energyBtn.BackgroundColor3 = GREY
	else
		priceBtn(energyBtn, "☀️ Купить Energy Sun", 10000, Color3.fromRGB(255, 200, 50))
	end
end

-- Подписка на изменения атрибутов
for _, n in ipairs({
	"Money", "Income", "RocketCount", "ReadyRockets", "RocketTier",
	"TurretLevel", "TurretCount", "HeliOwned", "HeliState", "HeliAmmo",
	"HeliArmor", "HeliCooldownEnd", "HasEnergySun", "EnergySunCharge"
	}) do
	player:GetAttributeChangedSignal(n):Connect(refresh)
end

shop:GetPropertyChangedSignal("Visible"):Connect(refresh)
refresh()

-- Обновление статуса вертолёта
task.spawn(function()
	while true do
		task.wait(1)
		if attr("HeliState", "none") == "destroyed" then
			heliLabel.Text = heliStatusText()
		end
	end
end)

-- ===================== ОБРАБОТЧИКИ КНОПОК =====================
buyRocketBtn.MouseButton1Click:Connect(function()
	R.BuyRocket:FireServer()
end)

upgradeBtn.MouseButton1Click:Connect(function()
	R.UpgradeRocket:FireServer()
end)

turretBtn.MouseButton1Click:Connect(function()
	R.BuyTurret:FireServer()
end)

turretUpBtn.MouseButton1Click:Connect(function()
	if R.UpgradeTurret then R.UpgradeTurret:FireServer() end
end)

heliBtn.MouseButton1Click:Connect(function()
	if R.BuyHelicopter then R.BuyHelicopter:FireServer() end
end)

heliRecallButton.MouseButton1Click:Connect(function()
	if R.RecallHelicopter then R.RecallHelicopter:FireServer() end
end)

throwButton.MouseButton1Click:Connect(function()
	R.RequestThrow:FireServer()
end)

launchButton.MouseButton1Click:Connect(function()
	R.RequestLaunch:FireServer()
end)

sunButton.MouseButton1Click:Connect(function()
	R.BuyEnergySun:FireServer()
end)

energyBtn.MouseButton1Click:Connect(function()
	R.BuyEnergySun:FireServer()
end)

-- ===================== МУТАЦИЯ =====================
mutateButton.MouseButton1Click:Connect(function()
	local sunModel = nil
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and obj.Name:find("EnergySun_") and obj:GetAttribute("OwnerId") == player.UserId then
			sunModel = obj
			break
		end
	end

	if not sunModel then
		showToast("❌ Ваша Energy Sun не найдена на карте", false)
		return
	end

	local sunPos = sunModel:GetPivot().Position
	local nearestRocket = nil
	local nearestDist = 15

	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and m.Name:find("Rocket_") and m:GetAttribute("OwnerId") == player.UserId then
			if not m:GetAttribute("Flying") and not m:GetAttribute("Held") then
				local dist = (m:GetPivot().Position - sunPos).Magnitude
				if dist < nearestDist then
					nearestDist = dist
					nearestRocket = m
				end
			end
		end
	end

	if not nearestRocket then
		showToast("❌ Поднесите ракету к Energy Sun (в радиусе 15 м)", false)
		return
	end

	R.StartMutation:FireServer(nearestRocket)
	showToast("🌀 Мутация началась! Ждите 2 минуты", true)
end)

ultraButton.MouseButton1Click:Connect(function()
	startAiming("ultra")
end)

repairButton.MouseButton1Click:Connect(function()
	local selected = getSelectedRocket()
	if selected then
		R.StartRepair:FireServer(selected)
	else
		showToast("Выберите ракету для ремонта", false)
	end
end)

-- ===================== СОБЫТИЯ ОТ СЕРВЕРА =====================
R.ShopMessage.OnClientEvent:Connect(function(text, ok)
	showToast(text, ok)
	shopMsg.Text = text
	shopMsg.TextColor3 = ok and Color3.fromRGB(85, 255, 127) or Color3.fromRGB(255, 90, 90)
	task.delay(3, function()
		if shopMsg.Text == text then shopMsg.Text = "" end
	end)
end)

R.RocketStateChanged.OnClientEvent:Connect(function(stateType, value)
	if stateType == "Held" then
		buttonsFrame.Visible = value
		if value then clampQ() end
	end
end)

R.UltraFlash.OnClientEvent:Connect(function()
	local flash = mk("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.8,
		ZIndex = 999
	}, screenGui)
	task.delay(0.3, function() flash:Destroy() end)
end)

-- ===================== 4. ВЫБОР РАКЕТЫ =====================
local function setupRocketSelection()
	RunService.Heartbeat:Connect(function()
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		if player.Character then
			params.FilterDescendantsInstances = { player.Character }
		end

		local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
		local newSelected = nil

		if result then
			local inst = result.Instance
			while inst and inst ~= Workspace do
				if inst:IsA("Model") and inst.Name:find("Rocket_") and inst:GetAttribute("OwnerId") == player.UserId then
					newSelected = inst
					break
				end
				inst = inst.Parent
			end
		end

		if newSelected ~= selectedRocket then
			selectedRocket = newSelected
			repairButton.Visible = selectedRocket ~= nil
		end
	end)
end

setupRocketSelection()

-- ===================== 5. РАССТАНОВКА =====================
local placing = nil
local aiming = false
local PLACE_EXTRA = (Config.PLACE_EXTRA_RADIUS or 10) - (Config.PAD_MARGIN or 1.5)
local MIN_SPACING = Config.MIN_SPACING or 4
local TURRET_PAD = Config.Turret.footprint or 3

local function getPad()
	return Workspace:FindFirstChild("SpawnLocation" .. attr("SpawnIndex", 1))
end

local function clampToArea(pad, pos)
	local l = pad.CFrame:PointToObjectSpace(pos)
	local hx, hz = pad.Size.X / 2 + PLACE_EXTRA, pad.Size.Z / 2 + PLACE_EXTRA
	local w = pad.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(l.X, -hx, hx),
		0,
		math.clamp(l.Z, -hz, hz)
		))
	return Vector3.new(w.X, pad.Position.Y + pad.Size.Y / 2, w.Z)
end

local function myObjectPositions()
	local list = {}
	for _, c in ipairs(Workspace:GetChildren()) do
		if c:GetAttribute("OwnerId") == player.UserId and
			not c:GetAttribute("Held") and
			not c:GetAttribute("Flying") and
			c:GetAttribute("Airborne") == nil then
			table.insert(list, { pos = c:GetPivot().Position, pad = c:GetAttribute("TurretIndex") and TURRET_PAD or 0 })
		end
	end
	return list
end

local function myTurretModels()
	local list = {}
	for _, c in ipairs(Workspace:GetChildren()) do
		local idx = c:GetAttribute("TurretIndex")
		if c:IsA("Model") and idx and c:GetAttribute("OwnerId") == player.UserId then
			list[idx] = c
		end
	end
	return list
end

local function startPlacing(kind, turretIndex)
	if placing or aiming then return end
	local pad = getPad()
	if not pad then
		showToast("Площадка не найдена", false)
		return
	end

	placing = kind
	if kind == "rocket" then buttonsFrame.Visible = false end
	local minDist = MIN_SPACING + (kind == "turret" and 1 or 0)

	local marker = mk("Part", {
		Name = "PlaceMarker",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, minDist * 2, minDist * 2),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(60, 255, 120),
		Transparency = 0.45
	}, Workspace)

	local hintGui = mk("ScreenGui", { Name = "PlaceHint", DisplayOrder = 100 }, player.PlayerGui)
	local hint = label(hintGui, {
		Size = UDim2.new(0, 620, 0, 40),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		BackgroundColor3 = Color3.fromRGB(20, 20, 25),
		BackgroundTransparency = 0.3,
		Text = (kind == "rocket" and "📍 Куда поставить ракету?" or ("📍 Куда поставить ПВО #%d?"):format(turretIndex or 1)) .. "   ЛКМ — ок   |   ПКМ — отмена"
	})
	corner(hint, 10)

	local filter = { marker }
	if player.Character then table.insert(filter, player.Character) end
	for _, c in ipairs(Workspace:GetChildren()) do
		if c:GetAttribute("OwnerId") == player.UserId then
			table.insert(filter, c)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter

	local others = myObjectPositions()
	if kind == "turret" then
		local turret = myTurretModels()[turretIndex or 1]
		if turret then
			local tp = turret:GetPivot().Position
			for i = #others, 1, -1 do
				if (others[i].pos - tp).Magnitude < 0.5 then
					table.remove(others, i)
				end
			end
		end
	end

	local lastPos
	local renderConn, inputConn

	local function stop()
		placing = nil
		if renderConn then renderConn:Disconnect() end
		if inputConn then inputConn:Disconnect() end
		marker:Destroy()
		hintGui:Destroy()
	end

	renderConn = RunService.RenderStepped:Connect(function()
		local m = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(m.X, m.Y)
		local res = Workspace:Raycast(ray.Origin, ray.Direction * 1500, params)
		if not res then return end

		local p = clampToArea(pad, res.Position)
		local down = Workspace:Raycast(Vector3.new(p.X, p.Y + 40, p.Z), Vector3.new(0, -140, 0), params)
		if down then p = Vector3.new(p.X, down.Position.Y, p.Z) end

		lastPos = p
		marker.CFrame = CFrame.new(p + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))

		local free = true
		for _, o in ipairs(others) do
			if (Vector3.new(o.pos.X, 0, o.pos.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude < minDist + o.pad then
				free = false
				break
			end
		end
		marker.Color = free and Color3.fromRGB(60, 255, 120) or Color3.fromRGB(255, 80, 80)
	end)

	inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if lastPos then
				if kind == "rocket" then
					R.PlaceRocket:FireServer(lastPos)
					buttonsFrame.Visible = true
				else
					R.PlaceTurret:FireServer(lastPos, turretIndex or 1)
				end
				stop()
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.Escape then
			stop()
			if kind == "rocket" then buttonsFrame.Visible = true end
		end
	end)
end

local function startSelectTurret()
	if placing or aiming then return end
	placing = "select"

	local hintGui = mk("ScreenGui", { Name = "PlaceHint", DisplayOrder = 100 }, player.PlayerGui)
	local hint = label(hintGui, {
		Size = UDim2.new(0, 620, 0, 40),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		BackgroundColor3 = Color3.fromRGB(20, 20, 25),
		BackgroundTransparency = 0.3,
		Text = "🛡 ЛКМ по ПВО, которое переставить   |   ПКМ — отмена"
	})
	corner(hint, 10)

	local hl = mk("Highlight", {
		Name = "TurretSelectHL",
		FillColor = Color3.fromRGB(60, 200, 255),
		FillTransparency = 0.6,
		OutlineColor = Color3.new(1, 1, 1)
	}, Workspace)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = player.Character and { player.Character } or {}

	local hovered
	local renderConn, inputConn

	local function stop()
		placing = nil
		if renderConn then renderConn:Disconnect() end
		if inputConn then inputConn:Disconnect() end
		hintGui:Destroy()
		hl:Destroy()
	end

	renderConn = RunService.RenderStepped:Connect(function()
		local m = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(m.X, m.Y)
		local res = Workspace:Raycast(ray.Origin, ray.Direction * 1500, params)
		hovered = nil
		if res then
			local inst = res.Instance
			while inst and inst ~= Workspace do
				if inst:GetAttribute("TurretIndex") and inst:GetAttribute("OwnerId") == player.UserId then
					hovered = inst
					break
				end
				inst = inst.Parent
			end
		end
		hl.Adornee = hovered
	end)

	inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if hovered then
				local idx = hovered:GetAttribute("TurretIndex")
				stop()
				startPlacing("turret", idx)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.Escape then
			stop()
		end
	end)
end

placeButton.MouseButton1Click:Connect(function()
	startPlacing("rocket")
end)

turretPlaceButton.MouseButton1Click:Connect(function()
	if attr("TurretCount", 0) <= 1 then
		startPlacing("turret", 1)
	else
		startSelectTurret()
	end
end)

-- ===================== 6. КАМЕРА СВЕРХУ + ЗУМ =====================
local cameraPart = nil

local function findCameraPart()
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			local n = string.lower(obj.Name)
			if n == "camera" or n == "camerapoint" then
				return obj
			end
		end
	end
end

cameraPart = findCameraPart()

local zoom = { h = 0, focus = Vector3.zero, base = Vector3.zero, maxH = 0, minH = 0, groundY = 0 }

local function resetZoom()
	local p = cameraPart.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { cameraPart }
	local r = Workspace:Raycast(p, Vector3.new(0, -2000, 0), params)
	zoom.groundY = r and r.Position.Y or 0
	zoom.maxH = p.Y
	zoom.minH = zoom.groundY + 30
	zoom.h = p.Y
	zoom.base = Vector3.new(p.X, 0, p.Z)
	zoom.focus = zoom.base
end

local function topDownCF()
	local f = zoom.focus
	return CFrame.lookAt(Vector3.new(f.X, zoom.h, f.Z), Vector3.new(f.X, zoom.h - 1, f.Z), Vector3.new(0, 0, -1))
end

local function applyZoom(dir, mouseWorld)
	local oldH = zoom.h
	local newH = math.clamp(dir > 0 and oldH * 0.82 or oldH / 0.82, zoom.minH, zoom.maxH)
	if math.abs(newH - oldH) < 0.01 then return end

	local mp = mouseWorld and Vector3.new(mouseWorld.X, 0, mouseWorld.Z) or zoom.focus
	local k = (newH - zoom.groundY) / math.max(oldH - zoom.groundY, 0.01)
	local f = mp + (zoom.focus - mp) * k
	local maxOff = (zoom.maxH - newH) * math.tan(math.rad(35))
	local off = f - zoom.base
	if off.Magnitude > maxOff then off = maxOff > 0 and off.Unit * maxOff or Vector3.zero end
	zoom.focus = zoom.base + Vector3.new(off.X, 0, off.Z)
	zoom.h = newH
end

-- ===================== 7. ПРИЦЕЛИВАНИЕ =====================
local function createTargetMarker(hintText, color)
	local gui = mk("ScreenGui", { Name = "TargetMarkerGui", IgnoreGuiInset = true, DisplayOrder = 100 }, player.PlayerGui)

	local marker = mk("Frame", {
		Size = UDim2.new(0, 26, 0, 26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0
	}, gui)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, marker)
	mk("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, marker)

	for _, s in ipairs({ UDim2.new(0, 2, 0, 60), UDim2.new(0, 60, 0, 2) }) do
		mk("Frame", {
			Size = s,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			BackgroundColor3 = color,
			BorderSizePixel = 0
		}, marker)
	end

	local hint = label(gui, {
		Size = UDim2.new(0, 760, 0, 40),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		BackgroundTransparency = 0.3,
		BackgroundColor3 = Color3.fromRGB(20, 20, 25),
		Text = hintText
	})
	corner(hint, 10)

	local sub = label(gui, {
		Size = UDim2.new(0, 760, 0, 28),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		BackgroundTransparency = 0.4,
		BackgroundColor3 = Color3.fromRGB(20, 20, 25),
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(255, 190, 90),
		Text = "🔍 Колесо мыши / Q,E — зум    🟠 оранжевый круг — вражеский вертолёт в воздухе"
	})
	corner(sub, 8)

	return gui, marker
end

local function createGroundMarker(radius, color)
	return mk("Part", {
		Name = "TargetGroundMarker",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.6
	}, Workspace)
end

local heliCache, heliCacheT = {}, 0

local function heliModels()
	local now = os.clock()
	if now - heliCacheT > 0.25 then
		heliCacheT = now
		heliCache = {}
		for _, c in ipairs(Workspace:GetChildren()) do
			if c:IsA("Model") and c.Name:sub(1, 5) == "Heli_" then
				table.insert(heliCache, c)
			end
		end
	end
	return heliCache
end

local function raycastFromMouse(extraFilter)
	local m = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(m.X, m.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local filter = {}
	for _, o in ipairs(extraFilter) do table.insert(filter, o) end
	if player.Character then table.insert(filter, player.Character) end
	if cameraPart then table.insert(filter, cameraPart) end
	for _, h in ipairs(heliModels()) do table.insert(filter, h) end
	params.FilterDescendantsInstances = filter

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 10000, params)
	if result then return result.Position end

	local o, d = ray.Origin, ray.Direction
	if math.abs(d.Y) > 0.0001 then
		local t = -o.Y / d.Y
		if t > 0 then return o + d * t end
	end
end

local function startAiming(mode)
	mode = mode or "rocket"
	if placing or aiming then return end

	if not cameraPart or not cameraPart.Parent then
		cameraPart = findCameraPart()
	end
	if not cameraPart then
		warn("[RocketClient] ❌ Парт камеры не найден")
		return
	end

	local isHeli = mode == "heli"
	local isUltra = mode == "ultra"

	aiming = true
	UserInputService.MouseIconEnabled = false

	if not isHeli and not isUltra then
		buttonsFrame.Visible = false
	end

	resetZoom()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	camera.CFrame = topDownCF()

	local color = isHeli and Color3.fromRGB(60, 170, 255) or (isUltra and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 40, 40))
	local radius = isHeli and (HC and HC.detectRange or 60) or (isUltra and 60 or Config.Tiers[attr("RocketTier", 1)].radius)
	local hintText = isHeli and "🚁 ЛКМ — куда лететь вертолёту   |   ПКМ — отмена" or
		(isUltra and "💥 ЛКМ — выбрать место для ультра-удара   |   ПКМ — отмена" or
			"🎯 ЛКМ — выбрать цель   |   ПКМ — отмена")

	local markerGui, marker = createTargetMarker(hintText, color)
	local groundMarker = createGroundMarker(radius, color)

	local rings = {}
	local fuseR = Config.HELI_FUSE_RADIUS or 12

	local function updateRings()
		local seen = {}
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local filter = { groundMarker }
		for _, h in ipairs(heliModels()) do table.insert(filter, h) end
		for _, r in pairs(rings) do table.insert(filter, r) end
		params.FilterDescendantsInstances = filter

		for _, h in ipairs(heliModels()) do
			if h.Parent and h:GetAttribute("OwnerId") ~= player.UserId and h:GetAttribute("Airborne") then
				local ring = rings[h]
				if not ring then
					ring = mk("Part", {
						Name = "HeliRing",
						Shape = Enum.PartType.Cylinder,
						Size = Vector3.new(0.2, fuseR * 2, fuseR * 2),
						Anchored = true,
						CanCollide = false,
						CanQuery = false,
						Material = Enum.Material.Neon,
						Color = Color3.fromRGB(255, 150, 40),
						Transparency = 0.35
					}, Workspace)
					rings[h] = ring
				end
				local p = h:GetPivot().Position
				local down = Workspace:Raycast(p, Vector3.new(0, -300, 0), params)
				local y = down and down.Position.Y or (p.Y - 45)
				ring.CFrame = CFrame.new(p.X, y + 0.6, p.Z) * CFrame.Angles(0, 0, math.rad(90))
				seen[h] = true
			end
		end

		for h, r in pairs(rings) do
			if not seen[h] then
				r:Destroy()
				rings[h] = nil
			end
		end
	end

	local lastHit
	local renderConn, inputConn, wheelConn

	local function stop()
		aiming = false
		UserInputService.MouseIconEnabled = true
		if renderConn then renderConn:Disconnect() end
		if inputConn then inputConn:Disconnect() end
		if wheelConn then wheelConn:Disconnect() end
		markerGui:Destroy()
		groundMarker:Destroy()
		for _, r in pairs(rings) do r:Destroy() end
	end

	renderConn = RunService.RenderStepped:Connect(function()
		if not aiming then return end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = topDownCF()

		local m = UserInputService:GetMouseLocation()
		marker.Position = UDim2.new(0, m.X, 0, m.Y)

		local extra = { groundMarker }
		for _, r in pairs(rings) do table.insert(extra, r) end
		local hit = raycastFromMouse(extra)
		if hit then
			lastHit = hit
			groundMarker.CFrame = CFrame.new(hit + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
		updateRings()
	end)

	wheelConn = UserInputService.InputChanged:Connect(function(input)
		if not aiming or input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
		applyZoom(input.Position.Z, lastHit)
	end)

	inputConn = UserInputService.InputBegan:Connect(function(input)
		if not aiming then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not lastHit then return end
			if isHeli then
				R.SendHelicopter:FireServer(lastHit)
				stop()
				camera.CameraType = Enum.CameraType.Custom
			elseif isUltra then
				R.ChargeUltra:FireServer(lastHit)
				stop()
				camera.CameraType = Enum.CameraType.Custom
			else
				R.SetTarget:FireServer(lastHit, selectedQuantity)
				stop()
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.Escape then
			stop()
			camera.CameraType = Enum.CameraType.Custom
			if not isHeli and not isUltra then buttonsFrame.Visible = true end
		elseif input.KeyCode == Enum.KeyCode.E then
			applyZoom(1, lastHit)
		elseif input.KeyCode == Enum.KeyCode.Q then
			applyZoom(-1, lastHit)
		end
	end)
end

R.CameraFollowStart.OnClientEvent:Connect(function()
	startAiming("rocket")
end)

heliSendButton.MouseButton1Click:Connect(function()
	startAiming("heli")
end)

-- ===================== 8. КАМЕРА ЗА РАКЕТОЙ =====================
local followActive = false
local lastHoriz = Vector3.new(0, 0, -1)

R.CameraFollowUpdate.OnClientEvent:Connect(function(flightCF)
	camera.CameraType = Enum.CameraType.Scriptable
	local pos, dir = flightCF.Position, flightCF.LookVector
	local horiz = Vector3.new(dir.X, 0, dir.Z)
	if horiz.Magnitude > 0.05 then lastHoriz = horiz.Unit end

	local k = math.abs(dir.Y)
	local behind = (-dir * 12):Lerp(-lastHoriz * 10, k)
	local desired = CFrame.lookAt(pos + behind + Vector3.new(0, 4, 0), pos)

	if not followActive then
		followActive = true
		camera.CFrame = desired
	else
		camera.CFrame = camera.CFrame:Lerp(desired, 0.3)
	end
	camera.FieldOfView = 70 + 15 * math.clamp(-dir.Y, 0, 1)
end)

R.CameraFollowEnd.OnClientEvent:Connect(function()
	followActive = false
	task.wait(0.4)
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
end)

print("[RocketClient] ✅ Готов")