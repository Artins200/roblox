--[[
	CombatPose — процедурный «аниматор» поз.

	Работает с шарнирами (Motor6D) любого рига: R6 и R15. У каждого шарнира
	запоминается его родной C0, а затем каждый кадр шарнир поворачивается
	вокруг ЭТОЙ ЖЕ точки. Анимаций-ассетов не нужно вообще.

	Соглашение об углах (все в радианах, оси родительской части):
	  p (pitch) — «вперёд»:  конечность уходит вперёд (-Z), корпус наклоняется
	  y (yaw)   — «поворот»:  скрутка корпуса, горизонтальная закрутка
	  r (roll)  — «в сторону»: конечность отводится в сторону, корпус кренится
	  bend      — сгиб второго сегмента (локоть R15 / колено R15), градусы

	Позы удобно писать в градусах: Pose.deg{ ra = { p = 95, r = 10 } }.
]]

local Pose = {}

Pose.ORDER = { "body", "neck", "la", "ra", "ll", "rl" }

-- Первый сегмент: R6-имя → R15-имя
local JOINT_NAMES = {
	body = { "RootJoint", "Root" },
	neck = { "Neck", "Neck" },
	la   = { "Left Shoulder", "LeftShoulder" },
	ra   = { "Right Shoulder", "RightShoulder" },
	ll   = { "Left Hip", "LeftHip" },
	rl   = { "Right Hip", "RightHip" },
}

-- Второй сегмент (только R15): локоть / колено
local BEND_NAMES = {
	la = "LeftElbow",
	ra = "RightElbow",
	ll = "LeftKnee",
	rl = "RightKnee",
}

local WAIST_NAMES = { "Waist" }

-- ---------------------------------------------------------------------------
-- Конструкторы поз
-- ---------------------------------------------------------------------------

local function zero()
	return { p = 0, y = 0, r = 0, bend = 0 }
end

-- Пустая поза (все нули = родная стойка персонажа)
function Pose.blank()
	local out = {}
	for i = 1, #Pose.ORDER do
		out[Pose.ORDER[i]] = zero()
	end
	out.bob = 0
	return out
end

function Pose.copy(a)
	local out = Pose.blank()
	if not a then
		return out
	end
	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local s, d = a[k], out[k]
		if s then
			d.p, d.y, d.r, d.bend = s.p or 0, s.y or 0, s.r or 0, s.bend or 0
		end
	end
	out.bob = a.bob or 0
	return out
end

-- Градусы → радианы. Pose.deg{ body = { p = 10, y = -20 }, ra = { p = 95, bend = 40 } }
function Pose.deg(t)
	local out = Pose.blank()
	if not t then
		return out
	end
	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local v = t[k]
		if v then
			local d = out[k]
			d.p = math.rad(v.p or v[1] or 0)
			d.y = math.rad(v.y or v[2] or 0)
			d.r = math.rad(v.r or v[3] or 0)
			d.bend = math.rad(v.bend or v[4] or 0)
		end
	end
	out.bob = t.bob or 0
	return out
end

-- Линейная смесь поз: t = 0 → a, t = 1 → b
function Pose.mix(a, b, t)
	local out = Pose.blank()
	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local x, z, d = a and a[k], b and b[k], out[k]
		if x and z then
			d.p = x.p + (z.p - x.p) * t
			d.y = x.y + (z.y - x.y) * t
			d.r = x.r + (z.r - x.r) * t
			d.bend = (x.bend or 0) + ((z.bend or 0) - (x.bend or 0)) * t
		elseif z then
			d.p, d.y, d.r, d.bend = z.p * t, z.y * t, z.r * t, (z.bend or 0) * t
		elseif x then
			d.p, d.y, d.r, d.bend = x.p * (1 - t), x.y * (1 - t), x.r * (1 - t), (x.bend or 0) * (1 - t)
		end
	end
	out.bob = (a and a.bob or 0) + ((b and b.bob or 0) - (a and a.bob or 0)) * t
	return out
end

-- Сложение поз (для наложения «дыхания», тряски, отдачи) с весом s
function Pose.add(a, b, s)
	s = s or 1
	local out = Pose.copy(a)
	if not b then
		return out
	end
	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local z, d = b[k], out[k]
		if z then
			d.p = d.p + (z.p or 0) * s
			d.y = d.y + (z.y or 0) * s
			d.r = d.r + (z.r or 0) * s
			d.bend = (d.bend or 0) + (z.bend or 0) * s
		end
	end
	out.bob = (a and a.bob or 0) + (b.bob or 0) * s
	return out
end

-- ---------------------------------------------------------------------------
-- Работа с ригом персонажа
-- ---------------------------------------------------------------------------

local function findJoint(character, names)
	if type(names) == "string" then
		names = { names }
	end
	for i = 1, #names do
		local j = character:FindFirstChild(names[i], true)
		if j and j:IsA("Motor6D") then
			return j
		end
	end
	return nil
end

