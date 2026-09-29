--[[
	CombatServer — серверная часть боя.

	* держит состояние бойцов (энергия, шкала ульты, полёт);
	* обрабатывает 4 атаки: комбо ударов, пинок, лазер, ульту;
	* считает урон по манекенам и игрокам, рассылает эффекты и звуки;
	* следит за регенерацией, возвратом упавших и таблицей лидеров арены.

	Манекены — просто белые болванчики: они ничего не делают и не умирают.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local RS = game:GetService("ReplicatedStorage")
local SSS = script.Parent

local Config = require(RS:WaitForChild("CombatConfig"))
local Vfx = require(SSS:WaitForChild("CombatVfx"))
local Dummies = require(SSS:WaitForChild("CombatDummies"))

local remotes
local state = {}

local function now()
	return os.clock()
end

local function stOf(player)
	local s = state[player]
	if not s then
		s = {
			comboIndex = 0, comboT = 0,
			energy = Config.Energy.max, ult = 0,
			ultActive = false, flying = false, boosting = false,
			lastDamage = -999, invulnUntil = 0,
			damage = 0, maxHit = 0, kos = 0, bestCombo = 0, combo = 0,
		}
		state[player] = s
	end
	return s
end

local function getRoot(char)
	if not char then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getHum(char)
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

local function isDummy(model)
	return model ~= nil and model:GetAttribute("Dummy") == true
end

-- ---------------------------------------------------------------------------
-- Статы игрока (клиент читает их для HUD)
-- ---------------------------------------------------------------------------
local function statValue(player, name, default)
	local folder = player:FindFirstChild("CombatStats")
	if not folder then
		return default
	end
	local v = folder:FindFirstChild(name)
	if v and v:IsA("NumberValue") then
		return v.Value
	end
	return default
end

local function setStat(player, name, value)
	local folder = player:FindFirstChild("CombatStats")
	if not folder then
		return
	end
	local v = folder:FindFirstChild(name)
	if v and v:IsA("NumberValue") and v.Value ~= value then
		v.Value = value
	end
end

local function setupPlayer(player)
	local stats = player:FindFirstChild("CombatStats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "CombatStats"
		stats.Parent = player
		local function num(name, value)
			local v = Instance.new("NumberValue")
			v.Name = name
			v.Value = value
			v.Parent = stats
		end
		num("Energy", Config.Energy.max)
		num("Ult", 0)
		num("Damage", 0)
		num("MaxHit", 0)
		num("KOs", 0)
	end
	local board = player:FindFirstChild("leaderstats")
	if not board then
		board = Instance.new("Folder")
		board.Name = "leaderstats"
		board.Parent = player
		local dmg = Instance.new("IntValue")
		dmg.Name = "Урон"
		dmg.Value = 0
		dmg.Parent = board
		local ko = Instance.new("IntValue")
		ko.Name = "КО"
		ko.Value = 0
		ko.Parent = board
	end
	stOf(player)
end

-- ---------------------------------------------------------------------------
-- Поиск целей (простой и надёжный: скан манекенов и игроков)
-- ---------------------------------------------------------------------------
local function findTargets(attacker, origin, dir, reach, radius)
	local out = {}
	local flatDir = Vector3.new(dir.X, dir.Y, dir.Z)
	if flatDir.Magnitude < 0.001 then
		flatDir = Vector3.new(0, 0, -1)
	end
	flatDir = flatDir.Unit

	local function consider(model, hum, root)
		if not root or not hum or model == attacker then
			return
		end
		local to = root.Position - origin
		local along = to:Dot(flatDir)
		if along < -3 or along > reach then
			return
		end
		local perp = to - flatDir * along
		local hitRadius = radius + math.max(root.Size.X, root.Size.Z) * 0.5
		if perp.Magnitude > hitRadius then
			return
		end
		out[#out + 1] = { model = model, hum = hum, root = root, pos = root.Position, along = along }
	end

	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		if ch then
			consider(ch, getHum(ch), getRoot(ch))
		end
	end
	local folder = Dummies.folder
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then
				consider(m, m:FindFirstChildOfClass("Humanoid"), m:FindFirstChild("HumanoidRootPart"))
			end
		end
	end
	table.sort(out, function(a, b)
		return a.along < b.along
	end)
	return out
end

local function findInRadius(center, radius, exceptModel)
	local out = {}
	local function consider(model, hum, root)
		if not root or not hum or model == exceptModel then
			return
		end
		if (root.Position - center).Magnitude <= radius then
			out[#out + 1] = { model = model, hum = hum, root = root, pos = root.Position }
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		if ch then
			consider(ch, getHum(ch), getRoot(ch))
		end
	end
	local folder = Dummies.folder
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then
				consider(m, m:FindFirstChildOfClass("Humanoid"), m:FindFirstChild("HumanoidRootPart"))
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Урон
-- ---------------------------------------------------------------------------
local function ownerOf(model)
	return Players:GetPlayerFromCharacter(model)
end

local function applyDamage(attacker, victimModel, victimHum, victimRoot, amount, opts)
	opts = opts or {}
	if not victimHum or victimHum.Health <= 0 then
		return false
	end
	local victimPlayer = ownerOf(victimModel)
	if victimPlayer then
		local vs = stOf(victimPlayer)
		if now() < (vs.invulnUntil or 0) then
			return false
		end
	end

	local crit = math.random() < Config.Crit.chance
	local dmg = amount
	if crit then
		dmg = math.floor(dmg * Config.Crit.mult)
	end
	dmg = math.floor(dmg * (0.92 + math.random() * 0.16))
	if dmg < 1 then
		dmg = 1
	end

	local dummy = isDummy(victimModel)
	if dummy then
		-- манекен не умирает: просто держим полную жизнь
		victimHum.Health = victimHum.MaxHealth
	else
		victimHum:TakeDamage(dmg)
	end

	-- импульс
	if victimRoot and not dummy then
		local push = opts.dir or Vector3.new(0, 0, 0)
		push = Vector3.new(push.X, 0, push.Z)
		if push.Magnitude > 0.001 then
			push = push.Unit
		else
			push = Vector3.new(0, 0, 0)
		end
		local kn = (opts.knock or 0) / math.max(victimRoot.AssemblyMass, 1)
		local up = (opts.up or 0) / math.max(victimRoot.AssemblyMass, 1)
		victimRoot.AssemblyLinearVelocity = victimRoot.AssemblyLinearVelocity
			+ push * kn + Vector3.new(0, up, 0)
	elseif victimRoot and dummy and opts.knock and opts.knock > 0 then
		local push = opts.dir or Vector3.new(0, 0, 0)
		victimRoot.AssemblyLinearVelocity = victimRoot.AssemblyLinearVelocity
			+ Vector3.new(push.X, 0, push.Z) * Config.Dummy.hitPush * (opts.knock / 60)
	end

	-- эффекты попадания
	local pos = victimRoot and victimRoot.Position or (opts.pos or Vector3.new(0, 0, 0))
	local scale = opts.fxScale or 4
	local color = (opts.heavy and Config.Colors.ultHot) or Config.Colors.hit
	Vfx.impact(pos + Vector3.new(0, 0.4, 0), color, scale * 0.5, 0.35)
	Vfx.sparks(pos, opts.dir or Vector3.new(0, 1, 0), opts.heavy and 10 or 5, color, 26, 0.4, 0.35)
	if opts.heavy then
		Vfx.ring(pos, Config.Colors.plasmaHot, 1.2, 9, 0.4, false, 0.45)
		Vfx.shockwave(pos - Vector3.new(0, 2.6, 0), color, 14, 0.5)
	end

	-- вспышка у жертвы + звук всем
	remotes.Action:FireAllClients(victimModel, "hit", {
		dir = opts.dir or Vector3.new(0, 0, -1),
		power = math.clamp((opts.power or 1) * 0.6, 0.4, 1.6),
	})
	remotes.Sfx:FireAllClients(opts.heavy and "hitHeavy" or "hit", pos, 1, 0.9 + math.random() * 0.25)
	Vfx.flash(pos, color, 1.6, 12, 0.2)

	-- уведомление атакующему
	if attacker then
		local aplayer = ownerOf(attacker)
		if aplayer then
			local as = stOf(aplayer)
			as.damage = as.damage + dmg
			if dmg > as.maxHit then
				as.maxHit = dmg
			end
			as.combo = as.combo + 1
			if as.combo > as.bestCombo then
				as.bestCombo = as.combo
			end
			as.ult = math.min(Config.Ult.max, as.ult + dmg * Config.Ult.perDamageDealt * (opts.ultBonus or 1))
			setStat(aplayer, "Damage", as.damage)
			setStat(aplayer, "MaxHit", as.maxHit)
			local killed = (not dummy) and victimHum.Health <= 0
			if killed then
				as.kos = as.kos + 1
				setStat(aplayer, "KOs", as.kos)
			end
			remotes.Feedback:FireClient(aplayer, {
				kind = "hit", damage = dmg, crit = crit, killed = killed,
				target = victimModel.Name, pos = pos,
			})
		end
	end

	-- ульта жертвы копится от полученного урона
	if victimPlayer then
		local vs = stOf(victimPlayer)
		vs.ult = math.min(Config.Ult.max, vs.ult + dmg * Config.Ult.perDamageTaken)
		vs.lastDamage = now()
		remotes.Hurt:FireClient(victimPlayer, { damage = dmg })
		if dummy then
			victimHum.Health = victimHum.MaxHealth
		end
	end
	return true
end

-- Луч: урон по всем, кто стоит в коридоре
local function damageBeam(attacker, origin, dir, range, radius, damage, opts)
	opts = opts or {}
	local hitAny = false
	local step = radius * 0.8
	local d = 0
	while d <= range do
		local center = origin + dir * d
		local list = findInRadius(center, radius, attacker)
		for i = 1, #list do
			local t = list[i]
			if not t.marked then
				t.marked = true
				hitAny = applyDamage(attacker, t.model, t.hum, t.root, damage, {
					dir = dir,
					knock = opts.knock or 60,
					up = opts.up or 12,
					power = opts.power or 1.6,
					heavy = true,
					fxScale = opts.fxScale or 8,
				}) or hitAny
			end
		end
		d = d + step
	end
	return hitAny
end

-- ---------------------------------------------------------------------------
-- Рассылка анимаций
-- ---------------------------------------------------------------------------
local function broadcast(char, name, data, caster)
	data = data or {}
	if caster then
		data.auth = true
	end
	remotes.Action:FireAllClients(char, name, data)
end

local function sfxAll(name, pos, vol, pitch)
	remotes.Sfx:FireAllClients(name, pos, vol or 1, pitch or 1)
end

-- ---------------------------------------------------------------------------
-- Энергия и кулдауны
-- ---------------------------------------------------------------------------
local function spend(player, id)
	local def = Config.Abilities[id]
	if not def then
		return false
	end
	local s = stOf(player)
	if def.energy > 0 and s.energy < def.energy then
		remotes.Ack:FireClient(player, "denied", { action = id, reason = "energy" })
		return false
	end
	if def.energy > 0 then
		s.energy = s.energy - def.energy
		setStat(player, "Energy", math.floor(s.energy))
	end
	return true
end

local function safeDir(char, data)
	local root = getRoot(char)
	local dir
	if data and typeof(data.look) == "Vector3" then
		dir = data.look
	elseif root then
		dir = root.CFrame.LookVector
	end
	if not dir then
		dir = Vector3.new(0, 0, -1)
	end
	if dir.Magnitude < 0.001 then
		dir = Vector3.new(0, 0, -1)
	end
	return dir.Unit
end

-- ---------------------------------------------------------------------------
-- Атаки
-- ---------------------------------------------------------------------------
local ATTACKS = {}

ATTACKS.punch = function(player, char, hum, root, s, data)
	local index = tonumber(data.index) or 1
	index = math.clamp(math.floor(index), 1, #Config.Combo.names)
	local name = Config.Combo.names[index]
	local dir = safeDir(char, data)
	local origin = root.Position + Vector3.new(0, 1.2, 0)

	broadcast(char, name, {}, player)
	sfxAll("whoosh", origin, 0.8, 1.15 + index * 0.05)

	-- рывок вперёд у атакующего
	local lunge = Config.Combo.lunge[index] or 3
	root.AssemblyLinearVelocity = root.AssemblyLinearVelocity
		+ Vector3.new(dir.X, 0, dir.Z) * lunge * 3

	local targets = findTargets(char, origin, dir, Config.Combo.reach[index], Config.Combo.radius[index])
	if #targets == 0 then
		remotes.Feedback:FireClient(player, { kind = "miss" })
		Vfx.ring(origin + dir * 3.4, Config.Colors.plasma, 0.8, 5.5, 0.28, true, 0.3)
		return
	end

	local finisher = (index == #Config.Combo.names)
	local heavy = finisher or index == 3
	for i = 1, #targets do
		local t = targets[i]
		local dirTo = t.pos - origin
		if dirTo.Magnitude < 0.1 then
			dirTo = dir
		end
		applyDamage(player, t.model, t.hum, t.root, Config.Combo.damage[index], {
			dir = Vector3.new(dirTo.X, 0, dirTo.Z).Unit,
			pos = t.pos + Vector3.new(0, 0.8, 0),
			knock = Config.Combo.knock[index],
			up = Config.Combo.launch[index],
			power = index / 2,
			heavy = heavy,
			fxScale = finisher and 9 or (4 + index),
			ultBonus = Config.Combo.ult[index] * 0.3,
		})
	end

	if finisher then
		Vfx.slash(CFrame.new(origin + dir * 3) * CFrame.Angles(0, math.atan2(dir.X, -dir.Z), 0),
			Config.Colors.plasma, 14, 9, 0.3)
		Vfx.ring(origin, Config.Colors.plasmaHot, 2, 20, 0.45, false, 0.5)
		Vfx.flash(origin + dir * 4, Config.Colors.plasmaHot, 2, 20, 0.25)
		sfxAll("whooshBig", origin, 1, 0.9)
	end
end

ATTACKS.kick = function(player, char, hum, root, s, data)
	if not spend(player, "kick") then
		return
	end
	local dir = safeDir(char, data)
	local origin = root.Position + Vector3.new(0, 1.4, 0)
	broadcast(char, "kick", {}, player)
	sfxAll("whoosh", origin, 1, 0.9)

	-- атакующий подпрыгивает вперёд
	root.AssemblyLinearVelocity = root.AssemblyLinearVelocity
		+ Vector3.new(dir.X, 0, dir.Z) * 26 + Vector3.new(0, 16, 0)

	local targets = findTargets(char, origin, dir, Config.Damage.kickReach, Config.Damage.kickRadius)
	if #targets == 0 then
		remotes.Feedback:FireClient(player, { kind = "miss" })
		return
	end
	for i = 1, #targets do
		local t = targets[i]
		local dirTo = t.pos - origin
		if dirTo.Magnitude < 0.1 then
			dirTo = dir
		end
		applyDamage(player, t.model, t.hum, t.root, Config.Damage.kick, {
			dir = Vector3.new(dirTo.X, 0, dirTo.Z).Unit,
			pos = t.pos + Vector3.new(0, 1, 0),
			knock = Config.Damage.kickKnock,
			up = Config.Damage.kickLaunch,
			power = 1.8,
			heavy = true,
			fxScale = 10,
		})
	end
	Vfx.ring(origin + dir * 4, Config.Colors.ultHot, 1.4, 12, 0.35, true, 0.4)
end

ATTACKS.laser = function(player, char, hum, root, s, data)
	if not spend(player, "laser") then
		return
	end
	local dir = safeDir(char, data)
	broadcast(char, "laserCharge", {}, player)
	sfxAll("charge", root.Position, 0.7, 1.2)

	task.spawn(function()
		task.wait(0.3)
		if not char.Parent then
			return
		end
		local r = getRoot(char)
		if not r then
			return
		end
		local origin = r.Position + Vector3.new(0, 1.6, 0) + dir * 2
		broadcast(char, "laser", {}, player)

		local range = Config.Damage.laserRange
		local hitPoint, hitPos = nil, nil
		-- луч упирается в арену/постройки, но бьёт всё живое по пути
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local filter = { char }
		if Dummies.folder then
			filter[#filter + 1] = Dummies.folder
		end
		params.FilterDescendantsInstances = filter
		local result = workspace:Raycast(origin, dir * range, params)
		if result then
			hitPos = result.Position
			hitPoint = result.Instance
		end
		local to = hitPos or (origin + dir * range)

		Vfx.beam(origin, to, Config.Colors.plasma, 1.6, 0.28, 2.6, Config.Colors.plasmaHot)
		Vfx.flash(origin, Config.Colors.plasmaHot, 3, 26, 0.22)
		Vfx.impact(to, Config.Colors.plasmaHot, 8, 0.4)
		sfxAll("laser", origin, 1, 1)
		remotes.Action:FireAllClients(char, "laserFire", { auth = true }, nil)

		damageBeam(player, origin, dir, (to - origin).Magnitude + 2, Config.Damage.laserRadius,
			Config.Damage.laser, { knock = 70, up = 14, power = 1.6, fxScale = 9 })
	end)
end

ATTACKS.ult = function(player, char, hum, root, s, data)
	if s.ultActive then
		return
	end
	if s.ult < Config.Ult.max - 0.5 then
		remotes.Ack:FireClient(player, "denied", { action = "ult", reason = "energy" })
		return
	end
	local origin = root.Position
	s.ult = 0
	s.ultActive = true
	s.invulnUntil = now() + 3.4
	setStat(player, "Ult", 0)

	remotes.Ult:FireAllClients({ phase = "charge", caster = char, name = player.Name })
	sfxAll("ultCharge", origin, 1, 0.7)
	Vfx.pillar(origin, Config.Colors.ult, 60, 6, 1.0)
	Vfx.chargeOrb(root, Vector3.new(0, 0, 0), Config.Colors.ult, 1.0, 3)

	task.spawn(function()
		local ok, err = pcall(function()
		task.wait(1.0)
		if not char.Parent then
			return
		end
		local r = getRoot(char)
		if not r then
			return
		end
		local here = r.Position

		-- НОВА
		remotes.Ult:FireAllClients({ phase = "burst", caster = char })
		Vfx.nova(here, Config.Colors.ultHot, 52, 1.3)
		Vfx.ring(here, Config.Colors.ult, 3, 70, 0.9, false, 0.8)
		Vfx.flash(here, Config.Colors.ultHot, 5, 90, 0.5)
		sfxAll("ultFire", here, 1, 0.6)
		r.AssemblyLinearVelocity = Vector3.new(0, 72, 0)

		local list = findInRadius(here, 46, char)
		for i = 1, #list do
			local t = list[i]
			local dirTo = t.pos - here
			if dirTo.Magnitude < 0.5 then
				dirTo = Vector3.new(0, 1, 0)
			end
			applyDamage(player, t.model, t.hum, t.root, Config.Damage.ultNova, {
				dir = Vector3.new(dirTo.X, 0, dirTo.Z).Unit,
				knock = 210, up = 70, power = 2.4, heavy = true, fxScale = 14,
			})
		end

		task.wait(0.45)
		if not char.Parent then
			return
		end
		local r2 = getRoot(char)
		if not r2 then
			return
		end

		-- ГИГАНТСКИЙ ЛУЧ
		remotes.Ult:FireAllClients({ phase = "beam", caster = char })
		sfxAll("ultFire", r2.Position, 1, 0.5)
		local aim = safeDir(char, {})
		local start = r2.Position + Vector3.new(0, 0.5, 0)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local filter = { char }
		if Dummies.folder then
			filter[#filter + 1] = Dummies.folder
		end
		params.FilterDescendantsInstances = filter
		local result = workspace:Raycast(start + aim * 2, aim * Config.Damage.ultBeamRange, params)
		local endPos = result and result.Position or (start + aim * Config.Damage.ultBeamRange)
		Vfx.giantBeam(start, aim, (endPos - start).Magnitude, Config.Colors.ult, Config.Colors.ultHot,
			Config.Damage.ultBeamRadius, 1.1)
		Vfx.flash(start, Config.Colors.ultHot, 4, 60, 0.4)
		damageBeam(player, start, aim, (endPos - start).Magnitude + 4, Config.Damage.ultBeamRadius,
			Config.Damage.ultBeam, { knock = 260, up = 80, power = 2.6, fxScale = 18 })

		task.wait(1.0)
		if not char.Parent then
			return
		end
		local r3 = getRoot(char)

		-- ПРИЗЕМЛЕНИЕ
		remotes.Ult:FireAllClients({ phase = "end", caster = char })
		if r3 then
			r3.AssemblyLinearVelocity = Vector3.new(0, -140, 0)
			task.wait(0.3)
			local ground = r3.Position
			Vfx.shockwave(ground - Vector3.new(0, 2.6, 0), Config.Colors.ultHot, 40, 0.7)
			Vfx.dust(ground, 14, Color3.fromRGB(200, 205, 220), 1.6)
			Vfx.scorch(ground - Vector3.new(0, 2.9, 0), 12, 8)
			sfxAll("hitHeavy", ground, 1, 0.6)
			local list2 = findInRadius(ground, 26, char)
			for i = 1, #list2 do
				local t = list2[i]
				applyDamage(player, t.model, t.hum, t.root, Config.Damage.ultSlam, {
					knock = 120, up = 34, power = 2, heavy = true, fxScale = 12,
				})
			end
		end
		end)
		s.ultActive = false
		s.invulnUntil = now() + 0.6
		if not ok then
			warn("[EPIC COMBAT] сценарий ульты: " .. tostring(err))
		end
	end)
end

ATTACKS.fly = function(player, char, hum, root, s, data)
	local on = data.state and true or false
	s.flying = on
	if not on then
		s.boosting = false
		if hum and hum.Health > 0 then
			hum.PlatformStand = false
		end
		root.AssemblyLinearVelocity = root.AssemblyLinearVelocity * 0.3
	else
		if hum and hum.Health > 0 then
			hum.PlatformStand = true
			root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + Vector3.new(0, 26, 0)
		end
		Vfx.ring(root.Position - Vector3.new(0, 2.4, 0), Config.Colors.ice, 1.5, 14, 0.5, false, 0.4)
		Vfx.pillar(root.Position, Config.Colors.ice, 22, 3.2, 0.5, true)
	end
	broadcast(char, "setFly", { state = on }, player)
end

ATTACKS.boost = function(player, char, hum, root, s, data)
	s.boosting = data.state and true or false
end

ATTACKS.doublejump = function(player, char, hum, root, s, data)
	-- двойной прыжок рисует клиент; сервер только показывает эффект всем
	Vfx.ring(root.Position - Vector3.new(0, 2.6, 0), Config.Colors.ice, 1.2, 11, 0.4, false, 0.4)
	sfxAll("jump", root.Position, 0.8, 1.3)
end

ATTACKS.reset = function(player, char, hum, root, s, data)
	local n = Dummies.resetAll(Vfx)
	remotes.Ack:FireClient(player, "announce", {
		text = "МАНЕКЕНЫ НА МЕСТАХ", sub = "сброшено: " .. tostring(n),
		color = Config.Colors.plasma, time = 1.4, scale = 0.8,
	})
end

-- ---------------------------------------------------------------------------
-- Обработка запросов
-- ---------------------------------------------------------------------------
local function onAttack(player, action, data)
	if type(action) ~= "string" then
		return
	end
	local char = player.Character
	local hum = getHum(char)
	local root = getRoot(char)
	if not hum or not root then
		return
	end
	local s = stOf(player)
	local fn = ATTACKS[action]
	if fn then
		local ok, err = pcall(fn, player, char, hum, root, s, data or {})
		if not ok then
			warn("[EPIC COMBAT] атака " .. action .. ": " .. tostring(err))
		end
	end
end

-- ---------------------------------------------------------------------------
-- Персонаж
-- ---------------------------------------------------------------------------
local function onCharacter(player, char)
	local hum = char:WaitForChild("Humanoid", 8)
	local root = char:WaitForChild("HumanoidRootPart", 8)
	if not hum or not root then
		return
	end
	hum.MaxHealth = Config.Fighter.health
	hum.Health = Config.Fighter.health
	hum.WalkSpeed = Config.Fighter.walkSpeed
	hum.UseJumpPower = true
	hum.JumpPower = Config.Fighter.jumpPower
	hum.BreakJointsOnDeath = false
	hum.PlatformStand = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayDistance = 0
	hum.NameDisplayDistance = 0

	local s = stOf(player)
	s.flying = false
	s.boosting = false
	s.ultActive = false
	s.comboIndex = 0
	s.combo = 0
	s.lastDamage = now() - Config.Fighter.regenDelay
	s.invulnUntil = now() + Config.Fighter.spawnProtect
	s.energy = Config.Energy.max
	setStat(player, "Energy", Config.Energy.max)

	-- стандартные анимации Roblox нам мешают
	local function killAnimate(inst)
		if inst and (inst.Name == "Animate" or inst.Name == "AnimateR15") then
			inst:Destroy()
		end
	end
	for _, obj in ipairs(char:GetChildren()) do
		killAnimate(obj)
	end
	char.ChildAdded:Connect(killAnimate)

	broadcast(char, "respawn", {}, nil)
	remotes.Ack:FireClient(player, "announce", {
		text = "В БОЙ!", sub = "ЛКМ — комбо · F — пинок · R — лазер · X — ульта · V — полёт",
		color = Config.Colors.plasmaHot, time = 2.4, scale = 0.9,
	})
end

-- ---------------------------------------------------------------------------
-- Табло арены
-- ---------------------------------------------------------------------------
local boardRows

local function collectRows()
	local list = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local s = state[pl]
		if s then
			list[#list + 1] = { name = pl.Name, damage = s.damage, kos = s.kos }
		end
	end
	table.sort(list, function(a, b)
		return a.damage > b.damage
	end)
	return list
end

local function updateScoreboard()
	local gui
	local board = workspace:FindFirstChild("Scoreboard", true)
	if board then
		gui = board:FindFirstChildOfClass("SurfaceGui") or board:FindFirstChildOfClass("BillboardGui")
	end
	if not gui then
		return
	end
	if not boardRows then
		boardRows = {}
		for i = 1, 8 do
			local row = gui:FindFirstChild("Row" .. i)
			if row and row:IsA("TextLabel") then
				boardRows[i] = row
			end
		end
	end
	local list = collectRows()
	for i = 1, 8 do
		local row = boardRows[i]
		if row then
			local entry = list[i]
			if entry then
				row.Text = i .. ". " .. entry.name .. "   " .. math.floor(entry.damage) .. " урона · " .. entry.kos .. " КО"
			else
				row.Text = i .. ". —"
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Запуск
-- ---------------------------------------------------------------------------
local spawnPad

local function init()
	remotes = RS:WaitForChild("CombatRemotes", 20)
	if not remotes then
		warn("[EPIC COMBAT] сервер не нашёл CombatRemotes")
		return
	end
	Vfx.init()
	local okD, errD = pcall(function()
		Dummies.init()
	end)
	if not okD then
		warn("[EPIC COMBAT] манекены: " .. tostring(errD))
	end

	spawnPad = workspace:FindFirstChild("ArenaSpawn", true)
	Players.RespawnTime = Config.Fighter.koTime
	Players.CharacterAutoLoads = true

	local attackRemote = remotes:WaitForChild("Attack", 10)
	if attackRemote then
		attackRemote.OnServerEvent:Connect(onAttack)
	end

	local function hookPlayer(pl)
		setupPlayer(pl)
		pl.CharacterAdded:Connect(function(c)
			task.spawn(function()
				local ok, err = pcall(onCharacter, pl, c)
				if not ok then
					warn("[EPIC COMBAT] персонаж: " .. tostring(err))
				end
			end)
		end)
		if pl.Character then
			task.spawn(function()
				pcall(onCharacter, pl, pl.Character)
			end)
		end
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, pl in ipairs(Players:GetPlayers()) do
		hookPlayer(pl)
	end
	Players.PlayerRemoving:Connect(function(pl)
		state[pl] = nil
	end)

	-- главный цикл
	local acc = 0
	local scoreAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		-- энергия, ульта, регенерация
		for pl, s in pairs(state) do
			local char = pl.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			s.energy = math.min(Config.Energy.max, s.energy + Config.Energy.regen * dt)
			s.ult = math.min(Config.Ult.max, s.ult + Config.Ult.passive * dt)
			s.combo = (s.combo > 0) and (s.combo - dt * 0.6) or 0
			if hum and hum.Health > 0 then
				if s.flying then
					local drain = Config.Move.flyHoverDrain + (s.boosting and Config.Move.flyBoostCost or 0)
					s.energy = math.max(0, s.energy - drain * dt)
					if s.energy <= 0 then
						s.boosting = false
					end
				end
				if now() - s.lastDamage > Config.Fighter.regenDelay and hum.Health < hum.MaxHealth then
					hum.Health = math.min(hum.MaxHealth, hum.Health + Config.Fighter.regenPerSecond * dt)
				end
			elseif s.flying then
				s.flying = false
				s.boosting = false
			end
			setStat(pl, "Energy", math.floor(s.energy))
			setStat(pl, "Ult", math.floor(s.ult))
		end

		-- манекены: полная жизнь и возврат на место
		pcall(Dummies.update, dt, Vfx)

		-- вернуть упавших на арену
		acc = acc + dt
		if acc >= 0.5 then
			acc = 0
			for _, pl in ipairs(Players:GetPlayers()) do
				local char = pl.Character
				local root = getRoot(char)
				if root and root.Position.Y < Config.Move.fallResetY then
					local pad = spawnPad or workspace:FindFirstChild("ArenaSpawn", true)
					if pad and pad:IsA("BasePart") then
						char:PivotTo(pad.CFrame * CFrame.new(0, 6, 0))
						root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
						Vfx.pillar(root.Position, Config.Colors.plasma, 30, 3, 0.8)
						remotes.Hurt:FireClient(pl, { kind = "fall", damage = 0 })
					end
				end
			end
			pcall(Vfx.cleanup)
		end

		-- табло
		scoreAcc = scoreAcc + dt
		if scoreAcc >= 2 then
			scoreAcc = 0
			pcall(updateScoreboard)
		end
	end)
end

init()

return true
