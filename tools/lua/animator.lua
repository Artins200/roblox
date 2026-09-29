--[[
	CombatAnimator — процедурный аниматор бойцов (R6 и R15).

	Каждый клиент сам рисует анимации ВСЕМ персонажам:
	  * передвижение (шаг/бег/прыжок/падение/приземление),
	  * полёт (поза супермена, крены, буст, пикирование, шлейф-«крылья»),
	  * четыре атаки: комбо ударов, пинок, лазер, ульта,
	  * реакции на попадание и нокдаун,
	плюс локальные эффекты: трейлы кулаков/ног, аура ульты, орбы зарядки,
	энергощит, звуки, вспышки манекенов.

	Опционально играет настоящие анимации из Toolbox — если в
	Config.ToolboxAnims указаны ID, для этих действий процедурная поза отключается.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local RS = script.Parent
local Config = require(RS:WaitForChild("CombatConfig"))
local Pose = require(RS:WaitForChild("CombatPose"))
local Actions = require(RS:WaitForChild("CombatActions"))

local Animator = {}
Animator.list = {}
Animator.hitStopUntil = 0
Animator.timeScaleTarget = 1
Animator.errors = {}
Animator.ready = 0

local function now()
	return os.clock()
end

Animator.warnCount = 0
local function warnOnce(key, msg)
	if Animator.errors[key] or Animator.warnCount > 20 then
		return
	end
	Animator.errors[key] = true
	Animator.warnCount = Animator.warnCount + 1
	warn("[EPIC COMBAT] " .. msg)
end

-- ---------------------------------------------------------------------------
-- Локальная папка эффектов (создаётся на клиенте, не репликуется)
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

local fxCount = 0
local function fxPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.SmoothNoOutlines
	p.BottomSurface = Enum.SurfaceType.SmoothNoOutlines
	p.Size = Vector3.new(1, 1, 1)
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = fx()
	fxCount = fxCount + 1
	if fxCount > 220 then
		fxCount = 0
		local kids = fx():GetChildren()
		for i = 1, math.min(60, #kids) do
			kids[i]:Destroy()
		end
	end
	return p
end

-- ---------------------------------------------------------------------------
-- Звук
-- ---------------------------------------------------------------------------
local function playSound(name, position, volumeMul, pitchMul)
	local def = Config.Sfx[name]
	if not def or not def.id or def.id == "" then
		return
	end
	local cam = workspace.CurrentCamera
	if cam and position and (cam.CFrame.Position - position).Magnitude > (Config.Sfx.maxDistance or 400) then
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
	s.RollOffMaxDistance = 220
	s.RollOffMinDistance = 14
	s.Parent = host
	s:Play()
	Debris:AddItem(s, 6)
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
	t.Name = "FxTrail"
	t.Attachment0 = a
	t.Attachment1 = b
	t.Color = ColorSequence.new(c1, c2)
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	t.Lifetime = lifetime or 0.22
	t.LightEmission = 1
	t.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, thickness or 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	t.Enabled = false
	t.Parent = part
	return t
end

-- ===========================================================================
-- Экземпляр аниматора персонажа
-- ===========================================================================
local Anim = {}
Anim.__index = Anim

function Animator.get(character)
	local a = Animator.list[character]
	if not a then
		a = setmetatable({}, Anim)
		local ok, err = pcall(function()
			a:init(character)
		end)
		if not ok then
			warnOnce("init", "не смог завести аниматор персонажа: " .. tostring(err))
			return nil
		end
		if not a.rig or not a.rig.ready then
			warnOnce("rig", "у персонажа не найдены шарниры (ожидался R6/R15)")
			return nil
		end
		Animator.list[character] = a
		Animator.ready = Animator.ready + 1
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

function Animator.hitStop(duration, scale)
	Animator.hitStopUntil = math.max(Animator.hitStopUntil, now() + (duration or 0.06))
	Animator.timeScaleTarget = scale or 0.15
end

function Anim:init(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then
		return
	end
	self.character = character
	self.humanoid = hum
	self.root = root
	self.rig = Pose.newRig(character)
	self.state = {
		flying = false, blocking = false, ko = false,
		boost = 0, bank = 0, phase = 0, wasGrounded = true, dead = false,
	}
	self.action = nil
	self.flinch = nil
	self.trails = {}
	self.aura = nil
	self.shield = nil
	self.builtFx = false
	self.nextBuildFx = now() + 0.35
	self.trackKillUntil = now() + 5
	self.nextTrackKill = 0
	self.player = Players:GetPlayerFromCharacter(character)
	self.isLocal = (self.player == Players.LocalPlayer)
	self.tracks = {}
	self.tracksTried = false
	self.chargeHold = 0
	self.flashUntil = 0
	self.flashColor = nil
	-- гасим стандартные анимации Roblox, иначе они спорят с нашими позами
	self:killDefaultAnims()
	if character:GetAttribute("Dummy") then
		self:setupFlash()
	end
	return true
end

function Anim:killDefaultAnims()
	local c = self.character
	local function kill(inst)
		if inst and (inst.Name == "Animate" or inst.Name == "AnimateR15" or inst.Name == "Ragdoll") then
			pcall(function()
				inst:Destroy()
			end)
		end
	end
	for _, obj in ipairs(c:GetChildren()) do
		kill(obj)
	end
	if not self.animWatcher then
		self.animWatcher = c.ChildAdded:Connect(kill)
	end
end

function Anim:stopHumanoidTracks()
	local animator = self.humanoid and self.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local ok = pcall(function()
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end)
	return ok
end

function Anim:destroy()
	if self.animWatcher then
		pcall(function()
			self.animWatcher:Disconnect()
		end)
	end
	for _, t in pairs(self.trails or {}) do
		if t and t.Parent then
			t:Destroy()
		end
	end
	for _, key in ipairs({ "aura", "orbs", "engines", "wings" }) do
		local set = self[key]
		if set then
			for _, p in pairs(set) do
				if p and p.Parent then
					p:Destroy()
				end
			end
		end
	end
	if self.shield and self.shield.Parent then
		self.shield:Destroy()
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
-- Постоянные локальные эффекты персонажа
-- ---------------------------------------------------------------------------
function Anim:buildFx()
	local c = self.character
	if self.builtFx then
		return
	end
	if c:GetAttribute("Dummy") then
		-- у белых манекенов не должно быть трейлов и аур
		self.builtFx = true
		return
	end
	local laPart = Pose.limb(c, "la")
	local raPart = Pose.limb(c, "ra")
	local llPart = Pose.limb(c, "ll")
	local rlPart = Pose.limb(c, "rl")
	self.trails.la = laPart and makeTrail(laPart, Vector3.new(0, 0.95, 0.15), Vector3.new(0, -0.95, -0.4),
		Config.Colors.plasma, Config.Colors.plasmaHot, 1.1, 0.2)
	self.trails.ra = raPart and makeTrail(raPart, Vector3.new(0, 0.95, 0.15), Vector3.new(0, -0.95, -0.4),
		Config.Colors.plasma, Config.Colors.plasmaHot, 1.1, 0.2)
	self.trails.ll = llPart and makeTrail(llPart, Vector3.new(0, 0.9, 0.1), Vector3.new(0, -1.1, -0.35),
		Config.Colors.violet, Config.Colors.plasma, 1.2, 0.22)
	self.trails.rl = rlPart and makeTrail(rlPart, Vector3.new(0, 0.9, 0.1), Vector3.new(0, -1.1, -0.35),
		Config.Colors.violet, Config.Colors.plasma, 1.2, 0.22)
	-- «крылья» полёта: две длинные ленты от плеч назад
	local torso = c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso")
	if torso then
		local a1 = Instance.new("Attachment")
		a1.Name = "WingA1"
		a1.Position = Vector3.new(-0.55, 0.2, 0.5)
		a1.Parent = torso
		local a2 = Instance.new("Attachment")
		a2.Name = "WingA2"
		a2.Position = Vector3.new(0.55, 0.2, 0.5)
		a2.Parent = torso
		local b1 = Instance.new("Attachment")
		b1.Name = "WingB1"
		b1.Position = Vector3.new(-0.55, -0.9, 0.9)
		b1.Parent = torso
		local b2 = Instance.new("Attachment")
		b2.Name = "WingB2"
		b2.Position = Vector3.new(0.55, -0.9, 0.9)
		b2.Parent = torso
		local w1 = Instance.new("Trail")
		w1.Name = "WingTrail"
		w1.Attachment0 = a1
		w1.Attachment1 = b1
		w1.Color = ColorSequence.new(Config.Colors.ice, Config.Colors.plasma)
		w1.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		w1.LightEmission = 1
		w1.Lifetime = 0.34
		w1.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 3.4),
			NumberSequenceKeypoint.new(1, 0),
		})
		w1.Enabled = false
		w1.Parent = torso
		local w2 = w1:Clone()
		w2.Attachment0 = a2
		w2.Attachment1 = b2
		w2.Parent = torso
		self.wings = { w1, w2 }
	end
	self.builtFx = true
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
-- Анимации из Toolbox (если указаны ID)
-- ---------------------------------------------------------------------------
function Anim:loadTracks()
	if self.tracksTried then
		return
	end
	self.tracksTried = true
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
				pcall(function()
					track.Priority = Enum.AnimationPriority.Action4
				end)
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
	local ok = pcall(function()
		track:Play(0.08)
	end)
	return ok
end

function Anim:stopTracks()
	for _, track in pairs(self.tracks or {}) do
		pcall(function()
			if track.IsPlaying then
				track:Stop(0.1)
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Действия
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
		local interruptible = cur.loop or (self.action.t >= (cur.chain or 0))
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
	self.fxPrev = 0
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

-- Реакция на попадание: поза выбирается по направлению удара в локальных осях
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
			name = (x > 0) and "hitSideR" or "hitSideL"
		end
	end
	local def = Actions.get(name)
	if not def then
		return
	end
	self.flinch = {
		def = def,
		t = 0,
		dur = def.duration,
		w = math.clamp(0.55 + (power or 1) * 0.3, 0.5, 1),
	}
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
		if self.rig then
			Pose.reset(self.rig)
		end
	end
end

-- ===========================================================================
-- Позы по состояниям
-- ===========================================================================
local BREATH = {
	body = { p = 0.03 }, neck = { p = -0.05 },
	la = { p = 0.05, r = -0.04 }, ra = { p = 0.05, r = 0.04 },
	ll = { p = 0, r = 0 }, rl = { p = 0, r = 0 }, bob = 0,
}

function Anim:locomotion(dt, speed, grounded, vel)
	local L = Actions.LOCO
	local pose = Pose.copy(Actions.STANCE)
	local walkSpeed = math.max(self.humanoid.WalkSpeed or 16, 1)
	local run = math.clamp((speed - walkSpeed * 0.9) / (walkSpeed * 0.6), 0, 1)

	if grounded then
		if speed > 0.7 then
			self.state.phase = (self.state.phase or 0) + speed * dt * 0.3
		end
		local amp = math.rad(L.walkAmp + (L.runAmp - L.walkAmp) * run)
		local armsAmp = math.rad(L.walkArms + (L.runArms - L.walkArms) * run)
		local s = math.sin(self.state.phase)
		local c = math.cos(self.state.phase)
		local k = math.clamp(speed / walkSpeed, 0, 1.35)
		pose.ll.p = pose.ll.p + amp * s * k
		pose.rl.p = pose.rl.p - amp * s * k
		pose.ll.bend = (pose.ll.bend or 0) - math.rad(30) * math.max(0, -s) * k
		pose.rl.bend = (pose.rl.bend or 0) - math.rad(30) * math.max(0, s) * k
		pose.la.p = pose.la.p - armsAmp * s * k
		pose.ra.p = pose.ra.p + armsAmp * s * k
		pose.la.r = pose.la.r - math.rad(6) * k
		pose.ra.r = pose.ra.r + math.rad(6) * k
		pose.la.bend = (pose.la.bend or 0) + math.rad(18) * k
		pose.ra.bend = (pose.ra.bend or 0) + math.rad(18) * k
		pose.body.y = pose.body.y - math.rad(L.sway) * s * (0.35 + run * 0.6)
		pose.body.r = pose.body.r + math.rad(L.sway * 0.35) * c * (0.4 + run * 0.6)
		pose.body.p = pose.body.p + math.rad(L.runLean * 0.55) * run * k
		pose.neck.p = pose.neck.p - math.rad(L.runLean * 0.5) * run * k
		pose.bob = pose.bob - L.bobAmp * math.abs(c) * k * (0.55 + run * 0.5)
		return pose
	end

	-- В воздухе (без полёта): прыжок ↔ падение по вертикальной скорости
	local t = math.clamp((vel.Y + 14) / 26, 0, 1)
	pose = Pose.mix(Actions.POSES.fall, Actions.POSES.jump, t)
	local sway = math.clamp(vel.X * 0.02 + vel.Z * 0.02, -0.25, 0.25)
	pose.body.r = pose.body.r + sway
	pose.body.y = pose.body.y + sway * 0.6
	return pose
end

function Anim:flightPose(dt, speed, vel)
	local M = Config.Move
	local cruise = math.clamp(speed / math.max(M.flySpeed * 0.45, 1), 0, 1)
	local pose
	local pitch = math.clamp(vel.Y / 55, -1, 1)
	if pitch < -0.35 then
		-- пикируем
		pose = Pose.mix(Actions.POSES.flyCruise, Actions.POSES.flyDive, math.clamp(-pitch, 0, 1))
	elseif pitch > 0.45 then
		-- набираем высоту из зависания
		pose = Pose.mix(Actions.POSES.flyCruise, Actions.POSES.flyHover, math.clamp((1 - cruise) * 0.7, 0, 1))
		pose.body.p = pose.body.p + math.rad(20) * pitch
	else
		pose = Pose.mix(Actions.POSES.flyHover, Actions.POSES.flyCruise, cruise)
	end
	local boost = self.state.boost or 0
	if boost > 0 then
		pose = Pose.mix(pose, Actions.POSES.flyBoost, boost)
	end
	-- крен в поворотах (bank) и лёгкий «трепет» крыльев
	pose.body.y = pose.body.y + (self.state.bank or 0)
	pose.body.r = pose.body.r + (self.state.bank or 0) * 0.35
	local t = now()
	local flutter = math.rad(3) * math.sin(t * 6.5)
	pose.la.p = pose.la.p + flutter
	pose.ra.p = pose.ra.p - flutter
	pose.ll.p = pose.ll.p + flutter * 0.8
	pose.rl.p = pose.rl.p - flutter * 0.8
	pose.bob = pose.bob + 0.05 * math.sin(t * 3.6)
	return pose
end

-- ===========================================================================
-- События анимации (звук, трейл, вспышка, тряска)
-- ===========================================================================
function Anim:handleEvent(e)
	local c = self.character
	local root = self.root
	local pos = root.Position
	local hand = e.hand
	local handPart = hand and Pose.limb(c, hand)
	local hp = handPart and handPart.CFrame.Position or pos
	local ev = e.e

	if ev == "whoosh" then
		playSound("whoosh", pos, e.vol or 1, (e.pitch or 1) * (0.95 + math.random() * 0.15))
	elseif ev == "whooshBig" then
		playSound("whooshBig", pos, 1, (e.pitch or 1) * (0.95 + math.random() * 0.12))
	elseif ev == "fist" or ev == "swing" or ev == "heavyFist" then
		self:toggleTrail(hand or "ra", ev == "heavyFist" and 0.34 or 0.22)
		playSound("hit", hp, 0.4, 1.5)
		if ev == "heavyFist" then
			local p = fxPart({
				Name = "FistFlash",
				Shape = Enum.PartType.Ball,
				Color = Config.Colors.plasmaHot,
				Size = Vector3.new(1.6, 1.6, 1.6),
				CFrame = CFrame.new(hp),
			})
			Debris:AddItem(p, 0.4)
			local TweenService = game:GetService("TweenService")
			TweenService:Create(p, TweenInfo.new(0.26), { Size = Vector3.new(5.5, 5.5, 5.5), Transparency = 1 }):Play()
		end
	elseif ev == "kickTrail" then
		self:toggleTrail(hand or "rl", 0.34)
		playSound("hit", hp, 0.5, 1.2)
	elseif ev == "spin" then
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
			Size = Vector3.new(0.2, 15, 15), Transparency = 1,
		}):Play()
		Debris:AddItem(ring, 0.6)
	elseif ev == "chargeStart" then
		self.chargeHold = now() + 0.4
	elseif ev == "chargeLoop" or ev == "palms" then
		self.chargeHold = now() + 0.45
		if e.sound then
			playSound(e.sound, pos, 0.6, 1.1)
		end
	elseif ev == "laserFire" then
		playSound("laser", hp, 1, 0.95 + math.random() * 0.1)
		local dir = root.CFrame.LookVector
		local muzzle = hp + dir * 1.4
		local p = fxPart({
			Name = "Muzzle",
			Shape = Enum.PartType.Ball,
			Color = Config.Colors.plasmaHot,
			Size = Vector3.new(1.4, 1.4, 1.4),
			CFrame = CFrame.new(muzzle),
		})
		local TweenService = game:GetService("TweenService")
		TweenService:Create(p, TweenInfo.new(0.2), { Size = Vector3.new(4.5, 4.5, 4.5), Transparency = 1 }):Play()
		Debris:AddItem(p, 0.45)
		self.chargeHold = 0
		self:cameraFx("punch", 2.2)
	elseif ev == "auraBurst" then
		local ring = fxPart({
			Name = "AuraRing",
			Shape = Enum.PartType.Cylinder,
			Color = Config.Colors.ult,
			Size = Vector3.new(0.4, 3, 3),
			CFrame = CFrame.new(pos - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Transparency = 0.2,
		})
		local TweenService = game:GetService("TweenService")
		TweenService:Create(ring, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.2, 18, 18), Transparency = 1,
		}):Play()
		Debris:AddItem(ring, 0.95)
		playSound("whooshBig", pos, 0.7, 0.8)
	elseif ev == "ultChargeLoop" then
		playSound("ultCharge", pos, 0.55, 1)
	elseif ev == "ultNova" then
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
				Size = Vector3.new(0.3, 60, 60), Transparency = 1,
			}):Play()
			Debris:AddItem(ring, 1.5)
		end
		local dome = fxPart({
			Name = "UltDome",
			Shape = Enum.PartType.Ball,
			Color = col,
			Size = Vector3.new(6, 6, 6),
			CFrame = CFrame.new(pos),
			Transparency = 0.35,
		})
		local TweenService = game:GetService("TweenService")
		TweenService:Create(dome, TweenInfo.new(0.75), { Size = Vector3.new(48, 48, 48), Transparency = 1 }):Play()
		Debris:AddItem(dome, 1.2)
	elseif ev == "ultBeamLoop" then
		self.chargeHold = now() + 0.6
		playSound("ultFire", hp, 0.5, 1.4)
	elseif ev == "beamPulse" then
		local p = fxPart({
			Name = "BeamCore",
			Shape = Enum.PartType.Ball,
			Color = Config.Colors.ultHot,
			Size = Vector3.new(3, 3, 3),
			CFrame = CFrame.new(hp + root.CFrame.LookVector * 2),
			Transparency = 0.2,
		})
		local TweenService = game:GetService("TweenService")
		TweenService:Create(p, TweenInfo.new(0.4), { Size = Vector3.new(12, 12, 12), Transparency = 1 }):Play()
		Debris:AddItem(p, 0.6)
	elseif ev == "landDust" then
		playSound("land", pos, 1, 1)
		local disc = fxPart({
			Name = "Dust",
			Shape = Enum.PartType.Cylinder,
			Color = Color3.fromRGB(190, 200, 220),
			Material = Enum.Material.SmoothPlastic,
			Size = Vector3.new(0.3, 5, 5),
			CFrame = CFrame.new(pos - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Transparency = 0.45,
		})
		local TweenService = game:GetService("TweenService")
		TweenService:Create(disc, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.2, 26, 26), Transparency = 1,
		}):Play()
		Debris:AddItem(disc, 1)
	elseif ev == "scorch" then
		local s = fxPart({
			Name = "Scorch",
			Shape = Enum.PartType.Cylinder,
			Color = Color3.fromRGB(20, 16, 24),
			Material = Enum.Material.Slate,
			Size = Vector3.new(0.12, 9, 9),
			CFrame = CFrame.new(pos - Vector3.new(0, 2.94, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Transparency = 0.25,
		})
		Debris:AddItem(s, 6)
	elseif ev == "flipBurst" then
		playSound("whoosh", pos, 1, 1.4)
	end

	if ev == "shake" then
		self:cameraFx("shake", e.shake or e.power or 1)
	elseif ev == "shakeSelf" then
		self:cameraFx("shake", (e.shake or e.power or 1) * 0.6)
	elseif ev == "lunge" then
		self:cameraFx("punch", e.power or 2)
	end
	if e.hitStop and e.hitStop > 0 then
		Animator.hitStop(e.hitStop, 0.2)
	end
	if e.shake and self.isLocal then
		self:cameraFx("shake", e.shake)
	end
	if e.flash and self.isLocal then
		local Camera = RS:FindFirstChild("CombatCamera")
		if Camera then
			local ok = pcall(function()
				require(Camera).flash(Config.Colors.plasmaHot, e.flash, 0.3)
			end)
		end
	end
end

function Anim:cameraFx(kind, power)
	if not self.isLocal then
		return
	end
	local mod = RS:FindFirstChild("CombatCamera")
	if not mod then
		return
	end
	pcall(function()
		local Camera = require(mod)
		if kind == "shake" then
			Camera.shake(power)
		elseif kind == "punch" then
			Camera.punch(power)
		end
	end)
end

function Anim:checkEvents()
	local a = self.action
	if not a or a.hasTrack then
		return
	end
	local def = a.def
	local life = def.duration
	local prog = a.t / life
	local fxList = def.fx
	if not fxList then
		return
	end
	for i = 1, #fxList do
		local e = fxList[i]
		if e.t > self.fxPrev and e.t <= prog then
			local ok, err = pcall(function()
				self:handleEvent(e)
			end)
			if not ok then
				warnOnce("fx:" .. tostring(e.e), "событие анимации " .. tostring(e.e) .. ": " .. tostring(err))
			end
		end
	end
	self.fxPrev = prog
end

-- ===========================================================================
-- Кадр
-- ===========================================================================
function Anim:render(dt)
	local c = self.character
	local hum = self.humanoid
	local root = self.root
	if not (c.Parent and hum and hum.Parent and root and root.Parent) then
		return
	end

	if hum.Health <= 0 then
		if not self.state.ko then
			self.state.ko = true
			self:play("ko")
		end
		if self.wings then
			for _, w in ipairs(self.wings) do
				w.Enabled = false
			end
		end
		if self.shield then
			self.shield.Transparency = 1
		end
		return
	end
	if self.state.ko then
		self:setKO(false)
	end

	-- первые секунды глушим чужие анимации персонажа
	if now() < self.trackKillUntil and now() >= self.nextTrackKill then
		self.nextTrackKill = now() + 0.25
		self:killDefaultAnims()
		self:stopHumanoidTracks()
	end
	if not self.builtFx and now() >= self.nextBuildFx then
		self:buildFx()
		if not self.builtFx then
			self.nextBuildFx = now() + 1
		end
	end
	if not self.tracksTried then
		self:loadTracks()
	end

	local scale = 1
	if now() < Animator.hitStopUntil then
		scale = Animator.timeScaleTarget or 0.2
	end
	local adt = dt * scale

	local vel = root.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local speed = flat.Magnitude
	local grounded = (hum.FloorMaterial ~= Enum.Material.Air) and math.abs(vel.Y) < 12

	if grounded and not self.state.wasGrounded and speed > 2 then
		self:play("land", {}, true)
	elseif not grounded and self.state.wasGrounded and vel.Y > 10 then
		if not self.action or self.action.name ~= "flip" then
			self:play("jump")
		end
	end
	self.state.wasGrounded = grounded

	local pose
	if self.state.flying then
		pose = self:flightPose(adt, speed, vel)
	else
		pose = self:locomotion(adt, speed, grounded, vel)
	end

	if self.state.blocking and not self.state.flying and speed < 1.2 then
		pose = Pose.mix(Actions.STANCE, pose, 0.25)
	end

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
				local fade = def.outFade or 0.13
				local outStart = life - fade
				if a.t > outStart then
					w = math.min(w, math.clamp(1 - (a.t - outStart) / fade, 0, 1))
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

	if self.flinch then
		local f = self.flinch
		f.t = f.t + adt
		local prog = f.t / f.dur
		if prog >= 1 then
			self.flinch = nil
		else
			local w = f.w
			if prog > 0.7 then
				w = w * (1 - (prog - 0.7) / 0.3)
			end
			if prog < 0.12 then
				w = w * (prog / 0.12)
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
	self:renderFx(dt, pose, speed, vel, grounded)
end

function Anim:renderFx(dt, pose, speed, vel, grounded)
	local c = self.character
	local root = self.root
	local pos = root.Position
	local hum = self.humanoid

	-- трейл полёта («крылья»)
	if self.wings then
		local want = self.state.flying and speed > 26
		for _, w in ipairs(self.wings) do
			if w.Parent then
				w.Enabled = want and true or false
				if want then
					local boost = self.state.boost or 0
					local thick = 3.2 + boost * 4
					w.WidthScale = NumberSequence.new({
						NumberSequenceKeypoint.new(0, thick),
						NumberSequenceKeypoint.new(1, 0),
					})
				end
			end
		end
	end

	-- щит блока
	if self.state.blocking and not self.shield then
		local shield = fxPart({
			Name = "Guard",
			Shape = Enum.PartType.Ball,
			Color = Config.Colors.ice,
			Size = Vector3.new(6, 6, 6),
			Transparency = 0.72,
		})
		self.shield = shield
	end
	if self.shield then
		if self.state.blocking then
			self.shield.CFrame = root.CFrame
			self.shield.Transparency = 0.68 + 0.06 * math.sin(now() * 6)
		else
			self.shield.Transparency = 1
		end
	end

	-- орбы зарядки в ладонях
	local wantOrbs = self.chargeHold and now() < self.chargeHold
	if wantOrbs then
		if not self.orbs then
			self.orbs = {}
			for _, key in ipairs({ "ra", "la" }) do
				self.orbs[key] = fxPart({
					Name = "PalmOrb",
					Shape = Enum.PartType.Ball,
					Color = (key == "ra") and Config.Colors.plasma or Config.Colors.violet,
					Size = Vector3.new(1.2, 1.2, 1.2),
					Transparency = 0.2,
				})
			end
		end
		for key, orb in pairs(self.orbs) do
			local part = Pose.limb(c, key)
			if part and orb.Parent then
				local s = 1.1 + 0.25 * math.sin(now() * 14)
				orb.Size = Vector3.new(s, s, s)
				orb.CFrame = part.CFrame * CFrame.new(0, -1.1, -0.25)
			end
		end
	elseif self.orbs then
		for _, orb in pairs(self.orbs) do
			if orb.Parent then
				orb:Destroy()
			end
		end
		self.orbs = nil
	end

	-- аура заряженной ульты у игрока
	local ult = 0
	if self.player then
		local stats = self.player:FindFirstChild("CombatStats")
		if stats then
			local u = stats:FindFirstChild("Ult")
			if u and u:IsA("NumberValue") then
				ult = u.Value
			end
		end
	else
		ult = 0
	end
	local needAura = self.state.ultActive or (self.player ~= nil and ult >= Config.Ult.max)
	if needAura then
		if not self.aura then
			self.aura = {
				fxPart({ Name = "AuraRing1", Shape = Enum.PartType.Cylinder, Color = Config.Colors.ult,
					Size = Vector3.new(0.25, 7, 7), Transparency = 0.3 }),
				fxPart({ Name = "AuraRing2", Shape = Enum.PartType.Cylinder, Color = Config.Colors.ultHot,
					Size = Vector3.new(0.18, 5.4, 5.4), Transparency = 0.45 }),
			}
		end
		local t = now()
		local r1, r2 = self.aura[1], self.aura[2]
		if r1.Parent then
			r1.CFrame = CFrame.new(pos + Vector3.new(0, 1.2 + math.sin(t * 2.2) * 0.5, 0))
				* CFrame.Angles(math.rad(t * 120), math.rad(t * 40), math.rad(90))
		end
		if r2.Parent then
			r2.CFrame = CFrame.new(pos + Vector3.new(0, -0.6 + math.sin(t * 2.2 + 1) * 0.4, 0))
				* CFrame.Angles(math.rad(t * -90), math.rad(t * 25), math.rad(90 + 24))
		end
	elseif self.aura then
		for _, p in pairs(self.aura) do
			if p.Parent then
				p:Destroy()
			end
		end
		self.aura = nil
	end

	-- вспышка манекена при попадании
	if self.flashUntil > 0 then
		if now() < self.flashUntil then
			local k = (self.flashUntil - now()) / 0.14
			self:applyFlash(Color3.new(self.flashColor.R, self.flashColor.G, self.flashColor.B), math.clamp(k, 0, 1))
		else
			self.flashUntil = 0
			self:applyFlash(nil, 0)
		end
	end
end

-- Подсветка деталей (используется для белых манекенов)
function Anim:applyFlash(color, k)
	local c = self.character
	local parts = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
		"UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }
	for _, name in ipairs(parts) do
		local p = c:FindFirstChild(name)
		if p and p:IsA("BasePart") and not p:GetAttribute("NoFlash") then
			if color then
				p.Color = p.Color:Lerp(color, k)
			elseif self.baseColors then
				local base = self.baseColors[p]
				if base then
					p.Color = base
				end
			end
		end
	end
end

function Anim:setupFlash()
	local c = self.character
	self.baseColors = {}
	for _, name in ipairs({ "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
		"UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }) do
		local p = c:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			self.baseColors[p] = p.Color
		end
	end
end

function Anim:flash(color, time)
	if not self.baseColors then
		return
	end
	self.flashColor = color or Config.Dummy.flashColor
	self.flashUntil = now() + (time or 0.14)
end

-- ===========================================================================
-- Сервис
-- ===========================================================================
function Animator.setChargeHold(character, seconds)
	local a = Animator.list[character]
	if a then
		a.chargeHold = now() + seconds
	end
end

function Animator.update(dt)
	for character, a in pairs(Animator.list) do
		if not character.Parent then
			Animator.forget(character)
		else
			local ok, err = pcall(function()
				a:render(dt)
			end)
			if not ok then
				warnOnce("render:" .. tostring(err), "отрисовка анимации: " .. tostring(err))
			end
		end
	end
end

-- Диагностика для экрана F3
function Animator.info()
	local n = 0
	for _ in pairs(Animator.list) do
		n = n + 1
	end
	local first = next(Animator.list)
	local sample = nil
	if first then
		local a = Animator.list[first]
		sample = {
			name = first.Name,
			rig = a.rig and a.rig.r15 and "R15" or "R6",
			joints = a.rig and a.rig.jointsFound or 0,
			action = a.action and a.action.name or "-",
		}
	end
	return n, sample
end

return Animator
