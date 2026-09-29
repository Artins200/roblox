--[[
	CombatHud — весь интерфейс бойца.

	* Полосы: ЗДОРОВЬЕ, ЭНЕРГИЯ, УЛЬТА «ОБЛИТЕРАЦИЯ»
	* Счётчик КОМБО + всплеск при попадании
	* Панель способностей с откатами и подсказками клавиш
	* Прицел + маркер попадания (обычный/крит)
	* Табло ТОП БОЙЦОВ и личная статистика (урон, DPS, макс. удар, КО)
	* Баннеры-объявления, виньетка при низком HP, индикатор полёта
	* Панель управления (скрывается по H)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local RS = script.Parent
local Config = require(RS:WaitForChild("CombatConfig"))

local Hud = {}

local player = Players.LocalPlayer

local gui
local barHp, barHpChip, txtHp
local barEn, barEnTxt
local barUlt, barUltTxt, ultStroke, ultFill
local comboBox, comboText, comboSub
local abilitySlots = {}
local crosshair, hitmarker, hitDot
local banner, bannerSub
local topBoard, topRows = {}, {}
local statDamage, statDps, statMax, statKo, statCombo
local flyBox, flyText
local helpBox
local chargeBar, chargeFill, chargeLabel
local ultReadyOverlay

local C = Config.Colors

local function slotColor(slot)
	return slot.color or Color3.new(1, 1, 1)
end

local FONT = Enum.Font.GothamBold
local FONT_BLACK = Enum.Font.GothamBlack

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(inst, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, inst)
	return inst
end

local function stroke(inst, color, thickness, transparency)
	new("UIStroke", {
		Color = color or Color3.fromRGB(0, 0, 0),
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.25,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
	return inst
end

local function frame(props, parent)
	return new("Frame", props, parent)
end

local function label(props, parent)
	local l = new("TextLabel", props, parent)
	l.BackgroundTransparency = props.BackgroundTransparency or 1
	l.BorderSizePixel = 0
	return l
end

local function number(n)
	local s = tostring(math.floor(n + 0.5))
	return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^%s+", ""))
end

Hud.number = number

-- ---------------------------------------------------------------------------
-- Построение интерфейса
-- ---------------------------------------------------------------------------
function Hud.init()
	if gui then
		return
	end
	local pgui = player:WaitForChild("PlayerGui")
	gui = new("ScreenGui", {
		Name = "CombatHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3,
	}, pgui)

	-- ======================= ПОЛОСЫ (низ, центр) =======================
	local bars = frame({
		Name = "Bars",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.new(0, 640, 0, 118),
		BackgroundTransparency = 1,
	}, gui)

	local function makeBar(y, height, color1, color2, textPrefix)
		local holder = frame({
			Name = "Bar" .. (textPrefix or ""),
			Position = UDim2.new(0, 0, 0, y),
			Size = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = Color3.fromRGB(12, 14, 22),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, bars)
		corner(holder, height / 2)
		stroke(holder, Color3.fromRGB(0, 0, 0), 2, 0.35)

		local chip = frame({
			Name = "Chip",
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
		}, holder)
		corner(chip, height / 2)

		local fill = frame({
			Name = "Fill",
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundColor3 = color1,
			BorderSizePixel = 0,
		}, holder)
		corner(fill, height / 2)
		local grad = new("UIGradient", { Color = ColorSequence.new(color1, color2), Rotation = 0 }, fill)

		local text = label({
			Text = "0 / 0",
			Font = FONT_BLACK,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextStrokeTransparency = 0.4,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			Size = UDim2.new(1, -20, 1, 0),
			Position = UDim2.new(0, 10, 0, 0),
			ZIndex = 2,
		}, holder)
		return holder, fill, text, chip
	end

	local hpBar
	hpBar, barHp, txtHp, barHpChip = makeBar(0, 34, Color3.fromRGB(190, 40, 40), Color3.fromRGB(255, 110, 70), "Hp")
	txtHp.TextSize = 20
	local enBar
	enBar, barEn, barEnTxt = makeBar(40, 18, C.energy, Color3.fromRGB(150, 255, 230), "En")
	barEnTxt.Text = ""
	enBar.BackgroundTransparency = 0.35

	-- ульта (отдельный стиль — маджента → золото)
	local ultHolder = frame({
		Name = "UltBar",
		Position = UDim2.new(0, 0, 0, 64),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = Color3.fromRGB(14, 10, 22),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, bars)
	corner(ultHolder, 13)
	ultStroke = stroke(ultHolder, C.ult, 2, 0.4)
	ultFill = frame({
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = C.ult,
		BorderSizePixel = 0,
	}, ultHolder)
	corner(ultFill, 13)
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.ult),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(200, 120, 255)),
			ColorSequenceKeypoint.new(1, C.ultHot),
		}),
		Rotation = 0,
	}, ultFill)
	barUlt = ultFill
	barUltTxt = label({
		Name = "UltText",
		Text = "УЛЬТА «ОБЛИТЕРАЦИЯ» — 0%",
		Font = FONT_BLACK,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0.35,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.new(0, 10, 0, 0),
		ZIndex = 2,
	}, ultHolder)


	-- ======================= СТАТИСТИКА (низ, справа от полос) =======================
	local stats = frame({
		Name = "Stats",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -22),
		Size = UDim2.new(0, 230, 0, 96),
		BackgroundColor3 = Color3.fromRGB(10, 12, 20),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, gui)
	corner(stats, 10)
	stroke(stats, Color3.fromRGB(80, 200, 255), 1.5, 0.6)
	label({
		Text = "СТАТИСТИКА",
		Font = FONT_BLACK,
		TextSize = 13,
		TextColor3 = C.energy,
		Position = UDim2.new(0, 10, 0, 4),
		Size = UDim2.new(1, -20, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, stats)
	local function statLine(y, name, color)
		label({
			Text = name,
			Font = FONT,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(180, 190, 210),
			Position = UDim2.new(0, 10, 0, y),
			Size = UDim2.new(0.6, 0, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, stats)
		return label({
			Text = "0",
			Font = FONT_BLACK,
			TextSize = 14,
			TextColor3 = color or Color3.new(1, 1, 1),
			Position = UDim2.new(0.35, 0, 0, y),
			Size = UDim2.new(0.6, -10, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Right,
		}, stats)
	end
	statDamage = statLine(22, "УРОН", Color3.fromRGB(255, 210, 120))
	statDps = statLine(40, "DPS", Color3.fromRGB(255, 140, 120))
	statMax = statLine(58, "МАКС. УДАР", Color3.fromRGB(255, 240, 180))
	statKo = statLine(76, "НОКАУТЫ", Color3.fromRGB(255, 120, 160))

	-- ======================= ТАБЛО (верх, слева) =======================
	topBoard = frame({
		Name = "TopBoard",
		Position = UDim2.new(0, 18, 0, 18),
		Size = UDim2.new(0, 250, 0, 26 + 5 * 18),
		BackgroundColor3 = Color3.fromRGB(10, 12, 20),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, gui)
	corner(topBoard, 10)
	stroke(topBoard, C.ultHot, 1.5, 0.55)
	label({
		Text = "ТОП БОЙЦОВ ПО УРОНУ",
		Font = FONT_BLACK,
		TextSize = 13,
		TextColor3 = C.ultHot,
		Position = UDim2.new(0, 10, 0, 5),
		Size = UDim2.new(1, -20, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, topBoard)
	for i = 1, 5 do
		local row = label({
			Text = (i .. ". —"),
			Font = FONT,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(230, 235, 245),
			Position = UDim2.new(0, 12, 0, 22 + (i - 1) * 18),
			Size = UDim2.new(1, -24, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, topBoard)
		topRows[i] = row
	end

	-- ======================= СПОСОБНОСТИ (низ, слева) =======================
	local abil = frame({
		Name = "Abilities",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -22),
		Size = UDim2.new(0, 288, 0, 150),
		BackgroundTransparency = 1,
	}, gui)
	local list = {
		{ id = "punch", key = "ЛКМ", name = "КОМБО", color = C.plasma },
		{ id = "heavy", key = "ПКМ", name = "ТЯЖЁЛЫЙ", color = Color3.fromRGB(255, 160, 80) },
		{ id = "kick", key = "E", name = "ПИНОК", color = Color3.fromRGB(255, 210, 90) },
		{ id = "dash", key = "Q", name = "РЫВОК", color = C.violet },
		{ id = "laser", key = "F", name = "ЛАЗЕР", color = C.plasma },
		{ id = "barrage", key = "C", name = "ЗАЛП", color = Color3.fromRGB(120, 255, 220) },
		{ id = "block", key = "R", name = "БЛОК", color = C.block },
		{ id = "ult", key = "X", name = "УЛЬТА", color = C.ult },
		{ id = "fly", key = "V", name = "ПОЛЁТ", color = Color3.fromRGB(140, 200, 255) },
		{ id = "taunt", key = "Z", name = "ТАУНТ", color = Color3.fromRGB(255, 150, 220) },
		{ id = "reset", key = "T", name = "МАНЕКЕНЫ", color = Color3.fromRGB(200, 200, 210) },
		{ id = "help", key = "H", name = "ПАНЕЛЬ", color = Color3.fromRGB(160, 170, 190) },
	}
	for i, info in ipairs(list) do
		local col = (i - 1) % 6
		local row = math.floor((i - 1) / 6)
		local slot = frame({
			Name = "Slot_" .. info.name,
			Position = UDim2.new(0, col * 48, 1, -row * 76 - 76),
			Size = UDim2.new(0, 44, 0, 72),
			BackgroundColor3 = Color3.fromRGB(12, 14, 22),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		}, abil)
		corner(slot, 7)
		stroke(slot, info.color, 1.5, 0.35)
		label({
			Text = info.key,
			Font = FONT_BLACK,
			TextSize = 14,
			TextColor3 = info.color,
			Position = UDim2.new(0, 0, 0, 3),
			Size = UDim2.new(1, 0, 0, 16),
		}, slot)
		local cdOverlay = frame({
			Name = "Cooldown",
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, slot)
		corner(cdOverlay, 7)
		label({
			Text = info.name,
			Font = FONT,
			TextSize = 9,
			TextColor3 = Color3.fromRGB(225, 230, 240),
			TextWrapped = true,
			Position = UDim2.new(0, 1, 0, 20),
			Size = UDim2.new(1, -2, 0, 50),
			Rotation = 0,
			ZIndex = 4,
		}, slot)
		abilitySlots[info.id] = { overlay = cdOverlay, stroke = slot:FindFirstChildOfClass("UIStroke"), color = info.color }
	end

	-- ======================= ПРИЦЕЛ + МАРКЕР ПОПАДАНИЯ =======================
	crosshair = frame({
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 26, 0, 26),
		BackgroundTransparency = 1,
	}, gui)
	for _, def in ipairs({
		{ UDim2.new(0, 2, 0, 7), UDim2.new(0.5, -1, 0, 0) },
		{ UDim2.new(0, 2, 0, 7), UDim2.new(0.5, -1, 1, -7) },
		{ UDim2.new(0, 7, 0, 2), UDim2.new(0, 0, 0.5, -1) },
		{ UDim2.new(0, 7, 0, 2), UDim2.new(1, -7, 0.5, -1) },
	}) do
		frame({
			Size = def[1],
			Position = def[2],
			BackgroundColor3 = Color3.fromRGB(230, 250, 255),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
		}, crosshair)
	end
	hitDot = frame({
		Size = UDim2.new(0, 3, 0, 3),
		Position = UDim2.new(0.5, -1.5, 0.5, -1.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.2,
	}, crosshair)

	hitmarker = frame({
		Name = "Hitmarker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 44, 0, 44),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	for _, rot in ipairs({ 45, 135, 225, 315 }) do
		local line = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 2.5, 0, 13),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Rotation = rot,
		}, hitmarker)
		local r = math.rad(rot)
		line.Position = UDim2.new(0.5, math.cos(r) * 14, 0.5, math.sin(r) * 14)
	end

	-- ======================= ЗАРЯД =======================
	local charge = frame({
		Name = "Charge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 44),
		Size = UDim2.new(0, 180, 0, 12),
		BackgroundColor3 = Color3.fromRGB(10, 12, 20),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
		ClipsDescendants = true,
	}, gui)
	corner(charge, 6)
	stroke(charge, Color3.fromRGB(255, 180, 90), 1.5, 0.3)
	chargeFill = frame({
		Size = UDim2.new(0, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 170, 60),
		BorderSizePixel = 0,
	}, charge)
	corner(chargeFill, 6)
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 90, 60)),
	}, chargeFill)
	chargeLabel = label({
		Text = "ЗАРЯД 0%",
		Font = FONT_BLACK,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 240, 220),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.new(0, 200, 0, 14),
	}, charge)
	chargeBar = charge

	-- ======================= КОМБО =======================
	comboBox = frame({
		Name = "Combo",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.new(0, 220, 0, 74),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	comboText = label({
		Text = "1",
		Font = FONT_BLACK,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 235, 150),
		TextStrokeTransparency = 0.3,
		Size = UDim2.new(1, 0, 0.72, 0),
	}, comboBox)
	comboSub = label({
		Text = "КОМБО",
		Font = FONT_BLACK,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 200, 120),
		Position = UDim2.new(0, 0, 0.72, 0),
		Size = UDim2.new(1, 0, 0.28, 0),
		TextStrokeTransparency = 0.5,
	}, comboBox)

	-- ======================= ПОЛЁТ =======================
	flyBox = frame({
		Name = "FlyInfo",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -126),
		Size = UDim2.new(0, 230, 0, 30),
		BackgroundColor3 = Color3.fromRGB(10, 12, 20),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	corner(flyBox, 8)
	stroke(flyBox, Config.Colors.plasma, 1.5, 0.4)
	flyText = label({
		Text = "ПОЛЁТ",
		Font = FONT_BLACK,
		TextSize = 14,
		TextColor3 = Config.Colors.plasma,
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, flyBox)

	-- ======================= БАННЕР =======================
	banner = label({
		Name = "Banner",
		Text = "",
		Font = FONT_BLACK,
		TextScaled = true,
		TextColor3 = C.ultHot,
		TextStrokeTransparency = 0.15,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.new(0, 700, 0, 46),
		TextTransparency = 1,
		Visible = false,
	}, gui)
	bannerSub = label({
		Name = "BannerSub",
		Text = "",
		Font = FONT,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0.4,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 144),
		Size = UDim2.new(0, 700, 0, 22),
		TextTransparency = 1,
		Visible = false,
	}, gui)

	-- ======================= ПАНЕЛЬ УПРАВЛЕНИЯ =======================
	helpBox = frame({
		Name = "Help",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.42, 0),
		Size = UDim2.new(0, 320, 0, 26 + #Config.Help * 19),
		BackgroundColor3 = Color3.fromRGB(10, 12, 20),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, gui)
	corner(helpBox, 10)
	stroke(helpBox, Color3.fromRGB(150, 160, 190), 1.5, 0.6)
	label({
		Text = "УПРАВЛЕНИЕ  (H — скрыть)",
		Font = FONT_BLACK,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(200, 210, 235),
		Position = UDim2.new(0, 10, 0, 5),
		Size = UDim2.new(1, -20, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, helpBox)
	for i, line in ipairs(Config.Help) do
		label({
			Text = line[1],
			Font = FONT_BLACK,
			TextSize = 12,
			TextColor3 = C.plasma,
			Position = UDim2.new(0, 10, 0, 20 + (i - 1) * 19),
			Size = UDim2.new(0, 82, 0, 17),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, helpBox)
		label({
			Text = line[2],
			Font = FONT,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(225, 230, 240),
			Position = UDim2.new(0, 94, 0, 20 + (i - 1) * 19),
			Size = UDim2.new(1, -104, 0, 17),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, helpBox)
	end

	-- оверлей «ульта готова»
	ultReadyOverlay = frame({
		Name = "UltReady",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local edge = frame({
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Config.Colors.ult,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
	}, ultReadyOverlay)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.35, 1),
			NumberSequenceKeypoint.new(0.65, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Rotation = 90,
	}, edge)
end

-- ---------------------------------------------------------------------------
-- Обновление
-- ---------------------------------------------------------------------------
local shownHp = 1
local chipHp = 1
local shownEn = 1
local shownUlt = 0
local comboScale = 1
local hitmarkerScale = 1
local hitTime = 0
local bannerUntil = 0
local helpVisible = true

function Hud.setHelpVisible(v)
	helpVisible = v
	if helpBox then
		helpBox.Visible = v
	end
end

function Hud.toggleHelp()
	Hud.setHelpVisible(not helpVisible)
	return helpVisible
end

function Hud.announce(text, sub, color, time, scale)
	if not gui then
		return
	end
	banner.Text = text
	banner.TextColor3 = color or C.ultHot
	bannerSub.Text = sub or ""
	banner.Visible = true
	bannerSub.Visible = true
	banner.TextTransparency = 0
	bannerSub.TextTransparency = 0
	banner.Size = UDim2.new(0, 700 * (scale or 1), 0, 46 * (scale or 1))
	bannerUntil = os.clock() + (time or 2.4)
	local a = TweenService:Create(banner, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 700 * (scale or 1), 0, 46 * (scale or 1)),
	})
	a:Play()
end

function Hud.hitmarker(crit, kill)
	if not gui then
		return
	end
	hitmarker.Visible = true
	hitTime = os.clock()
	hitmarkerScale = crit and 1.5 or 1
	if kill then
		hitmarkerScale = hitmarkerScale + 0.4
	end
	local col = crit and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(255, 255, 255)
	for _, line in ipairs(hitmarker:GetChildren()) do
		if line:IsA("Frame") then
			line.BackgroundColor3 = col
			line.BackgroundTransparency = 0
		end
	end
end

function Hud.combo(streak)
	if not gui then
		return
	end
	comboBox.Visible = true
	comboText.Text = tostring(streak) .. "×"
	comboText.TextColor3 = (streak >= 8 and C.ult) or (streak >= 5 and C.ultHot) or Color3.fromRGB(255, 235, 150)
	comboScale = 1.35
	comboBox.Size = UDim2.new(0, 220 * comboScale, 0, 74 * comboScale)
end

function Hud.setCharge(show, frac, label)
	if not gui then
		return
	end
	chargeBar.Visible = show and true or false
	if show then
		chargeFill.Size = UDim2.new(math.clamp(frac or 0, 0, 1), 0, 1, 0)
		chargeLabel.Text = label or ("ЗАРЯД " .. math.floor((frac or 0) * 100) .. "%")
	end
end

function Hud.update(dt, state)
	if not gui then
		return
	end
	state = state or {}
	local maxHp = state.maxHealth or 100
	local hp = math.clamp((state.health or 0) / math.max(maxHp, 1), 0, 1)
	local en = math.clamp((state.energy or 0) / (state.maxEnergy or 100), 0, 1)
	local ult = math.clamp((state.ult or 0) / (state.maxUlt or 100), 0, 1)

	-- полосы
	shownHp = shownHp + (hp - shownHp) * math.min(dt * 14, 1)
	chipHp = chipHp + (hp - chipHp) * math.min(dt * 2.5, 1)
	if chipHp < shownHp then
		chipHp = shownHp
	end
	shownEn = shownEn + (en - shownEn) * math.min(dt * 12, 1)
	shownUlt = shownUlt + (ult - shownUlt) * math.min(dt * 10, 1)

	barHp.Size = UDim2.new(shownHp, 0, 1, 0)
	barHpChip.Size = UDim2.new(chipHp, 0, 1, 0)
	txtHp.Text = number(state.health or 0) .. " / " .. number(maxHp)
	barEn.Size = UDim2.new(shownEn, 0, 1, 0)
	barEnTxt.Text = ""
	barUlt.Size = UDim2.new(shownUlt, 0, 1, 0)
	local full = ult >= 0.999
	barUltTxt.Text = full and "УЛЬТА ГОТОВА — ЖМИ  X !" or ("УЛЬТА «ОБЛИТЕРАЦИЯ» — " .. math.floor(ult * 100) .. "%")
	barUltTxt.TextColor3 = full and Color3.fromRGB(30, 10, 30) or Color3.fromRGB(255, 255, 255)
	ultStroke.Color = full and C.ultHot or C.ult
	ultStroke.Transparency = full and (0.1 + 0.25 * math.abs(math.sin(os.clock() * 6))) or 0.4
	ultReadyOverlay.Visible = full and not state.ultActive or false
	if ultReadyOverlay.Visible then
		ultReadyOverlay:FindFirstChildWhichIsA("Frame").BackgroundTransparency = 0.9 - 0.06 * math.abs(math.sin(os.clock() * 5))
	end

	-- откаты
	for name, data in pairs(state.cooldowns or {}) do
		local slot = abilitySlots[name]
		if slot then
			local frac = math.clamp(data.frac or 0, 0, 1)
			slot.overlay.Size = UDim2.new(1, 0, frac, 0)
			slot.overlay.BackgroundTransparency = 0.4
			slot.overlay.Visible = frac > 0.01
			slot.stroke.Color = (frac > 0.01) and Color3.fromRGB(90, 90, 110) or slot.color
		end
	end
	-- способность с недостатком энергии подсвечиваем тускло
	local ultSlot = abilitySlots["ult"]
	if ultSlot then
		ultSlot.overlay.Visible = not full
		ultSlot.overlay.Size = UDim2.new(1, 0, 1 - ult, 0)
		ultSlot.overlay.BackgroundTransparency = 0.55
		ultSlot.stroke.Color = full and C.ultHot or slotColor(ultSlot)
	end

	-- маркер попадания
	if hitmarker.Visible then
		local age = os.clock() - hitTime
		if age > 0.22 then
			hitmarker.Visible = false
		else
			local s = 1 + (1 - age / 0.22) * 0.5 * (hitmarkerScale or 1)
			hitmarker.Size = UDim2.new(0, 44 * s, 0, 44 * s)
			for _, line in ipairs(hitmarker:GetChildren()) do
				if line:IsA("Frame") then
					line.BackgroundTransparency = math.clamp(age / 0.22, 0, 1)
				end
			end
		end
	end

	-- комбо
	if comboBox.Visible then
		comboScale = comboScale + (1 - comboScale) * math.min(dt * 8, 1)
		comboBox.Size = UDim2.new(0, 220 * comboScale, 0, 74 * comboScale)
		if (state.comboTimer or 0) <= 0 then
			comboBox.Visible = false
		end
	end

	-- статистика
	statDamage.Text = number(state.totalDamage or 0)
	statDps.Text = number(state.dps or 0)
	statMax.Text = number(state.maxHit or 0)
	statKo.Text = number(state.kos or 0)

	-- табло
	local board = state.topBoard
	if board then
		for i, row in ipairs(topRows) do
			local entry = board[i]
			if entry then
				row.Text = i .. ". " .. entry.name .. "   " .. number(entry.damage)
				row.TextColor3 = (i == 1) and C.ultHot or Color3.fromRGB(230, 235, 245)
			else
				row.Text = i .. ". —"
			end
		end
	end

	-- полёт
	local flying = state.flying
	flyBox.Visible = flying and true or false
	if flying then
		flyText.Text = string.format("ПОЛЁТ  %d  стад/с%s", math.floor(state.speed or 0), state.boost and "  ⚡БУСТ" or "")
	end

	-- баннер
	if banner.Visible then
		local left = bannerUntil - os.clock()
		if left <= 0 then
			banner.Visible = false
			bannerSub.Visible = false
		elseif left < 0.5 then
			banner.TextTransparency = 1 - left / 0.5
			bannerSub.TextTransparency = 1 - left / 0.5
		end
	end
end

return Hud
