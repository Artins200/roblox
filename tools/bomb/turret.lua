local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

repeat task.wait() until _G.RocketSystem and _G.RocketSystem.Ready
local RS = _G.RocketSystem
RS.services = RS.services or {}
if RS.services.Turret then
	warn("[Turret] ❌ ДУБЛЬ! Отключён: " .. script:GetFullName())
	return
end
RS.services.Turret = script:GetFullName()

local Config = RS.Config
local TC = Config.Turret

local MISSILE_MODEL_OFFSET = CFrame.Angles(math.rad(-90), 0, 0)
local FIRE_ANGLE = math.rad(6)
local MISSILE_SPEED = TC.missileSpeed or 180

-- ================= ЦЕНЫ =================
function RS.turretPrice(owned)
	return TC.price + owned * TC.extraPrice
end

function RS.turretUpgradePrice(level, count)
	local nxt = TC.levels[level + 1]
	return nxt and nxt.upgradePrice * math.max(count, 1) or nil
end

-- ================= УТИЛИТЫ =================
local function objParts(obj)
	if obj:IsA("BasePart") then return { obj } end
	local list = {}
	for _, d in ipairs(obj:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(list, d) end
	end
	return list
end

local function setMissileVisible(m, visible)
	for part, trans in pairs(m.parts) do
		if part.Parent then
			part.Transparency = visible and trans or 1
		end
	end
end

local function objPivot(obj)
	return obj:IsA("Model") and obj:GetPivot() or obj.CFrame
end

local function smallExplosion(pos, radius)
	local ex = Instance.new("Explosion")
	ex.Position = pos
	ex.BlastRadius = radius
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.Parent = Workspace
end

local function isDisabled(T)
	return (T.disabledUntil or 0) > tick()
end

local function stripJoints(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

-- ================= БИЛБОРД =================
local function updateOne(T)
	if not T.label or not T.model.Parent then return end

	if isDisabled(T) then
		T.label.Text = ("⚡ ПВО #%d ОТКЛЮЧЕНО: %dс"):format(T.index, math.ceil(T.disabledUntil - tick()))
		T.label.TextColor3 = Color3.fromRGB(255, 80, 80)
	elseif T.reloading then
		T.label.Text = ("⚡ Лазер №%d перезарядка: %dс"):format(T.index, math.max(0, math.ceil(T.reloadEnd - tick())))
		T.label.TextColor3 = Color3.fromRGB(255, 170, 60)
	else
		T.label.Text = ("⚡ Лазер №%d  ур.%d   заряд %d/%d"):format(T.index, T.data.turretLevel, T.missilesLeft, #T.missiles)
		T.label.TextColor3 = Color3.fromRGB(120, 200, 255)
	end
end

function RS.updateTurretBillboard(data)
	for _, T in ipairs(data.turrets or {}) do
		updateOne(T)
	end
end

-- ================= ПЕРЕМЕЩЕНИЕ / УДАЛЕНИЕ =================
function RS.moveTurret(data, T, pos)
	if not T or not T.model.Parent then return end
	RS.placeAtRest(T.model, pos)
	T.home = pos
	T.baseCF = T.model:GetPivot()
	T.yaw = 0
end

function RS.clearTurrets(data)
	for _, T in ipairs(data.turrets or {}) do
		T.target = nil
		if T.model.Parent then T.model:Destroy() end
	end
	data.turrets = {}
	if data.player.Parent then
		data.player:SetAttribute("TurretCount", 0)
	end
end

-- ================= ОТКЛЮЧЕНИЕ =================
function RS.disableTurret(T, seconds)
	if not T or not T.model.Parent then return end
	T.disabledUntil = tick() + seconds
	T.target = nil

	local pp = T.model.PrimaryPart
	if pp then
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxassetid://243660364"
		smoke.Rate = 25
		smoke.Speed = NumberRange.new(2, 4)
		smoke.Lifetime = NumberRange.new(1.5, 2.5)
		smoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2),
			NumberSequenceKeypoint.new(1, 6)
		})
		smoke.Color = ColorSequence.new(Color3.fromRGB(60, 60, 60))
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1)
		})
		smoke.Parent = pp
		Debris:AddItem(smoke, seconds)

		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxassetid://243660364"
		sparks.Rate = 15
		sparks.Speed = NumberRange.new(6, 12)
		sparks.Lifetime = NumberRange.new(0.2, 0.4)
		sparks.Size = NumberSequence.new(0.5, 0)
		sparks.LightEmission = 1
		sparks.Color = ColorSequence.new(
			Color3.fromRGB(255, 230, 120),
			Color3.fromRGB(255, 120, 0)
		)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Parent = pp
		Debris:AddItem(sparks, seconds)
	end

	task.spawn(function()
		while T.model.Parent and isDisabled(T) do
			updateOne(T)
			task.wait(1)
		end
		updateOne(T)
	end)
