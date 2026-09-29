--[[
	CombatClient — точка входа клиента.

	Всё запускается по частям и каждая часть завёрнута в pcall: если что-то
	одно не завелось, остальное продолжает работать, а в Output появляется
	строка с пометкой [EPIC COMBAT], по которой видно, что именно упало.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local RS = game:GetService("ReplicatedStorage")

local Config = require(RS:WaitForChild("CombatConfig"))
local Animator = require(RS:WaitForChild("CombatAnimator"))
local Hud = require(RS:WaitForChild("CombatHud"))
local Camera = require(RS:WaitForChild("CombatCamera"))
local Input = require(RS:WaitForChild("CombatInput"))

local function boot(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("[EPIC COMBAT] " .. name .. ": ок")
	else
		warn("[EPIC COMBAT] " .. name .. ": " .. tostring(err))
	end
	return ok
end

-- ---------------------------------------------------------------------------
-- Запуск подсистем
-- ---------------------------------------------------------------------------
boot("интерфейс", function()
	local ok = Hud.init()
	if not ok then
		error("не удалось создать ScreenGui")
	end
end)

boot("камера", function()
	Camera.bind(70)
end)

boot("управление", function()
	Input.start()
end)

boot("аниматор", function()
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(Animator.update, dt)
		if not ok then
			warn("[EPIC COMBAT] аниматор: " .. tostring(err))
		end
	end)
end)

boot("CoreGui", function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- ---------------------------------------------------------------------------
-- Регистрация всех бойцов (игроки и белые манекены)
-- ---------------------------------------------------------------------------
local function tryRegister(model)
	if not model or not model.Parent then
		return false
	end
	if not model:FindFirstChildOfClass("Humanoid") then
		return false
	end
	if not model:FindFirstChild("HumanoidRootPart") then
		return false
	end
	return Animator.get(model) ~= nil
end

boot("регистрация бойцов", function()
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") then
			tryRegister(obj)
		end
	end

	workspace.DescendantAdded:Connect(function(obj)
		if obj:IsA("Humanoid") then
			local model = obj.Parent
			if model and model:IsA("Model") then
				task.defer(function()
					tryRegister(model)
				end)
			end
		end
	end)

	local function watchPlayer(pl)
		if pl.Character then
			task.delay(0.3, function()
				tryRegister(pl.Character)
			end)
		end
		pl.CharacterAdded:Connect(function(c)
			task.delay(0.3, function()
				tryRegister(c)
			end)
		end)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		watchPlayer(pl)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end)

-- ---------------------------------------------------------------------------
-- Оживление декораций арены (чисто локальная косметика)
-- ---------------------------------------------------------------------------
boot("декор", function()
	local spinners = {}
	local floaters = {}
	task.spawn(function()
		task.wait(2)
		local decor = workspace:FindFirstChild("Decor")
		if not decor then
			return
		end
		for _, part in ipairs(decor:GetChildren()) do
			if part:IsA("BasePart") then
				local n = string.sub(part.Name, 1, 4)
				if n == "Spin" then
					spinners[#spinners + 1] = { part = part, speed = part:GetAttribute("Speed") or 0.6 }
				elseif n == "Bob" then
					floaters[#floaters + 1] = { part = part, base = part.Position.Y, amp = 1.6, phase = math.random() * 6 }
				end
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		for i = 1, #spinners do
			local info = spinners[i]
			if info.part.Parent then
				info.part.CFrame = info.part.CFrame * CFrame.Angles(0, dt * info.speed, 0)
			end
		end
		for i = 1, #floaters do
			local info = floaters[i]
			if info.part.Parent then
				local p = info.part.Position
				info.part.Position = Vector3.new(p.X, info.base + math.sin(t * 1.4 + info.phase) * info.amp, p.Z)
			end
		end
	end)
end)

print("[EPIC COMBAT] загружено. F3 — диагностика, H — подсказки.")
