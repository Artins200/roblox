--[[
	CombatFloat — всплывающие цифры урона.

	Урон рисуется в мире (BillboardGui на невидимой детали) и улетает вверх,
	криты — крупнее и с золотой обводкой. Числа видит только атакующий.
]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Float = {}

local folder
local counter = 0
local MAX_NUMBERS = 60

local function home()
	if not folder or not folder.Parent then
		folder = workspace:FindFirstChild("CombatFloaters")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "CombatFloaters"
			folder.Parent = workspace
		end
	end
	return folder
end

local function fmt(n)
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^%s+", ""))
end

local function makeLabel(text, color, stroke, size)
	local host = Instance.new("Part")
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.Transparency = 1
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Name = "Float" .. counter
	host.Parent = home()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Float"
	billboard.Size = UDim2.new(6, 0, 2, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 320
	billboard.Parent = host

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.GothamBlack
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.35
	label.TextStrokeColor3 = stroke or Color3.fromRGB(0, 0, 0)
	label.RichText = true
	label.Parent = billboard
	if size then
		local scale = Instance.new("UIScale")
		scale.Scale = size
		scale.Parent = label
	end
	return host, label
end

-- Показать урон в мире
function Float.show(position, amount, opts)
	opts = opts or {}
	if #home():GetChildren() > MAX_NUMBERS then
		return
	end
	counter = counter + 1
	local crit = opts.crit
	local color = opts.color or (crit and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(255, 255, 255))
	local text = opts.text or ("<b>" .. fmt(amount) .. "</b>")
	if crit then
		text = text .. " <font size='18'>КРИТ!</font>"
	end
	local scale = crit and 1.55 or 1
	if opts.kill then
		scale = scale + 0.35
	end
	local offset = Vector3.new((math.random() - 0.5) * 4, math.random() * 2, (math.random() - 0.5) * 4)
	local host, label = makeLabel(text, color, Color3.fromRGB(8, 8, 16), scale)
	host.CFrame = CFrame.new(position + offset)
	Debris:AddItem(host, 1.5)

	local rise = (opts.kill and 9) or (crit and 7) or 5.5
	local inf = TweenInfo.new(0.95, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(host, inf, { CFrame = CFrame.new(position + offset + Vector3.new(0, rise, 0)) }):Play()
	TweenService:Create(label, TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

-- Короткая надпись («БЛОК!», «ПРОМАХ», «+ЭНЕРГИЯ»)
function Float.text(position, text, color)
	Float.show(position, 0, { text = text, color = color })
end

Float.fmt = fmt

return Float
