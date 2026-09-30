local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

repeat task.wait() until _G.RocketSystem and _G.RocketSystem.Ready
local RS = _G.RocketSystem
RS.services = RS.services or {}
if RS.services.Heli then
	warn("[Heli] ❌ ДУБЛЬ! Отключён: " .. script:GetFullName())
	return
end
RS.services.Heli = script:GetFullName()
local Config = RS.Config
local remotes = RS.remotes

-- ===================== КОНФИГ =====================
local HC = {
	modelName = "Helicopter",
	price = 6000,
	armor = 3,
	rocketNames = { "RocketTip", "RocketTip1", "RocketTip2", "RocketTip3", "RocketTip4", "RocketTip5" },
	fireInterval = 15,
	reload = 3,
	rocketSpeed = 140,
	rocketDamage = 20,
	rocketRadius = 10,
	detectRange = 70,
	speed = 55,
	vSpeed = 18,
	accel = 1.5,
	flyHeight = 45,
	crashRadius = 30,
	crashDamage = 100,
	turretDisable = 20,
	respawn = 240,
	homes = {
		Vector3.new(9.897, 15.862, -151.08),
		Vector3.new(-153.434, 15.862, -17.039),
		Vector3.new(137.447, 15.862, 43.346),
		Vector3.new(-61.026, 15.862, 153.756),
	},
}
Config.Helicopter = HC
remotes.GetHeliConfig.OnServerInvoke = function() return HC end

local HELI_MODEL_OFFSET = CFrame.new()
local HELI_ROCKET_OFFSET = CFrame.new()

local BuyHeli, SendHeli, RecallHeli = remotes.BuyHelicopter, remotes.SendHelicopter, remotes.RecallHelicopter

-- ===================== УТИЛИТЫ =====================
local helis = {}
RS.helis = helis

local function msg(p, text, ok)
	if typeof(p) == "Instance" and p.Parent then
		remotes.ShopMessage:FireClient(p, text, ok)
	end
end

local function money(p)
	return p:GetAttribute("Money") or 0
end

local function now()
	return Workspace:GetServerTimeNow()
end

