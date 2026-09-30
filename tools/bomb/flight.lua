local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

repeat task.wait() until _G.RocketSystem and _G.RocketSystem.Ready
local RS = _G.RocketSystem
RS.services = RS.services or {}
if RS.services.Flight then
	warn("[Flight] ❌ ДУБЛЬ! Отключён: " .. script:GetFullName())
	return
end
RS.services.Flight = script:GetFullName()

local Config = RS.Config
local remotes = RS.remotes
local RocketStateChanged = remotes.RocketStateChanged
local CameraFollowUpdate = remotes.CameraFollowUpdate
local CameraFollowEnd = remotes.CameraFollowEnd

local ROCKET_MODEL_OFFSET = CFrame.Angles(math.rad(-90), 0, 0)
local FLAME_DIRECTION = Enum.NormalId.Bottom
local HOLD_OFFSET = CFrame.new(0, -0.4, -1.3)
local SALVO_DELAY = 0.15
local TARGET_SCATTER = 5
local SPIN_TURNS = 1.5

local holdConns = {}
local putDown

local function getHand(char)
	return char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
end

-- ================= В РУКАХ =================
local function detach(data)
	local model = data.held
	if not model then return end
	data.held = nil
	if model.Parent then
		model:SetAttribute("Held", false)
	end
	if holdConns[model] then
		holdConns[model]:Disconnect()
		holdConns[model] = nil
	end
end

local function attach(data, model)
	local char = data.player.Character
	local hand = char and getHand(char)
	if not hand then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	data.held = model
	model:SetAttribute("Held", true)
	RS.makeStatic(model, false)

	holdConns[model] = RunService.Heartbeat:Connect(function()
		if not model.Parent or data.held ~= model then
			if holdConns[model] then
				holdConns[model]:Disconnect()
				holdConns[model] = nil
			end
			return
		end
		if not hand:IsDescendantOf(Workspace) or (hum and hum.Health <= 0) then
			if holdConns[model] then
				holdConns[model]:Disconnect()
				holdConns[model] = nil
			end
			putDown(data, model, RS.getHome(model))
			return
		end
		model:PivotTo(hand.CFrame * HOLD_OFFSET)
	end)
	RS.fire(RocketStateChanged, data, "Held", true)
end

putDown = function(data, model, pos)
	detach(data)
	RS.setHome(model, pos)
	RS.makeStatic(model, true)
	RS.placeAtRest(model, pos)
	data.noPickup = model
	RS.fire(RocketStateChanged, data, "Held", false)
end

RunService.Heartbeat:Connect(function()
	for _, data in pairs(RS.players) do
		if not data.held and not data.bot then
			local char = data.player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				if data.noPickup and (not data.noPickup.Parent
					or (data.noPickup:GetPivot().Position - hrp.Position).Magnitude > Config.PICKUP_DISTANCE + 2) then
					data.noPickup = nil
				end

				local best, bestD = nil, Config.PICKUP_DISTANCE
				for _, m in ipairs(data.rockets) do
					if m ~= data.noPickup and RS.isReady(m) and m.PrimaryPart then
						local d = (m.PrimaryPart.Position - hrp.Position).Magnitude
						if d <= bestD then
							best, bestD = m, d
						end
					end
				end
				if best then attach(data, best) end
			end
		end
	end
end)

remotes.RequestThrow.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data or not data.held then return end
	putDown(data, data.held, RS.getHome(data.held))
end)

-- ================= РАССТАНОВКА =================
remotes.PlaceRocket.OnServerEvent:Connect(function(player, pos)
	if typeof(pos) ~= "Vector3" then return end
	local data = RS.players[player.UserId]
	if not data or not data.held then return end

	local model = data.held
	local finalPos, ok = RS.resolvePlacement(data, pos, model, 0)
	if not ok then
		RS.msg(data, "Здесь совсем нет места — выберите другую точку", false)
		RocketStateChanged:FireClient(player, "Held", true)
		return
	end
	putDown(data, model, finalPos)
	if (finalPos - pos).Magnitude > 2 then
		RS.msg(data, "Место было занято — поставил рядом", true)
	else
		RS.msg(data, "Ракета поставлена", true)
	end
end)

