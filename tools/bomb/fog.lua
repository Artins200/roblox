-- ===================== ТУМАН ВОЙНЫ (клиент) =====================
-- Карта скрыта туманом, видна только СВОЯ база/спавн (круг ясности).
-- После покупки спутника открываются и базы врагов.
-- Камера в режиме прицеливания/полёта тоже раскрывает область вокруг себя.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local TILE = 64
local FOG_COLOR = Color3.fromRGB(11, 13, 20)
local BASE_PAD_EXTRA = 26
local CHAR_RADIUS = 20
local FOCUS_RADIUS = 80

local gui = Instance.new("ScreenGui")
gui.Name = "FogGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1 -- мир(0) < туман(1) < HUD(10) < окна(50+)
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local tiles = {}
local gridCols, gridRows = 0, 0
local viewport = Vector2.new(0, 0)

local function rebuildGrid()
	for _, t in ipairs(tiles) do
		t:Destroy()
	end
	tiles = {}

	viewport = camera.ViewportSize
	gridCols = math.max(1, math.ceil(viewport.X / TILE))
	gridRows = math.max(1, math.ceil(viewport.Y / TILE))

	for r = 0, gridRows - 1 do
		for c = 0, gridCols - 1 do
			local f = Instance.new("Frame")
			f.Name = "Fog"
			f.AnchorPoint = Vector2.new(0, 0)
			f.Size = UDim2.new(0, TILE + 1, 0, TILE + 1)
			f.Position = UDim2.new(0, c * TILE, 0, r * TILE)
			f.BackgroundColor3 = FOG_COLOR
			f.BackgroundTransparency = 0
			f.BorderSizePixel = 0
			f.Active = false
			f.ZIndex = 1
			f.Parent = gui
			tiles[#tiles + 1] = f
		end
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { player.Character }

local function addPadCircle(list, pad)
	if not pad then return end
	local pos = pad.Position
	local radius = pad.Size.Magnitude / 2 + BASE_PAD_EXTRA
	local sp, vis = camera:WorldToViewportPoint(pos)
	if not vis then return end
	local right = camera.CFrame.RightVector
	local se = camera:WorldToViewportPoint(pos + right * radius)
	local rpx = (Vector2.new(se.X, se.Y) - Vector2.new(sp.X, sp.Y)).Magnitude
	if rpx < 40 then rpx = 40 end
	list[#list + 1] = { s = Vector2.new(sp.X, sp.Y), r = rpx }
end

local function addPointCircle(list, pos, worldRadius)
	local sp, vis = camera:WorldToViewportPoint(pos)
	if not vis then return end
	local right = camera.CFrame.RightVector
	local se = camera:WorldToViewportPoint(pos + right * worldRadius)
	local rpx = (Vector2.new(se.X, se.Y) - Vector2.new(sp.X, sp.Y)).Magnitude
	if rpx < 30 then rpx = 30 end
	list[#list + 1] = { s = Vector2.new(sp.X, sp.Y), r = rpx }
end

local function collectVisibleCircles()
	local list = {}

	-- 1) своя площадка/база
	local si = player:GetAttribute("SpawnIndex")
	if si then
		addPadCircle(list, Workspace:FindFirstChild("SpawnLocation" .. si))
	end

	-- 2) свой персонаж
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		addPointCircle(list, hrp.Position, CHAR_RADIUS)
	end

	-- 3) со спутником — видны и базы врагов
	if player:GetAttribute("HasSatellite") then
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local esi = other:GetAttribute("SpawnIndex")
				if esi then
					addPadCircle(list, Workspace:FindFirstChild("SpawnLocation" .. esi))
				end
			end
		end
		local bots = ReplicatedStorage:FindFirstChild("RocketBots")
		if bots then
			for _, folder in ipairs(bots:GetChildren()) do
				local bi = folder:GetAttribute("SpawnIndex")
				if bi then
					addPadCircle(list, Workspace:FindFirstChild("SpawnLocation" .. bi))
				end
			end
		end
	end

	-- 4) режим прицеливания/полёта: круг ясности там, куда смотрит камера
	if player:GetAttribute("CamReveal") then
		local vp = camera.ViewportSize
		local ray = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
		rayParams.FilterDescendantsInstances = { player.Character }
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 3000, rayParams)
		if hit then
			addPointCircle(list, hit.Position, FOCUS_RADIUS)
		end
	end

	return list
end

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	if camera ~= Workspace.CurrentCamera then
		camera = Workspace.CurrentCamera
		rebuildGrid()
	end
	if math.abs(camera.ViewportSize.X - viewport.X) > 2 or math.abs(camera.ViewportSize.Y - viewport.Y) > 2 then
		rebuildGrid()
	end

	-- обновляем максимум раз в ~0.08с (для плавности достаточно 12+ fps)
	acc = acc + dt
	if acc < 0.08 then return end
	acc = 0

	local circles = collectVisibleCircles()

	for _, t in ipairs(tiles) do
		local cx = t.Position.X.Offset + TILE / 2
		local cy = t.Position.Y.Offset + TILE / 2
		local trans = 0
		for i = 1, #circles do
			local v = circles[i]
			local dx = cx - v.s.X
			local dy = cy - v.s.Y
			local d = math.sqrt(dx * dx + dy * dy)
			if d <= v.r * 0.82 then
				trans = 1
				break
			elseif d <= v.r then
				if trans < 0.45 then trans = 0.45 end
			end
		end
		if t.BackgroundTransparency ~= trans then
			t.BackgroundTransparency = trans
		end
	end
end)

rebuildGrid()

-- тонкая рамка-подсказка в углу (не мешает игре)
local hint = Instance.new("TextLabel")
hint.Name = "FogHint"
hint.BackgroundTransparency = 1
hint.AnchorPoint = Vector2.new(0, 1)
hint.Position = UDim2.new(0, 12, 1, -8)
hint.Size = UDim2.new(0, 460, 0, 20)
hint.Font = Enum.Font.Gotham
hint.TextSize = 13
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextColor3 = Color3.fromRGB(150, 160, 180)
hint.TextStrokeTransparency = 0.6
hint.Text = "🌫 Туман войны: видна только своя база. Со спутником — и базы врагов"
hint.ZIndex = 5
hint.Parent = gui

print("[FogOfWar] ✅ Туман войны активен")