local function objParts(obj)
	if obj:IsA("BasePart") then return { obj } end
	local list = {}
	for _, d in ipairs(obj:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(list, d) end
	end
	return list
end

local function objPivot(obj)
	return obj:IsA("Model") and obj:GetPivot() or obj.CFrame
end

local function setObjVisible(r, visible)
	for part, tr in pairs(r.parts) do
		if part.Parent then
			part.Transparency = visible and tr or 1
		end
	end
end

local function setAttr(H, n, v)
	local p = H.data.player
	if p.Parent then p:SetAttribute(n, v) end
end

local function smallExplosion(pos, radius)
	local ex = Instance.new("Explosion")
	ex.Position = pos
	ex.BlastRadius = radius
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.Parent = Workspace
end

local function isAirborne(H)
	return H.entry ~= nil and H.entry.alive and H.model.Parent ~= nil
end

local function stripJoints(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

local STATE_TEXT = {
	idle = "на базе",
	takeoff = "взлёт",
	flying = "летит",
	hover = "на позиции",
	returning = "домой",
	falling = "ПАДАЕТ!",
	destroyed = "сбит"
}

local function updateBillboard(H)
	if not H.label then return end
	local armor = H.entry and math.max(H.entry.armorLeft, 0) or HC.armor
	local ammo
	if H.reloading then
		ammo = "♻"
	else
		local cd = HC.fireInterval - (tick() - H.lastFire)
		ammo = (cd > 0 and H.state ~= "idle") and ("%d (%ds)"):format(H.ammo, math.ceil(cd)) or tostring(H.ammo)
	end
	H.label.Text = ("🚁 %s | 🛡%d | 🚀%s/%d"):format(STATE_TEXT[H.state] or H.state, armor, ammo, #H.rockets)
end

local function setState(H, s)
	H.state = s
	setAttr(H, "HeliState", s)
	updateBillboard(H)
end

local function applyCF(H, cf)
	H.model:PivotTo(cf * HELI_MODEL_OFFSET)
	local pivot = H.model:GetPivot()
	for _, r in ipairs(H.rotors) do
		if r.part.Parent then
			local spin = r.tail and CFrame.Angles(H.rotorAngle, 0, 0) or CFrame.Angles(0, H.rotorAngle, 0)
			r.part.CFrame = pivot * r.offset * spin
		end
	end
end

-- ===================== ПУБЛИЧНОЕ API =====================
function RS.hitHeli(entry, hits, attackerId, label)
	if not entry or not entry.isHeli or not entry.alive or not entry.model.Parent then
		return 0
	end
	local before = entry.armorLeft
	entry.armorLeft = math.max(0, before - hits)
	local dealt = before - entry.armorLeft
	if dealt <= 0 then return 0 end

	local pos = entry.model:GetPivot().Position
	smallExplosion(pos, 6)
	if entry.armorLeft <= 0 then entry.alive = false end

	local RW = Config.Reward
	if attackerId and RW then
		local amount = dealt * RW.heliHit + (entry.alive and 0 or RW.heliKill)
		RS.giveMoney(attackerId, amount, pos, entry.alive and label or (label .. " — СБИТ! 🔥"))
	end
	return dealt
end

function RS.hitHelisInRadius(pos, radius, attackerId, hits, label)
	local n = 0
	for uid, H in pairs(helis) do
		if uid ~= attackerId and isAirborne(H) and (H.model:GetPivot().Position - pos).Magnitude <= radius then
			if RS.hitHeli(H.entry, hits, attackerId, label) > 0 then
				n = n + 1
			end
		end
	end
	return n
end

function RS.heliProximity(pos, ownerId, radius)
	for uid, H in pairs(helis) do
		if uid ~= ownerId and isAirborne(H) and (H.model:GetPivot().Position - pos).Magnitude <= radius then
			return true
		end
	end
	return false
end

function RS.removeHeli(data)
	local H = helis[data.userId]
	if not H then return end

	RS.flying[H.model] = nil
	if H.fx then
		for _, e in ipairs(H.fx) do e:Destroy() end
		H.fx = nil
	end
	H.model:Destroy()
	helis[data.userId] = nil
	data.heli = nil

	local p = data.player
	if p.Parent then
		p:SetAttribute("HeliOwned", false)
		p:SetAttribute("HeliState", "none")
		p:SetAttribute("HeliAmmo", 0)
		p:SetAttribute("HeliArmor", 0)
		p:SetAttribute("HeliCooldownEnd", 0)
	end
end

-- ===================== УРОН ПО ПЛОЩАДИ =====================
local function splash(pos, radius, damage, ownerId, label, quiet)
	local hits = {}
	for uid, victim in pairs(RS.players) do
		if uid ~= ownerId then
			local vt = Config.Tiers[victim.tier]
			for _, m in ipairs(victim.rockets) do
				if m.Parent and m.PrimaryPart and not m:GetAttribute("Flying") then
					local d = (m.PrimaryPart.Position - pos).Magnitude
					if d <= radius then
						local dmg = damage * (0.3 + 0.7 * (1 - d / radius))
						if math.random() < vt.resist then dmg = dmg * 0.25 end
						table.insert(hits, { m = m, dmg = math.floor(dmg + 0.5), tier = victim.tier })
					end
				end
			end
		end
	end

	local stats = { damage = 0, kills = 0, killTierSum = 0 }
	for _, h in ipairs(hits) do
		local dealt, killed = RS.applyDamage(h.m, h.dmg)
		stats.damage = stats.damage + dealt
		if killed then
			stats.kills = stats.kills + 1
			stats.killTierSum = stats.killTierSum + h.tier
		end
	end
	RS.rewardCombat(ownerId, stats, label or "🚁 вертолёт", pos, quiet)
	return #hits
end

-- ===================== СПАВН =====================
local function spawnHeli(data)
	if helis[data.userId] then return nil, "Вертолёт уже есть" end

	local template = RS.findTemplate(HC.modelName)
	if not template then return nil, "Модель 'Helicopter' не найдена в ServerStorage" end

	local home = HC.homes[data.spawnIndex]
	if not home then return nil, "Нет координаты вертолёта для базы " .. tostring(data.spawnIndex) end

	local model = RS.prepareModel(template:Clone())
	if not model.PrimaryPart then
		model:Destroy()
		return nil, "У модели вертолёта нет деталей"
	end

	model.Name = "Heli_" .. data.player.Name
	model:SetAttribute("OwnerId", data.userId)
	model:SetAttribute("Airborne", false)
	RS.makeStatic(model, true)
	model.Parent = Workspace

	local look = template:GetPivot().LookVector
	local yaw = math.atan2(-look.X, -look.Z)

	local H = {
		data = data,
		model = model,
		home = home,
		pos = home,
		vel = Vector3.zero,
		yaw = yaw,
		baseYaw = yaw,
		pitch = 0,
		roll = 0,
		state = "idle",
		target = home,
		swayT = math.random() * 10,
		rotorAngle = 0,
		rotors = {},
		rockets = {},
		ammo = 0,
		reloading = false,
		lastFire = -999,
		scanT = 0,
		enemy = nil,
		entry = nil,
		fall = nil,
		lastArmor = HC.armor,
		cooldownEnd = 0,
		bbT = 0,
	}

	model:PivotTo(CFrame.new(home) * CFrame.Angles(0, yaw, 0) * HELI_MODEL_OFFSET)
	local _, size = model:GetBoundingBox()
	H.halfH = size.Y / 2

	local pivot = model:GetPivot()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= model.PrimaryPart then
			local n = string.lower(d.Name)
			if n:find("rotor") or n:find("blade") or n:find("propeller") or n:find("винт") then
				table.insert(H.rotors, {
					part = d,
					offset = pivot:ToObjectSpace(d.CFrame),
					tail = n:find("tail") ~= nil
				})
			end
		end
	end

	for _, name in ipairs(HC.rocketNames) do
		local obj
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == name and (d:IsA("BasePart") or d:IsA("Model")) then
				obj = d
				break
			end
		end
		if obj then
			local parts = {}
			for _, p in ipairs(objParts(obj)) do
				parts[p] = p.Transparency
			end
			table.insert(H.rockets, { obj = obj, parts = parts })
		else
			warn("[Heli] ⚠ " .. name .. " не найден внутри модели Helicopter")
		end
	end
	H.ammo = #H.rockets

	local gui = Instance.new("BillboardGui")
	gui.Name = "HeliInfo"
	gui.Size = UDim2.new(0, 280, 0, 40)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = model.PrimaryPart

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 220, 255)
	label.Parent = gui
	H.gui, H.label = gui, label

	helis[data.userId] = H
	data.heli = H
	setAttr(H, "HeliOwned", true)
	setAttr(H, "HeliAmmo", H.ammo)
	setAttr(H, "HeliArmor", HC.armor)
	setAttr(H, "HeliCooldownEnd", 0)
	setState(H, "idle")
	return H
end

function RS.spawnHeli(data)
	return spawnHeli(data)
end

-- ===================== ВЗЛЁТ / ПОСАДКА =====================
local function registerTarget(H)
	H.entry = {
		model = H.model,
		owner = H.data.userId,
		tier = 1,
		evasion = 0,
		armorLeft = HC.armor,
		alive = true,
		isHeli = true,
		H = H
	}
	H.lastArmor = HC.armor
	RS.flying[H.model] = H.entry
	H.model:SetAttribute("Airborne", true)
	setAttr(H, "HeliArmor", HC.armor)
end

local function land(H)
	RS.flying[H.model] = nil
	H.entry = nil
	H.enemy = nil
	H.model:SetAttribute("Airborne", false)
	H.pos = H.home
	H.vel = Vector3.zero
	H.pitch, H.roll = 0, 0
	applyCF(H, CFrame.new(H.home) * CFrame.Angles(0, H.baseYaw, 0))
	setAttr(H, "HeliArmor", HC.armor)
	setState(H, "idle")
	msg(H.data.player, "🚁 Вертолёт вернулся на базу", true)
end

local function send(H, pos)
	H.target = Vector3.new(pos.X, H.home.Y, pos.Z)
	if H.state == "idle" then
		H.pos = H.home
		H.vel = Vector3.zero
		H.yaw = H.baseYaw
		registerTarget(H)
		setState(H, "takeoff")
	elseif H.state == "returning" or H.state == "hover" then
		setState(H, "flying")
	end
end

function RS.sendHeli(data, pos)
	local H = helis[data.userId]
	if not H or H.state == "destroyed" or H.state == "falling" then return false end
	send(H, pos)
	return true
end

function RS.recallHeli(data)
	local H = helis[data.userId]
	if not H then return false end
	if H.state == "takeoff" or H.state == "flying" or H.state == "hover" then
		H.target = H.home
		setState(H, "returning")
		return true
	end
	return false
end

-- ===================== БОЙ =====================
local function findEnemy(H)
	local myPos = H.model:GetPivot().Position
	local best, bestD = nil, HC.detectRange

	for uid, other in pairs(helis) do
		if uid ~= H.data.userId and isAirborne(other) then
			local d = (other.model:GetPivot().Position - myPos).Magnitude
			if d <= bestD then
				best = { model = other.model, heli = other }
				bestD = d
			end
		end
	end

	if best then return best end

	bestD = HC.detectRange
	for uid, victim in pairs(RS.players) do
		if uid ~= H.data.userId then
			for _, m in ipairs(victim.rockets) do
				if m.Parent and m.PrimaryPart and not m:GetAttribute("Flying") then
					local d = (m.PrimaryPart.Position - myPos).Magnitude
					if d <= bestD then
						best = { model = m }
						bestD = d
					end
				end
			end
		end
	end
	return best
end

local function enemyValid(H, e)
	if not e or not e.model.Parent then return false end
	if e.heli then
		if not isAirborne(e.heli) then return false end
	elseif not e.model.PrimaryPart or e.model:GetAttribute("Flying") then
		return false
	end
	return (e.model:GetPivot().Position - H.model:GetPivot().Position).Magnitude <= HC.detectRange * 1.3
end

local function startReload(H)
	H.reloading = true
	updateBillboard(H)
	task.delay(HC.reload, function()
		if helis[H.data.userId] ~= H then return end
		H.reloading = false
		H.ammo = #H.rockets
		if H.state ~= "destroyed" then
			for _, r in ipairs(H.rockets) do
				setObjVisible(r, true)
			end
		end
		setAttr(H, "HeliAmmo", H.ammo)
		updateBillboard(H)
	end)
end

local function fireRocket(H, tgt)
	local r = H.rockets[#H.rockets - H.ammo + 1]
	if not r or not r.obj.Parent then
		H.ammo = 0
		return
	end

	H.ammo = H.ammo - 1
	H.lastFire = tick()
	setAttr(H, "HeliAmmo", H.ammo)

	local startCF = objPivot(r.obj)
	local okClone, proj = pcall(function()
		local p = RS.prepareModel(r.obj:Clone())
		stripJoints(p)
		RS.makeStatic(p, false)
		return p
	end)

	if not okClone or not proj or not proj.PrimaryPart then
		warn("[Heli] ❌ Не удалось создать ракету вертолёта:", proj)
		return
	end

	proj.Name = "HeliRocket"
	proj.Parent = Workspace
	proj:PivotTo(startCF)
	setObjVisible(r, false)
	updateBillboard(H)

	local trail = Instance.new("ParticleEmitter")
	trail.Texture = "rbxassetid://243660364"
	trail.Rate = 60
	trail.Lifetime = NumberRange.new(0.5, 0.9)
	trail.Speed = NumberRange.new(0, 1)
	trail.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 2.5)
	})
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = proj.PrimaryPart

	local ownerId = H.data.userId
	local targetModel = tgt.model

	task.spawn(function()
		local ok, err = pcall(function()
			local pos = startCF.Position
			local lastTarget = targetModel:GetPivot().Position
			local t0 = tick()

			while tick() - t0 < 6 do
				local dt = RunService.Heartbeat:Wait()
				if targetModel.Parent then
					lastTarget = targetModel:GetPivot().Position
				end
				local to = lastTarget - pos
				local d = to.Magnitude
				if d < 3 then break end
				pos = pos + to.Unit * math.min(HC.rocketSpeed * dt, d)
				proj:PivotTo(CFrame.lookAt(pos, lastTarget) * HELI_ROCKET_OFFSET)
			end

			local ex = Instance.new("Explosion")
			ex.Position = pos
			ex.BlastRadius = HC.rocketRadius
			ex.BlastPressure = 0
			ex.DestroyJointRadiusPercent = 0
			ex.Parent = Workspace

			splash(pos, HC.rocketRadius, HC.rocketDamage, ownerId, "🚁 ракета вертолёта", true)
			RS.hitHelisInRadius(pos, HC.rocketRadius, ownerId, 1, "🚁 попадание по вражескому вертолёту")
		end)
		if not ok then warn("[Heli] ❌ Ошибка полёта ракеты:", err) end
		if proj.Parent then proj:Destroy() end
	end)

	if H.ammo <= 0 then startReload(H) end
