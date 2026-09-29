--[[
	CombatPose — процедурный «аниматор» поз для R6 (и на всякий случай R15).

	Идея: у каждого шарнира (Motor6D) мы запоминаем его родной C0, а затем
	каждый кадр поворачиваем шарнир на нужные углы вокруг ЭТОЙ ЖЕ точки.
	Получается анимация без единого ассета: удары, полёт, нокдауны и т.д.

	Соглашение об углах (все в радианах, ось — родительская часть):
	  p (pitch) — «вперёд»: конечность уходит вперёд (-Z), тело наклоняется вперёд
	  y (yaw)   — «поворот»: скрутка корпуса, горизонтальная закрутка конечности
	  r (roll)  — «в сторону»: конечность отводится вправо (+X), корпус кренится
	Порядок применения: roll → yaw → pitch  (CFrame.Angles(p, y, r) = Rx*Ry*Rz)

	Позу можно задавать в градусах через Pose.deg{...} — читать удобнее.
]]

local Pose = {}

Pose.ORDER = { "body", "neck", "la", "ra", "ll", "rl" }

-- Имена шарниров в R6 / R15
local JOINT_NAMES = {
	body = { "RootJoint", "Root" },
	neck = { "Neck", "Neck" },
	la   = { "Left Shoulder", "LeftShoulder" },
	ra   = { "Right Shoulder", "RightShoulder" },
	ll   = { "Left Hip", "LeftHip" },
	rl   = { "Right Hip", "RightHip" },
}

-- ---------------------------------------------------------------------------
-- Конструкторы поз
-- ---------------------------------------------------------------------------

local function isZero(v)
	return v == 0 or v == nil
end

-- Пустая поза (все нули = родная стойка персонажа)
function Pose.blank()
	local out = {}
	for i = 1, #Pose.ORDER do
		out[Pose.ORDER[i]] = { p = 0, y = 0, r = 0 }
	end
	out.bob = 0
	return out
end

-- Градусы → радианы. Pose.deg{ body = { p = 10, y = -20 }, ra = { p = 95 } }
function Pose.deg(t)
	local out = Pose.blank()
	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local v = t[k]
		if v then
			out[k].p = math.rad(v.p or v[1] or 0)
			out[k].y = math.rad(v.y or v[2] or 0)
			out[k].r = math.rad(v.r or v[3] or 0)
		end
	end
	out.bob = t.bob or 0
	return out
end

function Pose.copy(a)
	local out = Pose.blank()
	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local s = a[k]
		local d = out[k]
		if s then
			d.p, d.y, d.r = s.p or 0, s.y or 0, s.r or 0
		end
	end
	out.bob = a.bob or 0
	return out
end

-- Линейная смесь поз: t = 0 → a, t = 1 → b
function Pose.mix(a, b, t)
	local out = Pose.blank()
	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local x, z = a[k], b[k]
		local d = out[k]
		if x and z then
			d.p = x.p + (z.p - x.p) * t
			d.y = x.y + (z.y - x.y) * t
			d.r = x.r + (z.r - x.r) * t
		elseif z then
			d.p, d.y, d.r = z.p * t, z.y * t, z.r * t
		elseif x then
			d.p, d.y, d.r = x.p * (1 - t), x.y * (1 - t), x.r * (1 - t)
		end
	end
	out.bob = (a.bob or 0) + ((b.bob or 0) - (a.bob or 0)) * t
	return out
end

-- Сложение поз (для наложения «дыхания», тряски, отдачи) с весом s
function Pose.add(a, b, s)
	s = s or 1
	local out = Pose.copy(a)
	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local z = b[k]
		local d = out[k]
		if z then
			d.p = d.p + (z.p or 0) * s
			d.y = d.y + (z.y or 0) * s
			d.r = d.r + (z.r or 0) * s
		end
	end
	out.bob = (a.bob or 0) + (b.bob or 0) * s
	return out
end

-- ---------------------------------------------------------------------------
-- Работа с ригом персонажа
-- ---------------------------------------------------------------------------

local function findJoint(character, names)
	for i = 1, #names do
		local j = character:FindFirstChild(names[i], true)
		if j and j:IsA("Motor6D") then
			return j
		end
	end
	return nil
end

-- Создаёт описание рига: шарниры + их родные C0 (точка вращения и ориентация)
function Pose.newRig(character)
	local rig = { model = character, joints = {}, rest = {}, last = {}, ready = false }
	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local j = findJoint(character, JOINT_NAMES[k])
		if j then
			rig.joints[k] = j
			local c0 = j.C0
			rig.rest[k] = {
				pos = c0.Position,
				rot = c0 - c0.Position,
			}
			rig.last[k] = { p = 0, y = 0, r = 0 }
		end
	end
	rig.ready = (rig.joints.body ~= nil)
	return rig
end

local EPS = 0.0009
local BOB_EPS = 0.012

-- Применяет позу к шарнирам (клиентская, локальная операция — ничего не ломает)
function Pose.apply(rig, pose, force)
	if not rig or not rig.ready then
		return
	end
	local dirty = force and true or false
	if not dirty then
		for i = 1, #Pose.ORDER do
			local k = Pose.ORDER[i]
			local want, had = pose[k], rig.last[k]
			if had and want then
				if math.abs(want.p - had.p) > EPS or math.abs(want.y - had.y) > EPS
					or math.abs(want.r - had.r) > EPS then
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
		return
	end

	for i = 1, #Pose.ORDER do
		local k = Pose.ORDER[i]
		local j = rig.joints[k]
		if j then
			local a = pose[k] or { p = 0, y = 0, r = 0 }
			local rest = rig.rest[k]
			local c0 = CFrame.new(rest.pos) * CFrame.Angles(a.p, a.y, a.r) * rest.rot
			if k == "body" and pose.bob and pose.bob ~= 0 then
				c0 = c0 + Vector3.new(0, pose.bob, 0)
			end
			j.C0 = c0
			local last = rig.last[k]
			if last then
				last.p, last.y, last.r = a.p, a.y, a.r
			end
		end
	end
	rig.last.bob = pose.bob or 0
end

-- Сбрасывает персонажа в родную стойку (когда его удалили/респавн)
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
		end
	end
end

-- Мировое направление взгляда корпуса (для ориентации эффектов)
function Pose.forward(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		return root.CFrame.LookVector
	end
	return Vector3.new(0, 0, -1)
end

-- Возвращает CFrame «плеча» в мире — удобно для спавна эффектов у кулака
function Pose.limbCFrame(character, partName)
	local part = character:FindFirstChild(partName, true)
	if part then
		return part.CFrame
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return root and root.CFrame or CFrame.new()
end

return Pose
