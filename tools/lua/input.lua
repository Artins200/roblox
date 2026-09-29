--[[
	CombatInput — управление бойцом и клиентская логика.

	* комбо ударов (ЛКМ), заряженный удар (ПКМ), пинок (E), рывок (Q),
	  лазер (F), залп (C), блок (R), полёт (V), ульта (X), таунт (Z), сброс (T)
	* двойной прыжок с сальто, спринт на Shift
	* полёт: камера-относительное движение, пробел вверх, Ctrl вниз, Shift — буст
	* приём серверных событий: попадания, урон, отдача, нокдаун, ульта
	* ведение статистики (урон, DPS, комбо, нокауты) для HUD и табло
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local RS = script.Parent
local Config = require(RS:WaitForChild("CombatConfig"))
local Animator = require(RS:WaitForChild("CombatAnimator"))
local Hud = require(RS:WaitForChild("CombatHud"))
local Camera = require(RS:WaitForChild("CombatCamera"))
local Float = require(RS:WaitForChild("CombatFloat"))

local Input = {}
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local State = {
	energy = 100, maxEnergy = Config.Energy.max,
	ult = 0, maxUlt = Config.Ult.max,
	cooldowns = {},
	combo = 0, comboTimer = 0, bestCombo = 0,
	damageEvents = {},
	totalDamage = 0, maxHit = 0, dps = 0, kos = 0,
	flying = false, blocking = false, charging = false, chargeFrac = 0,
	ultActive = false, speed = 0, boost = false,
	topBoard = {},
	lastDeny = 0,
}
Input.state = State

local remotes
local character, humanoid, root, anim
local comboIndex = 0
local comboT = 0
local chargeStart = 0
local mouse1Down = false
local mouse2Down = false
local punchQueued = false
local lastPunch = 0
local lastLaser = 0
local lastBarrage = 0
local jumpCount = 0
local wasGrounded = true
local bank = 0
local lastYaw = 0
local boostAmount = 0
local sprinting = false

local FLY = Config.Move

-- ---------------------------------------------------------------------------
-- Помощники
-- ---------------------------------------------------------------------------
local function stats()
	return player:FindFirstChild("CombatStats")
end

local function cdReady(id)
	local c = State.cooldowns[id]
	return (not c) or (os.clock() >= c.endT)
end

local function cdLeft(id)
	local c = State.cooldowns[id]
	if not c then
		return 0
	end
	return math.max(0, c.endT - os.clock())
end

local function startCd(id)
	local def = Config.Abilities[id]
	if not def or def.cooldown <= 0 then
		return
	end
	State.cooldowns[id] = { endT = os.clock() + def.cooldown, total = def.cooldown }
end

local function cost(id)
	local def = Config.Abilities[id]
	if not def or def.energy <= 0 then
		return true
	end
	if State.energy < def.energy then
		Float.text(root.Position + Vector3.new(0, 4, 0), "НЕТ ЭНЕРГИИ", Config.Colors.danger)
		return false
	end
	State.energy = math.max(0, State.energy - def.energy)
	return true
end

local function canUse(id)
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	-- в полёте руки заняты управлением: удары/пинок/таунт недоступны
	if State.flying and (id == "punch" or id == "kick" or id == "heavy" or id == "taunt") then
		return false
	end
	if not cdReady(id) then
		return false
	end
	return true
end

local function fire(action, data)
	if remotes then
		remotes.Attack:FireServer(action, data)
	end
end

local function viewDir()
	if not camera then
		camera = workspace.CurrentCamera
	end
	local look = camera.CFrame.LookVector
	return Vector3.new(look.X, look.Y, look.Z)
end

local function flatDir()
	local look = viewDir()
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
		flat = Vector3.new(flat.X, 0, flat.Z)
	end
	return flat.Unit
end

-- ---------------------------------------------------------------------------
-- Удары и способности
-- ---------------------------------------------------------------------------
local function advanceCombo()
	local now = os.clock()
	if now - comboT > Config.Combo.window then
		comboIndex = 0
	end
	comboIndex = comboIndex % #Config.Combo.names + 1
	comboT = now
end

local function doPunch()
	if not canUse("punch") or not character then
		return
	end
	if State.blocking then
		return
	end
	advanceCombo()
	local name = Config.Combo.names[comboIndex]
	startCd("punch")
	local a = anim or Animator.get(character)
	if a then
		a:play(name, {})
	end
	-- финальный удар комбо — мощнее, с рывком вперёд
	if comboIndex == #Config.Combo.names then
		local flat = flatDir()
		if root then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X + flat.X * 14, v.Y + 6, v.Z + flat.Z * 14)
		end
	end
	fire("punch", { index = comboIndex, look = flatDir() })
end

local function doKick()
	if not canUse("kick") or not cost("kick") then
		return
	end
	startCd("kick")
	local a = anim or Animator.get(character)
	if a then
		a:play("kick", {})
	end
	local flat = flatDir()
	if root then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X + flat.X * 10, v.Y + 26, v.Z + flat.Z * 10)
	end
	fire("kick", { look = flat })
