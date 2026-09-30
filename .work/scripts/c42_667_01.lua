local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

if pg:FindFirstChild("RoundGui") then
	warn("[RoundClient] ❌ ДУБЛЬ, отключён: " .. script:GetFullName())
	return
end

local remotes = ReplicatedStorage:WaitForChild("RocketRemotes", 30)
if not remotes then return end
local RoundResult = remotes:WaitForChild("RoundResult", 30)

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function corner(o, r)
	mk("UICorner", { CornerRadius = UDim.new(0, r or 12) }, o)
end

local function label(parent, props)
	local base = {
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = ""
	}
	for k, v in pairs(props) do base[k] = v end
	return mk("TextLabel", base, parent)
end

local gui = mk("ScreenGui", { Name = "RoundGui", ResetOnSpawn = false, DisplayOrder = 50 }, pg)

-- ===================== ТАЙМЕР =====================
local timerFrame = mk("Frame", {
	Size = UDim2.new(0, 250, 0, 60),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -20, 0, 20),
	BackgroundColor3 = Color3.fromRGB(20, 20, 25),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0
}, gui)
corner(timerFrame)

local timerStroke = mk("UIStroke", { Color = Color3.fromRGB(255, 200, 80), Thickness = 2 }, timerFrame)

local roundLabel = label(timerFrame, {
	Size = UDim2.new(1, -16, 0, 20),
	Position = UDim2.new(0, 8, 0, 4),
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(200, 200, 210),
	Text = "⏱ Раунд 1"
})

local timeLabel = label(timerFrame, {
	Size = UDim2.new(1, -16, 0, 32),
	Position = UDim2.new(0, 8, 0, 24),
	TextColor3 = Color3.fromRGB(255, 220, 100),
	Text = "30:00"
})

-- ===================== ТОП =====================
local lbFrame = mk("Frame", {
	Size = UDim2.new(0, 250, 0, 34),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -20, 0, 88),
	BackgroundColor3 = Color3.fromRGB(20, 20, 25),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0
}, gui)
corner(lbFrame)

label(lbFrame, {
	Size = UDim2.new(1, -16, 0, 26),
	Position = UDim2.new(0, 8, 0, 4),
	TextColor3 = Color3.fromRGB(255, 200, 80),
	Text = "🏆 ТОП РАУНДА",
	TextXAlignment = Enum.TextXAlignment.Left
})

local lbRows = {}
for i = 1, 5 do
	local row = label(lbFrame, {
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.new(0, 8, 0, 34 + (i - 1) * 24),
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false
	})
	lbRows[i] = row
end

local function renderLeaderboard()
	local raw = remotes:GetAttribute("Leaderboard")
	local ok, list = pcall(HttpService.JSONDecode, HttpService, raw or "[]")
	if not ok or type(list) ~= "table" then return end

	local n = 0
	for i, row in ipairs(lbRows) do
		local e = list[i]
		if e then
			n = i
			row.Visible = true
			local me = e.n == player.Name
			row.Text = ("%d. %s%s — %d$  ⚔%d"):format(i, e.b and "🤖 " or "", e.n, e.e, e.k)
			row.TextColor3 = me and Color3.fromRGB(120, 255, 140) or
				(e.b and Color3.fromRGB(255, 190, 120) or Color3.fromRGB(230, 230, 235))
		else
			row.Visible = false
		end
	end
	lbFrame.Size = UDim2.new(0, 250, 0, 38 + n * 24)
end

remotes:GetAttributeChangedSignal("Leaderboard"):Connect(renderLeaderboard)
renderLeaderboard()

-- Таймер
local pulse = 0
RunService.RenderStepped:Connect(function(dt)
	local endAt = remotes:GetAttribute("RoundEnd") or 0
	local left = math.max(0, endAt - Workspace:GetServerTimeNow())
	roundLabel.Text = ("⏱ Раунд %d"):format(remotes:GetAttribute("RoundNumber") or 1)
	timeLabel.Text = ("%d:%02d"):format(left // 60, math.floor(left % 60))

	if left <= 30 then
		pulse = pulse + dt * 6
		local k = (math.sin(pulse) + 1) / 2
		timeLabel.TextColor3 = Color3.fromRGB(255, 60 + 60 * k, 60)
		timerStroke.Color = Color3.fromRGB(255, 80, 80)
	else
		timeLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
		timerStroke.Color = Color3.fromRGB(255, 200, 80)
	end
end)

-- ===================== ЭКРАН РЕЗУЛЬТАТОВ =====================
local overlay = mk("Frame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	Visible = false,
	ZIndex = 10
}, gui)

local panel = mk("Frame", {
	Size = UDim2.new(0, 640, 0, 500),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(20, 20, 25),
	ZIndex = 11
}, overlay)
corner(panel, 18)
mk("UIStroke", { Color = Color3.fromRGB(255, 200, 80), Thickness = 3 }, panel)

