--[[
	CombatAnimator — клиентский аниматор бойцов.

	Каждый клиент сам рисует анимации ВСЕМ персонажам (игрокам и манекенам):
	  * передвижение (шаг/бег/прыжок/падение/приземление),
	  * полёт (поза супермена, крены, буст),
	  * удары, пинки, лазеры, залп, ульта, таунт,
	  * реакции на попадание в зависимости от направления удара,
	  * нокдаун (сервер укладывает в рэгдолл),

	плюс локальные визуальные эффекты: трейлы кулаков/ног, аура ульты,
	энергощит блока, свечение энергоядра, звуки.

	Опционально умеет проигрывать настоящие анимации из Toolbox — если в
	CombatConfig.ToolboxAnims указаны ID, для этих действий процедурная поза
	отключается и играет трек.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local RS = script.Parent
local Config = require(RS:WaitForChild("CombatConfig"))
local Pose = require(RS:WaitForChild("CombatPose"))
local Actions = require(RS:WaitForChild("CombatActions"))

local Animator = {}
Animator.list = {}
Animator.timeScale = 1      -- «хит-стоп»: замедление анимаций в момент мощного удара
Animator.hitStopUntil = 0

local function now()
	return os.clock()
end

-- ---------------------------------------------------------------------------
-- Локальная папка эффектов (создаётся на клиенте, ничего не репликуется)
-- ---------------------------------------------------------------------------
local localFx
local function fx()
	if not localFx or not localFx.Parent then
		localFx = workspace:FindFirstChild("LocalCombatFx")
		if not localFx then
			localFx = Instance.new("Folder")
			localFx.Name = "LocalCombatFx"
			localFx.Parent = workspace
		end
	end
	return localFx
end

local function fxPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Locked = true
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.SmoothNoOutlines
	p.BottomSurface = Enum.SurfaceType.SmoothNoOutlines
	p.Size = Vector3.new(1, 1, 1)
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = fx()
	return p
end

-- ---------------------------------------------------------------------------
-- Аудио (локальное, позиционное)
-- ---------------------------------------------------------------------------
local function playSound(name, position, volumeMul, pitchMul)
	local def = Config.Sfx[name]
	if not def then
		return
	end
	local cam = workspace.CurrentCamera
	if cam and position and (cam.CFrame.Position - position).Magnitude > Config.Sfx.maxDistance then
		return
	end
	local host = Instance.new("Part")
	host.Name = "Sfx"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = CFrame.new(position or Vector3.new(0, 0, 0))
	host.Parent = fx()
	Debris:AddItem(host, 8)
	local s = Instance.new("Sound")
	s.SoundId = def.id
	s.Volume = (def.volume or 1) * (volumeMul or 1)
	s.PlaybackSpeed = (def.pitch or 1) * (pitchMul or 1)
	s.RollOffMaxDistance = def.loop and 60 or 220
	s.RollOffMinDistance = 12
	s.Parent = host
	s:Play()
	if not def.loop then
		Debris:AddItem(s, 6)
	end
	return s
end

Animator.playSound = playSound

-- ---------------------------------------------------------------------------
-- Трейлы
-- ---------------------------------------------------------------------------
local function makeTrail(part, aPos, bPos, c1, c2, thickness, lifetime)
	local a = Instance.new("Attachment")
	a.Name = "FxTrailA"
	a.Position = aPos
	a.Parent = part
	local b = Instance.new("Attachment")
	b.Name = "FxTrailB"
	b.Position = bPos
	b.Parent = part
	local t = Instance.new("Trail")
	t.Attachment0 = a
	t.Attachment1 = b
	t.Color = ColorSequence.new(c1, c2)
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	t.Lifetime = lifetime or 0.24
	t.MinLength = 0.02
	t.FaceCamera = true
	t.LightEmission = 1
	t.LightInfluence = 0
	t.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, thickness or 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	t.Enabled = false
	t.Parent = part
	return t
end

-- ---------------------------------------------------------------------------
-- Объект-аниматор одного персонажа
-- ---------------------------------------------------------------------------
local Anim = {}
Anim.__index = Anim

function Animator.get(character)
	local a = Animator.list[character]
	if not a then
		a = setmetatable({}, Anim)
		if not a:init(character) then
			return nil
		end
		Animator.list[character] = a
	end
	return a
end

function Animator.forget(character)
	local a = Animator.list[character]
	if a then
		a:destroy()
		Animator.list[character] = nil
	end
end

function Animator.clearFor(character)
	Animator.forget(character)
end

-- Хит-стоп: на мгновение «замораживаем» анимации для сочности удара
function Animator.hitStop(duration, scale)
	Animator.hitStopUntil = math.max(Animator.hitStopUntil, now() + (duration or 0.07))
	Animator.timeScaleTarget = scale or 0.12
end

function Anim:init(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then
		return false
	end
	self.character = character
	self.humanoid = hum
	self.root = root
	self.rig = Pose.newRig(character)
	self.state = {
		flying = false,
		blocking = false,
		ko = false,
		boost = 0,
		bank = 0,
		phase = 0,
		wasGrounded = true,
		dead = false,
	}
	self.action = nil
	self.flinch = nil
	self.trails = {}
	self.aura = nil
	self.shield = nil
	self.nextBuildFx = now() + 0.3
	self.builtFx = false
	self.fxPrev = 0
	self.player = Players:GetPlayerFromCharacter(character)
	self.isLocal = (self.player == Players.LocalPlayer)
	self.tracks = {}
	self.trackTried = false
	-- глушим стандартные анимации персонажа (idle/walk/jump), если они стартовали
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		local ok = pcall(function()
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end)
	end
	return true
end

function Anim:destroy()
	if self.trails then
		for _, t in pairs(self.trails) do
			if t and t.Parent then
				t:Destroy()
			end
		end
	end
	if self.aura then
		for _, p in pairs(self.aura) do
			if p and p.Parent then
				p:Destroy()
			end
		end
	end
	if self.shield and self.shield.Parent then
		self.shield:Destroy()
	end
	if self.flyTrail and self.flyTrail.Parent then
		self.flyTrail:Destroy()
	end
	if self.tracks then
		for _, track in pairs(self.tracks) do
			pcall(function()
				track:Stop(0)
				track:Destroy()
			end)
		end
	end
	self.state.dead = true
end

-- ---------------------------------------------------------------------------
-- Построение локальных эффектов персонажа (трейлы, щит)
-- ---------------------------------------------------------------------------
local ARM_TRAILS = {
	ra = { part = "Right Arm", a = Vector3.new(0.3, 0.95, 0.1), b = Vector3.new(-0.3, -0.95, -0.35), color = Config.Colors.plasma },
	la = { part = "Left Arm", a = Vector3.new(-0.3, 0.95, 0.1), b = Vector3.new(0.3, -0.95, -0.35), color = Config.Colors.plasma },
}

function Anim:buildFx()
	local c = self.character
	local built = false
	for key, def in pairs(ARM_TRAILS) do
		local part = c:FindFirstChild(def.part)
		if part then
			if not part:FindFirstChild("FxTrailA") then
				self.trails[key] = makeTrail(part, def.a, def.b, Color3.new(1, 1, 1), def.color, 1.5, 0.22)
			else
				self.trails[key] = part:FindFirstChildOfClass("Trail")
			end
			built = true
		end
	end
	for _, legName in ipairs({ "Right Leg", "Left Leg" }) do
		local part = c:FindFirstChild(legName)
		if part and not part:FindFirstChild("FxTrailA") then
			local key = (legName == "Right Leg") and "rl" or "ll"
			self.trails[key] = makeTrail(part, Vector3.new(0.3, 0.95, 0.1), Vector3.new(-0.3, -0.95, -0.3), Color3.new(1, 1, 1), Config.Colors.violet, 1.4, 0.2)
		end
	end
	-- трейл полёта
	if self.root and not self.root:FindFirstChild("FxTrailA") and not self.flyTrail then
		self.flyTrail = makeTrail(self.root, Vector3.new(0.7, 0.2, 0.6), Vector3.new(-0.7, -0.2, 0.6),
			Config.Colors.plasma, Config.Colors.violet, 3.2, 0.32)
	end
	-- энергощит блока
	if not self.shield then
		self.shield = fxPart({
			Name = "BlockShield",
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.ForceField,
			Color = Config.Colors.block,
			Size = Vector3.new(7, 7.4, 6),
			Transparency = 0.62,
		})
		self.shield.Transparency = 1
	end
	self.builtFx = built
end

function Anim:toggleTrail(key, seconds)
	local t = self.trails and self.trails[key]
	if not t then
		return
	end
	t.Enabled = true
	task.delay(seconds or 0.22, function()
		if t and t.Parent then
			t.Enabled = false
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Треки из Toolbox (если пользователь указал ID анимаций)
-- ---------------------------------------------------------------------------
function Anim:loadTracks()
	if self.trackTried then
		return
	end
	self.trackTried = true
	local animator = self.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for name, id in pairs(Config.ToolboxAnims) do
		if type(id) == "string" and id ~= "" then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, track = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action4
				self.tracks[name] = track
			end
		end
	end
end

function Anim:playTrack(name, looped)
	local track = self.tracks and self.tracks[name]
	if not track then
		return false
	end
	track.Looped = looped and true or false
	pcall(function()
		track:Play(0.08)
	end)
	return true
end

function Anim:stopTracks()
	if not self.tracks then
		return
	end
	for _, track in pairs(self.tracks) do
		if track.IsPlaying then
			pcall(function()
				track:Stop(0.12)
			end)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Управление действиями
-- ---------------------------------------------------------------------------
function Anim:play(name, data, force)
	local def = Actions.get(name)
	if not def then
		return false
	end
	if self.state.ko and name ~= "ko" then
		return false
	end
	if self.action and not force then
		local cur = self.action.def
		local interruptible = cur.loop or (self.action.t >= cur.chain)
		if not interruptible then
			return false
		end
		if cur.name == name and def.loop then
			return false
		end
	end
	local hasTrack = self:playTrack(name, def.loop)
	if not hasTrack then
		self:stopTracks()
	end
	self.action = {
		def = def,
		name = name,
		t = 0,
		w = 0,
		data = data or {},
		hasTrack = hasTrack,
	}
	self.actName = name
	self.fxPrev = 0
	self.fxDone = {}
	return true
end

function Anim:stop(name)
	if self.action and (not name or self.action.name == name) then
		if self.action.hasTrack then
			self:stopTracks()
		end
		self.action = nil
	end
end

function Anim:stopAll()
	if self.action then
		if self.action.hasTrack then
			self:stopTracks()
		end
		self.action = nil
	end
end

function Anim:setState(key, value)
	self.state[key] = value
end

-- Реакция на попадание: pose выбирается по направлению удара в локальных осях
function Anim:flinch(dirLocal, power)
	if self.state.ko then
		return
	end
	local name = "hitFront"
	if dirLocal then
		local x, z = dirLocal.X, dirLocal.Z
		if math.abs(z) >= math.abs(x) then
			name = (z > 0) and "hitBack" or "hitFront"
		else
			name = (x > 0) and "hitSideL" or "hitSideR"
		end
	end
	local def = Actions.get(name)
	if not def then
		return
	end
	local dur = def.duration
	self.flinch = {
		def = def,
		t = 0,
		dur = dur,
		w = math.clamp(0.55 + (power or 1) * 0.35, 0.5, 1),
	}
	playSound("hit", self.root.Position, 0.6)
end

function Anim:setKO(ko)
	if ko == self.state.ko then
		return
	end
	self.state.ko = ko
	if ko then
		self:play("ko")
		self.flinch = nil
		playSound("ko", self.root.Position, 1)
	else
		self:stopAll()
	end
end

-- ---------------------------------------------------------------------------
-- Сборка поз по состояниям
-- ---------------------------------------------------------------------------
local BREATH = {
	body = { p = 0.03 }, neck = { p = -0.05 },
	la = { p = 0.05, r = -0.04 }, ra = { p = 0.05, r = 0.04 },
	ll = { p = 0, r = 0 }, rl = { p = 0, r = 0 }, bob = 0,
}

function Anim:locomotion(dt, speed, grounded, vel)
	local L = Actions.LOCO
	local pose = Pose.copy(Actions.STANCE)
	local walkSpeed = math.max(self.humanoid.WalkSpeed, 1)
	local run = math.clamp((speed - walkSpeed * 0.9) / (walkSpeed * 0.6), 0, 1)

	if grounded then
		if speed > 0.7 then
			self.state.phase = (self.state.phase or 0) + speed * dt * 0.30
		end
		local amp = math.rad(L.walkAmp + (L.runAmp - L.walkAmp) * run)
		local armsAmp = math.rad(L.walkArms + (L.runArms - L.walkArms) * run)
		local s = math.sin(self.state.phase)
		local c = math.cos(self.state.phase)
		local k = math.clamp(speed / walkSpeed, 0, 1.35)
		pose.ll.p = pose.ll.p + amp * s * k
		pose.rl.p = pose.rl.p - amp * s * k
		pose.ll.r = pose.ll.r - math.rad(2) * c * k
		pose.rl.r = pose.rl.r + math.rad(2) * c * k
		pose.la.p = pose.la.p - armsAmp * s * k
		pose.ra.p = pose.ra.p + armsAmp * s * k
		pose.la.r = pose.la.r - math.rad(6) * k
		pose.ra.r = pose.ra.r + math.rad(6) * k
		pose.body.y = pose.body.y - math.rad(L.sway) * s * (0.35 + run * 0.6)
		pose.body.r = pose.body.r + math.rad(L.sway * 0.35) * c * (0.4 + run * 0.6)
		pose.body.p = pose.body.p + math.rad(L.runLean * 0.55) * run * k
		pose.neck.p = pose.neck.p - math.rad(L.runLean * 0.4) * run * k
		pose.bob = pose.bob - L.bobAmp * math.abs(c) * k * (0.55 + run * 0.5)
		return pose
	end

	-- В воздухе (без полёта): прыжок ↔ падение по вертикальной скорости
	local vy = vel.Y
	local t = math.clamp((vy + 14) / 26, 0, 1)
	pose = Pose.mix(Actions.POSES.fall, Actions.POSES.jump, t)
	local sway = math.clamp(vel.X * 0.02 + vel.Z * 0.02, -0.25, 0.25)
	pose.body.r = pose.body.r + sway
	pose.body.y = pose.body.y + sway * 0.6
	return pose
end

function Anim:flightPose(dt, speed, vel)
	local M = Config.Move
	local cruise = math.clamp(speed / (M.flySpeed * 0.5), 0, 1)
	local pose = Pose.mix(Actions.POSES.flyHover, Actions.POSES.flyCruise, cruise)
	local boost = self.state.boost or 0
	if boost > 0 then
		pose = Pose.mix(pose, Actions.POSES.flyBoost, boost)
	end
	-- тангаж по вертикальной скорости: вверх — нос вверх, вниз — пикируем
	local pitch = math.clamp(vel.Y / 55, -1, 1)
	pose.body.p = pose.body.p + math.rad(26) * pitch * (1 - boost * 0.4)
	-- крен в поворотах (bank) и «трепет»
	pose.body.y = pose.body.y + (self.state.bank or 0)
	local t = now()
	local flutter = math.rad(2.5) * math.sin(t * 7)
	pose.la.p = pose.la.p + flutter
	pose.ra.p = pose.ra.p - flutter
	pose.ll.p = pose.ll.p + flutter * 0.8
	pose.rl.p = pose.rl.p - flutter * 0.8
	pose.body.r = pose.body.r + math.rad(1.5) * math.sin(t * 3.3)
	pose.bob = pose.bob + 0.06 * math.sin(t * 4)
	return pose
end

-- ---------------------------------------------------------------------------
-- События анимации (вспышки, трейлы, звуки, тряска)
-- ---------------------------------------------------------------------------
function Anim:handleEvent(e, prog)
	local c = self.character
	local root = self.root
	local pos = root.Position
	local hand = e.hand
	local handPart = hand and c:FindFirstChild(hand == "la" and "Left Arm" or hand == "ra" and "Right Arm"
		or hand == "rl" and "Right Leg" or hand == "ll" and "Left Leg" or nil)
	local hp = handPart and handPart.CFrame.Position or pos

	if e.e == "whoosh" then
		playSound("whoosh", pos, 1, 0.95 + math.random() * 0.2)
	elseif e.e == "whooshBig" then
		playSound("whooshBig", pos, 1, 0.95 + math.random() * 0.15)
	elseif e.e == "fist" or e.e == "swing" or e.e == "heavyFist" then
		self:toggleTrail(hand or "ra", e.e == "heavyFist" and 0.34 or 0.24)
		if e.e == "heavyFist" then
			local p = fxPart({
				Name = "FistFlash",
				Shape = Enum.PartType.Ball,
				Color = Config.Colors.plasmaHot,
				Size = Vector3.new(1.6, 1.6, 1.6),
				CFrame = CFrame.new(hp),
			})
			Debris:AddItem(p, 0.35)
			local TweenService = game:GetService("TweenService")
			TweenService:Create(p, TweenInfo.new(0.25), { Size = Vector3.new(5, 5, 5), Transparency = 1 }):Play()
		end
		playSound("hit", hp, 0.35, 1.4)
	elseif e.e == "kickTrail" then
		self:toggleTrail(hand or "rl", 0.3)
	elseif e.e == "chargeStart" then
		self.chargeHold = now() + 0.35
	elseif e.e == "laserCharge" or e.e == "chargeLoop" then
		-- орбы на ладонях создаёт сам персонаж по флагу в render
		self.chargeHold = now() + (e.e == "laserCharge" and 0.35 or 0.4)
	elseif e.e == "laserFire" or e.e == "palmShot" then
		playSound("laser", hp, 1, 0.95 + math.random() * 0.2)
		local dir = root.CFrame.LookVector
		local muzzle = hp + dir * 1.2
		local p = fxPart({
			Name = "Muzzle",
			Shape = Enum.PartType.Ball,
			Color = Config.Colors.plasmaHot,
			Size = Vector3.new(1.2, 1.2, 1.2),
			CFrame = CFrame.new(muzzle),
		})
		local TweenService = game:GetService("TweenService")
		TweenService:Create(p, TweenInfo.new(0.18), { Size = Vector3.new(3.4, 3.4, 3.4), Transparency = 1 }):Play()
		Debris:AddItem(p, 0.4)
		if self.isLocal then
			require(RS:WaitForChild("CombatCamera")).punch(1.4)
		end
	elseif e.e == "dashBurst" then
		playSound("dash", pos, 1)
		for i = 1, 4 do
			local g = fxPart({
				Name = "DashGhost",
				Color = Config.Colors.violet,
				Size = Vector3.new(2, 2.6, 1.2) * (1 + i * 0.15),
				CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, 0) * CFrame.new(0, 0, i * 1.4),
				Transparency = 0.5 + i * 0.1,
			})
			local TweenService = game:GetService("TweenService")
			TweenService:Create(g, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			Debris:AddItem(g, 0.5)
		end
		if self.isLocal then
			require(RS:WaitForChild("CombatCamera")).punch(2)
		end
	elseif e.e == "flipBurst" then
		playSound("whoosh", pos, 1, 1.4)
	elseif e.e == "spin" then
		-- вертушка 5-го удара: резкое кольцо вокруг корпуса
		playSound("whooshBig", pos, 0.9, 1.5)
		local ring = fxPart({
			Name = "SpinRing",
			Shape = Enum.PartType.Cylinder,
			Color = Config.Colors.plasmaHot,
			Size = Vector3.new(0.35, 2.4, 2.4),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Transparency = 0.2,
		})
		local TweenService = game:GetService("TweenService")
		TweenService:Create(ring, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.2, 15, 15),
			Transparency = 1,
		}):Play()
		Debris:AddItem(ring, 0.6)
	elseif e.e == "landDust" then
		playSound("land", pos, 1)
	elseif e.e == "tauntBurst" or e.e == "auraBurst" then
		local col = (e.e == "auraBurst") and Config.Colors.ult or Config.Colors.plasma
		local ring = fxPart({
			Name = "AuraRing",
			Shape = Enum.PartType.Cylinder,
			Color = col,
			Size = Vector3.new(0.4, 3, 3),
			CFrame = CFrame.new(pos - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Transparency = 0.2,
		})
		local TweenService = game:GetService("TweenService")
		TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.2, 16, 16),
			Transparency = 1,
		}):Play()
		Debris:AddItem(ring, 0.9)
		playSound("whooshBig", pos, 0.7, 0.8)
	elseif e.e == "ultChargeLoop" then
		playSound("ultCharge", pos, 0.6)
	elseif e.e == "ultNova" then
		playSound("ultFire", pos, 1, 0.6)
		local col = Config.Colors.ult
		for i = 1, 3 do
			local ring = fxPart({
				Name = "UltRing",
				Shape = Enum.PartType.Cylinder,
				Color = (i % 2 == 0) and Config.Colors.ultHot or col,
				Size = Vector3.new(0.5, 4, 4),
				CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90 + i * 8)),
				Transparency = 0.15,
			})
			local TweenService = game:GetService("TweenService")
			TweenService:Create(ring, TweenInfo.new(0.9 + i * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.3, 60, 60),
				Transparency = 1,
			}):Play()
			Debris:AddItem(ring, 1.4)
		end
		local TweenService = game:GetService("TweenService")
		local dome = fxPart({
			Name = "UltDome",
			Shape = Enum.PartType.Ball,
			Color = col,
			Size = Vector3.new(6, 6, 6),
			CFrame = CFrame.new(pos),
			Transparency = 0.35,
		})
		TweenService:Create(dome, TweenInfo.new(0.7), { Size = Vector3.new(46, 46, 46), Transparency = 1 }):Play()
		Debris:AddItem(dome, 1.1)
	elseif e.e == "ultBeamLoop" then
		self.ultBeamHold = now() + 0.55
	end

	if e.e == "shake" and self.isLocal then
		require(RS:WaitForChild("CombatCamera")).shake(e.power or 1)
	elseif e.e == "shakeSelf" and self.isLocal then
		require(RS:WaitForChild("CombatCamera")).shake((e.power or 1) * 0.6)
	elseif e.e == "lunge" and self.isLocal then
		require(RS:WaitForChild("CombatCamera")).punch(2.2)
	end
