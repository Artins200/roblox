--[[
	CombatDummies — тренировочные манекены.

	Это ПРОСТО белые болванчики: стоят на своих местах, ничего не делают и
	принимают любые удары (жизнь не кончается). У них нет имён, полосок HP и
	никакого ИИ — только вспышка от попадания, лёгкий толчок и возврат на место,
	если их сильно отбросило.
]]

local Players = game:GetService("Players")

local RS = script.Parent
local Config = require(RS:WaitForChild("CombatConfig"))

local Dummies = {}
Dummies.folder = nil
Dummies.list = {}

local WHITE = Config.Dummy.color
local MAT = Config.Dummy.material

local function newPart(name, size, cf, parent, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = false
	p.CanCollide = collide ~= false
	p.CanQuery = true
	p.TopSurface = Enum.SurfaceType.SmoothNoOutlines
	p.BottomSurface = Enum.SurfaceType.SmoothNoOutlines
	p.Material = MAT
	p.Color = WHITE
	p.Locked = true
	p.Parent = parent
	return p
end

local function joint(name, parent, part0, part1, c0, c1)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = parent
	return m
end

-- Классическая R6-фигура манекена (та же схема, что у персонажа игрока)
function Dummies.buildRig(cf, parent)
	local model = Instance.new("Model")
	model.Name = "Dummy"
	model.Parent = parent

	local hrp = newPart("HumanoidRootPart", Vector3.new(2, 2, 1), cf * CFrame.new(0, 3, 0), model, false)
	local torso = newPart("Torso", Vector3.new(2, 2, 1), cf * CFrame.new(0, 3, 0), model, true)
	local head = newPart("Head", Vector3.new(1, 1, 1), cf * CFrame.new(0, 4.5, 0), model, true)
	local la = newPart("Left Arm", Vector3.new(1, 2, 1), cf * CFrame.new(-1.5, 3, 0), model, true)
	local ra = newPart("Right Arm", Vector3.new(1, 2, 1), cf * CFrame.new(1.5, 3, 0), model, true)
	local ll = newPart("Left Leg", Vector3.new(1, 2, 1), cf * CFrame.new(-0.5, 1, 0), model, true)
	local rl = newPart("Right Leg", Vector3.new(1, 2, 1), cf * CFrame.new(0.5, 1, 0), model, true)
	model.PrimaryPart = hrp

	joint("RootJoint", hrp, hrp, torso, CFrame.new(), CFrame.new())
	joint("Neck", torso, torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
	joint("Left Shoulder", torso, torso, la, CFrame.new(-1, 0.5, 0), CFrame.new(0.5, 0.5, 0))
	joint("Right Shoulder", torso, torso, ra, CFrame.new(1, 0.5, 0), CFrame.new(-0.5, 0.5, 0))
	joint("Left Hip", torso, torso, ll, CFrame.new(-0.5, -1, 0), CFrame.new(0, 1, 0))
	joint("Right Hip", torso, torso, rl, CFrame.new(0.5, -1, 0), CFrame.new(0, 1, 0))

	local hum = Instance.new("Humanoid")
	hum.Name = "Humanoid"
	hum.RigType = Enum.HumanoidRigType.R6
	hum.MaxHealth = Config.Dummy.health
	hum.Health = Config.Dummy.health
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayDistance = 0
	hum.NameDisplayDistance = 0
	hum.Parent = model
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)

	model:SetAttribute("Dummy", true)
	model:SetAttribute("NoFlash", false)

	Dummies.list[model] = {
		home = cf * CFrame.new(0, 3, 0),
		root = hrp,
		hum = hum,
		displaced = 0,
	}
	return model, hum
end

-- Места: ровный круг вокруг центра арены + центр
local function spots()
	local out = {}
	local count = math.max(1, Config.Dummy.count)
	local r = Config.Dummy.ringRadius
	for i = 1, count do
		local ang = (i - 1) / count * math.pi * 2
		local x = math.sin(ang) * r
		local z = math.cos(ang) * r
		-- манекен смотрит в центр арены
		local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.atan2(x, z), 0)
		out[#out + 1] = cf
	end
	return out
end

function Dummies.init(arena)
	local parent = Dummies.folder
	if not parent or not parent.Parent then
		parent = workspace:FindFirstChild("CombatDummies")
		if not parent then
			parent = Instance.new("Folder")
			parent.Name = "CombatDummies"
			parent.Parent = workspace
		end
		Dummies.folder = parent
	end

	local all = spots()
	for i = 1, #all do
		local ok, err = pcall(function()
			Dummies.buildRig(all[i], parent)
		end)
		if not ok then
			warn("[EPIC COMBAT] манекен не создан: " .. tostring(err))
		end
	end
	return #all
end

function Dummies.getFromCharacter(model)
	local info = Dummies.list[model]
	if info and info.root and info.root.Parent then
		return info
	end
	return nil
end

function Dummies.getFromPart(part)
	if not part then
		return nil
	end
	local model = part:FindFirstAncestorOfClass("Model")
	while model and not Dummies.list[model] do
		model = model:FindFirstAncestorOfClass("Model")
	end
	return model and Dummies.list[model] or nil
end

function Dummies.count()
	local n = 0
	for _, info in pairs(Dummies.list) do
		if info.root and info.root.Parent then
			n = n + 1
		end
	end
	return n
end

function Dummies.resetAll(Vfx)
	for model, info in pairs(Dummies.list) do
		if info.root and info.root.Parent and model.Parent then
			model:PivotTo(info.home)
			info.root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			info.root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
			info.displaced = 0
			if info.hum then
				info.hum.Health = info.hum.MaxHealth
			end
			if Vfx then
				Vfx.pillar(info.home.Position, Config.Colors.plasma, 18, 2.4, 0.8)
				Vfx.ring(info.home.Position - Vector3.new(0, 2.6, 0), Config.Colors.plasma, 2, 12, 0.6, false, 0.4)
			end
		end
	end
	return Dummies.count()
end

-- Возврат манекенов на места, поддержание полной жизни и «неубиваемости»
function Dummies.update(dt, Vfx)
	for model, info in pairs(Dummies.list) do
		if not model.Parent or not info.root or not info.root.Parent then
			Dummies.list[model] = nil
		else
			if info.hum and info.hum.Health < info.hum.MaxHealth then
				info.hum.Health = info.hum.MaxHealth
			end
			local root = info.root
			local away = (root.Position - info.home.Position).Magnitude
			if away > 6 then
				info.displaced = (info.displaced or 0) + dt
				-- гасим разлёт, чтобы манекен не улетал с арены
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = v * math.max(0, 1 - dt * 2.5)
			else
				info.displaced = 0
			end
			if (info.displaced or 0) > Config.Dummy.returnTime then
				model:PivotTo(info.home)
				root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				info.displaced = 0
				if Vfx then
					Vfx.ring(info.home.Position, Config.Colors.plasma, 1.6, 10, 0.5, false, 0.5)
				end
			end
		end
	end
end

return Dummies
