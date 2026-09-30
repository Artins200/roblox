local pulser = script.Parent
local tweenService = game:GetService("TweenService")

local originalSize = pulser.Size

local PULSE_DURATION = 1
local CYCLE_INTERVAL = 3

-- The expansion will last the full duration.
-- The fade will start halfway through the expansion.
local FADE_DELAY = PULSE_DURATION / 2
local FADE_DURATION = PULSE_DURATION / 2

while true do
	local clone = pulser:Clone()
	script.Parent.Parent["Core Part"].CorePulse:Play()
	
	-- Destroy the script within the clone to prevent it from duplicating and stacking
	local scriptInClone = clone:FindFirstChild(script.Name)
	if scriptInClone then
		scriptInClone:Destroy()
	end

	clone.Parent = pulser.Parent
	clone.Size = originalSize
	clone.Anchored = true
	clone.CanCollide = false
	clone.Transparency = 0 -- Start fully opaque so the middle doesn't fade early

	-- Tween for size (lasts the full duration)
	local sizeTweenInfo = TweenInfo.new(
		PULSE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	local sizeGoal = {
		Size = Vector3.new(29.697, 29.697, 29.697)
	}
	local sizeTween = tweenService:Create(clone, sizeTweenInfo, sizeGoal)

	-- Tween for transparency (starts after a delay)
	local transparencyTweenInfo = TweenInfo.new(
		FADE_DURATION,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.Out
	)
	local transparencyGoal = {
		Transparency = 1
	}
	local transparencyTween = tweenService:Create(clone, transparencyTweenInfo, transparencyGoal)

	-- Play animations
	sizeTween:Play()
	
	task.wait(FADE_DELAY)
	transparencyTween:Play()

	-- Wait for the size animation to complete before cleaning up
	sizeTween.Completed:Wait()
	clone:Destroy()

	task.wait(CYCLE_INTERVAL)
end

