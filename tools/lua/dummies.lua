--[[
	CombatDummies — белые манекены для тренировки.

	Риг (R6) собирается прямо в коде: детали, Motor6D-шарниры, Humanoid.
	У каждого манекена:
	  * табличка с именем и полосой HP,
	  * вспышка при попадании,
	  * перезапуск после нокаута,
	  * возврат на пост, если его отбросило слишком далеко,
	  * рэгдолл при смерти (шаровые шарниры вместо Motor6D).

	Посты манекенов лежат в Workspace.Arena.DummyPosts и называются
	"Post_<тип>_<номер>" (тип: normal / heavy / titan).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("CombatConfig"))

local Dummies = {}

local folder
local posts = {}
local alive = {}       -- [post] = model
local pending = {}     -- [post] = true (запланирован респавн)
local downSince = {}   -- [model] = time
local hitTween = {}    -- [model] = token

local WHITE = Config.Dummy.types.normal.color

-- ---------------------------------------------------------------------------
-- Утилиты
-- ---------------------------------------------------------------------------
local function cm(x, y, z)
	return CFrame.new(x, y, z)
end

-- ---------------------------------------------------------------------------
-- Сборка белого R6-манекена
-- ---------------------------------------------------------------------------
function Dummies.buildRig(name, scale, color, parent)
	scale = scale or 1
	color = color or WHITE

	local model = Instance.new("Model")
	model.Name = name or "Dummy"

	local parts = {}

	local function makePart(pname, size, pos, transparency, canCollide, shape)
		local p = Instance.new("Part")
		p.Name = pname
		p.Size = Vector3.new(size[1] * scale, size[2] * scale, size[3] * scale)
		-- пропорциональное масштабирование: ступни остаются на y = 0
		p.CFrame = CFrame.new(pos[1] * scale, pos[2] * scale, pos[3] * scale)
		p.Anchored = true
		p.CanCollide = canCollide ~= false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = color
		p.Transparency = transparency or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		parts[pname] = p
		return p
	end

	-- Раскладка классического R6 (все размеры — «1×2×1», ступни на y=0)
	makePart("HumanoidRootPart", { 2, 2, 1 }, { 0, 3, 0 }, 1, false)
	makePart("Torso", { 2, 2, 1 }, { 0, 3, 0 })
	makePart("Head", { 2, 1, 1 }, { 0, 4.5, 0 })
	makePart("Left Arm", { 1, 2, 1 }, { -1.5, 3, 0 })
	makePart("Right Arm", { 1, 2, 1 }, { 1.5, 3, 0 })
	makePart("Left Leg", { 1, 2, 1 }, { -0.5, 1, 0 })
	makePart("Right Leg", { 1, 2, 1 }, { 0.5, 1, 0 })

	-- Голова-улыбка (та самая классика)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = parts.Head

	-- Шарниры
	local function joint(jname, part0, part1, c0, c1)
		local j = Instance.new("Motor6D")
		j.Name = jname
		j.Part0 = parts[part0]
		j.Part1 = parts[part1]
		j.C0 = c0
		j.C1 = c1
		j.Parent = parts[part0]
		return j
	end

	joint("RootJoint", "HumanoidRootPart", "Torso", cm(0, 0, 0), cm(0, 0, 0))
	joint("Neck", "Torso", "Head", cm(0, 1, 0), cm(0, -0.5, 0))
	joint("Left Shoulder", "Torso", "Left Arm", cm(-1, 0.5, 0), cm(0.5, 0.5, 0))
	joint("Right Shoulder", "Torso", "Right Arm", cm(1, 0.5, 0), cm(-0.5, 0.5, 0))
	joint("Left Hip", "Torso", "Left Leg", cm(-0.5, -1, 0), cm(0, 1, 0))
	joint("Right Hip", "Torso", "Right Leg", cm(0.5, -1, 0), cm(0, 1, 0))

	-- Humanoid
	local hum = Instance.new("Humanoid")
	hum.Name = "Humanoid"
	hum.MaxHealth = Config.Dummy.types.normal.health
	hum.Health = hum.MaxHealth
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.AutoRotate = true
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayDistance = 0
	hum.NameDisplayDistance = 0
	hum.Parent = model

	local animator = Instance.new("Animator")
	animator.Parent = hum

	-- Табличка
	local pad = Instance.new("BillboardGui")
	pad.Name = "DummyHud"
	pad.Size = UDim2.new(0, 190, 0, 52)
	pad.StudsOffset = Vector3.new(0, 3.4 * scale, 0)
	pad.AlwaysOnTop = false
	pad.MaxDistance = 260
	pad.Parent = parts.Head

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 1, 0)
	holder.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
	holder.BackgroundTransparency = 0.25
	holder.BorderSizePixel = 0
	holder.Parent = pad
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = holder
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(230, 235, 245)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.5
	stroke.Parent = holder

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -10, 0, 18)
	title.Position = UDim2.new(0, 5, 0, 3)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Text = "МАНЕКЕН"
	title.Parent = holder

	local bg = Instance.new("Frame")
	bg.Name = "HpBar"
	bg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	bg.BorderSizePixel = 0
	bg.Position = UDim2.new(0, 5, 0, 24)
	bg.Size = UDim2.new(1, -10, 0, 12)
	bg.ClipsDescendants = true
	bg.Parent = holder
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, 6)
	c2.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.fromRGB(120, 255, 150)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.Parent = bg
	local c3 = Instance.new("UICorner")
	c3.CornerRadius = UDim.new(0, 6)
	c3.Parent = fill
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(90, 255, 140), Color3.fromRGB(255, 220, 90))
	grad.Parent = fill

	local hpText = Instance.new("TextLabel")
	hpText.Name = "HpText"
	hpText.BackgroundTransparency = 1
	hpText.Position = UDim2.new(0, 5, 0, 38)
	hpText.Size = UDim2.new(1, -10, 0, 14)
	hpText.Font = Enum.Font.GothamBold
	hpText.TextSize = 13
	hpText.TextColor3 = Color3.fromRGB(230, 240, 255)
	hpText.Text = "0 / 0"
	hpText.Parent = holder

	model.PrimaryPart = parts.HumanoidRootPart

	-- физика: детали больше не закреплены
	for _, p in pairs(parts) do
		p.Anchored = false
	end

	if parent then
		model.Parent = parent
	end
	return model, parts, hum