end

local function combat(H, dt)
	H.scanT = H.scanT - dt
	if H.scanT <= 0 or not enemyValid(H, H.enemy) then
		H.scanT = 0.5
		H.enemy = findEnemy(H)
	end
	local e = H.enemy
	if not e then return end
	if not H.reloading and H.ammo > 0 and tick() - H.lastFire >= HC.fireInterval then
		fireRocket(H, e)
	end
end

-- ===================== ПАДЕНИЕ / КРУШЕНИЕ =====================
local respawn

local function crash(H, pos)
	if H.fx then
		for _, e in ipairs(H.fx) do
			e.Enabled = false
			Debris:AddItem(e, 3)
		end
		H.fx = nil
	end

	local ex = Instance.new("Explosion")
	ex.Position = pos
	ex.BlastRadius = HC.crashRadius
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.Parent = Workspace

	local ownerId = H.data.userId
	local hitRockets = splash(pos, HC.crashRadius, HC.crashDamage, ownerId, "💥 падение вертолёта на базу врага", false)

	local hitTurret = false
	for uid, victim in pairs(RS.players) do
		if uid ~= ownerId then
			for _, T in ipairs(victim.turrets or {}) do
				if T.model.Parent and (T.model:GetPivot().Position - pos).Magnitude <= HC.crashRadius then
					if RS.disableTurret then RS.disableTurret(T, HC.turretDisable) end
					hitTurret = true
					RS.msg(victim, ("⚡ Вертолёт %s рухнул на вашу базу! ПВО #%d отключено на %dс"):format(H.data.player.Name, T.index, HC.turretDisable), false)
				end
			end
		end
	end

	if hitTurret then
		msg(H.data.player, "💥 Вертолёт рухнул прямо на ПВО врага — оно отключено на " .. HC.turretDisable .. "с!", true)
	elseif hitRockets > 0 then
		msg(H.data.player, "💥 Вертолёт рухнул на базу врага и повредил " .. hitRockets .. " ракет!", true)
	else
		msg(H.data.player, ("💥 Вертолёт разбился. Восстановление через %d мин"):format(HC.respawn // 60), false)
	end

	RS.flying[H.model] = nil
	H.entry = nil
	H.fall = nil
	H.enemy = nil
	RS.setVisible(H.model, false)
	if H.gui then H.gui.Enabled = false end
	RS.makeStatic(H.model, false)
	H.model:PivotTo(CFrame.new(H.home) * CFrame.Angles(0, H.baseYaw, 0) * HELI_MODEL_OFFSET)
	H.cooldownEnd = now() + HC.respawn
	setAttr(H, "HeliCooldownEnd", H.cooldownEnd)
	setState(H, "destroyed")
	task.delay(HC.respawn, respawn, H)
end

respawn = function(H)
	if helis[H.data.userId] ~= H or not H.model.Parent then return end

	H.pos = H.home
	H.vel = Vector3.zero
	H.yaw = H.baseYaw
	H.pitch, H.roll = 0, 0
	H.fall = nil
	H.enemy = nil
	H.reloading = false
	H.ammo = #H.rockets
	H.entry = nil
	H.lastFire = -999
	RS.makeStatic(H.model, true)
	RS.setVisible(H.model, true)
	for _, r in ipairs(H.rockets) do
		setObjVisible(r, true)
	end
	if H.gui then H.gui.Enabled = true end
	applyCF(H, CFrame.new(H.home) * CFrame.Angles(0, H.baseYaw, 0))
	setAttr(H, "HeliAmmo", H.ammo)
	setAttr(H, "HeliArmor", HC.armor)
	setAttr(H, "HeliCooldownEnd", 0)
	setState(H, "idle")
	msg(H.data.player, "🚁 Вертолёт восстановлен и готов к вылету!", true)
end

local function startFall(H)
	RS.flying[H.model] = nil
	H.entry = nil
	H.enemy = nil
	H.model:SetAttribute("Airborne", false)

	local hv = Vector3.new(H.vel.X, 0, H.vel.Z)
	local ang = math.random() * math.pi * 2
	H.fall = {
		t = 0,
		spin = math.rad(90),
		rollDir = (math.random() < 0.5) and -1 or 1,
		drift = hv * 0.6 + Vector3.new(math.cos(ang), 0, math.sin(ang)) * (10 + math.random() * 20),
	}
	H.vel = Vector3.new(H.fall.drift.X, math.min(H.vel.Y, 0), H.fall.drift.Z)
	smallExplosion(H.pos, 6)

	local pp = H.model.PrimaryPart
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxassetid://243660364"
	fire.Rate = 80
	fire.Speed = NumberRange.new(3, 6)
	fire.Lifetime = NumberRange.new(0.3, 0.6)
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 0.5)
	})
	fire.Color = ColorSequence.new(
		Color3.fromRGB(255, 220, 120),
		Color3.fromRGB(255, 80, 0)
	)
	fire.LightEmission = 1
	fire.Transparency = NumberSequence.new(0.2, 1)
	fire.Parent = pp

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxassetid://243660364"
	smoke.Rate = 50
	smoke.Speed = NumberRange.new(2, 4)
	smoke.Lifetime = NumberRange.new(1.5, 2.5)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 8)
	})
	smoke.Color = ColorSequence.new(Color3.fromRGB(40, 40, 40))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1)
	})
	smoke.Parent = pp
	H.fx = { fire, smoke }

	setAttr(H, "HeliArmor", 0)
	setState(H, "falling")
	msg(H.data.player, "💥 Вертолёт сбит! Падает...", false)