end

function Anim:checkEvents()
	local a = self.action
	if not a then
		return
	end
	local def = a.def
	if not def.fx then
		return
	end
	local prog = a.t / def.duration
	if def.loop then
		prog = prog - math.floor(prog)
		if prog < self.fxPrev then
			self.fxDone = {}
		end
	end
	for i = 1, #def.fx do
		local e = def.fx[i]
		if not self.fxDone[i] and e.t > self.fxPrev and e.t <= prog then
			self.fxDone[i] = true
			self:handleEvent(e, prog)
		end
	end
	self.fxPrev = prog
end

-- ---------------------------------------------------------------------------
-- Главный кадр
-- ---------------------------------------------------------------------------
function Anim:render(dt)
	local c = self.character
	local hum = self.humanoid
	local root = self.root
	if not (c.Parent and hum and root and root.Parent) then
		return
	end
	if hum.Health <= 0 or c:GetAttribute("KO") then
		-- рэгдоллом управляет сервер, позы не навязываем
		self.state.ko = true
		if self.flyTrail then
			self.flyTrail.Enabled = false
		end
		if self.shield then
			self.shield.Transparency = 1
		end
		return
	end
	if self.state.ko then
		self:setKO(false)
	end

	if not self.builtFx and now() >= self.nextBuildFx then
		self:buildFx()
		self.nextBuildFx = now() + 0.5
	end
	if not self.trackTried then
		self:loadTracks()
	end

	-- масштаб времени (хит-стоп)
	local scale = 1
	if now() < Animator.hitStopUntil then
		scale = Animator.timeScaleTarget or 0.15
	end
	local adt = dt * scale

	local vel = root.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local speed = flat.Magnitude
	local grounded = (hum.FloorMaterial ~= Enum.Material.Air) and math.abs(vel.Y) < 12

	-- приземление
	if grounded and not self.state.wasGrounded and speed > 2 then
		self:play("land", {}, true)
	elseif not grounded and self.state.wasGrounded and vel.Y > 10 then
		if not self.action or self.action.name ~= "flip" then
			self:play("jump")
		end
	end
	self.state.wasGrounded = grounded

	-- локомоция
	local pose
	if self.state.flying then
		pose = self:flightPose(adt, speed, vel)
	else
		pose = self:locomotion(adt, speed, grounded, vel)
	end

	-- поза блока (накладывается поверх передвижения, когда держишь R)
	if self.state.blocking and not self.state.flying then
		pose = Pose.mix(pose, Actions.POSES.block, 0.9)
	end

	-- действие
	if self.action then
		local a = self.action
		local def = a.def
		a.t = a.t + adt
		local life = def.duration
		if not def.loop and a.t >= life then
			if a.hasTrack then
				self:stopTracks()
			end
			self.action = nil
		else
			local w = math.clamp(a.t / 0.07, 0, 1)
			if not def.loop then
				local outStart = life - 0.13
				if a.t > outStart then
					w = math.min(w, math.clamp(1 - (a.t - outStart) / 0.13, 0, 1))
				end
			end
			a.w = w * def.weight
			self:checkEvents()
			if not a.hasTrack then
				local ap = Actions.sample(def, a.t / life)
				pose = Pose.mix(pose, ap, a.w)
			end
		end
	end

	-- реакция на удар
	if self.flinch then
		local f = self.flinch
		f.t = f.t + adt
		local prog = f.t / f.dur
		if prog >= 1 then
			self.flinch = nil
		else
			local w = f.w
			if prog > 0.72 then
				w = w * (1 - (prog - 0.72) / 0.28)
			end
			if prog < 0.1 then
				w = w * (prog / 0.1)
			end
			pose = Pose.mix(pose, Actions.sample(f.def, prog), w)
		end
	end

	-- «дыхание» в стойке
	if speed < 1.2 and grounded and not self.action then
		local b = math.sin(now() * 1.9)
		local br = {}
		for k, v in pairs(BREATH) do
			br[k] = (type(v) == "table") and { p = v.p * b, y = 0, r = (v.r or 0) * b } or v * b
		end
		br.bob = 0.02 * b
		pose = Pose.add(pose, br, 1)
	end

	Pose.apply(self.rig, pose)

	-- локальные эффекты
	local stats
	if self.player then
		stats = self.player:FindFirstChild("CombatStats")
	end
	local ult = stats and stats:FindFirstChild("Ult") and stats.Ult.Value or 0
	local energy = stats and stats:FindFirstChild("Energy") and stats.Energy.Value or 0
	self:renderFx(dt, pose, speed, vel, grounded, ult, energy)