-- Описание рига: шарниры + их родные C0 (точка вращения и ориентация)
function Pose.newRig(character)
	local rig = {
		model = character,
		joints = {}, rest = {}, second = {}, secondRest = {},
		last = {}, ready = false, r15 = false, jointsFound = 0,
	}
	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local j = findJoint(character, JOINT_NAMES[k])
		if j then
			rig.joints[k] = j
			local c0 = j.C0
			rig.rest[k] = { pos = c0.Position, rot = c0 - c0.Position }
			rig.last[k] = zero()
			rig.jointsFound = rig.jointsFound + 1
		end
		local b = findJoint(character, BEND_NAMES[k])
		if b then
			rig.second[k] = b
			local c0 = b.C0
			rig.secondRest[k] = { pos = c0.Position, rot = c0 - c0.Position }
			rig.r15 = true
		end
	end
	rig.waist = findJoint(character, WAIST_NAMES)
	if rig.waist then
		-- у R15 корпус гнётся в двух местах: Root (тело) + Waist (поясница)
		local wc0 = rig.waist.C0
		rig.waistRest = { pos = wc0.Position, rot = wc0 - wc0.Position }
		rig.r15 = true
	end
	if rig.r15 then
		-- у R15 корневой шарнир называется Root, а не RootJoint
		rig.joints.body = rig.joints.body or findJoint(character, { "RootJoint", "Root" })
	end
	rig.ready = (rig.joints.body ~= nil) and (rig.joints.neck ~= nil)
	return rig
end

local EPS = 0.0012
local BOB_EPS = 0.012

local function sameAngles(a, b)
	return math.abs(a.p - b.p) < EPS and math.abs(a.y - b.y) < EPS
		and math.abs(a.r - b.r) < EPS and math.abs((a.bend or 0) - (b.bend or 0)) < EPS
end

-- Применяет позу к шарнирам (локальная операция, ничего не ломает)
function Pose.apply(rig, pose, force)
	if not rig or not rig.ready or not pose then
		return false
	end
	local dirty = force and true or false
	if not dirty then
		for i = 1, #Pose.ORDER do
			local k = Pose.ORDER[i]
			local want, had = pose[k], rig.last[k]
			if had and want then
				if not sameAngles(want, had) then
					dirty = true
					break
				end
			elseif want then
				dirty = true
				break
			end
		end
		if not dirty and math.abs((pose.bob or 0) - (rig.last.bob or 0)) > BOB_EPS then
			dirty = true
		end
	end
	if not dirty then
		return false
	end

	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local j = rig.joints[k]
		if j then
			local a = pose[k] or zero()
			local rest = rig.rest[k]
			local c0 = CFrame.new(rest.pos) * CFrame.Angles(a.p or 0, a.y or 0, a.r or 0) * rest.rot
			if k == "body" and pose.bob and pose.bob ~= 0 then
				c0 = c0 + Vector3.new(0, pose.bob, 0)
			end
			j.C0 = c0

			-- поясница R15: небольшой дополнительный изгиб корпуса
			if k == "body" and rig.waist and rig.waistRest then
				rig.waist.C0 = CFrame.new(rig.waistRest.pos)
					* CFrame.Angles((a.p or 0) * 0.35, (a.y or 0) * 0.45, (a.r or 0) * 0.3)
					* rig.waistRest.rot
			end

			-- второй сегмент (локоть/колено) — только если он есть у рига
			local sec = rig.second[k]
			if sec then
				local srest = rig.secondRest[k]
				local bend = a.bend or 0
				local sc = CFrame.new(srest.pos) * CFrame.Angles(bend, 0, 0) * srest.rot
				sec.C0 = sc
			end

			local last = rig.last[k]
			if last then
				last.p, last.y, last.r = a.p or 0, a.y or 0, a.r or 0
				last.bend = a.bend or 0
			end
		end
	end
	rig.last.bob = pose.bob or 0
	return true
end

-- Возвращает персонажа в родную стойку
function Pose.reset(rig)
	if not rig or not rig.ready then
		return
	end
	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local j = rig.joints[k]
		if j then
			local rest = rig.rest[k]
			j.C0 = CFrame.new(rest.pos) * rest.rot
			rig.last[k] = zero()
		end
		local sec = rig.second[k]
		if sec then
			local srest = rig.secondRest[k]
			sec.C0 = CFrame.new(srest.pos) * srest.rot
		end
	end
	if rig.waist and rig.waistRest then
		rig.waist.C0 = CFrame.new(rig.waistRest.pos) * rig.waistRest.rot
	end
	rig.last.bob = 0
end

function Pose.forward(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		return root.CFrame.LookVector
	end
	return Vector3.new(0, 0, -1)
end

-- Часть конечности для эффектов: у R6 это вся рука, у R15 — кисть/предплечье
local LIMB_PARTS = {
	la = { "Left Arm", "LeftLowerArm" },
	ra = { "Right Arm", "RightLowerArm" },
	ll = { "Left Leg", "LeftLowerLeg" },
	rl = { "Right Leg", "RightLowerLeg" },
}

function Pose.limb(character, key)
	local names = LIMB_PARTS[key]
	if not names then
		return nil
	end
	for i = 1, #names do
		local p = character:FindFirstChild(names[i], true)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

function Pose.limbCFrame(character, key)
	local p = Pose.limb(character, key)
	if p then
		return p.CFrame
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return root and root.CFrame or CFrame.new()
end

return Pose