end

local function startHeavy()
	if State.flying then
		return
	end
	State.charging = true
	chargeStart = os.clock()
	local a = anim or Animator.get(character)
	if a then
		a:play("heavyCharge", {}, true)
	end
	Animator.setChargeHold(character, 999)
end

local function releaseHeavy()
	if not State.charging then
		return
	end
	State.charging = false
	local frac = math.clamp((os.clock() - chargeStart) / 1.2, 0, 1)
	local a = anim or Animator.get(character)
	if a then
		a:stop("heavyCharge")
	end
	Animator.setChargeHold(character, 0)
	if frac < 0.08 then
		frac = 0.08
	end
	if not cost("heavy") then
		return
	end
	if not cdReady("heavy") then
		return
	end
	startCd("heavy")
	if a then
		a:play("heavy", { charge = frac })
	end
	fire("heavy", { charge = frac, look = flatDir() })
end

local function doDash()
	if not canUse("dash") or not cost("dash") then
		return
	end
	startCd("dash")
	local a = anim or Animator.get(character)
	if a then
		a:play("dash", {})
	end
	local dir = State.flying and viewDir() or flatDir()
	if root then
		root.AssemblyLinearVelocity = dir * FLY.dashSpeed + Vector3.new(0, FLY.dashUp, 0)
	end
	fire("dash", { look = dir })
end

local function doLaser()
	if not canUse("laser") or not cost("laser") then
		return
	end
	startCd("laser")
	local a = anim or Animator.get(character)
	if a then
		a:play("laser", {})
	end
	local origin = root and root.CFrame.Position or Vector3.new()
	if character then
		local torso = character:FindFirstChild("Torso") or root
		if torso then
			origin = torso.CFrame.Position
		end
	end
	local dir = viewDir()
	fire("laser", { origin = origin, direction = dir })
end

local function startBarrage()
	if State.flying then
		return
	end
	if not cost("barrage") then
		return
	end
	local a = anim or Animator.get(character)
	if a then
		a:play("barrage", {}, true)
	end
	fire("barrage", { state = "start" })
	Animator.setChargeHold(character, 999)
end

local function stopBarrage()
	local a = anim or Animator.get(character)
	if a then
		a:stop("barrage")
	end
	Animator.setChargeHold(character, 0)
	fire("barrage", { state = "stop" })
end

local function doTaunt()
	if not canUse("taunt") then
		return
	end
	startCd("taunt")
	local a = anim or Animator.get(character)
	if a then
		a:play("taunt", {})
	end
	fire("taunt", {})
end

local function doUlt()
	if not canUse("ult") then
		return
	end
	if State.ult < Config.Ult.max - 0.5 then
		Float.text(root.Position + Vector3.new(0, 4, 0),
			"УЛЬТА " .. math.floor(State.ult) .. "%", Config.Colors.ult)
		return
	end
	if State.ultActive then
		return
	end
	startCd("ult")
	fire("ult", {})