end

local function updateFall(H, dt)
	local f = H.fall
	f.t = f.t + dt
	H.rotorAngle = H.rotorAngle + dt * math.max(45 - f.t * 8, 8)
	f.spin = math.min(f.spin + dt * math.rad(160), math.rad(720))
	H.vel = Vector3.new(f.drift.X, H.vel.Y - 30 * dt, f.drift.Z)
	H.pos = H.pos + H.vel * dt
	H.yaw = H.yaw + f.spin * dt
	local k = math.min(f.t / 1.5, 1)
	H.pitch = math.rad(-25) * k + math.sin(f.t * 3) * math.rad(8) * k
	H.roll = f.rollDir * math.rad(40) * k
	applyCF(H, CFrame.new(H.pos) * CFrame.Angles(0, H.yaw, 0) * CFrame.Angles(H.pitch, 0, H.roll))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { H.model }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(filter, p.Character) end
	end
	params.FilterDescendantsInstances = filter

	local ray = Workspace:Raycast(H.pos, Vector3.new(0, -(H.halfH + 1), 0), params)
	if ray or H.pos.Y < H.home.Y - 80 or f.t > 15 then
		crash(H, ray and ray.Position or H.pos)
	end
end

-- ===================== ОСНОВНОЙ АПДЕЙТ =====================
local function updateHeli(H, dt)
	local st = H.state
	if st == "destroyed" then return end

	H.swayT = H.swayT + dt
	H.bbT = H.bbT + dt
	if H.bbT > 0.5 then
		H.bbT = 0
		updateBillboard(H)
	end

	if st == "idle" then
		H.rotorAngle = H.rotorAngle + dt * 4
		applyCF(H, CFrame.new(H.home) * CFrame.Angles(0, H.baseYaw, 0))
		return
	end

	if st == "falling" then
		updateFall(H, dt)
		return
	end

	H.rotorAngle = H.rotorAngle + dt * 45

	if H.entry then
		if H.entry.armorLeft ~= H.lastArmor then
			H.lastArmor = H.entry.armorLeft
			setAttr(H, "HeliArmor", math.max(H.entry.armorLeft, 0))
			if H.entry.alive then
				msg(H.data.player, ("🚁 Вертолёт подбит! Защита: %d/%d"):format(H.entry.armorLeft, HC.armor), false)
			end
		end
		if not H.entry.alive then
			startFall(H)
			return
		end
	end

	local flyY = H.home.Y + HC.flyHeight
	local goal = H.target
	local horizTo = Vector3.new(goal.X - H.pos.X, 0, goal.Z - H.pos.Z)
	local hd = horizTo.Magnitude
	local desiredY = flyY
	local hMul = 1

	if st == "takeoff" then
		hMul = math.clamp((H.pos.Y - H.home.Y) / (HC.flyHeight * 0.5), 0, 1)
		if H.pos.Y >= flyY - 4 then
			setState(H, "flying")
			st = "flying"
		end
	elseif st == "returning" and hd < 5 then
		desiredY = H.home.Y
	end

	local dvH = Vector3.zero
	if hd > 0.3 then
		dvH = horizTo.Unit * math.min(HC.speed, hd) * hMul
	end
	local dvy = math.clamp((desiredY - H.pos.Y) * 1.2, -HC.vSpeed, HC.vSpeed)
	local a = 1 - math.exp(-dt * HC.accel)
	H.vel = H.vel:Lerp(Vector3.new(dvH.X, dvy, dvH.Z), a)
	H.pos = H.pos + H.vel * dt

	if st == "flying" and hd < 3 then
		setState(H, "hover")
		st = "hover"
	elseif st == "hover" and hd > 8 then
		setState(H, "flying")
		st = "flying"
	end

	if st == "returning" and hd < 3 and H.pos.Y - H.home.Y < 0.8 then
		land(H)
		return
	end

	local hv = Vector3.new(H.vel.X, 0, H.vel.Z)
	local targetYaw = H.yaw
	if hv.Magnitude > 4 then
		targetYaw = math.atan2(-hv.X, -hv.Z)
	elseif H.enemy and H.enemy.model.Parent then
		local ep = H.enemy.model:GetPivot().Position
		targetYaw = math.atan2(-(ep.X - H.pos.X), -(ep.Z - H.pos.Z))
	elseif hd > 4 then
		targetYaw = math.atan2(-horizTo.X, -horizTo.Z)
	end

	local dy = (targetYaw - H.yaw + math.pi) % (2 * math.pi) - math.pi
	local yawStep = math.clamp(dy, -dt * 2.2, dt * 2.2)
	H.yaw = H.yaw + yawStep
	local yawRate = yawStep / math.max(dt, 1e-3)

	local lv = CFrame.Angles(0, H.yaw, 0):VectorToObjectSpace(H.vel)
	local air = math.clamp((H.pos.Y - H.home.Y) / 12, 0, 1)
	local t = H.swayT
	local wantPitch = math.clamp(lv.Z / HC.speed, -1, 1) * math.rad(20) + math.sin(t * 0.8) * math.rad(2) * air
	local wantRoll = -math.clamp(lv.X / HC.speed, -1, 1) * math.rad(20) + yawRate * math.rad(8)
		+ (math.sin(t * 1.3) * math.rad(4) + math.sin(t * 3.1) * math.rad(1.5)) * air

	H.pitch = H.pitch + (wantPitch - H.pitch) * math.min(dt * 3, 1)
	H.roll = H.roll + (wantRoll - H.roll) * math.min(dt * 3, 1)

	local sway = Vector3.new(
		math.sin(t * 1.1) * 1.2 + math.sin(t * 2.3) * 0.4,
		math.sin(t * 1.7) * 0.7,
		math.cos(t * 0.9)
	) * air
	applyCF(H, CFrame.new(H.pos + sway) * CFrame.Angles(0, H.yaw, 0) * CFrame.Angles(H.pitch, 0, H.roll))

	if st ~= "takeoff" then combat(H, dt) end
