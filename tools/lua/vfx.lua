--[[
	CombatVfx — серверный спавнер эпичных эффектов.

	Всё создаётся из обычных Part'ов с Neon-материалом и твинится TweenService.
	Никаких внешних ассетов, никакого риска «файл не загрузился» — зато
	взрывы, лучи, ударные волны, призраки рывка и вспышки выглядят сочно.

	Все эффекты сами себя убирают (Debris) и не мешают физике:
	CanCollide=false, CanQuery=false, CanTouch=false, Anchored=true.
]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Vfx = {}

local folder
local MAX_PARTS = 900

function Vfx.init()
	folder = workspace:FindFirstChild("CombatFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CombatFX"
		folder.Parent = workspace
	end
	return folder
end

local function ensure()
	if not folder then
		Vfx.init()
	end
	return folder
end

function Vfx.partCount()
	return folder and #folder:GetChildren() or 0
end

local function budget(n)
	-- Страховка от переполнения: если эффектов слишком много — убираем самые старые
function Vfx.cleanup()
	if not folder then
		return
	end
	local kids = folder:GetChildren()
	local n = #kids
	if n <= 0 then
		return
	end
	if n > MAX_PARTS * 0.75 then
		for i = 1, n - math.floor(MAX_PARTS * 0.5) do
			kids[i]:Destroy()
		end
		return
	end
	-- заодно подчищаем «пыль»/искры, которые уже отыграли
	for _, p in ipairs(kids) do
		if p:GetAttribute("Dead") then
			p:Destroy()
		end
	end
end

return Vfx.partCount() + (n or 1) <= MAX_PARTS
end

local function newPart(props, life)
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
	p.Parent = ensure()
	if life then
		Debris:AddItem(p, life + 1.5)
	end
	return p
end

local function tween(part, time, goal, style)
	TweenService:Create(part, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

-- ---------------------------------------------------------------------------
-- Базовые эффекты
-- ---------------------------------------------------------------------------

-- Вспышка-шар в точке удара
function Vfx.impact(pos, color, scale, life)
	if not budget(1) then
		return nil
	end
	scale = scale or 4
	life = life or 0.28
	local p = newPart({
		Name = "Impact",
		Shape = Enum.PartType.Ball,
		Color = color,
		Size = Vector3.new(scale * 0.3, scale * 0.3, scale * 0.3),
		CFrame = CFrame.new(pos),
		Transparency = 0.1,
	}, life)
	tween(p, life, { Size = Vector3.new(scale * 1.6, scale * 1.6, scale * 1.6), Transparency = 1 })
	local core = newPart({
		Name = "ImpactCore",
		Shape = Enum.PartType.Ball,
		Color = Color3.new(1, 1, 1),
		Size = Vector3.new(scale * 0.2, scale * 0.2, scale * 0.2),
		CFrame = CFrame.new(pos),
	}, life * 0.8)
	tween(core, life * 0.8, { Size = Vector3.new(scale * 0.9, scale * 0.9, scale * 0.9), Transparency = 1 })
	return p
end

-- Искры, летящие в стороны
function Vfx.sparks(pos, dir, count, color, speed, life, size)
	if not budget(count + 1) then
		return
	end
	count = count or 10
	speed = speed or 26
	life = life or 0.45
	size = size or 0.45
	dir = dir or Vector3.new(0, 1, 0)
	for i = 1, count do
		local spread = Vector3.new(
			math.random() * 2 - 1,
			math.random() * 2 - 1,
			math.random() * 2 - 1
		) * 0.85
		local d = (dir + spread).Unit
		local s = size * (0.5 + math.random() * 0.9)
		local p = newPart({
			Name = "Spark",
			Shape = Enum.PartType.Ball,
			Color = color,
			Size = Vector3.new(s, s, s),
			CFrame = CFrame.new(pos),
		}, life)
		local travel = speed * life * (0.6 + math.random() * 0.8)
		local goalPos = pos + d * travel + Vector3.new(0, -travel * 0.25, 0)
		tween(p, life, { CFrame = CFrame.new(goalPos), Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
	end
end

-- Расширяющееся кольцо (сплюснутый цилиндр). upright=false → лежит на земле
function Vfx.ring(pos, color, fromR, toR, life, upright, thick)
	if not budget(1) then
		return nil
	end
	life = life or 0.5
	thick = thick or 0.35
	local size = Vector3.new(thick, fromR * 2, fromR * 2)
	local cf = CFrame.new(pos)
	if not upright then
		cf = cf * CFrame.Angles(0, 0, math.rad(90))
	end
	local p = newPart({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Color = color,
		Size = size,
		CFrame = cf,
		Transparency = 0.15,
	}, life)
	local goalSize = Vector3.new(thick * 0.3, toR * 2, toR * 2)
	tween(p, life, { Size = goalSize, Transparency = 1 })
	return p
end

-- Ударная волна: кольцо + вспышка + искры
function Vfx.shockwave(pos, color, radius, life)
	life = life or 0.6
	Vfx.ring(pos, color, radius * 0.15, radius, life, false, 0.5)
	Vfx.impact(pos, color, radius * 0.5, life * 0.7)
	Vfx.sparks(pos, Vector3.new(0, 1, 0), 12, color, radius * 1.4, life, 0.5)
end

-- Луч от точки до точки
function Vfx.beam(from, to, color, thickness, life, taper, hot)
	local dist = (to - from).Magnitude
	if dist < 0.05 or not budget(3) then
		return nil
	end
	life = life or 0.3
	thickness = thickness or 1.2
	local mid = from + (to - from) * 0.5
	local cf = CFrame.lookAt(mid, to)
	local core = newPart({
		Name = "Beam",
		Color = hot or Color3.new(1, 1, 1),
		Material = Enum.Material.Neon,
		Size = Vector3.new(thickness * 0.45, thickness * 0.45, dist),
		CFrame = cf,
		Transparency = 0.05,
	}, life)
	local glow = newPart({
		Name = "BeamGlow",
		Color = color,
		Size = Vector3.new(thickness * 2.1, thickness * 2.1, dist),
		CFrame = cf,
		Transparency = 0.55,
	}, life)
	tween(core, life, { Transparency = 1, Size = Vector3.new(thickness * 0.1, thickness * 0.1, dist) })
	tween(glow, life, { Transparency = 1, Size = Vector3.new(thickness * (taper or 3.4), thickness * (taper or 3.4), dist) })
	return core
end

-- Столб света вверх
function Vfx.pillar(pos, color, height, radius, life, down)
	if not budget(4) then
		return
	end
	life = life or 0.8
	local h = down and -height or height
	local p = newPart({
		Name = "Pillar",
		Shape = Enum.PartType.Cylinder,
		Color = color,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(down and -90 or 90)),
		Transparency = 0.25,
	}, life)
	local core = newPart({
		Name = "PillarCore",
		Shape = Enum.PartType.Cylinder,
		Color = Color3.new(1, 1, 1),
		Size = Vector3.new(height, radius, radius),
		CFrame = p.CFrame,
		Transparency = 0.35,
	}, life)
	tween(p, life, { Transparency = 1, Size = Vector3.new(height * 1.4, radius * 4.6, radius * 4.6) })
	tween(core, life, { Transparency = 1, Size = Vector3.new(height * 1.2, radius * 1.6, radius * 1.6) })
	Vfx.ring(pos, color, radius, radius * 6, life, false, 0.5)
end

-- Разряд/вспышка света
function Vfx.flash(pos, color, brightness, range, life)
	if not budget(1) then
		return
	end
	life = life or 0.5
	local host = newPart({
		Name = "FlashHost",
		Color = color,
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = CFrame.new(pos),
		Transparency = 1,
	}, life)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness or 6
	light.Range = range or 40
	light.Shadows = false
	light.Parent = host
	TweenService:Create(light, TweenInfo.new(life), { Brightness = 0 }):Play()
end

-- Призрак (след рывка/полёта): копии частей персонажа
function Vfx.ghost(character, color, life, transparency)
	if not budget(8) then
		return
	end
	life = life or 0.45
	transparency = transparency or 0.55
	local names = { "HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "UpperTorso", "LowerTorso" }
	local made = {}
	for i = 1, #names do
		local part = character:FindFirstChild(names[i])
		if part and part:IsA("BasePart") then
			local p = newPart({
				Name = "Ghost",
				Color = color,
				Shape = (part.Shape == Enum.PartType.Ball) and Enum.PartType.Ball or Enum.PartType.Block,
				Size = part.Size,
				CFrame = part.CFrame,
				Transparency = transparency,
			}, life)
			tween(p, life, { Transparency = 1 })
			made[#made + 1] = p
		end
	end
	return made
end

-- Плоскость удара (дуга замаха)
function Vfx.slash(cf, color, length, width, life)
	if not budget(1) then
		return nil
	end
	life = life or 0.22
	local p = newPart({
		Name = "Slash",
		Color = color,
		Size = Vector3.new(width, length, 0.3),
		CFrame = cf,
		Transparency = 0.25,
	}, life)
	tween(p, life, { Transparency = 1, Size = Vector3.new(width * 2.2, length * 1.6, 0.1) })
	return p
end

-- Заряжающийся шар у точки (например, у кулака)
function Vfx.chargeOrb(adornee, offset, color, time, size)
	if not budget(3) then
		return nil
	end
	local p = newPart({
		Name = "ChargeOrb",
		Shape = Enum.PartType.Ball,
		Color = color,
		Size = Vector3.new(0.5, 0.5, 0.5),
		Transparency = 0.2,
	}, 4)
	if adornee and offset then
		p.CFrame = adornee.CFrame * offset
	end
	local core = newPart({
		Name = "ChargeCore",
		Shape = Enum.PartType.Ball,
		Color = Color3.new(1, 1, 1),
		Size = Vector3.new(0.3, 0.3, 0.3),
		Transparency = 0.1,
	}, 4)
	if adornee and offset then
		core.CFrame = p.CFrame
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 3
	light.Range = 18
	light.Parent = p
	local t = time or 0.5
	local s = size or 2.6
	tween(p, t, { Size = Vector3.new(s, s, s), Transparency = 0.35 })
	tween(core, t, { Size = Vector3.new(s * 0.4, s * 0.4, s * 0.4) })
	return { part = p, core = core, light = light }
end

function Vfx.stopOrb(orb, burstColor, burstScale)
	if not orb or not orb.part then
		return
	end
	local part = orb.part
	local pos = part.CFrame.Position
	local color = part.Color
	part:Destroy()
	if orb.core then
		orb.core:Destroy()
	end
	Vfx.impact(pos, burstColor or color, burstScale or 3, 0.22)
end

-- Нова: большой взрыв во все стороны
function Vfx.nova(pos, color, radius, life)
	life = life or 1.1
	Vfx.impact(pos, color, radius * 0.6, life * 0.5)
	Vfx.ring(pos, color, radius * 0.2, radius * 2.4, life, false, 0.9)
	Vfx.ring(pos, color, radius * 0.2, radius * 2.0, life * 1.3, true, 0.9)
	Vfx.pillar(pos, color, radius * 2.4, radius * 0.18, life)
	Vfx.sparks(pos, Vector3.new(0, 1, 0), 30, color, radius * 2.2, life, 0.9)
	Vfx.flash(pos, color, 12, radius * 2.2, life * 0.6)
end

-- Пыль/дым от приземления
function Vfx.dust(pos, count, color, scale)
	if not budget(count) then
		return
	end
	count = count or 8
	scale = scale or 1
	color = color or Color3.fromRGB(210, 210, 220)
	for i = 1, count do
		local a = math.random() * math.pi * 2
		local d = Vector3.new(math.cos(a), 0.35 + math.random() * 0.4, math.sin(a))
		local p = newPart({
			Name = "Dust",
			Shape = Enum.PartType.Ball,
			Color = color,
			Material = Enum.Material.ForceField,
			Size = Vector3.new(scale, scale, scale),
			CFrame = CFrame.new(pos + d * 1.2),
			Transparency = 0.4,
		}, 0.6)
		tween(p, 0.55, {
			CFrame = CFrame.new(pos + d * (5 + math.random() * 5) * scale),
			Size = Vector3.new(scale * 4, scale * 4, scale * 4),
			Transparency = 1,
		})
	end
end

-- Гигантский луч ульты: ядро + оболочка + волны вдоль луча
function Vfx.giantBeam(from, dir, length, color, hot, thickness, life)
	life = life or 1.0
	thickness = thickness or 20
	local to = from + dir.Unit * length
	Vfx.beam(from, to, color, thickness, life, 3.2, hot)
	for i = 1, 6 do
		local t = i / 7
		local pos = from + (to - from) * t
		local r = thickness * (0.8 + math.random() * 0.8)
		Vfx.ring(pos, hot, r * 0.2, r * 2.6, 0.4 + math.random() * 0.3, true, thickness * 0.12)
	end
	Vfx.flash(from, hot, 20, thickness * 6, life * 0.5)
end

-- След на земле (тёмный шрам) — декоративный, живёт долго
function Vfx.scorch(pos, radius, life)
	if not budget(1) then
		return
	end
	life = life or 12
	local p = newPart({
		Name = "Scorch",
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(20, 20, 25),
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 0.35,
	}, life)
	tween(p, life, { Transparency = 1 })
	return p
end

-- Взрыв серии снарядов (для залпа/ульты)
function Vfx.bolt(from, to, color, hot, thickness, life, impactScale)
	Vfx.beam(from, to, color, thickness or 1.6, life or 0.22, 2.6, hot)
	Vfx.impact(to, color, impactScale or 6, 0.3)
	Vfx.sparks(to, (from - to).Unit, 6, color, 30, 0.35, 0.35)
end

-- Страховка от переполнения: если эффектов слишком много — убираем самые старые
function Vfx.cleanup()
	if not folder then
		return
	end
	local kids = folder:GetChildren()
	local n = #kids
	if n <= 0 then
		return
	end
	if n > MAX_PARTS * 0.75 then
		for i = 1, n - math.floor(MAX_PARTS * 0.5) do
			kids[i]:Destroy()
		end
		return
	end
	-- заодно подчищаем «пыль»/искры, которые уже отыграли
	for _, p in ipairs(kids) do
		if p:GetAttribute("Dead") then
			p:Destroy()
		end
	end
end

return Vfx
