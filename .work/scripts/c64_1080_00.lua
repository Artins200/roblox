local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("[RocketSystem] Запуск ядра...")

-- ===================== КОНФИГ =====================
local Config = {
	PAYBACK_SECONDS = 120,
	MAX_ROCKETS = 9,
	COOLDOWN_TIME = 45,
	PICKUP_DISTANCE = 6,
	MIN_SPACING = 4,          -- мин. дистанция между объектами на базе
	PAD_MARGIN = 1.5,         -- отступ от края при автоспавне
	PLACE_EXTRA_RADIUS = 10,  -- на сколько стадов можно выйти за край площадки при ручной расстановке
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
		range = 220,
		missileSpeed = 170,
		levels = {
			{ reaction = 1.50, reload = 120, upgradePrice = 0 },
			{ reaction = 1.20, reload = 108, upgradePrice = 2000 },
			{ reaction = 0.95, reload = 97,  upgradePrice = 3500 },
			{ reaction = 0.70, reload = 86,  upgradePrice = 5500 },
			{ reaction = 0.45, reload = 75,  upgradePrice = 8000 },
		},
	},
}
for _, t in ipairs(Config.Tiers) do t.price = t.income * Config.PAYBACK_SECONDS end
function Config.getExtraRocketPrice(tierIndex, owned) return Config.Tiers[tierIndex].price + (owned - 1) * 150 end
function Config.getUpgradePrice(tierIndex, count)
	local nxt = Config.Tiers[tierIndex + 1]
	return nxt and nxt.price * count or nil
end

local RS = { Config = Config, players = {}, flying = {}, billboards = {}, Ready = false }
_G.RocketSystem = RS