end

-- ---------------------------------------------------------------------------
-- Рэгдолл (используется и для игроков)
-- ---------------------------------------------------------------------------
function Dummies.ragdoll(model)
	for _, j in ipairs(model:GetDescendants()) do
		if j:IsA("Motor6D") and j.Enabled then
			j.Enabled = false
			local p0, p1 = j.Part0, j.Part1
			if p0 and p1 then
				local a0 = Instance.new("Attachment")
				a0.Name = "RagA"
				a0.CFrame = j.C0
				a0.Parent = p0
				local a1 = Instance.new("Attachment")
				a1.Name = "RagB"
				a1.CFrame = j.C1
				a1.Parent = p1
				local socket = Instance.new("BallSocketConstraint")
				socket.Name = "RagSocket"
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				socket.LimitsEnabled = true
				socket.UpperAngle = 60
				socket.TwistLimitsEnabled = true
				socket.TwistUpperAngle = 45
				socket.TwistLowerAngle = -45
				socket.Parent = p0
			end
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = true
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Табличка манекена
-- ---------------------------------------------------------------------------
local function updateHud(hum, label)
	local holder = label
	local fill = holder:FindFirstChild("Fill")
	local text = holder.Parent:FindFirstChild("HpText")
	local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
	if fill then
		fill.Size = UDim2.new(frac, 0, 1, 0)
		fill.BackgroundColor3 = (frac > 0.5 and Color3.fromRGB(120, 255, 150))
			or (frac > 0.2 and Color3.fromRGB(255, 220, 90))
			or Color3.fromRGB(255, 90, 80)
	end
	if text then
		text.Text = math.floor(hum.Health) .. " / " .. math.floor(hum.MaxHealth)
	end
end