local title = label(panel, {
	Size = UDim2.new(1, -40, 0, 50),
	Position = UDim2.new(0, 20, 0, 14),
	TextColor3 = Color3.fromRGB(255, 200, 80),
	Text = "🏁 РАУНД ЗАВЕРШЁН",
	ZIndex = 12
})

local winnerLabel = label(panel, {
	Size = UDim2.new(1, -40, 0, 44),
	Position = UDim2.new(0, 20, 0, 66),
	TextColor3 = Color3.fromRGB(255, 240, 150),
	ZIndex = 12
})

local winnerSub = label(panel, {
	Size = UDim2.new(1, -40, 0, 26),
	Position = UDim2.new(0, 20, 0, 110),
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(200, 200, 210),
	ZIndex = 12
})

local header = label(panel, {
	Size = UDim2.new(1, -40, 0, 26),
	Position = UDim2.new(0, 20, 0, 150),
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(150, 150, 165),
	Text = "#      Участник                                  Заработано        Уничтожено        Ракеты",
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 12
})

local rows = {}
for i = 1, 6 do
	local r = mk("Frame", {
		Size = UDim2.new(1, -40, 0, 34),
		Position = UDim2.new(0, 20, 0, 180 + (i - 1) * 38),
		BackgroundColor3 = Color3.fromRGB(35, 35, 45),
		Visible = false,
		ZIndex = 12
	}, panel)
	corner(r, 8)

	local cols = {}
	local layout = { { 0, 0.07 }, { 0.07, 0.45 }, { 0.52, 0.18 }, { 0.70, 0.16 }, { 0.86, 0.14 } }
	for c, l in ipairs(layout) do
		cols[c] = label(r, {
			Size = UDim2.new(l[2], -6, 1, -6),
			Position = UDim2.new(l[1], 6, 0, 3),
			Font = c == 2 and Enum.Font.GothamBold or Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 13
		})
	end
	rows[i] = { frame = r, cols = cols }
end

local footer = label(panel, {
	Size = UDim2.new(1, -40, 0, 30),
	Position = UDim2.new(0, 20, 1, -76),
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(180, 255, 200),
	Text = "Базы сброшены — новый раунд уже идёт!",
	ZIndex = 12
})

local closeBtn = mk("TextButton", {
	Size = UDim2.new(0, 200, 0, 36),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	BackgroundColor3 = Color3.fromRGB(60, 200, 90),
	Text = "ПРОДОЛЖИТЬ",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	BorderSizePixel = 0,
	ZIndex = 12
}, panel)
corner(closeBtn, 10)

local session = 0
closeBtn.MouseButton1Click:Connect(function()
	overlay.Visible = false
end)

RoundResult.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end
	session = session + 1
	local my = session

	local results, w = info.results or {}, info.winner
	title.Text = ("🏁 РАУНД %d ЗАВЕРШЁН"):format(info.number or 1)

	local myPlace
	for i, e in ipairs(results) do
		if e.name == player.Name then myPlace = i end
	end

	if w then
		if w.name == player.Name then
			winnerLabel.Text = "🎉 ВЫ ПОБЕДИЛИ!"
			winnerLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
		else
			winnerLabel.Text = ("🏆 Победитель: %s%s"):format(w.bot and "🤖 " or "", w.name)
			winnerLabel.TextColor3 = Color3.fromRGB(255, 240, 150)
		end
		winnerSub.Text = ("Заработано %d$   •   уничтожено ракет: %d   •   %s"):format(w.earned, w.kills, w.tier)
			.. (myPlace and ("   |   Ваше место: %d/%d"):format(myPlace, #results) or "")
	else
		winnerLabel.Text = "Никто не участвовал"
		winnerSub.Text = ""
	end

	for i, row in ipairs(rows) do
		local e = results[i]
		if e then
			row.frame.Visible = true
			local me = e.name == player.Name
			row.frame.BackgroundColor3 = me and Color3.fromRGB(35, 70, 45) or
				(i == 1 and Color3.fromRGB(70, 60, 30) or Color3.fromRGB(35, 35, 45))
			row.cols[1].Text = i == 1 and "🥇" or i == 2 and "🥈" or i == 3 and "🥉" or tostring(i)
			row.cols[2].Text = (e.bot and "🤖 " or "") .. e.name
			row.cols[2].TextColor3 = me and Color3.fromRGB(120, 255, 140) or Color3.new(1, 1, 1)
			row.cols[3].Text = e.earned .. "$"
			row.cols[4].Text = tostring(e.kills)
			row.cols[5].Text = tostring(e.rockets)
		else
			row.frame.Visible = false
		end
	end

	overlay.Visible = true
	local showFor = info.showFor or 12

	task.spawn(function()
		for left = showFor, 1, -1 do
			if session ~= my or not overlay.Visible then return end
			footer.Text = ("Базы сброшены — новый раунд уже идёт!   Окно закроется через %dс"):format(left)
			task.wait(1)
		end
		if session == my then overlay.Visible = false end
	end)
end)

print("[RoundClient] ✅ Готов")