remotes.PlaceTurret.OnServerEvent:Connect(function(player, pos, index)
	if typeof(pos) ~= "Vector3" then return end
	local data = RS.players[player.UserId]
	if not data then return end

	local T = data.turrets and data.turrets[math.floor(tonumber(index) or 1)]
	if not T or not T.model.Parent then return end

	local finalPos, ok = RS.resolvePlacement(data, pos, T, 1)
	if not ok then
		RS.msg(data, "Здесь совсем нет места для ПВО", false)
		return
	end
	RS.moveTurret(data, T, finalPos)
	if (finalPos - pos).Magnitude > 2 then
		RS.msg(data, "Место было занято — ПВО поставлено рядом", true)
	else
		RS.msg(data, ("ПВО #%d переставлено"):format(T.index), true)
	end
end)

remotes.RequestLaunch.OnServerEvent:Connect(function(player)
	local data = RS.players[player.UserId]
	if not data or not data.held then return end
	-- без спутника сигнала нет — ракеты не запускаются
	if not RS.hasSignal(data) then
		RS.signalRefused(data)
		return
	end
	remotes.CameraFollowStart:FireClient(player)
end)

-- ================= ЭФФЕКТЫ =================
local function addFlightFX(model)
	local part = model.PrimaryPart
	if not part then return function() end end

	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxassetid://243660364"
	fire.EmissionDirection = FLAME_DIRECTION
	fire.Rate = 120
	fire.Speed = NumberRange.new(25, 35)
	fire.Lifetime = NumberRange.new(0.15, 0.3)
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 0)
	})
	fire.Color = ColorSequence.new(
		Color3.fromRGB(255, 240, 150),
		Color3.fromRGB(255, 90, 0)
	)
	fire.LightEmission = 1
	fire.Transparency = NumberSequence.new(0.1, 1)
	fire.SpreadAngle = Vector2.new(8, 8)
	fire.Parent = part

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxassetid://243660364"
	smoke.EmissionDirection = FLAME_DIRECTION
	smoke.Rate = 50
	smoke.Speed = NumberRange.new(3, 6)
	smoke.Lifetime = NumberRange.new(1.2, 2)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 6)
	})
	smoke.Color = ColorSequence.new(
		Color3.fromRGB(200, 200, 200),
		Color3.fromRGB(120, 120, 120)
	)
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1)
	})
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Parent = part

	return function()
		fire.Enabled = false
		smoke.Enabled = false
		Debris:AddItem(fire, 1)
		Debris:AddItem(smoke, 3)
	end
end

-- ================= ВЗРЫВ =================
local function explodeAt(position, tier, ownerId, label, model)
	local radius = tier.radius
	local damage = tier.damage
	local extra = ""
	local extraDamage = 0
	local extraRadius = 0

	-- Проверяем мутацию
	if model and model:GetAttribute("Mutated") then
		local mutation = model:GetAttribute("Mutation")
		if mutation == "nuclear" then
			radius = 55
			damage = 200
			extra = "💥 ЯДЕРНЫЙ ВЗРЫВ! "
		elseif mutation == "electric" then
			radius = 45
			damage = 80
			extra = "⚡ ЭЛЕКТРИЧЕСКИЙ ВЗРЫВ! "
		elseif mutation == "tank" then
			radius = radius * 1.2
			damage = damage * 1.3
			extra = "🛡️ УЛУЧШЕННЫЙ ВЗРЫВ! "
		elseif mutation == "speed" then
			-- Уже обработано в полете
		end
	end

	local ex = Instance.new("Explosion")
	ex.Position = position
	ex.BlastRadius = radius
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.Parent = Workspace

	local hits = {}
	for uid, victim in pairs(RS.players) do
		if uid ~= ownerId then
			for _, m in ipairs(victim.rockets) do
				if m.Parent and m.PrimaryPart and not m:GetAttribute("Flying") then
					local mTier = m:GetAttribute("Tier") or victim.tier
					local vt = Config.Tiers[mTier]
					local d = (m.PrimaryPart.Position - position).Magnitude
					if d <= radius then
						local dmg = damage * (0.15 + 0.85 * (1 - d / radius))
						if math.random() < vt.resist then dmg = dmg * 0.25 end
						table.insert(hits, { m = m, dmg = math.floor(dmg + 0.5), tier = mTier })
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

	-- Эффект ядерной бомбы: замедление дохода врагов
	if extra:find("ЯДЕРНЫЙ") then
		for uid, victim in pairs(RS.players) do
			if uid ~= ownerId and victim.player.Parent then
				local dist = (position - RS.spawnLocations[victim.spawnIndex].Position).Magnitude
				if dist < 70 then
					victim.incomeMult = 0.3
					task.delay(30, function()
						if victim then victim.incomeMult = 1 end
					end)
					RS.msg(victim, "☢️ Радиация! Доход снижен на 70% на 30 секунд!", false)
				end
			end
		end
	end

	-- Электрический взрыв: сбивает ПВО
	if extra:find("ЭЛЕКТРИЧЕСКИЙ") then
		for uid, victim in pairs(RS.players) do
			if uid ~= ownerId then
				for _, T in ipairs(victim.turrets or {}) do
					if T.model.Parent and (T.model:GetPivot().Position - position).Magnitude < radius then
						if RS.disableTurret then
							RS.disableTurret(T, 15)
							RS.msg(victim, ("⚡ ПВО #%d выведено из строя на 15 секунд!"):format(T.index), false)
						end
					end
				end
			end
		end
	end

	RS.rewardCombat(ownerId, stats, extra .. (label or "🚀 удар ракетами"), position)

	if RS.hitHelisInRadius then
		RS.hitHelisInRadius(position, radius, ownerId, tier.armor + (model and model:GetAttribute("MutatedArmor") or 0), "🚀 ракета поразила вражеский вертолёт")
	end
