--[[
	CombatInput — управление бойцом (клиент).

	Атаки:
	  ЛКМ — комбо из 4 ударов (зажми, серия пойдёт сама)
	  F   — пинок-лончер
	  R   — лазер
	  X   — ульта (когда шкала заряжена)
	  V   — полёт (пробел вверх, Ctrl вниз, Shift ускорение)

	Здесь же приём серверных событий (попадания, отдача, ульта, звуки) и
	статистика для HUD. Каждый обработчик завёрнут в safe(), поэтому сбой
	одной способности не ломает остальные.
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

local State = {
	energy = 100, maxEnergy = Config.Energy.max,
	ult = 0, maxUlt = Config.Ult.max,
	cooldowns = {},
	combo = 0, comboTimer = 0, bestCombo = 0,
	damageEvents = {},
	totalDamage = 0, maxHit = 0, dps = 0, kos = 0,
	flying = false, chargeFrac = 0,
	ultActive = false, speed = 0, boost = 0,
	diag = false, ultReady = false,
}
Input.state = State

local remotes
local character, humanoid, root, anim
local comboIndex = 0
local comboT = 0
local mouse1Down = false
local punchQueued = false
local lastPunch = 0
local jumpCount = 0
local wasGrounded = true
local bank = 0
local lastLook = Vector3.new(0, 0, -1)
local spaceDown = false
local ctrlDown = false
local shiftDown = false
local lastAck = 0
local diagClock = 0
local boostSent = false
local boostClock = 0

local FLY = Config.Move

local function safe(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		warn("[EPIC COMBAT] " .. name .. ": " .. tostring(err))
	end
	return ok
end

local function stats()
	return player:FindFirstChild("CombatStats")
end

local function statNum(name, default)
	local s = stats()
	if not s then
		return default
	end
	local v = s:FindFirstChild(name)
	if v and v:IsA("NumberValue") then
		return v.Value
	end
	return default
end

-- ---------------------------------------------------------------------------
-- Кулдауны
-- ---------------------------------------------------------------------------
local function cdLeft(id)
	local c = State.cooldowns[id]
	if not c then
		return 0
	end
	return math.max(0, c.endT - os.clock())
end

local function cdReady(id)
	return cdLeft(id) <= 0
end

local function startCd(id)
	local def = Config.Abilities[id]
	if not def or def.cooldown <= 0 then
		return
	end
	State.cooldowns[id] = { endT = os.clock() + def.cooldown, total = def.cooldown }
end

local function canPay(id)
	local def = Config.Abilities[id]
	if not def then
		return false
	end
	if def.energy <= 0 then
		return true
	end
	return State.energy >= def.energy
end

local function canUse(id)
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if State.flying and id ~= "fly" then
		return false
	end
	if not cdReady(id) then
		return false
	end
	if not canPay(id) then
		return false
	end
	return true
end

local function fire(action, data)
	if remotes then
		remotes.Attack:FireServer(action, data or {})
	end
end

local function cameraDir()
	local cam = workspace.CurrentCamera
	if not cam then
		return Vector3.new(0, 0, -1)
	end
	return cam.CFrame.LookVector
end

local function flatDir()
	local look = cameraDir()
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
		flat = Vector3.new(flat.X, 0, flat.Z)
	end
	return flat.Unit
end

-- ---------------------------------------------------------------------------
-- Атаки
-- ---------------------------------------------------------------------------
local function advanceCombo()
	if os.clock() - comboT > Config.Combo.window then
		comboIndex = 0
	end
	comboIndex = comboIndex % #Config.Combo.names + 1
	comboT = os.clock()
	return comboIndex
end

local function doPunch()
	if not canUse("punch") then
		return
	end
	local i = advanceCombo()
	local name = Config.Combo.names[i]
	startCd("punch")
	local a = anim
	if a then
		a:play(name, {})
	end
	fire("punch", { index = i, look = flatDir() })
end

local function doKick()
	if not canUse("kick") then
		return
	end
	startCd("kick")
	local a = anim
	if a then
		a:play("kick", {})
	end
	fire("kick", { look = flatDir() })
end

local function doLaser()
	if not canUse("laser") then
		return
	end
	startCd("laser")
	local a = anim
	if a then
		a:play("laserCharge", {}, true)
	end
	Animator.setChargeHold(character, 0.4)
	local dir = cameraDir()
	local flat = Vector3.new(dir.X, dir.Y, dir.Z)
	task.delay(0.3, function()
		if not character or not character.Parent then
			return
		end
		local aa = Animator.get(character)
		if aa then
			aa:play("laser", {}, true)
		end
		fire("laser", { look = flat })
	end)
end

local function doUlt()
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	if State.ult < Config.Ult.max - 0.5 then
		Hud.announce("УЛЬТА НЕ ГОТОВА", math.floor(State.ult) .. "% из 100%", Color3.fromRGB(200, 205, 220), 1.2, 0.7)
		return
	end
	if State.ultActive then
		return
	end
	if not cdReady("ult") then
		return
	end
	startCd("ult")
	State.ultActive = true
	local a = anim
	if a then
		a:setState("ultActive", true)
		a:play("ultCharge", {}, true)
	end
	fire("ult", { look = flatDir() })
end

-- ---------------------------------------------------------------------------
-- Полёт
-- ---------------------------------------------------------------------------
local function setFlight(on)
	if on then
		if State.flying then
			return
		end
		if not character or not humanoid or humanoid.Health <= 0 then
			return
		end
		State.flying = true
		humanoid.PlatformStand = true
		startCd("fly")
		local a = anim
		if a then
			a:setState("flying", true)
			a:play("jump", {}, true)
		end
		Hud.announce("ПОЛЁТ", "пробел — вверх · Ctrl — вниз · Shift — ускорение", Config.Colors.ice, 1.5, 0.8)
		fire("fly", { state = true })
	else
		if not State.flying then
			return
		end
		State.flying = false
		if humanoid and humanoid.Health > 0 then
			humanoid.PlatformStand = false
		end
		local a = anim
		if a then
			a:setState("flying", false)
		end
		fire("fly", { state = false })
	end
end

local function doubleJump()
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	if jumpCount >= 2 then
		return
	end
	jumpCount = 2
	local look = flatDir()
	root.AssemblyLinearVelocity = look * FLY.doubleJumpAhead + Vector3.new(0, FLY.doubleJumpUp, 0)
	if anim then
		anim:play("flip", {}, true)
	end
	fire("doublejump", {})
end

-- ---------------------------------------------------------------------------
-- Обновление полёта и земли
-- ---------------------------------------------------------------------------
local function updateFlight(dt)
	if not character or not humanoid or not root then
		return
	end
	State.flying = State.flying and humanoid.Health > 0

	if not State.flying then
		bank = bank + (0 - bank) * math.min(dt * 4, 1)
		if anim then
			anim:setState("bank", bank)
			anim:setState("boost", 0)
		end
		State.boost = 0
		return
	end

	local dir = cameraDir()
	local speed = FLY.flySpeed
	local boosting = shiftDown and State.energy > 2
	if boosting then
		speed = FLY.flyBoost
	end
	local target = Vector3.new(dir.X, dir.Y, dir.Z) * speed
	if spaceDown then
		target = target + Vector3.new(0, FLY.flyVertical, 0)
	elseif ctrlDown then
		target = target - Vector3.new(0, FLY.flyVertical, 0)
	end
	local boostK = boosting and 1 or 0
	State.boost = State.boost + (boostK - State.boost) * math.min(dt * 5, 1)

	local v = root.AssemblyLinearVelocity
	local k = math.min(dt * FLY.flyAccel, 1)
	root.AssemblyLinearVelocity = v + (target - v) * k

	-- крен в поворотах
	local look = dir
	local yaw = math.atan2(look.X, -look.Z)
	local lastYaw = math.atan2(lastLook.X, -lastLook.Z)
	local dy = yaw - lastYaw
	if dy > math.pi then
		dy = dy - math.pi * 2
	elseif dy < -math.pi then
		dy = dy + math.pi * 2
	end
	local wantBank = math.clamp(dy * 14, -0.7, 0.7)
	bank = bank + (wantBank - bank) * math.min(dt * 6, 1)
	lastLook = look

	State.speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if anim then
		anim:setState("bank", bank)
		anim:setState("boost", State.boost)
	end

	-- сообщаем серверу про ускорение (не чаще 3 раз в секунду)
	if boosting then
		if not boostSent or os.clock() - boostClock > 0.35 then
			boostSent = true
			boostClock = os.clock()
			fire("boost", { state = true })
		end
	elseif boostSent then
		boostSent = false
		fire("boost", { state = false })
	end
end

local function updateGround(dt)
	if not character or not humanoid or not root then
		return
	end
	if State.flying then
		return
	end
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if grounded and not wasGrounded then
		jumpCount = 0
	end
	wasGrounded = grounded
	-- спринт
	local want = Config.Fighter.walkSpeed
	if shiftDown and not State.flying then
		want = Config.Fighter.sprintSpeed
	end
	if math.abs(humanoid.WalkSpeed - want) > 0.05 and not State.flying then
		humanoid.WalkSpeed = want
	end
end

local function updateStats(dt)
	if not character or not humanoid or not root then
		return
	end
	State.energy = statNum("Energy", State.energy)
	State.ult = statNum("Ult", State.ult)
	State.totalDamage = statNum("Damage", 0)
	State.maxHit = statNum("MaxHit", 0)
	State.kos = statNum("KOs", 0)

	-- DPS по скользящему окну
	local now = os.clock()
	local ev = State.damageEvents
	while #ev > 0 and now - ev[1].t > 5 do
		table.remove(ev, 1)
	end
	local sum = 0
	for i = 1, #ev do
		sum = sum + ev[i].d
	end
	State.dps = sum / 5

	if State.comboTimer > 0 then
		State.comboTimer = math.max(0, State.comboTimer - dt)
		if State.comboTimer <= 0 then
			State.combo = 0
		end
	end

end

-- ---------------------------------------------------------------------------
-- Клавиатура
-- ---------------------------------------------------------------------------
local function bindKeys()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local kind = input.UserInputType
		local key = input.KeyCode
		if kind == Enum.UserInputType.MouseButton1 then
			mouse1Down = true
			safe("удар (ЛКМ)", doPunch)
		elseif key == Enum.KeyCode.F then
			safe("пинок (F)", doKick)
		elseif key == Enum.KeyCode.R then
			safe("лазер (R)", doLaser)
		elseif key == Enum.KeyCode.X then
			safe("ульта (X)", doUlt)
		elseif key == Enum.KeyCode.V then
			safe("полёт (V)", function()
				setFlight(not State.flying)
			end)
		elseif key == Enum.KeyCode.Space then
			spaceDown = true
			if not State.flying then
				local grounded = humanoid and humanoid.FloorMaterial ~= Enum.Material.Air
				if not grounded then
					safe("двойной прыжок", doubleJump)
				end
			end
		elseif key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.RightControl then
			ctrlDown = true
		elseif key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift then
			shiftDown = true
		elseif key == Enum.KeyCode.T then
			safe("сброс манекенов", function()
				fire("reset", {})
			end)
		elseif key == Enum.KeyCode.H then
			safe("панель", Hud.toggleHelp)
		elseif key == Enum.KeyCode.F3 then
			safe("диагностика", Hud.toggleDiag)
			State.diag = not State.diag
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local key = input.KeyCode
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouse1Down = false
		elseif key == Enum.KeyCode.Space then
			spaceDown = false
		elseif key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.RightControl then
			ctrlDown = false
		elseif key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift then
			shiftDown = false
		end
	end)
end

-- Автоповтор ударов при зажатой ЛКМ
local function autoPunch(dt)
	if not mouse1Down or State.flying then
		return
	end
	local now = os.clock()
	if now - lastPunch < 0.3 then
		return
	end
	if not cdReady("punch") then
		return
	end
	lastPunch = now
	safe("серия ударов", doPunch)
end

-- ---------------------------------------------------------------------------
-- Серверные события
-- ---------------------------------------------------------------------------
local function setupRemotes()
	remotes = RS:WaitForChild("CombatRemotes", 10)
	if not remotes then
		warn("[EPIC COMBAT] не нашёл CombatRemotes в ReplicatedStorage")
		return
	end
	local attack = remotes:WaitForChild("Attack", 10)
	local action = remotes:WaitForChild("Action", 10)
	local feedback = remotes:WaitForChild("Feedback", 10)
	local hurt = remotes:WaitForChild("Hurt", 10)
	local ult = remotes:WaitForChild("Ult", 10)
	local sfx = remotes:WaitForChild("Sfx", 10)
	local ack = remotes:WaitForChild("Ack", 10)
	if not (attack and action and feedback and hurt and ult and sfx and ack) then
		warn("[EPIC COMBAT] не все remote-объекты на месте")
		return
	end
	remotes.Attack = attack
	remotes.Action = action
	remotes.Feedback = feedback
	remotes.Hurt = hurt
	remotes.Ult = ult
	remotes.Sfx = sfx
	remotes.Ack = ack

	action.OnClientEvent:Connect(function(target, name, data)
		safe("событие " .. tostring(name), function()
			if not target or not target.Parent then
				return
			end
			data = data or {}
			local a = Animator.get(target)
			if name == "setFly" then
				if a then
					a:setState("flying", data.state and true or false)
				end
			elseif name == "setKO" then
				if a then
					a:setKO(data.state and true or false)
				end
			elseif name == "hit" then
				if a then
					local rel
					local r = target:FindFirstChild("HumanoidRootPart")
					if r and data.dir then
						rel = r.CFrame:VectorToObjectSpace(data.dir)
					end
					a:flinch(rel, data.power)
					if target:GetAttribute("Dummy") then
						a:flash(Config.Dummy.flashColor, 0.16)
					end
				end
			elseif name == "respawn" then
				if a then
					a:setKO(false)
				end
			elseif not data.auth then
				if a then
					a:play(name, data, true)
				end
			end
		end)
	end)

	feedback.OnClientEvent:Connect(function(info)
		safe("отклик", function()
			info = info or {}
			if info.kind == "hit" then
				local dmg = info.damage or 0
				State.damageEvents[#State.damageEvents + 1] = { t = os.clock(), d = dmg }
				if dmg > State.maxHit then
					State.maxHit = dmg
				end
				State.combo = (State.combo or 0) + 1
				State.comboTimer = 1.6
				if State.combo > State.bestCombo then
					State.bestCombo = State.combo
				end
				Hud.hitmarker(info.crit, info.killed)
				Hud.combo(State.combo)
				Float.show(info.pos or (root and root.Position + Vector3.new(0, 3, 0)) or Vector3.new(0, 5, 0),
					dmg, { crit = info.crit, kill = info.killed })
				if info.crit then
					Camera.punch(1.5)
				end
			elseif info.kind == "miss" then
				Hud.hitmarker(false, false)
			end
		end)
	end)

	hurt.OnClientEvent:Connect(function(info)
		safe("урон", function()
			info = info or {}
			if info.kind == "fall" then
				Hud.announce("ВОЗВРАТ НА АРЕНУ", "не улетай слишком далеко", Config.Colors.plasma, 1.6, 0.8)
				return
			end
			Camera.flash(Config.Colors.danger, 0.35, 0.4)
			Camera.shake(0.9)
			if State.flying then
				setFlight(false)
			end
			if info.damage and info.damage > 0 then
				Float.text(root and root.Position + Vector3.new(0, 4, 0) or Vector3.new(0, 5, 0),
					"-" .. math.floor(info.damage), Config.Colors.danger)
			end
		end)
	end)

	ult.OnClientEvent:Connect(function(info)
		safe("ульта", function()
			info = info or {}
			local caster = info.caster
			local isMe = (caster == character)
			local a = caster and Animator.get(caster)
			if info.phase == "charge" then
				if isMe then
					Hud.announce("ОБЛИТЕРАЦИЯ", "заряжаю ульту — не подходи", Config.Colors.ult, 1.2, 0.9)
				else
					Hud.announce("УЛЬТА ВРАГА", (caster and caster.Name or "") .. " заряжает удар", Config.Colors.danger, 1.6, 0.8)
				end
			elseif info.phase == "burst" then
				if a then
					a:play("ultBurst", {}, true)
				end
				if isMe then
					Hud.announce("ОБЛИТЕРАЦИЯ!", "", Config.Colors.ultHot, 1.6, 1.1)
				end
			elseif info.phase == "beam" then
				if a then
					a:play("ultBeam", {}, true)
				end
			elseif info.phase == "end" then
				if a then
					a:play("ultSlam", {}, true)
					a:setState("ultActive", false)
				end
				if isMe then
					State.ultActive = false
					Hud.announce("УЛЬТА ЗАВЕРШЕНА", "копи заново", Color3.fromRGB(200, 205, 220), 1.2, 0.7)
				end
			end
		end)
	end)

	sfx.OnClientEvent:Connect(function(name, position, vol, pitch)
		safe("звук", function()
			Animator.playSound(name, position, vol, pitch)
		end)
	end)

	ack.OnClientEvent:Connect(function(kind, info)
		safe("ack", function()
			lastAck = os.clock()
			info = info or {}
			if kind == "announce" then
				Hud.announce(info.text or "", info.sub, info.color, info.time or 1.6, info.scale or 0.85)
			elseif kind == "denied" then
				local def = Config.Abilities[info.action]
				local label = def and def.name or info.action
				if info.reason == "energy" then
					Hud.announce("НЕТ ЭНЕРГИИ", label, Config.Colors.danger, 1, 0.7)
				elseif info.reason == "cooldown" then
					Hud.announce("ПЕРЕЗАРЯДКА", label, Color3.fromRGB(200, 205, 220), 0.8, 0.65)
				end
			end
		end)
	end)

end

-- ---------------------------------------------------------------------------
-- Персонаж
-- ---------------------------------------------------------------------------
local function onCharacter(newChar)
	character = newChar
	humanoid = newChar:WaitForChild("Humanoid", 8)
	root = newChar:WaitForChild("HumanoidRootPart", 8)
	if not humanoid or not root then
		warn("[EPIC COMBAT] у персонажа нет Humanoid/HumanoidRootPart")
		return
	end
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.Fighter.jumpPower
	humanoid.WalkSpeed = Config.Fighter.walkSpeed
	humanoid.PlatformStand = false
	humanoid.BreakJointsOnDeath = false
	jumpCount = 0
	State.flying = false
	State.combo = 0
	comboIndex = 0
	bank = 0
	anim = Animator.get(newChar)
	Camera.bind(70)
	if anim then
		anim:setState("flying", false)
		anim:setState("ultActive", false)
	end
	Hud.announce("БОЙ!", "ЛКМ — комбо · F — пинок · R — лазер · X — ульта · V — полёт", Config.Colors.plasmaHot, 2.6, 0.95)

	humanoid.Died:Connect(function()
		safe("смерть", function()
			setFlight(false)
			State.ultActive = false
			if anim then
				anim:setKO(true)
			end
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- Запуск
-- ---------------------------------------------------------------------------
function Input.start()
	safe("настройка remote", setupRemotes)
	safe("привязка клавиш", bindKeys)
	safe("персонаж", function()
		onCharacter(player.Character or player.CharacterAdded:Wait())
	end)
	player.CharacterAdded:Connect(function(c)
		safe("новый персонаж", function()
			onCharacter(c)
		end)
	end)

	RunService.Heartbeat:Connect(function(dt)
		if not character or not character.Parent then
			return
		end
		safe("кадр", function()
			updateStats(dt)
			updateGround(dt)
			updateFlight(dt)
			autoPunch(dt)

			local st = State
			Hud.update(dt, {
				health = humanoid and humanoid.Health or 0,
				maxHealth = humanoid and humanoid.MaxHealth or 100,
				energy = st.energy, maxEnergy = Config.Energy.max,
				ult = st.ult, maxUlt = Config.Ult.max,
				cooldowns = st.cooldowns,
				combo = st.combo, comboTimer = st.comboTimer,
				totalDamage = st.totalDamage, dps = st.dps,
				maxHit = st.maxHit, kos = st.kos,
				flying = st.flying, speed = st.speed, boost = st.boost,
				ultActive = st.ultActive, chargeFrac = st.chargeFrac,
			})

			if st.ultActive then
				Hud.setCharge(true, math.clamp(st.ult / Config.Ult.max, 0, 1), "ОБЛИТЕРАЦИЯ")
			else
				Hud.setCharge(false)
			end
		end)
	end)

	-- экранные эффекты камеры
	RunService.RenderStepped:Connect(function(dt)
		safe("камера", function()
			Camera.update(dt)
			if humanoid and humanoid.MaxHealth > 0 then
				local frac = humanoid.Health / humanoid.MaxHealth
				Camera.setVignette(frac < 0.35 and (0.35 - frac) / 0.35 * 0.8 or 0)
			end
		end)
	end)

	-- диагностика (F3)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if State.diag then
				safe("диагностика", function()
					local n, sample = Animator.info()
					diagClock = math.floor(os.clock())
					local lines = {
						"БОЙЦОВ У АНИМАТОРА: " .. n,
					}
					if sample then
						lines[#lines + 1] = "РИГ: " .. tostring(sample.rig) .. " · шарниров " .. tostring(sample.joints)
							.. " · действие " .. tostring(sample.action)
					end
					lines[#lines + 1] = "СЕТЬ: " .. (lastAck > 0 and "ок" or "—")
						.. " · HP " .. math.floor(humanoid and humanoid.Health or 0)
						.. " · ЭНЕРГИЯ " .. math.floor(State.energy)
						.. " · УЛЬТА " .. math.floor(State.ult)
					lines[#lines + 1] = "ПОЛЁТ: " .. (State.flying and "да" or "нет")
						.. " · БАНК " .. string.format("%.2f", bank)
					Hud.setDiag(table.concat(lines, "\n"))
				end)
			end
		end
	end)
end

return Input