end

local function doReset()
	fire("reset", {})
end

local function setFlight(on)
	if on and not State.flying then
		if not canUse("fly") then
			return
		end
		State.flying = true
		humanoid.PlatformStand = true
		startCd("fly")
		local a = anim or Animator.get(character)
		if a then
			a:setState("flying", true)
			a:play("jump", {}, true)
		end
		Hud.announce("ПОЛЁТ ВКЛЮЧЁН", "пробел — вверх · Ctrl — вниз · Shift — буст", Config.Colors.plasma, 1.6, 0.7)
		fire("fly", { state = true })
	elseif (not on) and State.flying then
		State.flying = false
		-- если боец погиб, PlatformStand трогать нельзя: им управляет рэгдолл
		if humanoid and humanoid.Health > 0 then
			humanoid.PlatformStand = false
		end
		local a = anim or Animator.get(character)
		if a then
			a:setState("flying", false)
		end
		fire("fly", { state = false })
	end
end

-- ---------------------------------------------------------------------------
-- Двойной прыжок
-- ---------------------------------------------------------------------------
local function doubleJump()
	if State.flying then
		return
	end
	if jumpCount >= 2 then
		return
	end
	jumpCount = 2
	local a = anim or Animator.get(character)
	if a then
		a:play("flip", {}, true)
	end
	local flat = flatDir()
	local v = root and root.AssemblyLinearVelocity or Vector3.zero
	local horiz = Vector3.new(v.X, 0, v.Z)
	local dir = horiz.Magnitude > 4 and horiz.Unit or flat
	root.AssemblyLinearVelocity = Vector3.new(
		dir.X * math.max(horiz.Magnitude * 0.6, FLY.doubleJumpAhead),
		FLY.doubleJumpUp,
		dir.Z * math.max(horiz.Magnitude * 0.6, FLY.doubleJumpAhead)
	)
	fire("doublejump", {})
end