end

-- ================= ТРАЕКТОРИЯ =================
local function bezierPoint(p0, p1, p2, p3, t)
	local u = 1 - t
	return p0 * (u*u*u) + p1 * (3*u*u*t) + p2 * (3*u*t*t) + p3 * (t*t*t)
end

local function bezierTangent(p0, p1, p2, p3, t)
	local u = 1 - t
	return (p1 - p0) * (3*u*u) + (p2 - p1) * (6*u*t) + (p3 - p2) * (3*t*t)
end

local function buildPath(startPos, targetPos, speedMult, model)
	local flat = Vector3.new(targetPos.X - startPos.X, 0, targetPos.Z - startPos.Z)
	local dist = flat.Magnitude
	local apex = math.clamp(dist * 0.45, 45, 140)
	local flatDir = dist > 0.5 and flat.Unit or Vector3.new(0, 0, -1)

	-- Скоростная мутация
	local speed = speedMult
	if model and model:GetAttribute("Mutation") == "speed" then
		speed = 3.0
	end

	return {
		p0 = startPos,
		p1 = startPos + Vector3.new(0, apex, 0),
		p2 = targetPos + Vector3.new(0, apex * 0.85, 0),
		p3 = targetPos,
		rightVec = flatDir:Cross(Vector3.yAxis).Unit,
		time = math.clamp(dist / 75 + 0.9, 1.6, 3.2) / speed,
	}
end

local function evaluate(path, t)
	local pos = bezierPoint(path.p0, path.p1, path.p2, path.p3, t)
	local dir = bezierTangent(path.p0, path.p1, path.p2, path.p3, t)
	if dir.Magnitude < 0.001 then dir = Vector3.yAxis end
	dir = dir.Unit
	local flightCF = CFrame.lookAt(pos, pos + dir, path.rightVec)
	local spin = math.rad(360 * SPIN_TURNS) * (t * t * (3 - 2 * t))
	return flightCF, flightCF * CFrame.Angles(0, 0, spin) * ROCKET_MODEL_OFFSET
end