end

function Anim:renderFx(dt, pose, speed, vel, grounded, ult, energy)
	local c = self.character
	local root = self.root
	local pos = root.Position

	-- щит блока
	if self.shield then
		local want = self.state.blocking
		if want then
			self.shield.CFrame = root.CFrame
			self.shield.Transparency = 0.55 + 0.08 * math.sin(now() * 6)
			self.shield.Color = Config.Colors.block
		else
			self.shield.Transparency = 1
		end
	end

	-- трейл полёта
	if self.flyTrail then
		local want = self.state.flying and speed > 30
		self.flyTrail.Enabled = want and true or false
		if want then
			local boost = self.state.boost or 0
			local thickness = 2.6 + boost * 3.5
			self.flyTrail.WidthScale = NumberSequence.new({
				NumberSequenceKeypoint.new(0, thickness),
				NumberSequenceKeypoint.new(1, 0),
			})
		end
	end

	-- аура ульты
	local needAura = (ult >= Config.Ult.max) or self.state.ultActive
	if needAura then
		if not self.aura then
			self.aura = {
				fxPart({ Name = "AuraRing1", Shape = Enum.PartType.Cylinder, Color = Config.Colors.ult,
					Size = Vector3.new(0.25, 7, 7), Transparency = 0.3 }),
				fxPart({ Name = "AuraRing2", Shape = Enum.PartType.Cylinder, Color = Config.Colors.ultHot,
					Size = Vector3.new(0.18, 5.4, 5.4), Transparency = 0.45 }),
				fxPart({ Name = "AuraCore", Shape = Enum.PartType.Ball, Color = Config.Colors.ult,
					Size = Vector3.new(2.2, 2.2, 2.2), Transparency = 0.75 }),
			}
		end
		local t = now()
		local r1 = self.aura[1]
		local r2 = self.aura[2]
		local core = self.aura[3]
		r1.CFrame = CFrame.new(pos + Vector3.new(0, 1.2 + math.sin(t * 2.2) * 0.5, 0)) * CFrame.Angles(math.rad(t * 120), math.rad(t * 40), math.rad(90))
		r2.CFrame = CFrame.new(pos + Vector3.new(0, -0.6 + math.sin(t * 2.2 + 1) * 0.4, 0)) * CFrame.Angles(math.rad(t * -90), math.rad(t * 25), math.rad(90 + 24))
		core.CFrame = root.CFrame * CFrame.new(0, 0, 0.4)
		local pulse = 0.7 + 0.25 * math.sin(t * 8)
		core.Size = Vector3.new(2.2 * pulse, 2.2 * pulse, 2.2 * pulse)
	elseif self.aura then
		for _, p in pairs(self.aura) do
			p:Destroy()
		end
		self.aura = nil
	end

	-- энергоядро в груди (если есть деталь Core у персонажа)
	local core = c:FindFirstChild("Core")
	if core and core:IsA("BasePart") then
		local charge = math.clamp(ult / Config.Ult.max, 0, 1)
		local glow = 0.55 - 0.4 * charge
		core.Transparency = math.clamp(glow + 0.05 * math.sin(now() * 5), 0, 1)
		core.Color = Color3.new(0.2 + 0.8 * charge, 0.9 - 0.35 * charge, 1)
		core.Size = Vector3.new(0.55, 0.55, 0.55) * (0.9 + 0.25 * charge + 0.06 * math.sin(now() * 7))
	end

	-- орбы зарядки (тяжёлый удар / лазер / залп)
	local needOrb = self.chargeHold and now() < self.chargeHold
	if needOrb then
		for _, handName in ipairs({ "Right Arm", "Left Arm" }) do
			local part = c:FindFirstChild(handName)
			if part then
				local orb = self.orbParts and self.orbParts[handName]
				if not orb or not orb.Parent then
					orb = fxPart({
						Name = "PalmOrb",
						Shape = Enum.PartType.Ball,
						Color = (handName == "Right Arm") and Config.Colors.plasma or Config.Colors.violet,
						Size = Vector3.new(1.1, 1.1, 1.1),
						Transparency = 0.25,
					})
					if not self.orbParts then
						self.orbParts = {}
					end
					self.orbParts[handName] = orb
				end
				local s = 1.1 + 0.25 * math.sin(now() * 14)
				orb.Size = Vector3.new(s, s, s)
				orb.CFrame = part.CFrame * CFrame.new(0, -1.1, -0.2)
			end
		end
	elseif self.orbParts then
		for _, orb in pairs(self.orbParts) do
			if orb and orb.Parent then
				orb:Destroy()
			end
		end
		self.orbParts = nil
	end
end

function Animator.setChargeHold(character, seconds)
	local a = Animator.list[character]
	if a then
		a.chargeHold = now() + seconds
	end
end

-- Обновление всех персонажей
function Animator.update(dt)
	for character, a in pairs(Animator.list) do
		if not character.Parent then
			Animator.forget(character)
		else
			local ok, err = pcall(function()
				a:render(dt)
			end)
			if not ok then
				warn("[CombatAnimator] " .. tostring(err))
			end
		end
	end
end

return Animator