-- ---------------------------------------------------------------------------
-- Клавиши
-- ---------------------------------------------------------------------------
local function bindKeys()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouse1Down = true
			doPunch()
			return
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			mouse2Down = true
			startHeavy()
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.E then
			doKick()
		elseif k == Enum.KeyCode.Q then
			doDash()
		elseif k == Enum.KeyCode.F then
			doLaser()
		elseif k == Enum.KeyCode.C then
			startBarrage()
		elseif k == Enum.KeyCode.R then
			State.blocking = true
			fire("block", { state = true })
			if anim then
				anim:setState("blocking", true)
			end
		elseif k == Enum.KeyCode.V then
			setFlight(not State.flying)
		elseif k == Enum.KeyCode.X then
			doUlt()
		elseif k == Enum.KeyCode.Z then
			doTaunt()
		elseif k == Enum.KeyCode.T then
			doReset()
		elseif k == Enum.KeyCode.H then
			Hud.toggleHelp()
		elseif k == Enum.KeyCode.Space then
			local grounded = humanoid and humanoid.FloorMaterial ~= Enum.Material.Air
			if not grounded and not State.flying then
				doubleJump()
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouse1Down = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			mouse2Down = false
			releaseHeavy()
		elseif input.KeyCode == Enum.KeyCode.C then
			stopBarrage()
		elseif input.KeyCode == Enum.KeyCode.R then
			State.blocking = false
			fire("block", { state = false })
			if anim then
				anim:setState("blocking", false)
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Приём серверных событий
-- ---------------------------------------------------------------------------
local function setupRemotes()
	remotes = RS:WaitForChild("CombatRemotes")

	-- анимации других бойцов (и «авторитетные» для себя: ульта, нокдаун, удар)
	remotes.Action.OnClientEvent:Connect(function(targetChar, action, data)
		if not targetChar or not targetChar.Parent then
			return
		end
		local isMe = (targetChar == character)
		data = data or {}
		if action == "setFly" then
			local a = Animator.get(targetChar)
			if a then
				a:setState("flying", data.state and true or false)
			end
			return
		elseif action == "setBlock" then
			local a = Animator.get(targetChar)
			if a then
				a:setState("blocking", data.state and true or false)
			end
			return
		elseif action == "hit" then
			local a = Animator.get(targetChar)
			if a then
				a:flinch(data.dir, data.power)
			end
			return
		elseif action == "ko" then
			local a = Animator.get(targetChar)
			if a then
				a:setKO(true)
			end
			return
		elseif action == "barrageStop" then
			local a = Animator.get(targetChar)
			if a then
				a:stop("barrage")
			end
			if isMe then
				Animator.setChargeHold(targetChar, 0)
			end
			return
		elseif action == "respawn" then
			local a = Animator.get(targetChar)
			if a then
				a:setKO(false)
			end
			return
		end
		if isMe and not data.auth then
			return
		end
		local a = Animator.get(targetChar)
		if a then
			a:play(action, data)
		end
	end)

	-- обратная связь по нашим ударам
	remotes.Feedback.OnClientEvent:Connect(function(info)
		if not info then
			return
		end
		if info.kind == "hit" then
			local crit = info.crit
			Float.show(info.pos, info.damage, { crit = crit, kill = info.killed })
			Hud.hitmarker(crit, info.killed)
			Camera.punch(crit and 2.6 or 1.2, crit and 1.4 or 0.5)
			if info.killed then
				Camera.shake(1.6, 0.35)
			end
			State.totalDamage = State.totalDamage + (info.damage or 0)
			if (info.damage or 0) > State.maxHit then
				State.maxHit = info.damage
			end
			State.damageEvents[#State.damageEvents + 1] = { t = os.clock(), amount = info.damage or 0 }
			State.combo = State.combo + 1
			State.comboTimer = 2.6
			if State.combo > State.bestCombo then
				State.bestCombo = State.combo
			end
			Hud.combo(State.combo)
			if info.killed then
				State.kos = State.kos + 1
				Hud.announce("НОКАУТ!", info.target or "", Config.Colors.hit, 1.4, 0.8)
			end
		elseif info.kind == "miss" then
			Hud.hitmarker(false, false)
		end
	end)

	-- урон по нам
	remotes.Hurt.OnClientEvent:Connect(function(info)
		if not info then
			return
		end
		if info.kind == "fall" then
			Hud.announce("ВОЗВРАТ НА АРЕНУ", "не улетай за пределы боя", Config.Colors.plasma, 2, 0.85)
			Camera.flash(Config.Colors.plasma, 0.2, 0.5)
			return
		end
		local dmg = info.damage or 0
		local col = info.blocked and Config.Colors.block or Config.Colors.danger
		Float.show((root and root.CFrame.Position or Vector3.new()) + Vector3.new(0, 3.2, 0), dmg,
			{ color = col, text = info.blocked and ("<b>БЛОК</b> " .. Float.fmt(dmg)) or nil })
		Camera.punch(math.clamp(dmg / 160, 0.6, 3), 0.6)
		Camera.shake(math.clamp(dmg / 220, 0.3, 1.6), 0.3)
		Camera.flash(info.blocked and Config.Colors.block or Color3.fromRGB(255, 40, 40), info.blocked and 0.18 or 0.3, 0.3)
		Hud.hitmarker(false, false)
	end)

	-- отдача от ударов других бойцов
	remotes.Knock.OnClientEvent:Connect(function(info)
		if not info or not root then
			return
		end
		local dir = info.dir or Vector3.new(0, 0, 0)
		local power = info.power or 0
		local up = info.up or 0
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X + dir.X * power, math.max(v.Y, 0) + up, v.Z + dir.Z * power)
		if info.stun then
			Camera.shake(1.4, 0.3)
		end
	end)

	-- объявления ульты и прочие крупные события
	remotes.Ult.OnClientEvent:Connect(function(info)
		if not info then
			return
		end
		local phase = info.phase
		-- аура ульты у себя
		if info.caster == character and character then
			local mine = Animator.get(character)
			if mine then
				mine:setState("ultActive", phase ~= "end")
			end
			State.ultActive = (phase ~= "end")
		end
		if phase == "charge" then
			Hud.announce("ОБЛИТЕРАЦИЯ", (info.name or "") .. "  заряжает УЛЬТУ — уходи!", Config.Colors.ult, 1.8, 0.9)
			if info.caster == character then
				Camera.flash(Config.Colors.ult, 0.25, 0.6)
			end
			Camera.shake(0.8, 0.6)
		elseif phase == "burst" then
			Hud.announce("ВСПЛЕСК ЭНЕРГИИ!", "", Config.Colors.ultHot, 1.2, 0.9)
			Camera.shake(2.2, 0.7)
		elseif phase == "beam" then
			Hud.announce("ОБЛИТЕРАЦИЯ!", info.name or "", Config.Colors.ultHot, 2.0, 1.1)
			Camera.shake(2.4, 0.8)
			Camera.flash(Color3.new(1, 1, 1), 0.18, 0.5)
		elseif phase == "end" then
			Hud.announce("УЛЬТА ЗАВЕРШЕНА", "заряд сброшен — копи заново", Color3.fromRGB(200, 200, 200), 1.6, 0.8)
		end
	end)

	-- звуки, инициированные сервером
	remotes.Sfx.OnClientEvent:Connect(function(name, position, volume, pitch)
		Animator.playSound(name, position, volume, pitch)
	end)

	-- отказ сервера
	remotes.Ack.OnClientEvent:Connect(function(kind, action, reason)
		if kind == "announce" then
			Hud.announce(action or "СОБЫТИЕ", "", Config.Colors.plasmaHot, 2.2, 0.8)
			return
		end
		if kind ~= "denied" then
			return
		end
		if os.clock() - State.lastDeny < 0.6 then
			return
		end
		State.lastDeny = os.clock()
		local msg = (reason == "energy") and "НЕТ ЭНЕРГИИ" or (reason == "cooldown") and "ПЕРЕЗАРЯДКА" or "НЕЛЬЗЯ"
		if root then
			Float.text(root.CFrame.Position + Vector3.new(0, 4.4, 0), msg, Color3.fromRGB(255, 120, 120))
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Кадровая логика
-- ---------------------------------------------------------------------------
local function updateStats(dt)
	-- энергия: локальная регенерация + синхронизация с сервером
	local st = stats()
	local serverEn = st and st:FindFirstChild("Energy") and st.Energy.Value or nil
	local serverUlt = st and st:FindFirstChild("Ult") and st.Ult.Value or nil
	if serverEn then
		if math.abs(serverEn - State.energy) > 8 then
			State.energy = serverEn
		else
			State.energy = math.min(Config.Energy.max, State.energy + Config.Energy.regen * dt)
		end
	end
	if serverUlt then
		State.ult = serverUlt
	end

	-- DPS по окну 5 секунд
	local cutoff = os.clock() - 5
	local sum = 0
	local list = State.damageEvents
	local write = 1
	for i = 1, #list do
		if list[i].t >= cutoff then
			list[write] = list[i]
			write = write + 1
			sum = sum + list[i].amount
		end
	end
	for i = write, #list do
		list[i] = nil
	end
	State.dps = sum / 5

	if State.comboTimer > 0 then
		State.comboTimer = State.comboTimer - dt
		if State.comboTimer <= 0 then
			State.combo = 0
		end
	end
	State.speed = root and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude or 0
	State.boost = boostAmount > 0.4

	-- полоса откатов для HUD
	local cds = {}
	for id, def in pairs(Config.Abilities) do
		local c = State.cooldowns[id]
		local frac = 0
		if c then
			frac = math.clamp((c.endT - os.clock()) / math.max(c.total, 0.01), 0, 1)
			if frac <= 0 then
				State.cooldowns[id] = nil
			end
		end
		if def.energy > 0 and State.energy < def.energy then
			frac = math.max(frac, math.clamp(1 - State.energy / def.energy, 0, 1))
		end
		cds[id] = { frac = frac }
	end
	State.cooldownsView = cds
end

local boardTimer = 0
local function updateBoard(dt)
	boardTimer = boardTimer + dt
	if boardTimer < 1.5 then
		return
	end
	boardTimer = 0
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local ls = p:FindFirstChild("leaderstats")
		local dmg = ls and ls:FindFirstChild("Урон")
		if dmg then
			list[#list + 1] = { name = p.DisplayName or p.Name, damage = dmg.Value }
		end
	end
	table.sort(list, function(a, b)
		return a.damage > b.damage
	end)
	local top = {}
	for i = 1, math.min(5, #list) do
		top[i] = list[i]
	end
	State.topBoard = top
end

local function updateFlight(dt)
	if not State.flying or not root or not humanoid then
		return
	end
	local look = viewDir()
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit
	local right = Vector3.new(-flat.Z, 0, flat.X)

	local move = Vector3.new(0, 0, 0)
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		move = move + look
	elseif UserInputService:IsKeyDown(Enum.KeyCode.S) then
		move = move - look
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		move = move - right
	elseif UserInputService:IsKeyDown(Enum.KeyCode.D) then
		move = move + right
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		move = move + Vector3.new(0, 1, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		move = move - Vector3.new(0, 1, 0)
	end

	local boosting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and move.Magnitude > 0.05
	boostAmount = boostAmount + ((boosting and 1 or 0) - boostAmount) * math.min(dt * 4, 1)
	if boosting then
		State.energy = math.max(0, State.energy - FLY.flyBoostCost * dt)
	end

	local speed = FLY.flySpeed + (FLY.flyBoost - FLY.flySpeed) * boostAmount
	local target
	if move.Magnitude > 0.05 then
		target = move.Unit * speed
	else
		target = Vector3.new(0, 0, 0)
	end

	local v = root.AssemblyLinearVelocity
	local accel = (move.Magnitude > 0.05) and FLY.flyAccel or FLY.flyDamp
	root.AssemblyLinearVelocity = v:Lerp(target, math.min(dt * accel, 1))

	-- поворот к камере
	local desiredYaw
	if move.Magnitude > 0.05 then
		local f = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
		if f.Magnitude > 5 then
			desiredYaw = math.atan2(-f.X, -f.Z)
		end
	end
	if not desiredYaw then
		desiredYaw = math.atan2(-flat.X, -flat.Z)
	end
	local curYaw = math.atan2(-root.CFrame.LookVector.X, -root.CFrame.LookVector.Z)
	local diff = ((desiredYaw - curYaw + math.pi) % (math.pi * 2)) - math.pi
	local newYaw = curYaw + diff * math.min(dt * 5, 1)
	if math.abs(diff) > 0.02 then
		root.CFrame = CFrame.new(root.CFrame.Position) * CFrame.Angles(0, newYaw, 0)
	end

	-- крен в повороте
	local yawRate = diff * math.min(dt * 5, 1) / math.max(dt, 0.001)
	bank = bank + (math.clamp(yawRate * 0.4, -1.1, 1.1) - bank) * math.min(dt * 4, 1)

	local a = anim or Animator.get(character)
	if a then
		a:setState("flying", true)
		a:setState("bank", bank)
		a:setState("boost", boostAmount)
	end
end

local function updateGround(dt)
	if State.flying then
		return
	end
	-- спринт / блок / базовая скорость
	sprinting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
	local want = Config.Fighter.walkSpeed
	if sprinting then
		want = want * 1.45
	end
	if State.blocking then
		want = want * 0.5
	end
	if math.abs(humanoid.WalkSpeed - want) > 0.05 then
		humanoid.WalkSpeed = want
	end
	bank = bank + (0 - bank) * math.min(dt * 4, 1)
	local a = anim or Animator.get(character)
	if a then
		a:setState("bank", bank)
		a:setState("boost", 0)
	end
end

local function autoPunch(dt)
	if not mouse1Down or State.blocking then
		return
	end
	local now = os.clock()
	if now - lastPunch < 0.34 then
		return
	end
	if not cdReady("punch") then
		return
	end
	lastPunch = now
	doPunch()
end

-- ---------------------------------------------------------------------------
-- Запуск
-- ---------------------------------------------------------------------------
local function onCharacter(newChar)
	character = newChar
	humanoid = newChar:WaitForChild("Humanoid", 6)
	root = newChar:WaitForChild("HumanoidRootPart", 6)
	if not humanoid or not root then
		return
	end
	humanoid.WalkSpeed = Config.Fighter.walkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.Fighter.jumpPower
	humanoid.PlatformStand = false
	jumpCount = 0
	State.flying = false
	State.blocking = false
	State.charging = false
	State.energy = Config.Energy.max
	comboIndex = 0
	anim = Animator.get(newChar)
	Camera.bind(70)
	Hud.announce("БОЙ!", "ЛКМ — комбо ударов · V — полёт · X — ульта", Config.Colors.plasmaHot, 3, 1)

	humanoid.Died:Connect(function()
		setFlight(false)
		State.blocking = false
		State.charging = false
		State.combo = 0
		if anim then
			anim:setKO(true)
		end
	end)

	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed then
			jumpCount = 0
			if wasGrounded == false then
				wasGrounded = true
			end
		elseif newState == Enum.HumanoidStateType.Jumping or newState == Enum.HumanoidStateType.Freefall then
			if wasGrounded then
				wasGrounded = false
				jumpCount = math.max(jumpCount, 1)
			end
		end
	end)
end

function Input.start()
	setupRemotes()
	bindKeys()
	onCharacter(player.Character or player.CharacterAdded:Wait())
	player.CharacterAdded:Connect(onCharacter)

	-- табло лидеров (сервер пишет leaderstats, клиент просто читает)
	RunService.Heartbeat:Connect(function(dt)
		if not character or not character.Parent then
			return
		end
		updateStats(dt)
		updateGround(dt)
		updateFlight(dt)
		updateBoard(dt)
		autoPunch(dt)

		local st = State
		if st.charging then
			st.chargeFrac = math.clamp((os.clock() - chargeStart) / 1.2, 0, 1)
		else
			st.chargeFrac = 0
		end

		Hud.update(dt, {
			health = humanoid and humanoid.Health or 0,
			maxHealth = humanoid and humanoid.MaxHealth or 100,
			energy = st.energy,
			maxEnergy = Config.Energy.max,
			ult = st.ult,
			maxUlt = Config.Ult.max,
			cooldowns = st.cooldownsView or {},
			combo = st.combo,
			comboTimer = st.comboTimer,
			totalDamage = st.totalDamage,
			dps = st.dps,
			maxHit = st.maxHit,
			kos = st.kos,
			topBoard = st.topBoard,
			flying = st.flying,
			speed = st.speed,
			boost = st.boost,
			ultActive = st.ultActive,
		})

		if st.charging then
			Hud.setCharge(true, st.chargeFrac, "ЗАРЯД " .. math.floor(st.chargeFrac * 100) .. "%")
		else
			Hud.setCharge(false)
		end
	end)

	-- экранные эффекты камеры
	RunService.RenderStepped:Connect(function(dt)
		Camera.update(dt)
		-- виньетка при низком HP
		if humanoid and humanoid.MaxHealth > 0 then
			local frac = humanoid.Health / humanoid.MaxHealth
			Camera.setVignette(frac < 0.35 and (0.35 - frac) / 0.35 * 0.85 or 0)
		end
	end)
end

return Input
