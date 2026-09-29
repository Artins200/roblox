--[[
	CombatCamera — тряска камеры, удары (kick), вспышки и виньетки.

	Работает поверх стандартной камеры Roblox: каждый кадр добавляет небольшой
	доворот к CFrame камеры, меняет FOV и рисует экранные эффекты.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Camera = {}

local camera = workspace.CurrentCamera
local player = Players.LocalPlayer

local shakePower = 0
local shakeDecay = 6
local shakeSeed = math.random() * 100
local fovBase = 70
local fovOffset = 0
local fovOffsetTarget = 0
local punchOffset = 0
local roll = 0
local rollTarget = 0

local gui, flashFrame, vigTop, vigBottom, vigLeft, vigRight
local flashAlpha = 0
local flashTime = 0.35

local function build()
	if gui then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "CombatCameraFx"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")

	flashFrame = Instance.new("Frame")
	flashFrame.Name = "Flash"
	flashFrame.Size = UDim2.new(1, 0, 1, 0)
	flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.ZIndex = 2
	flashFrame.Parent = gui

	local function edge(name, size, pos, rotation)
		local f = Instance.new("Frame")
		f.Name = name
		f.Size = size
		f.Position = pos
		f.BackgroundColor3 = Color3.fromRGB(255, 30, 40)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.ZIndex = 1
		f.Parent = gui
		local g = Instance.new("UIGradient")
		g.Rotation = rotation
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		return f
	end
	vigTop = edge("VigTop", UDim2.new(1, 0, 0.28, 0), UDim2.new(0, 0, 0, 0), 90)
	vigBottom = edge("VigBottom", UDim2.new(1, 0, 0.28, 0), UDim2.new(0, 0, 0.72, 0), 270)
	vigLeft = edge("VigLeft", UDim2.new(0.2, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0)
	vigRight = edge("VigRight", UDim2.new(0.2, 0, 1, 0), UDim2.new(0.8, 0, 0, 0), 180)
end

function Camera.bind(baseFov)
	build()
	fovBase = baseFov or (camera and camera.FieldOfView) or 70
end

-- Короткий «пинок» камеры (при ударе/выстреле)
function Camera.punch(amount, fovKick, rollKick)
	punchOffset = math.max(punchOffset, amount or 1)
	fovOffsetTarget = math.max(fovOffsetTarget, (fovKick or 0) * (amount or 1))
	roll = roll + (rollKick or 0) * (amount or 1)
end

function Camera.shake(power, duration)
	shakePower = math.max(shakePower, power or 1)
	shakeDecay = 1 / math.max(duration or 0.35, 0.05)
end

function Camera.flash(color, alpha, time)
	build()
	flashFrame.BackgroundColor3 = color or Color3.new(1, 1, 1)
	flashAlpha = alpha or 0.5
	flashTime = time or 0.35
end

function Camera.setRoll(angle)
	rollTarget = angle or 0
end

function Camera.setFov(offset)
	fovOffsetTarget = offset or 0
end

function Camera.getRoll()
	return roll
end

local vignetteLevel = 0
function Camera.setVignette(level)
	vignetteLevel = math.clamp(level or 0, 0, 1)
	if not gui then
		build()
	end
	local t = 1 - vignetteLevel * 0.75
	vigTop.BackgroundTransparency = t
	vigBottom.BackgroundTransparency = t
	vigLeft.BackgroundTransparency = 1 - vignetteLevel * 0.6
	vigRight.BackgroundTransparency = 1 - vignetteLevel * 0.6
end

function Camera.update(dt)
	if not camera or not camera.Parent then
		camera = workspace.CurrentCamera
		if not camera then
			return
		end
	end
	local t = os.clock()

	-- затухание
	shakePower = math.max(0, shakePower - shakePower * shakeDecay * dt - 0.02 * dt)
	punchOffset = math.max(0, punchOffset - punchOffset * 9 * dt - 0.05 * dt)
	fovOffset = fovOffset + (fovOffsetTarget - fovOffset) * math.min(dt * 10, 1)
	fovOffsetTarget = fovOffsetTarget * (1 - math.min(dt * 2.5, 1))
	roll = roll + (rollTarget - roll) * math.min(dt * 4, 1)

	local sp = shakePower
	local nx = 0
	local ny = 0
	local nz = 0
	if sp > 0.001 then
		nx = (math.noise(t * 22 + shakeSeed, 0.5) * 2) * sp * 0.035
		ny = (math.noise(0.5, t * 20 + shakeSeed) * 2) * sp * 0.035
		nz = (math.noise(t * 17 + shakeSeed, 4.2) * 2) * sp * 0.05
	end
	local punch = punchOffset * 0.05

	camera.CFrame = camera.CFrame * CFrame.Angles(nx, ny, nz + roll) * CFrame.new(0, 0, punch)
	camera.FieldOfView = fovBase + fovOffset + punchOffset * 1.2

	if flashFrame then
		if flashAlpha > 0 then
			flashFrame.BackgroundTransparency = 1 - flashAlpha
			flashAlpha = math.max(0, flashAlpha - dt * (1 / math.max(flashTime, 0.05)) * 0.5)
		end
	end
end

return Camera