-- ================= ЗАЛП =================
function RS.launchSalvo(data, models, target)
	local main = data.held
	local hasCamera = main ~= nil
	detach(data)
	RS.fire(RocketStateChanged, data, "Held", false)

	local rockets = {}
	for i, model in ipairs(models) do
		if model.Parent then
			RS.makeStatic(model, false)
			model:SetAttribute("Flying", true)
			RS.updateLabels(model)

			-- у каждой ракеты своя версия (старые остаются боевыми)
			local tIdx = model:GetAttribute("Tier") or data.tier
			local rt = Config.Tiers[tIdx]

			local tgt = target
			if i > 1 then
				tgt = tgt + Vector3.new(
					(math.random() * 2 - 1) * TARGET_SCATTER,
					0,
					(math.random() * 2 - 1) * TARGET_SCATTER
				)
			end

			local armor = rt.armor
			if model:GetAttribute("Mutation") == "tank" then
				armor = 8
			end

			local entry = {
				model = model,
				owner = data.userId,
				tier = tIdx,
				armorLeft = armor,
				alive = true,
				isHeli = false,
			}
			RS.flying[model] = entry

			table.insert(rockets, {
				model = model,
				entry = entry,
				tierIdx = tIdx,
				tier = rt,
				path = buildPath(model:GetPivot().Position, tgt, rt.speed, model),
				delay = (i - 1) * SALVO_DELAY,
				isMain = (model == main),
				started = false,
				done = false,
				stopFX = nil,
			})
		end
	end
	RS.refreshReady(data)

	local elapsed = 0
	local remaining = #rockets
	local cameraEnded = false

	while remaining > 0 do
		local dt = RunService.Heartbeat:Wait()
		elapsed = elapsed + dt

		for _, r in ipairs(rockets) do
		 if not r.done then
			if not r.model.Parent then
				r.done = true
				remaining = remaining - 1
			elseif not r.entry.alive then
				r.done = true
				remaining = remaining - 1
				if r.stopFX then r.stopFX() end
				RS.setVisible(r.model, false)
				if r.isMain and not cameraEnded then
					cameraEnded = true
					RS.fire(CameraFollowEnd, data)
				end
			else
				local lt = elapsed - r.delay
				if lt >= 0 then
					if not r.started then
						r.started = true
						r.stopFX = addFlightFX(r.model)
					end

					local t = math.clamp(lt / r.path.time, 0, 1)
					local flightCF, modelCF = evaluate(r.path, t)
					r.model:PivotTo(modelCF)

					if r.isMain then
						RS.fire(CameraFollowUpdate, data, flightCF)
					end

					local fuse = t > 0.08 and RS.heliProximity and RS.heliProximity(
						flightCF.Position,
						data.userId,
						Config.HELI_FUSE_RADIUS
					)

					if fuse then
						r.done = true
						remaining = remaining - 1
						if r.stopFX then r.stopFX() end
						explodeAt(flightCF.Position, r.tier, data.userId, "🚀 подрыв у вражеского вертолёта", r.model)
						RS.setVisible(r.model, false)
					elseif t >= 1 then
						r.done = true
						remaining = remaining - 1
						if r.stopFX then r.stopFX() end
						explodeAt(r.path.p3, r.tier, data.userId, nil, r.model)
						RS.setVisible(r.model, false)
					end
				end
			end
		 end
		end
	end

	task.wait(0.8)
	if hasCamera and not cameraEnded then
		RS.fire(CameraFollowEnd, data)
	end

	for _, r in ipairs(rockets) do
		RS.flying[r.model] = nil
		if r.model.Parent then
			r.model:SetAttribute("Flying", false)
			r.model:SetAttribute("CooldownEnd", tick() + Config.COOLDOWN_TIME)
			RS.setVisible(r.model, true)
			RS.makeStatic(r.model, true)
			RS.placeAtRest(r.model, RS.getHome(r.model))
			RS.updateLabels(r.model)
		end
	end
	RS.refreshReady(data)
end

remotes.SetTarget.OnServerEvent:Connect(function(player, target, quantity)
	if typeof(target) ~= "Vector3" then return end
	local data = RS.players[player.UserId]
	if not data or not data.held or not RS.isReady(data.held) then
		CameraFollowEnd:FireClient(player)
		return
	end
	-- финальная проверка сигнала: без спутника запрещено
	if not RS.hasSignal(data) then
		RS.signalRefused(data)
		CameraFollowEnd:FireClient(player)
		return
	end

	local list = { data.held }
	quantity = math.floor(tonumber(quantity) or 1)
	for _, m in ipairs(data.rockets) do
		if #list >= quantity then break end
		if m ~= data.held and RS.isReady(m) then
			table.insert(list, m)
		end
	end
	task.spawn(RS.launchSalvo, data, list, target)
end)

print("[Flight] ✅ Сервис полёта готов")