end

-- ================= СПАВН =================
function RS.spawnTurret(data)
	data.turrets = data.turrets or {}
	if #data.turrets >= TC.maxCount then return false end

	local template = RS.findTemplate(TC.modelName)
	if not template then
		warn("[Turret] ❌ Модель '" .. TC.modelName .. "' не найдена")
		return false
	end

	local model = RS.prepareModel(template:Clone())
	if not model.PrimaryPart then
		model:Destroy()
		return false
	end

	local index = #data.turrets + 1
	model.Name = ("Turret_%s_%d"):format(data.player.Name, index)
	model:SetAttribute("OwnerId", data.userId)
	model:SetAttribute("TurretIndex", index)
	RS.makeStatic(model, true)
	model.Parent = Workspace

	local T = {
		data = data,
		index = index,
		model = model,
		missiles = {},
		missilesLeft = 0,
		reloading = false,
		reloadEnd = 0,
		target = nil,
		missileInFlight = false,
		flightStart = 0,
		lastFire = 0,
		yaw = 0,
		baseCF = CFrame.new(),
		disabledUntil = 0,
		home = nil,
		label = nil,
	}

	local pos = RS.findFreePosition(data, true, Config.MIN_SPACING + 3)
	table.insert(data.turrets, T)
	RS.moveTurret(data, T, pos)

	for i = 1, 8 do
		local obj
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "Missile" .. i and (d:IsA("BasePart") or d:IsA("Model")) then
				obj = d
				break
			end
		end
		if obj then
			local parts = {}
			for _, p in ipairs(objParts(obj)) do
				parts[p] = p.Transparency
			end
			table.insert(T.missiles, { obj = obj, parts = parts })
		else
			warn("[Turret] ⚠ Missile" .. i .. " не найден внутри модели ПВО")
		end
	end
	T.missilesLeft = #T.missiles

	local gui = Instance.new("BillboardGui")
	gui.Name = "TurretInfo"
	gui.Size = UDim2.new(0, 260, 0, 40)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = model.PrimaryPart

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = gui
	T.label = label
	updateOne(T)

	if data.player.Parent then
		data.player:SetAttribute("TurretCount", #data.turrets)
	end
	return true
end

-- ================= ПЕРЕЗАРЯДКА =================
local function startReload(T)
	local lvl = TC.levels[T.data.turretLevel]
	if not lvl then return end

	T.reloading = true
	T.reloadEnd = tick() + lvl.reload
	T.target = nil

	task.spawn(function()
		while T.model.Parent and tick() < T.reloadEnd do
			updateOne(T)
			task.wait(1)
		end
		if not T.model.Parent then return end
		T.missilesLeft = #T.missiles
		for _, m in ipairs(T.missiles) do
			setMissileVisible(m, true)
		end
		T.reloading = false
		updateOne(T)
	end)
end

-- ================= ЛАЗЕРНЫЙ ВЫСТРЕЛ =================
-- Луч мгновенно наносит урон (hitscan) и всегда хорошо виден.
local function spawnBeam(fromPos, toPos, color)
	local function ghost(pos)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.Position = pos
		p.Parent = Workspace
		return p
	end

	local p0 = ghost(fromPos)
	local p1 = ghost(toPos)
	local a0 = Instance.new("Attachment")
	a0.Parent = p0
	local a1 = Instance.new("Attachment")
	a1.Parent = p1

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(color, Color3.fromRGB(255, 255, 255))
	beam.Width0 = 0.45
	beam.Width1 = 0.18
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Parent = p0

	-- вспышка в точке попадания
	local flash = Instance.new("PointLight")
	flash.Color = color
	flash.Range = 10
	flash.Brightness = 4
	flash.Parent = p1

	local spark = Instance.new("ParticleEmitter")
	spark.Texture = "rbxassetid://243660364"
	spark.Rate = 0
	spark.Lifetime = NumberRange.new(0.15, 0.35)
	spark.Speed = NumberRange.new(6, 14)
	spark.Size = NumberSequence.new(0.7, 0)
	spark.LightEmission = 1
	spark.Color = ColorSequence.new(color, Color3.fromRGB(255, 255, 200))
	spark.SpreadAngle = Vector2.new(180, 180)
	spark:Emit(14)
	spark.Parent = p1

	Debris:AddItem(p0, 0.2)
	Debris:AddItem(p1, 0.3)
end

local function fireLaser(T, targetEntry)
	local data = T.data
	if not targetEntry.alive or not targetEntry.model.Parent then return end

	local m = T.missiles[#T.missiles - T.missilesLeft + 1]
	if not m then
		T.missilesLeft = 0
		startReload(T)
		return
	end

	T.missilesLeft = T.missilesLeft - 1
	T.lastFire = tick()

	local muzzle = T.model.PrimaryPart
	local fromPos = muzzle and muzzle.Position or T.model:GetPivot().Position
	local toPos = targetEntry.model:GetPivot().Position
	local color = Color3.fromRGB(255, 245, 120)
	spawnBeam(fromPos, toPos, color)

	-- мгновенный расчёт попадания
	if targetEntry.isHeli then
		if RS.hitHeli then
			RS.hitHeli(targetEntry, 1, data.userId, "⚡ Лазер ПВО подбил вражеский вертолёт")
		end
	else
		local evasion = Config.Tiers[targetEntry.tier].evasion
		if math.random() >= evasion then
			targetEntry.armorLeft = targetEntry.armorLeft - 1
			if targetEntry.armorLeft <= 0 then
				targetEntry.alive = false
				local killPos = targetEntry.model:GetPivot().Position
				smallExplosion(killPos, 14)
				RS.giveMoney(data.userId, Config.Reward.shootdownRocket * (targetEntry.tier or 1), killPos, "⚡ Лазер ПВО сбил вражескую ракету")
			end
		end
	end

	if T.missilesLeft <= 0 then
		startReload(T)
	end
	updateOne(T)
end

-- ================= ЦИКЛ ПВО =================
local function updateTurret(uid, data, T, dt)
	if not T.model.Parent or T.reloading or isDisabled(T) or #T.missiles == 0 then return end

	local lvl = TC.levels[data.turretLevel]
	if not lvl then return end

	if T.missilesLeft <= 0 then
		startReload(T)
		return
	end

	local myPos = T.model:GetPivot().Position

	if T.target and (not T.target.alive or not T.target.model.Parent
		or (T.target.model:GetPivot().Position - myPos).Magnitude > TC.range) then
		T.target = nil
	end

	if not T.target then
		local best, bestD = nil, TC.range
		for _, entry in pairs(RS.flying) do
			if entry.alive and entry.owner ~= uid and entry.model.Parent then
				local d = (entry.model:GetPivot().Position - myPos).Magnitude
				if d <= bestD then
					best = entry
					bestD = d
				end
			end
		end
		T.target = best
	end

	if not T.target then return end

	local tp = T.target.model:GetPivot().Position
	local flat = T.baseCF:VectorToObjectSpace(Vector3.new(tp.X - myPos.X, 0, tp.Z - myPos.Z))
	if flat.Magnitude < 0.5 then return end

	local desired = math.atan2(-flat.X, -flat.Z)
	local diff = (desired - T.yaw + math.pi) % (2 * math.pi) - math.pi
	local step = math.rad(180) / lvl.reaction * dt
	T.yaw = T.yaw + math.clamp(diff, -step, step)
	T.model:PivotTo(T.baseCF * CFrame.Angles(0, T.yaw, 0))

	if math.abs(diff) < FIRE_ANGLE and tick() - T.lastFire >= lvl.reaction then
		fireLaser(T, T.target)
	end
end

RunService.Heartbeat:Connect(function(dt)
	for uid, data in pairs(RS.players) do
		for _, T in ipairs(data.turrets or {}) do
			local ok, err = pcall(updateTurret, uid, data, T, dt)
			if not ok then warn("[Turret]", err) end
		end
	end
end)

print("[Turret] ✅ Сервис ПВО готов")