local TweenService = game:GetService("TweenService")
local part = script.Parent


local tweenInfo = TweenInfo.new(
	0.15,
	Enum.EasingStyle.Sine, 
	Enum.EasingDirection.InOut,
	-1, 
	true, 
	0 
)

local goal = {
	Size = part.Size * 1.3
}


local tween = TweenService:Create(part, tweenInfo, goal)
tween:Play()

