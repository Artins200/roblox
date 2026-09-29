--[[
	CombatClient — точка входа клиента.

	Запускает HUD, камеру, управление и аниматор, регистрирует всех персонажей
	(игроков и манекенов) и оживляет декорации арены.
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

-- интерфейс
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
end)

Hud.init()
Camera.bind(70)
Input.start()

-- ---------------------------------------------------------------------------
-- Регистрация персонажей для аниматора
-- ---------------------------------------------------------------------------
local function tryRegister(model)
	if model and model:IsA("Model") and model:FindFirstChildOfClass("Humanoid")
		and model:FindFirstChild("HumanoidRootPart") then
		Animator.get(model)
		return true
	end
	return false
end

local function scanAll()
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") then
			tryRegister(obj)
		end
	end
end

scanAll()

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

for _, pl in ipairs(Players:GetPlayers()) do
	if pl.Character then
		tryRegister(pl.Character)
		pl.CharacterAdded:Connect(function(c)
			task.wait(0.1)
			tryRegister(c)
		end)
	end
end

Players.PlayerAdded:Connect(function(pl)
	pl.CharacterAdded:Connect(function(c)
		task.wait(0.1)
		tryRegister(c)
	end)
end)

-- ---------------------------------------------------------------------------
-- Кадры
-- ---------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	Animator.update(dt)
end)

-- ---------------------------------------------------------------------------
-- Оживление декораций арены (клиентская косметика, ничего не ломает)
-- ---------------------------------------------------------------------------
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
			if string.sub(part.Name, 1, 4) == "Spin" then
				spinners[#spinners + 1] = { part = part, speed = part:GetAttribute("Speed") or 0.6 }
			elseif string.sub(part.Name, 1, 4) == "Bob" then
				floaters[#floaters + 1] = { part = part, base = part.Position.Y, amp = 1.6, phase = math.random() * 6 }
			end
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for _, info in ipairs(spinners) do
		if info.part.Parent then
			info.part.CFrame = info.part.CFrame * CFrame.Angles(0, dt * info.speed, 0)
		end
	end
	for _, info in ipairs(floaters) do
		if info.part.Parent then
			local p = info.part.Position
			info.part.Position = Vector3.new(p.X, info.base + math.sin(t * 1.4 + info.phase) * info.amp, p.Z)
		end
	end
end)