-- ===================== REMOTES =====================
local remotes = ReplicatedStorage:FindFirstChild("RocketRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "RocketRemotes"
	remotes.Parent = ReplicatedStorage
end
for _, n in ipairs({
	"RequestLaunch", "RequestThrow", "SetTarget", "RocketStateChanged",
	"CameraFollowStart", "CameraFollowUpdate", "CameraFollowEnd",
	"BuyRocket", "UpgradeRocket", "BuyTurret", "ShopMessage",
	"PlaceRocket", "PlaceTurret",
	}) do
	if not remotes:FindFirstChild(n) then
		local r = Instance.new("RemoteEvent") r.Name = n r.Parent = remotes
	end
end
local getConfig = remotes:FindFirstChild("GetConfig")
if not getConfig then
	getConfig = Instance.new("RemoteFunction") getConfig.Name = "GetConfig" getConfig.Parent = remotes
end
getConfig.OnServerInvoke = function()
	return {
		MAX_ROCKETS = Config.MAX_ROCKETS, Tiers = Config.Tiers, Turret = Config.Turret,
		PAD_MARGIN = Config.PAD_MARGIN, MIN_SPACING = Config.MIN_SPACING, PLACE_EXTRA_RADIUS = Config.PLACE_EXTRA_RADIUS,
	}
end
RS.remotes = remotes

-- ===================== СПАВНЫ =====================
RS.spawnLocations = {}
for i = 1, 4 do
	local s = Workspace:WaitForChild("SpawnLocation" .. i, 10)
	if not s then warn("[RocketSystem] ❌ SpawnLocation" .. i .. " не найден!") end
	RS.spawnLocations[i] = s
end
local occupied = {}
local function getFreeSpawnIndex()
	for i = 1, 4 do if RS.spawnLocations[i] and not occupied[i] then return i end end
	for i = 1, 4 do if RS.spawnLocations[i] then return i end end
	return nil
end

-- ===================== УТИЛИТЫ =====================
function RS.findTemplate(name)
	local lname = string.lower(name)
	for _, obj in ipairs(ServerStorage:GetDescendants()) do
		if string.lower(obj.Name) == lname and (obj:IsA("Model") or obj:IsA("BasePart")) then return obj end
	end
end

function RS.makeStatic(model, canCollide)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true p.CanCollide = canCollide p.Massless = true end
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
			if p:IsA("BasePart") then model.PrimaryPart = p break end
		end
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			if p:GetAttribute("OrigColor") == nil then p:SetAttribute("OrigColor", p.Color) end
			if p:GetAttribute("OrigTrans") == nil then p:SetAttribute("OrigTrans", p.Transparency) end
		end
	end
	return model
end

function RS.setVisible(model, visible)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.Transparency = visible and (p:GetAttribute("OrigTrans") or 0) or 1 end
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
	return Vector3.new(model:GetAttribute("HomeX"), model:GetAttribute("HomeY"), model:GetAttribute("HomeZ"))
end
function RS.setHome(model, pos)
	model:SetAttribute("HomeX", pos.X) model:SetAttribute("HomeY", pos.Y) model:SetAttribute("HomeZ", pos.Z)
end

function RS.isReady(m)
	return m.Parent ~= nil and not m:GetAttribute("Flying") and (m:GetAttribute("CooldownEnd") or 0) <= tick()
end

-- ===================== ПЛОЩАДКА / РАССТАНОВКА =====================
local SPACING = 7

-- Зажимает XZ в прямоугольник площадки, расширенный на extra; Y = верх площадки
function RS.clampToArea(part, worldPos, extra)
	local l = part.CFrame:PointToObjectSpace(worldPos)
	local hx = part.Size.X / 2 + extra
	local hz = part.Size.Z / 2 + extra
	local w = part.CFrame:PointToWorldSpace(Vector3.new(math.clamp(l.X, -hx, hx), 0, math.clamp(l.Z, -hz, hz)))
	return Vector3.new(w.X, part.Position.Y + part.Size.Y / 2, w.Z)
end

-- Ищет реальную землю под точкой (игнорируя персонажей и объекты игроков)
function RS.groundAt(x, z, fallbackY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {}
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(filter, p.Character) end end
	for _, c in ipairs(Workspace:GetChildren()) do if c:GetAttribute("OwnerId") then table.insert(filter, c) end end
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
		if m.Parent and m ~= ignore then table.insert(list, RS.getHome(m)) end
	end
	if data.turretHome and ignore ~= "turret" then table.insert(list, data.turretHome) end
	return list
end

function RS.isSpotFree(data, pos, minDist, ignore)
	for _, o in ipairs(RS.occupiedPositions(data, ignore)) do
		if (o - pos).Magnitude < minDist then return false end
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

-- Ручная расстановка: зажать в зону, найти землю; если занято — сдвинуть на ближайшее свободное
-- Возвращает (позиция, успех)
function RS.resolvePlacement(data, worldPos, ignore, extraSpacing)
	local pad = RS.spawnLocations[data.spawnIndex]
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
	bb.hp.Text = ("❤ %d/%d"):format(model:GetAttribute("HP") or 0, model:GetAttribute("MaxHP") or 0)
	local left = (model:GetAttribute("CooldownEnd") or 0) - tick()
	if model:GetAttribute("Flying") then
		bb.cd.Text = "🚀 в полёте" bb.cd.TextColor3 = Color3.fromRGB(255, 200, 80)
	elseif left > 0 then
		bb.cd.Text = ("⏳ %dс"):format(math.ceil(left)) bb.cd.TextColor3 = Color3.fromRGB(255, 140, 60)
	else
		bb.cd.Text = "✅ готова" bb.cd.TextColor3 = Color3.fromRGB(120, 255, 140)
	end
end

function RS.attachBillboard(model)
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
	pop.TextTransparency = 1 pop.TextStrokeTransparency = 1
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

-- ===================== УРОН / УНИЧТОЖЕНИЕ =====================
local DARK = Color3.fromRGB(45, 45, 45)
local function updateTint(model)
	local frac = (model:GetAttribute("HP") or 1) / math.max(model:GetAttribute("MaxHP") or 1, 1)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("OrigColor") then
			p.Color = p:GetAttribute("OrigColor"):Lerp(DARK, (1 - frac) * 0.8)
		end
	end
end

function RS.refreshReady(data)
	local n = 0
	for _, m in ipairs(data.rockets) do if RS.isReady(m) then n += 1 end end
	if data.player.Parent then
		data.player:SetAttribute("ReadyRockets", n)
		data.player:SetAttribute("RocketCount", #data.rockets)
	end
end

-- Гарантия: если ракет не осталось — выдать базовую
function RS.ensureHasRocket(data)
	if not data.player.Parent then return end
	for i = #data.rockets, 1, -1 do
		if not data.rockets[i].Parent then table.remove(data.rockets, i) end
	end
	if #data.rockets > 0 then return end
	data.tier = 1
	data.player:SetAttribute("RocketTier", 1)
	local ok, err = pcall(RS.spawnRocketModel, data)
	if ok and #data.rockets > 0 then
		print("[RocketSystem]", data.player.Name, "потерял все ракеты → выдана базовая")
		remotes.ShopMessage:FireClient(data.player, "💥 Все ракеты уничтожены! Выдана базовая ракета", false)
	else
		warn("[RocketSystem] Не удалось выдать базовую ракету:", err)
	end
	RS.refreshReady(data)
end

function RS.destroyRocket(model)
	local data = RS.players[model:GetAttribute("OwnerId")]
	local pos = model:GetPivot().Position

	local ex = Instance.new("Explosion")
	ex.Position = pos ex.BlastRadius = 8 ex.BlastPressure = 0 ex.DestroyJointRadiusPercent = 0
	ex.Parent = Workspace

	RS.flying[model] = nil
	RS.billboards[model] = nil
	if data then
		for i, m in ipairs(data.rockets) do
			if m == model then table.remove(data.rockets, i) break end
		end
		if data.held == model then
			data.held = nil
			remotes.RocketStateChanged:FireClient(data.player, "Held", false)
		end
		if data.noPickup == model then data.noPickup = nil end
	end
	model:Destroy()

	if data and data.player.Parent then
		if #data.rockets == 0 then
			task.defer(RS.ensureHasRocket, data)
		else
			remotes.ShopMessage:FireClient(data.player, "💥 Ракета уничтожена!", false)
		end
		RS.refreshReady(data)
	end
end

function RS.applyDamage(model, dmg)
	if not model.Parent then return end
	local hp = math.max(0, (model:GetAttribute("HP") or 0) - dmg)
	model:SetAttribute("HP", hp)
	updateTint(model)
	RS.updateLabels(model)
	if hp <= 0 then RS.destroyRocket(model) end
end

-- ===================== СПАВН РАКЕТ =====================
function RS.spawnRocketModel(data, homePos)
	local tier = Config.Tiers[data.tier]
	local template = RS.findTemplate(tier.name)
	if not template then
		warn("[RocketSystem] ❌ Модель '" .. tier.name .. "' не найдена, использую базовую")
		template = RS.findTemplate(Config.Tiers[1].name)
	end
	if not template then warn("[RocketSystem] ❌ Нет ни одной модели ракеты!") return end
	local pad = RS.spawnLocations[data.spawnIndex]
	if not pad then return end

	local model = RS.prepareModel(template:Clone())
	if not model.PrimaryPart then model:Destroy() return end
	model.Name = "Rocket_" .. data.player.Name
	RS.makeStatic(model, true)

	local home = homePos or RS.findFreePosition(data, false, Config.MIN_SPACING)
	model:SetAttribute("OwnerId", data.userId)
	model:SetAttribute("HP", tier.hp)
	model:SetAttribute("MaxHP", tier.hp)
	model:SetAttribute("Flying", false)
	model:SetAttribute("Held", false)
	model:SetAttribute("CooldownEnd", 0)
	RS.setHome(model, home)

	model.Parent = Workspace
	RS.placeAtRest(model, home)
	RS.attachBillboard(model)
	table.insert(data.rockets, model)
	RS.refreshReady(data)
	return model
end

function RS.addRocket(data) return RS.spawnRocketModel(data) end

function RS.rebuildFleet(data)
	local homes = {}
	for _, m in ipairs(data.rockets) do
		table.insert(homes, RS.getHome(m))
		RS.flying[m] = nil RS.billboards[m] = nil
		m:Destroy()
	end
	data.rockets = {}
	for _, h in ipairs(homes) do RS.spawnRocketModel(data, h) end
end

-- ===================== ТИК: ДОХОД + КД + ГАРАНТИЯ РАКЕТЫ =====================
task.spawn(function()
	while true do
		task.wait(1)
		for _, data in pairs(RS.players) do
			local tier = Config.Tiers[data.tier]
			local total = 0
			for _, m in ipairs(data.rockets) do
				if m.Parent then
					total += tier.income
					RS.popupMoney(m, tier.income)
					RS.updateLabels(m)
				end
			end
			if data.player.Parent then
				data.player:SetAttribute("Income", total)
				if total > 0 then data.player:SetAttribute("Money", (data.player:GetAttribute("Money") or 0) + total) end
				RS.refreshReady(data)
				if #data.rockets == 0 and data.spawnedOnce then RS.ensureHasRocket(data) end
			end
		end
	end
end)

-- ===================== ИГРОКИ =====================
local function onPlayerAdded(player)
	if RS.players[player.UserId] then return end
	local spawnIndex = getFreeSpawnIndex()
	if not spawnIndex then warn("[RocketSystem] ❌ Нет SpawnLocation для " .. player.Name) return end
	occupied[spawnIndex] = player

	local data = {
		player = player, userId = player.UserId, spawnIndex = spawnIndex,
		tier = 1, rockets = {}, held = nil, noPickup = nil, spawnedOnce = false,
		turret = nil, turretLevel = 0, turretHome = nil,
	}
	RS.players[player.UserId] = data

	player:SetAttribute("SpawnIndex", spawnIndex)
	player:SetAttribute("Money", 0)
	player:SetAttribute("Income", 0)
	player:SetAttribute("RocketCount", 1)
	player:SetAttribute("ReadyRockets", 1)
	player:SetAttribute("RocketTier", 1)
	player:SetAttribute("TurretLevel", 0)
	print("[RocketSystem] Игрок", player.Name, "→ база №", spawnIndex)

	local function onCharacter(character)
		task.wait(0.2)
		pcall(function()
			if character:WaitForChild("HumanoidRootPart", 5) then
				character:PivotTo(RS.spawnLocations[spawnIndex].CFrame + Vector3.new(0, 5, 0))
			end
		end)
		if not data.spawnedOnce then
			data.spawnedOnce = true
			local ok, err = pcall(RS.spawnRocketModel, data)
			if not ok then warn("[RocketSystem] Ошибка спавна ракеты:", err) end
		end
	end
	if player.Character then task.spawn(onCharacter, player.Character) end
	player.CharacterAdded:Connect(onCharacter)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end

Players.PlayerRemoving:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end
	if occupied[data.spawnIndex] == player then occupied[data.spawnIndex] = nil end
	for _, m in ipairs(data.rockets) do RS.flying[m] = nil RS.billboards[m] = nil m:Destroy() end
	if data.turret and data.turret.model then data.turret.model:Destroy() end
	RS.players[player.UserId] = nil
end)

RS.Ready = true
print("[RocketSystem] ✅ Ядро готово")