end

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.1)
	for _, H in pairs(helis) do
		if H.model.Parent then
			local ok, err = pcall(updateHeli, H, dt)
			if not ok then warn("[Heli]", err) end
		end
	end
end)

-- ===================== РЕМОУТЫ =====================
BuyHeli.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end

	if data.heli then
		msg(player, "Вертолёт уже куплен", false)
		return
	end
	if money(player) < HC.price then
		msg(player, "Не хватает денег", false)
		return
	end

	local H, err = spawnHeli(data)
	if not H then
		msg(player, "❌ " .. tostring(err), false)
		return
	end

	player:SetAttribute("Money", money(player) - HC.price)
	msg(player, "🚁 Вертолёт куплен! Нажмите «ОТПРАВИТЬ ВЕРТОЛЁТ» и выберите точку", true)
end)

SendHeli.OnServerEvent:Connect(function(player, pos)
	if typeof(pos) ~= "Vector3" then return end
	local data = RS.players[player.UserId]
	local H = data and data.heli
	if not H then
		msg(player, "У вас нет вертолёта", false)
		return
	end
	if H.state == "destroyed" then
		msg(player, ("Вертолёт восстанавливается: %dс"):format(math.max(0, math.ceil(H.cooldownEnd - now()))), false)
		return
	end
	if H.state == "falling" then
		msg(player, "Вертолёт падает!", false)
		return
	end
	send(H, pos)
	msg(player, "🚁 Вертолёт летит к цели", true)
end)

RecallHeli.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data then return end
	if RS.recallHeli(data) then
		msg(player, "🚁 Вертолёт возвращается", true)
	end
end)

-- ===================== ИГРОКИ =====================
local function initAttrs(player)
	if player:GetAttribute("HeliOwned") == nil then
		player:SetAttribute("HeliOwned", false)
		player:SetAttribute("HeliState", "none")
		player:SetAttribute("HeliAmmo", 0)
		player:SetAttribute("HeliArmor", 0)
		player:SetAttribute("HeliCooldownEnd", 0)
	end
end

Players.PlayerAdded:Connect(initAttrs)
for _, p in ipairs(Players:GetPlayers()) do
	initAttrs(p)
end

Players.PlayerRemoving:Connect(function(player)
	local data = RS.players[player.UserId]
	if data then RS.removeHeli(data) end
end)

print("[Heli] ✅ Сервис вертолёта готов")