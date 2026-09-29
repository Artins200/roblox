--[[
	CombatServer — вся боевая логика (серверная, авторитетная часть).

	Сервер проверяет откаты, энергию и заряд ульты, наносит урон, раскидывает
	бойцов, запускает эффекты (VFX), ведёт leaderstats и статистику, управляет
	нокдаунами, возвращает упавших на арену и обслуживает манекены.

	Клиент только присылает «намерения» (Attack) — всё остальное решает сервер.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("CombatConfig"))
local Vfx = require(script.Parent:WaitForChild("CombatVfx"))
local Dummies = require(script.Parent:WaitForChild("CombatDummies"))

local remotes
local state = {}      -- [player] = состояние бойца
local spawnPad        -- куда возвращать упавших

local ULTMAX = Config.Ult.max

-- ---------------------------------------------------------------------------
-- Утилиты
-- ---------------------------------------------------------------------------
local function now()
	return os.clock()
end

local function getRoot(char)
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHum(char)
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function st(player)
	return state[player]
end

local function syncStats(player)
	local s = st(player)
	if not s then
		return
	end
	local cs = player:FindFirstChild("CombatStats")
	if not cs then
		return
	end
	local e = cs:FindFirstChild("Energy")
	local u = cs:FindFirstChild("Ult")
	if e and math.abs(e.Value - s.energy) >= 1 then
		e.Value = math.floor(s.energy)
	end
	if u and math.abs(u.Value - s.ult) >= 1 then
		u.Value = math.floor(s.ult)
	end
end

local function broadcastAction(char, name, data, auth)
	if not char then
		return
	end
	data = data or {}
	if auth then
		data.auth = true
	end
	remotes.Action:FireAllClients(char, name, data)
end

local function sfxAll(name, position, volume, pitch)
	remotes.Sfx:FireAllClients(name, position, volume, pitch)
end

local function deny(player, action, reason)
	remotes.Ack:FireClient(player, "denied", action, reason)
end

-- Проверка отката и трата энергии. Возвращает true, если действие разрешено.
local function spend(player, action, opts)
	opts = opts or {}
	local s = st(player)
	if not s then
		return false
	end
	local def = Config.Abilities[action]
	if not def then
		return true
	end
	local t = now()
	if (s.cds[action] or 0) > t then
		deny(player, action, "cooldown")
		return false
	end
	if not opts.freeEnergy and def.energy > 0 then
		if s.energy < def.energy then
			deny(player, action, "energy")
			return false
		end
		s.energy = s.energy - def.energy
		s.lastEnergySpend = t
		syncStats(player)
	end
	if def.cooldown > 0 then
		s.cds[action] = t + def.cooldown
	end
	return true
end

local function addUlt(player, amount)
	local s = st(player)
	if not s or s.ultRun then
		return
	end
	s.ult = math.clamp(s.ult + amount, 0, ULTMAX)
	syncStats(player)
	if s.ult >= ULTMAX and not s.ultReadySent then
		s.ultReadySent = true
		sfxAll("ready", getRoot(player.Character) and getRoot(player.Character).Position or Vector3.new(), 0.7)
	end
end

-- Направление «куда смотрит» атакующий (клиент присылает вектор, проверяем его)
local function safeDir(char, data)
	local root = getRoot(char)
	local fallback = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
	local d = data and data.look
	if typeof(d) ~= "Vector3" then
		return Vector3.new(fallback.X, 0, fallback.Z).Unit
	end
	if d.Magnitude < 0.01 then
		return fallback
	end
	d = d.Unit
	return d
end

-- ---------------------------------------------------------------------------
-- Поиск целей
-- ---------------------------------------------------------------------------
local function fxFolders()
	local list = {}
	for _, name in ipairs({ "CombatFX", "CombatFloaters", "LocalCombatFx" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			list[#list + 1] = f
		end
	end
	return list
end

local function overlapParams(exclude)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	local list = fxFolders()
	if exclude then
		list[#list + 1] = exclude
	end
	op.FilterDescendantsInstances = list
	op.MaxParts = 60
	return op
end

-- Находит живые цели в «капсуле» перед бойцом
local function findTargets(attackerChar, origin, dir, reach, radius, maxCount)
	local look = origin + dir * reach
	if (look - origin).Magnitude < 0.1 then
		look = origin + Vector3.new(0, 0, -1) * reach
	end
	local cf = CFrame.lookAt(origin + dir * (reach * 0.5), look)
	local size = Vector3.new(radius * 2, radius * 2.2, reach + radius)
	local parts = workspace:GetPartBoundsInBox(cf, size, overlapParams(attackerChar))
	local seen = {}
	local out = {}
	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] and model ~= attackerChar then
			local hum = getHum(model)
			if hum and hum.Health > 0 then
				seen[model] = true
				local r = getRoot(model)
				local pos = r and r.Position or part.Position
				out[#out + 1] = { model = model, hum = hum, root = r, pos = pos, dist = (pos - origin).Magnitude }
			end
		end
	end
	table.sort(out, function(a, b)
		return a.dist < b.dist
	end)
	if maxCount and #out > maxCount then
		local cut = {}
		for i = 1, maxCount do
			cut[i] = out[i]
		end
		return cut
	end
	return out
end

local function rayHit(attackerChar, origin, dir, range)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local list = fxFolders()
	list[#list + 1] = attackerChar
	rp.FilterDescendantsInstances = list
	rp.IgnoreWater = true
	return workspace:Raycast(origin, dir.Unit * range, rp)
end

-- ---------------------------------------------------------------------------
-- Урон
-- ---------------------------------------------------------------------------
local KO_ATTR = "KO"
local LAST_ATTACKER = "LastAttacker"

local function knockTarget(targetModel, dir, power, up, stun)
	local player = Players:GetPlayerFromCharacter(targetModel)
	if player then
		remotes.Knock:FireClient(player, {
			dir = Vector3.new(dir.X, 0, dir.Z),
			power = power,
			up = up,
			stun = stun,
		})
	else
		local root = getRoot(targetModel)
		if root then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(
				v.X + dir.X * power, math.max(v.Y, 0) + up, v.Z + dir.Z * power)
		end
	end
end

local function applyDamage(attacker, targetModel, hum, amount, opts)
	opts = opts or {}
	if not hum or hum.Health <= 0 or not targetModel.Parent then
		return 0
	end
	local s = st(attacker)
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)

	-- блок цели
	local blocked = false
	if targetPlayer then
		local ts = st(targetPlayer)
		if ts and ts.blocking then
			blocked = true
		end
		-- неуязвимость во время рывка
		if ts and (ts.invulnUntil or 0) > now() then
			return 0
		end
	end

	local crit = (not opts.noCrit) and math.random() < Config.Crit.chance
	local final = amount
	if blocked then
		final = final * 0.25
	end
	if crit then
		final = final * Config.Crit.mult
	end
	final = math.floor(final + 0.5)

	local before = hum.Health
	hum:TakeDamage(final)
	local dealt = math.max(0, before - hum.Health)
	local killed = hum.Health <= 0

	local root = getRoot(targetModel) or hum.Parent.PrimaryPart
	local hitPos = opts.pos or (root and root.CFrame.Position + Vector3.new(0, 0.5, 0)) or Vector3.new()
	local dir = opts.dir or Vector3.new(0, 1, 0)

	-- эффекты попадания
	Vfx.impact(hitPos, Config.Colors.hit, opts.fxScale or 4, 0.26)
	Vfx.sparks(hitPos, dir, opts.sparks or 8, Config.Colors.hit, 26, 0.4, 0.4)
	if crit or (opts.fxScale or 0) >= 8 then
		Vfx.ring(hitPos, Config.Colors.ultHot, 1.2, 9, 0.35, true, 0.3)
	end
	sfxAll((opts.heavy and "hitHeavy") or "hit", hitPos, 1, 0.95 + math.random() * 0.2)

	-- отдача
	if opts.knock and opts.knock > 0 then
		knockTarget(targetModel, dir, opts.knock, opts.up or 0, opts.heavy)
	end

	-- анимация реакции цели
	local local_dir = dir
	local troot = getRoot(targetModel)
	if troot then
		local_dir = troot.CFrame:VectorToObjectSpace(dir)
	end
	broadcastAction(targetModel, "hit", { dir = local_dir, power = opts.power or 1 })

	-- уведомления
	if targetPlayer then
		remotes.Hurt:FireClient(targetPlayer, {
			damage = dealt,
			blocked = blocked,
			from = hitPos,
			crit = crit,
		})
	else
		hum:SetAttribute("LastHit", now())
	end

	if s then
		remotes.Feedback:FireClient(attacker, {
			kind = "hit",
			damage = dealt,
			pos = hitPos,
			crit = crit,
			killed = killed,
			target = targetModel.Name,
		})
		s.damageDealt = s.damageDealt + dealt
		addUlt(attacker, dealt * Config.Ult.perDamageDealt + (opts.ultBonus or 0))
		-- статистика комбо
		if now() - (s.lastHit or 0) < 2.5 then
			s.hitStreak = (s.hitStreak or 0) + 1
		else
			s.hitStreak = 1
		end
		s.lastHit = now()
		local ls = attacker:FindFirstChild("leaderstats")
		if ls then
			local dmgStat = ls:FindFirstChild("Урон")
			if dmgStat then
				dmgStat.Value = s.damageDealt
			end
			local comboStat = ls:FindFirstChild("Комбо")
			if comboStat and s.hitStreak > comboStat.Value then
				comboStat.Value = s.hitStreak
			end
		end
	end

	if targetPlayer then
		local ts = st(targetPlayer)
		if ts then
			ts.lastDamage = now()
			addUlt(targetPlayer, dealt * Config.Ult.perDamageTaken)
		end
	end

	if killed then
		hum:SetAttribute(LAST_ATTACKER, attacker.Name)
		local ls = attacker:FindFirstChild("leaderstats")
		if ls then
			local ko = ls:FindFirstChild("КО")
			if ko then
				ko.Value = ko.Value + 1
			end
		end
		if s then
			s.kills = (s.kills or 0) + 1
		end
		sfxAll("boom", hitPos, 1, 1)
	end
	return dealt
end

-- Урон по области
local function damageArea(attacker, center, radius, amount, opts)
	opts = opts or {}
	local found = workspace:GetPartBoundsInBox(
		CFrame.new(center), Vector3.new(radius * 2, radius * 2, radius * 2), overlapParams(attacker.Character))
	local seen = {}
	for _, part in ipairs(found) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] and (not attacker.Character or model ~= attacker.Character) then
			seen[model] = true
			local hum = getHum(model)
			if hum and hum.Health > 0 then
				local root = getRoot(model)
				local pos = (root and root.Position or part.Position)
				local dir = (pos - center)
				if dir.Magnitude < 0.5 then
					dir = Vector3.new(0, 1, 0)
				end
				opts.pos = pos
				opts.dir = Vector3.new(dir.X, 0, dir.Z).Unit
				applyDamage(attacker, model, hum, amount, opts)
			end
		end
	end
end

-- Урон по «коридору» (для луча ульты)
local function damageBeam(attacker, origin, dir, range, radius, amount, opts)
	opts = opts or {}
	local hits = 0
	local targets = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character and pl.Character ~= attacker.Character then
			local hum = getHum(pl.Character)
			if hum and hum.Health > 0 then
				targets[#targets + 1] = pl.Character
			end
		end
	end
	local dummies = workspace:FindFirstChild("CombatDummies")
	if dummies then
		for _, model in ipairs(dummies:GetChildren()) do
			local hum = getHum(model)
			if hum and hum.Health > 0 then
				targets[#targets + 1] = model
			end
		end
	end
	for _, model in ipairs(targets) do
		local root = getRoot(model)
		local hum = getHum(model)
		if root and hum and hum.Health > 0 then
			local rel = root.Position - origin
			local along = rel:Dot(dir)
			if along > 0 and along < range then
				local perp = (rel - dir * along).Magnitude
				if perp < radius then
					opts.pos = root.Position
					opts.dir = dir
					applyDamage(attacker, model, hum, amount, opts)
					hits = hits + 1
				end
			end
		end
	end
	return hits
end

-- ---------------------------------------------------------------------------
-- Атаки
-- ---------------------------------------------------------------------------
local ATTACKS = {}

ATTACKS.punch = function(player, char, hum, root, s, data)
	if not spend(player, "punch") then
		return
	end
	local t = now()
	if t - (s.comboT or 0) > Config.Combo.window then
		s.comboIndex = 0
	end
	s.comboIndex = (s.comboIndex or 0) % #Config.Combo.names + 1
	s.comboT = t
	local i = s.comboIndex
	local dir = safeDir(char, data)
	local origin = root.Position + Vector3.new(0, 1, 0)
	local name = Config.Combo.names[i]
	local dmg = Config.Combo.damage[i] * (0.9 + math.random() * 0.2)
	local targets = findTargets(char, origin, dir, Config.Combo.reach[i], Config.Combo.radius[i], 3)
	broadcastAction(char, name, {}, false)
	sfxAll("whoosh", origin, 0.8, 1.1)

	if #targets == 0 then
		remotes.Feedback:FireClient(player, { kind = "miss" })
		return
	end
	local finisher = (i == #Config.Combo.names)
	for _, tgt in ipairs(targets) do
		local tdir = (tgt.pos - origin)
		if tdir.Magnitude < 0.1 then
			tdir = dir
		end
		applyDamage(player, tgt.model, tgt.hum, dmg, {
			dir = Vector3.new(tdir.X, 0.25, tdir.Z).Unit,
			pos = tgt.pos + Vector3.new(0, 0.6, 0),
			knock = Config.Combo.knock[i],
			up = finisher and 30 or 4,
			power = i / 3,
			fxScale = finisher and 9 or 4 + i,
			heavy = finisher,
			ultBonus = Config.Combo.ult[i] * 0.2,
		})
	end
	-- дуга замаха
	if finisher then
		Vfx.ring(origin + dir * 4, Config.Colors.plasma, 1.5, 14, 0.35, true, 0.4)
	end
end

ATTACKS.kick = function(player, char, hum, root, s, data)
	if not spend(player, "kick") then
		return
	end
	local dir = safeDir(char, data)
	local origin = root.Position + Vector3.new(0, 1.2, 0)
	broadcastAction(char, "kick", {}, false)
	local targets = findTargets(char, origin, dir, Config.Damage.kickReach, Config.Damage.kickRadius, 3)
	if #targets == 0 then
		remotes.Feedback:FireClient(player, { kind = "miss" })
		return
	end
	for _, tgt in ipairs(targets) do
		local tdir = (tgt.pos - origin)
		if tdir.Magnitude < 0.1 then
			tdir = dir
		end
		applyDamage(player, tgt.model, tgt.hum, Config.Damage.kick, {
			dir = Vector3.new(tdir.X, 0.3, tdir.Z).Unit,
			pos = tgt.pos + Vector3.new(0, 0.8, 0),
			knock = Config.Damage.kickKnock,
			up = Config.Damage.kickLauncher,
			power = 1.4,
			heavy = true,
			fxScale = 8,
		})
	end
	sfxAll("whooshBig", origin, 1, 0.95)
end

ATTACKS.heavy = function(player, char, hum, root, s, data)
	if not spend(player, "heavy") then
		return
	end
	local charge = math.clamp(tonumber(data.charge) or 0, 0, 1)
	local dmg = Config.Damage.heavyMin + (Config.Damage.heavyMax - Config.Damage.heavyMin) * charge
	local dir = safeDir(char, data)
	local origin = root.Position + Vector3.new(0, 1, 0)
	broadcastAction(char, "heavy", { charge = charge }, false)
	sfxAll("whooshBig", origin, 1, 0.75)

	-- выпад вперёд
	knockTarget(char, dir, 24 + charge * 26, 6, false)

	local targets = findTargets(char, origin, dir, Config.Damage.heavyReach, Config.Damage.heavyRadius, 4)
	if #targets == 0 then
		remotes.Feedback:FireClient(player, { kind = "miss" })
		Vfx.shockwave(origin + dir * 8, Config.Colors.ultHot, 10, 0.5)
		return
	end
	local hitPoint = targets[1].pos
	for _, tgt in ipairs(targets) do
		applyDamage(player, tgt.model, tgt.hum, dmg, {
			dir = Vector3.new(dir.X, 0.25, dir.Z).Unit,
			pos = tgt.pos + Vector3.new(0, 0.8, 0),
			knock = Config.Damage.heavyKnock * (0.6 + charge * 0.6),
			up = 22 + charge * 34,
			power = 2.2,
			heavy = true,
			fxScale = 12,
			sparks = 16,
		})
	end
	Vfx.shockwave(hitPoint, Config.Colors.ultHot, 16 + charge * 14, 0.7)
	Vfx.dust(hitPoint, 10, Config.Colors.hit, 1.4)
	if charge > 0.75 then
		Vfx.flash(hitPoint, Config.Colors.hit, 14, 60, 0.4)
	end
end

ATTACKS.dash = function(player, char, hum, root, s, data)
	if not spend(player, "dash") then
		return
	end
	local dir = safeDir(char, data)
	s.invulnUntil = now() + 0.35
	broadcastAction(char, "dash", {}, false)
	sfxAll("dash", root.Position, 1, 1)
	local origin = root.Position
	local pos = root.CFrame:ToWorldSpace(CFrame.new(0, 0.5, 2)).Position
	Vfx.ghost(char, Config.Colors.violet, 0.4, 0.6)
	Vfx.ring(origin, Config.Colors.violet, 1.5, 8, 0.35, false, 0.35)
	-- рывок проходит сквозь врагов: лёгкий урон + отталкивание
	local targets = findTargets(char, origin, dir, 10, 4.5, 4)
	for _, tgt in ipairs(targets) do
		applyDamage(player, tgt.model, tgt.hum, 45, {
			dir = Vector3.new(dir.X, 0.2, dir.Z).Unit,
			pos = tgt.pos + Vector3.new(0, 0.6, 0),
			knock = 26,
			up = 6,
			power = 0.8,
			fxScale = 4,
			noCrit = true,
		})
	end
end

ATTACKS.laser = function(player, char, hum, root, s, data)
	if not spend(player, "laser") then
		return
	end
	local dir = data.direction
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.01 then
		dir = root.CFrame.LookVector
	end
	dir = dir.Unit
	local torso = char:FindFirstChild("Torso") or root
	local origin = torso.Position + dir * 1.6
	local claimed = data.origin
	if typeof(claimed) == "Vector3" and (claimed - torso.Position).Magnitude < 14 then
		origin = claimed + dir * 0.6
	end
	broadcastAction(char, "laser", {}, false)

	local hit = rayHit(char, origin, dir, Config.Damage.laserRange)
	local endPos = origin + dir * Config.Damage.laserRange
	if hit then
		endPos = hit.Position
	end
	-- мощный луч
	Vfx.beam(origin, endPos, Config.Colors.plasma, 2.4, 0.32, 3.2, Config.Colors.plasmaHot)
	Vfx.impact(endPos, Config.Colors.plasma, 6, 0.3)
	sfxAll("laser", origin, 1, 1)
	sfxAll("boom", endPos, 0.6, 1.2)

	if hit then
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		local tgtHum = model and getHum(model)
		if tgtHum and tgtHum.Health > 0 and model ~= char then
			applyDamage(player, model, tgtHum, Config.Damage.laser, {
				dir = dir,
				pos = hit.Position,
				knock = 30,
				up = 4,
				power = 1.2,
				heavy = true,
				fxScale = 9,
				sparks = 14,
			})
		else
			remotes.Feedback:FireClient(player, { kind = "miss" })
			Vfx.sparks(endPos, hit.Normal, 10, Config.Colors.plasma, 22, 0.4, 0.4)
			Vfx.scorch(endPos, 3, 8)
		end
	end
end

ATTACKS.barrage = function(player, char, hum, root, s, data)
	local start = data.state == "start"
	if start then
		if s.barrage then
			return
		end
		if not spend(player, "barrage", { freeEnergy = true }) then
			return
		end
		if s.energy < 10 then
			deny(player, "barrage", "energy")
			return
		end
		s.barrage = true
		broadcastAction(char, "barrage", {}, false)
		task.spawn(function()
			while s.barrage do
				local pl = player
				local c = pl.Character
				local h = getHum(c)
				local r = getRoot(c)
				if not c or not h or h.Health <= 0 or not r then
					break
				end
				if s.energy < 3 then
					break
				end
				s.energy = math.max(0, s.energy - 2.6)
				syncStats(pl)
				local look = r.CFrame.LookVector
				local dir = (look + Vector3.new(
					(math.random() - 0.5) * 0.09,
					(math.random() - 0.5) * 0.09,
					(math.random() - 0.5) * 0.09)).Unit
				local origin = r.Position + Vector3.new(0, 1.2, 0) + dir * 1.6
				local hit = rayHit(c, origin, dir, Config.Damage.barrageRange)
				local endPos = origin + dir * Config.Damage.barrageRange
				if hit then
					endPos = hit.Position
				end
				local color = (math.random() < 0.5) and Config.Colors.plasma or Config.Colors.violet
				Vfx.bolt(origin, endPos, color, Config.Colors.plasmaHot, 1.3, 0.18, 5)
				sfxAll("laser", origin, 0.5, 1.5 + math.random() * 0.3)
				if hit then
					local model = hit.Instance:FindFirstAncestorOfClass("Model")
					local tgtHum = model and getHum(model)
					if tgtHum and tgtHum.Health > 0 and model ~= c then
						applyDamage(player, model, tgtHum, Config.Damage.barrage, {
							dir = dir,
							pos = hit.Position,
							knock = 6,
							up = 1,
							power = 0.6,
							fxScale = 3.5,
							sparks = 4,
							noCrit = true,
						})
					end
				end
				task.wait(0.09)
			end
			s.barrage = false
			remotes.Action:FireAllClients(player.Character, "barrageStop", { auth = true })
		end)
	else
		s.barrage = false
		remotes.Action:FireAllClients(char, "barrageStop", { auth = true })
	end
end

ATTACKS.fly = function(player, char, hum, root, s, data)
	local on = data.state and true or false
	if on and not spend(player, "fly") then
		return
	end
	s.flying = on
	remotes.Action:FireAllClients(char, "setFly", { state = on })
	if on then
		Vfx.ring(root.Position, Config.Colors.plasma, 1.5, 9, 0.5, false, 0.4)
		Vfx.dust(root.Position, 8, Config.Colors.plasma, 1.2)
		sfxAll("dash", root.Position, 0.8, 1.2)
	else
		Vfx.dust(root.Position, 6, Color3.fromRGB(200, 200, 220), 1)
	end
end

ATTACKS.block = function(player, char, hum, root, s, data)
	local on = data.state and true or false
	if on and not spend(player, "block") then
		return
	end
	s.blocking = on
	remotes.Action:FireAllClients(char, "setBlock", { state = on })
	if on then
		sfxAll("block", root.Position, 0.8, 1)
		Vfx.ring(root.Position, Config.Colors.block, 1, 6, 0.35, false, 0.3)
	end
end

ATTACKS.doublejump = function(player, char, hum, root, s, data)
	local pos = root.Position
	Vfx.ring(pos - Vector3.new(0, 2.2, 0), Config.Colors.plasma, 1.5, 10, 0.45, false, 0.5)
	Vfx.dust(pos - Vector3.new(0, 2.4, 0), 8, Config.Colors.plasma, 1.2)
	sfxAll("whoosh", pos, 0.8, 1.3)
end

ATTACKS.taunt = function(player, char, hum, root, s, data)
	if not spend(player, "taunt") then
		return
	end
	broadcastAction(char, "taunt", {}, false)
	local pos = root.Position
	Vfx.ring(pos, Config.Colors.ult, 2, 26, 0.8, false, 0.7)
	Vfx.ring(pos + Vector3.new(0, 2, 0), Config.Colors.ult, 2, 16, 0.7, true, 0.5)
	Vfx.pillar(pos, Config.Colors.ult, 26, 2.2, 0.7)
	sfxAll("ultCharge", pos, 1, 0.9)
	damageArea(player, pos, Config.Damage.tauntRadius, Config.Damage.tauntShock, {
		knock = 45,
		up = 18,
		power = 1.2,
		fxScale = 5,
		noCrit = true,
		dir = Vector3.new(0, 1, 0),
	})
end

ATTACKS.reset = function(player, char, hum, root, s, data)
	if not spend(player, "reset") then
		return
	end
	Dummies.resetAll(player)
	Vfx.ring(root.Position, Config.Colors.plasma, 2, 40, 1.0, false, 0.8)
	Vfx.pillar(root.Position, Config.Colors.plasma, 40, 3, 0.8)
	local pos = root.Position
	remotes.Action:FireAllClients(char, "taunt", { auth = true })
	remotes.Ack:FireAllClients("announce", "МАНЕКЕНЫ ВОССТАНОВЛЕНЫ")
	sfxAll("ultCharge", pos, 1, 1.2)
end

-- ---------------------------------------------------------------------------
-- УЛЬТА «ОБЛИТЕРАЦИЯ»
-- ---------------------------------------------------------------------------
local function nearestTarget(origin, maxDist, excludeChar)
	local best, bestDist = nil, maxDist
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and p.Character ~= excludeChar then
			list[#list + 1] = p.Character
		end
	end
	local dummies = workspace:FindFirstChild("CombatDummies")
	if dummies then
		for _, m in ipairs(dummies:GetChildren()) do
			list[#list + 1] = m
		end
	end
	for _, model in ipairs(list) do
		local hum = getHum(model)
		local root = getRoot(model)
		if hum and hum.Health > 0 and root then
			local d = (root.Position - origin).Magnitude
			if d < bestDist then
				best, bestDist = model, d
			end
		end
	end
	return best
end

local function doUlt(player, char, hum, root, s)
	if s.ultRun then
		return
	end
	if s.ult < ULTMAX - 0.5 then
		deny(player, "ult", "energy")
		return
	end
	s.ultRun = true
	s.ult = 0
	s.ultReadySent = false
	syncStats(player)

	local name = player.DisplayName
	task.spawn(function()
		local c = player.Character
		local r = c and getRoot(c)
		if not r then
			s.ultRun = false
			return
		end
		local pos = r.Position

		-- ФАЗА 1: зарядка
		remotes.Action:FireAllClients(c, "ultCharge", { auth = true })
		remotes.Ult:FireAllClients({ phase = "charge", caster = c, name = name })
		Vfx.pillar(pos, Config.Colors.ult, 80, 7, 1.2)
		Vfx.ring(pos, Config.Colors.ult, 2, 34, 1.2, false, 0.7)
		Vfx.flash(pos, Config.Colors.ult, 12, 90, 1.0)
		sfxAll("ultCharge", pos, 1, 0.6)
		-- подброс в воздух
		knockTarget(c, Vector3.new(0, 1, 0), 0, 55, false)
		task.wait(1.5)
		if not getHum(player.Character) or getHum(player.Character).Health <= 0 then
			s.ultRun = false
			return
		end
		c = player.Character
		r = getRoot(c)
		pos = r and r.Position or pos

		-- ФАЗА 2: вспышка
		remotes.Action:FireAllClients(c, "ultBurst", { auth = true })
		remotes.Ult:FireAllClients({ phase = "burst", caster = c, name = name })
		Vfx.nova(pos, Config.Colors.ult, 46, 1.2)
		sfxAll("boom", pos, 1, 0.8)
		task.wait(0.55)

		-- ФАЗА 3: залп энергетических снарядов по врагам
		remotes.Action:FireAllClients(c, "ultFire", { auth = true })
		for i = 1, Config.Damage.ultBoltCount do
			c = player.Character
			r = c and getRoot(c)
			if not r or not getHum(c) or getHum(c).Health <= 0 then
				break
			end
			local origin = r.Position + Vector3.new(0, 2.4, 0)
			local target = nearestTarget(origin, Config.Damage.ultBoltRange, c)
			local to
			if target then
				local tr = getRoot(target)
				to = tr and tr.Position or (origin + Vector3.new(0, 0, -30))
				to = to + Vector3.new((math.random() - 0.5) * 5, (math.random() - 0.5) * 3, (math.random() - 0.5) * 5)
			else
				to = origin + Vector3.new(
					(math.random() - 0.5) * 90, -math.random() * 12, (math.random() - 0.5) * 90)
			end
			local color = ((i % 2) == 0) and Config.Colors.ultHot or Config.Colors.ult
			Vfx.beam(origin, to, color, 2.6, 0.26, 2.6, Config.Colors.ultHot)
			Vfx.impact(to, color, 12, 0.35)
			damageArea(player, to, Config.Damage.ultBoltRadius, Config.Damage.ultBolt, {
				knock = 12,
				up = 8,
				power = 1,
				noCrit = true,
				fxScale = 4,
			})
			if i % 2 == 1 then
				sfxAll("laser", origin, 0.9, 1.2)
			end
			task.wait(0.075)
		end
		task.wait(0.35)

		-- ФАЗА 4: луч облитерации
		c = player.Character
		r = c and getRoot(c)
		if not r or not getHum(c) or getHum(c).Health <= 0 then
			s.ultRun = false
			remotes.Action:FireAllClients(player.Character, "ultEnd", { auth = true })
			return
		end
		local origin = r.Position + Vector3.new(0, 2.6, 0)
		local target = nearestTarget(origin, 320, c)
		local dir
		if target then
			local tr = getRoot(target)
			dir = (tr.Position - origin).Unit
		else
			dir = r.CFrame.LookVector
		end
		remotes.Ult:FireAllClients({ phase = "beam", caster = c, name = name })
		Vfx.giantBeam(origin, dir, Config.Damage.ultBeamRange, Config.Colors.ult,
			Config.Colors.ultHot, Config.Damage.ultBeamRadius, 1.3)
		sfxAll("ultFire", origin, 1, 0.5)
		damageBeam(player, origin, dir, Config.Damage.ultBeamRange, Config.Damage.ultBeamRadius,
			Config.Damage.ultBeam, { knock = 120, up = 55, power = 3, heavy = true, fxScale = 14 })
		-- финальная нова на конце луча + след
		local hit = rayHit(c, origin, dir, Config.Damage.ultBeamRange)
		local endPos = hit and hit.Position or (origin + dir * Config.Damage.ultBeamRange)
		Vfx.nova(endPos, Config.Colors.ultHot, Config.Damage.ultNovaRadius, 1.5)
		Vfx.scorch(endPos - Vector3.new(0, 1, 0), 34, 16)
		sfxAll("boom", endPos, 1, 0.5)
		task.wait(1.0)

		-- ФАЗА 5: завершение
		remotes.Action:FireAllClients(player.Character, "ultEnd", { auth = true })
		remotes.Ult:FireAllClients({ phase = "end", caster = player.Character, name = name })
		s.ultRun = false
		syncStats(player)
	end)
end

ATTACKS.ult = function(player, char, hum, root, s, data)
	if not spend(player, "ult", { freeEnergy = true }) then
		return
	end
	doUlt(player, char, hum, root, s)
end

-- ---------------------------------------------------------------------------
-- Подключение игрока
-- ---------------------------------------------------------------------------
local function setupPlayer(player)
	state[player] = {
		energy = Config.Energy.max,
		ult = 0,
		cds = {},
		blocking = false,
		flying = false,
		comboIndex = 0,
		comboT = 0,
		damageDealt = 0,
		kills = 0,
		hitStreak = 0,
		lastDamage = 0,
		lastAction = 0,
		invulnUntil = 0,
	}

	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local function mkStat(name, value, cls)
		local v = Instance.new(cls or "IntValue")
		v.Name = name
		v.Value = value
		v.Parent = ls
		return v
	end
	mkStat("Урон", 0)
	mkStat("КО", 0)
	mkStat("Комбо", 0)

	local cs = player:FindFirstChild("CombatStats")
	if not cs then
		cs = Instance.new("Folder")
		cs.Name = "CombatStats"
		cs.Parent = player
	end
	local function mk(name, value)
		local v = Instance.new("IntValue")
		v.Name = name
		v.Value = value
		v.Parent = cs
		return v
	end
	mk("Energy", Config.Energy.max)
	mk("Ult", 0)

	-- регенерация
	task.spawn(function()
		while player.Parent do
			task.wait(0.25)
			local s = st(player)
			if s then
				local dt = 0.25
				s.energy = math.min(Config.Energy.max, s.energy + Config.Energy.regen * dt)
				if not s.ultRun then
					s.ult = math.min(ULTMAX, s.ult + Config.Ult.passive * dt)
					if s.ult >= ULTMAX and not s.ultReadySent then
						s.ultReadySent = true
						local r = player.Character and getRoot(player.Character)
						sfxAll("ready", r and r.Position or Vector3.new(), 0.8)
					end
				end
				-- регенерация здоровья
				local char = player.Character
				local hum = getHum(char)
				if hum and hum.Health > 0 and (now() - (s.lastDamage or 0)) > Config.Fighter.regenDelay then
					local maxHp = hum.MaxHealth
					if hum.Health < maxHp then
						hum.Health = math.min(maxHp, hum.Health + maxHp * Config.Fighter.regenPerSecond * dt)
					end
				end
				syncStats(player)
			end
		end
	end)
end

local function onCharacter(player, char)
	local hum = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not hum or not root then
		return
	end
	hum.MaxHealth = Config.Fighter.health
	hum.Health = Config.Fighter.health
	hum.WalkSpeed = Config.Fighter.walkSpeed
	hum.JumpPower = Config.Fighter.jumpPower
	hum.UseJumpPower = true
	hum.BreakJointsOnDeath = false
	hum.NameDisplayDistance = 0
	hum.HealthDisplayDistance = 0
	-- выкидываем стандартный Animate: он играет свои анимации через Animator
	-- и смешивался бы с нашими процедурными позами
	local animate = char:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	for _, obj in ipairs(char:GetChildren()) do
		if obj:IsA("LocalScript") and obj.Name == "Animate" then
			obj:Destroy()
		end
	end
	char:SetAttribute(KO_ATTR, false)
	local s = st(player)
	if s then
		s.flying = false
		s.blocking = false
		s.comboIndex = 0
		s.barrage = false
		s.energy = Config.Energy.max
		s.ultRun = false
		s.cds = {}
	end
	syncStats(player)
	-- появиться на арене
	local spawnPart = workspace:FindFirstChild("ArenaSpawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		char:PivotTo(spawnPart.CFrame * CFrame.new(0, 4, 0))
	end
	Vfx.pillar(root.Position, Config.Colors.plasma, 24, 3, 0.8)
	Vfx.ring(root.Position, Config.Colors.plasma, 2, 16, 0.7, false, 0.5)
	sfxAll("ready", root.Position, 1)

	hum.Died:Connect(function()
		char:SetAttribute(KO_ATTR, true)
		broadcastAction(char, "ko", { auth = true })
		Dummies.ragdoll(char)
		if s then
			s.flying = false
			s.blocking = false
			s.barrage = false
			s.ultRun = false
			s.energy = Config.Energy.max
			syncStats(player)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Табло на арене
-- ---------------------------------------------------------------------------
local function updateScoreboard()
	local board = workspace:FindFirstChild("Arena")
	local sboard = board and board:FindFirstChild("Scoreboard")
	if not sboard then
		return
	end
	local gui = sboard:FindFirstChildOfClass("SurfaceGui")
	if not gui then
		return
	end
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local ls = p:FindFirstChild("leaderstats")
		if ls then
			local dStat = ls:FindFirstChild("Урон")
			local kStat = ls:FindFirstChild("КО")
			local cStat = ls:FindFirstChild("Комбо")
			list[#list + 1] = {
				name = p.DisplayName,
				damage = dStat and dStat.Value or 0,
				ko = kStat and kStat.Value or 0,
				combo = cStat and cStat.Value or 0,
			}
		end
	end
	table.sort(list, function(a, b)
		return a.damage > b.damage
	end)
	for i = 1, 8 do
		local row = gui:FindFirstChild("Row" .. i)
		local entry = list[i]
		if row and row:IsA("TextLabel") then
			if entry then
				row.Text = string.format("%d. %s   %d ур.   %d КО   x%d",
					i, entry.name, entry.damage, entry.ko, entry.combo)
			else
				row.Text = i .. ". —"
			end
		end
	end
	local title = gui:FindFirstChild("Title")
	if title then
		title.Text = "ЛУЧШИЕ БОЙЦЫ АРЕНЫ"
	end
end

-- ---------------------------------------------------------------------------
-- Запуск
-- ---------------------------------------------------------------------------
local function init()
	Players.RespawnTime = Config.Fighter.koTime
	Players.CharacterAutoLoads = true

	remotes = RS:WaitForChild("CombatRemotes")
	Vfx.init()

	local spawnPart = workspace:FindFirstChild("ArenaSpawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		spawnPad = spawnPart
	end

	Dummies.init()

	Players.PlayerAdded:Connect(setupPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		setupPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		state[p] = nil
	end)

	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function(char)
			onCharacter(p, char)
		end)
		if p.Character then
			onCharacter(p, p.Character)
		end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterAdded:Connect(function(char)
			onCharacter(p, char)
		end)
		if p.Character then
			onCharacter(p, p.Character)
		end
	end

	-- приём «намерений» клиента
	remotes.Attack.OnServerEvent:Connect(function(player, action, data)
		if type(action) ~= "string" or #action > 24 then
			return
		end
		local s = st(player)
		local char = player.Character
		if not s or not char then
			return
		end
		local hum = getHum(char)
		local root = getRoot(char)
		if not hum or not root or hum.Health <= 0 then
			return
		end
		local t = now()
		if t - (s.lastAction or 0) < 0.03 then
			return
		end
		s.lastAction = t
		local handler = ATTACKS[action]
		if handler then
			local ok, err = pcall(handler, player, char, hum, root, s, data or {})
			if not ok then
				warn("[CombatServer] " .. action .. ": " .. tostring(err))
			end
		end
	end)

	-- обслуживающие циклы
	task.spawn(function()
		while true do
			task.wait(1)
			-- возврат упавших с арены
			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				local root = getRoot(char)
				if root and root.Position.Y < Config.Move.fallResetY then
					local pad = spawnPad or workspace:FindFirstChild("ArenaSpawn")
					if pad then
						char:PivotTo(pad.CFrame * CFrame.new(0, 6, 0))
						root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
						Vfx.pillar(root.Position, Config.Colors.plasma, 30, 3, 0.8)
						Vfx.ring(root.Position, Config.Colors.plasma, 2, 18, 0.7, false, 0.5)
						remotes.Hurt:FireClient(p, { kind = "fall", damage = 0 })
					end
				end
			end
			-- дроу-лимит эффектов
			Vfx.cleanup()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(2)
			updateScoreboard()
		end
	end)
end

init()