local function flash(model, color)
	local token = (hitTween[model] or 0) + 1
	hitTween[model] = token
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.Color = color
		end
	end
	task.delay(0.12, function()
		if hitTween[model] == token and model.Parent then
			for _, p in ipairs(model:GetChildren()) do
				if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
					p.Color = WHITE
				end
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Спавн / сброс
-- ---------------------------------------------------------------------------
local function spawnDummy(post)
	local def = Config.Dummy.types[post.type] or Config.Dummy.types.normal
	local model, parts, hum = Dummies.buildRig(post.type .. "_Dummy", def.scale, def.color, folder)
	model.Name = def.label
	model:SetAttribute("DummyType", post.type)

	-- ставим строго на площадку поста (её верх — уровень пола), лицом по развороту поста
	local top = post.part.CFrame * CFrame.new(0, post.part.Size.Y * 0.5, 0)
	model:PivotTo(top * CFrame.new(0, 3 * def.scale, 0))

	hum.MaxHealth = def.health
	hum.Health = def.health
	local holder = parts.Head:FindFirstChild("DummyHud")
	if holder then
		local frame = holder:FindFirstChildWhichIsA("Frame")
		local title = frame and frame:FindFirstChild("Title")
		if title then
			title.Text = def.label
		end
		if frame then
			updateHud(hum, frame:FindFirstChild("HpBar"))
		end
	end

	hum.HealthChanged:Connect(function(h)
		if hum.Health > 0 and holder then
			local frame = holder:FindFirstChildWhichIsA("Frame")
			if frame then
				updateHud(hum, frame:FindFirstChild("HpBar"))
			end
			flash(model, Color3.fromRGB(255, 150, 150))
		end
	end)

	hum.Died:Connect(function()
		flash(model, Color3.fromRGB(120, 120, 130))
		Dummies.ragdoll(model)
		alive[post] = nil
		if not pending[post] then
			pending[post] = true
			task.delay(Config.Dummy.respawnTime, function()
				pending[post] = nil
				if model.Parent then
					Debris:AddItem(model, 4)
				end
				if folder then
					spawnDummy(post)
				end
			end)
		end
	end)

	alive[post] = model
	downSince[model] = nil
	return model
end

function Dummies.getFromCharacter(model)
	for post, m in pairs(alive) do
		if m == model then
			return post
		end
	end
	return nil
end

function Dummies.getFromPart(part)
	local model = part and part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return model
	end
	return nil
end

function Dummies.resetAll(byPlayer)
	for post, model in pairs(alive) do
		if model and model.Parent then
			model:Destroy()
		end
		alive[post] = nil
	end
	for post in pairs(posts) do
		if not pending[post] then
			spawnDummy(post)
		end
	end
end

function Dummies.count()
	local n = 0
	for _ in pairs(alive) do
		n = n + 1
	end
	return n
end

-- ---------------------------------------------------------------------------
-- Инициализация + обслуживание
-- ---------------------------------------------------------------------------
function Dummies.init()
	folder = workspace:FindFirstChild("CombatDummies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CombatDummies"
		folder.Parent = workspace
	end
	local arena = workspace:FindFirstChild("Arena")
	local postsFolder = arena and arena:FindFirstChild("DummyPosts")
	if not postsFolder then
		warn("[Dummies] Не найдена папка Arena.DummyPosts — манекены не созданы")
		return
	end
	for _, part in ipairs(postsFolder:GetChildren()) do
		if part:IsA("BasePart") then
			local kind = string.match(part.Name, "^Post_(%a+)_") or "normal"
			if not Config.Dummy.types[kind] then
				kind = "normal"
			end
			posts[part] = { part = part, type = kind }
		end
	end
	for post in pairs(posts) do
		spawnDummy(post)
	end

	-- обслуживание: вернуть улетевших, поднять залежавшихся
	task.spawn(function()
		while true do
			task.wait(2)
			for post, model in pairs(alive) do
				local hum = model:FindFirstChildOfClass("Humanoid")
				if not hum or hum.Health <= 0 then
					alive[post] = nil
					if not pending[post] then
						pending[post] = true
						task.delay(Config.Dummy.respawnTime, function()
							pending[post] = nil
							spawnDummy(post)
						end)
					end
				else
					local root = model:FindFirstChild("HumanoidRootPart")
					if root then
						local dist = (Vector3.new(root.Position.X, 0, root.Position.Z)
							- Vector3.new(post.part.Position.X, 0, post.part.Position.Z)).Magnitude
						if dist > Config.Dummy.maxFlingDistance or root.Position.Y < -30 then
							-- вернуть на пост
							model:PivotTo(CFrame.new(post.part.Position + Vector3.new(0, 3, 0)))
							root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
							root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
						end
					end
					-- залежался (сбит с ног) — встаём принудительно
					if hum:GetState() == Enum.HumanoidStateType.Physics
						or hum:GetState() == Enum.HumanoidStateType.FallingDown then
						local since = downSince[model]
						if not since then
							downSince[model] = os.clock()
						elseif os.clock() - since > Config.Dummy.maxDownTime then
							downSince[model] = nil
							spawnDummy(post)
							model:Destroy()
						end
					else
						downSince[model] = nil
					end
				end
			end
		end
	end)
end

return Dummies
