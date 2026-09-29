--[[
	CombatHud — интерфейс бойца.

	Низ по центру: четыре компактные кнопки способностей (ЛКМ · F · R · X),
	над ними тонкие полосы ЖИЗНЬ / ЭНЕРГИЯ / УЛЬТА и строка со статистикой.
	Плюс: комбо, прицел и маркер попадания, баннеры, панель помощи (H),
	диагностика (F3).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local RS = script.Parent
local Config = require(RS:WaitForChild("CombatConfig"))

local Hud = {}

local player = Players.LocalPlayer
local C = Config.Colors
local FONT = Enum.Font.GothamBold
local FONT_BLACK = Enum.Font.GothamBlack

local gui
local barHp, txtHp
local barEn, txtEn
local barUlt, txtUlt, ultStroke
local statLine
local slotViews = {}
local comboBox, comboText
local crosshair, hitmarker
local banner, bannerSub, bannerT
local helpBox, diagLabel
local chargeBox, chargeFill, chargeText
local flyTag
local ultWasFull = false

-- ---------------------------------------------------------------------------
-- Мелкие помощники
-- ---------------------------------------------------------------------------
local function new(class, props, parent)
	local inst = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			inst[k] = v
		end
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
		Transparency = transparency or 0.3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
	return inst
end

local function frame(props, parent)
	return new("Frame", props, parent)
end

local function label(props, parent)
	local p = props or {}
	local l = new("TextLabel", p, parent)
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	return l
end

local function number(n)
	local s = tostring(math.floor((n or 0) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	out = out:gsub("^%s+", "")
	return out
end
Hud.number = number

local function fracFill(bar, frac)
	bar.Size = UDim2.new(math.clamp(frac or 0, 0, 1), 0, 1, 0)
end

-- ---------------------------------------------------------------------------
-- Построение интерфейса
-- ---------------------------------------------------------------------------
function Hud.init()
	if gui then
		return true
	end
	local pgui = player:WaitForChild("PlayerGui", 10)
	if not pgui then
		return false
	end
	gui = new("ScreenGui", {
		Name = "CombatHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3,
	}, pgui)

	-- ============================ ПОЛОСЫ ============================
	local stack = frame({
		Name = "Bars",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0, 340, 0, 168),
		BackgroundTransparency = 1,
	}, gui)

	local function bar(name, y, h, col1, col2, r)
		local holder = frame({
			Name = name,
			Position = UDim2.new(0, 0, 0, y),
			Size = UDim2.new(1, 0, 0, h),
			BackgroundColor3 = Color3.fromRGB(10, 12, 20),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, stack)
		corner(holder, r or h * 0.5)
		stroke(holder, Color3.fromRGB(0, 0, 0), 1.5, 0.4)
		local fill = frame({
			Name = "Fill",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = col1,
			BorderSizePixel = 0,
		}, holder)
		corner(fill, r or h * 0.5)
		new("UIGradient", { Color = ColorSequence.new(col1, col2), Rotation = 0 }, fill)
		return holder, fill
	end

	local hpHolder
	hpHolder, barHp = bar("Hp", 0, 20, Color3.fromRGB(180, 40, 40), Color3.fromRGB(255, 120, 80))
	txtHp = label({
		Text = "2500 / 2500", Font = FONT_BLACK, TextSize = 14,
		TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 6, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2,
	}, hpHolder)

	local enHolder
	enHolder, barEn = bar("En", 26, 8, C.energy, Color3.fromRGB(160, 255, 240), 4)

	ultStroke = nil
	local ultHolder
	ultHolder, barUlt = bar("Ult", 40, 13, C.ult, C.ultHot, 6)
	ultStroke = ultHolder:FindFirstChildOfClass("UIStroke")
	txtUlt = label({
		Text = "УЛЬТА 0%", Font = FONT_BLACK, TextSize = 11,
		TextColor3 = Color3.fromRGB(255, 240, 255), TextStrokeTransparency = 0.55,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 6, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2,
	}, ultHolder)

	statLine = label({
		Text = "", Font = FONT, TextSize = 12,
		TextColor3 = Color3.fromRGB(210, 220, 235), TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Position = UDim2.new(0, 0, 0, 58), Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, stack)

	flyTag = label({
		Text = "", Font = FONT_BLACK, TextSize = 12,
		TextColor3 = C.ice, TextStrokeTransparency = 0.6,
		Position = UDim2.new(0, 0, 0, 74), Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, stack)

	-- ==================== ЧЕТЫРЕ КНОПКИ СПОСОБНОСТЕЙ ====================
	local order = { "punch", "kick", "laser", "ult" }
	local size = 52
	local gap = 10
	local total = #order * size + (#order - 1) * gap

	local row = frame({
		Name = "Abilities",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.new(0, total, 0, size),
		BackgroundTransparency = 1,
	}, gui)

	for i, id in ipairs(order) do
		local def = Config.Abilities[id]
		local col = C.plasma
		if id == "kick" then
			col = Color3.fromRGB(255, 200, 90)
		elseif id == "laser" then
			col = C.plasma
		elseif id == "ult" then
			col = C.ult
		end
		local slot = frame({
			Name = "Slot_" .. id,
			Position = UDim2.new(0, (i - 1) * (size + gap), 0, 0),
			Size = UDim2.new(0, size, 0, size),
			BackgroundColor3 = Color3.fromRGB(12, 14, 22),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
		}, row)
		corner(slot, 10)
		local st = stroke(slot, col, 1.6, 0.3)

		local fill = frame({
			Name = "Charge",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundColor3 = col,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
		}, slot)
		corner(fill, 10)

		local keyLabel = label({
			Text = def.key, Font = FONT_BLACK, TextSize = 15, TextColor3 = col,
			TextStrokeTransparency = 0.75,
			Position = UDim2.new(0, 0, 0, 3), Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3,
		}, slot)
		local nameLabel = label({
			Text = def.name, Font = FONT, TextSize = 9,
			TextColor3 = Color3.fromRGB(225, 232, 245), TextWrapped = true,
			Position = UDim2.new(0, 0, 0, 21), Size = UDim2.new(1, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3,
		}, slot)
		local cdLabel = label({
			Text = "", Font = FONT_BLACK, TextSize = 16,
			TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeTransparency = 0.4,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4, Visible = false,
		}, slot)

		slotViews[id] = {
			slot = slot, fill = fill, stroke = st, color = col,
			label = keyLabel, name = nameLabel, cd = cdLabel,
		}
	end

	-- ============================ ПРИЦЕЛ ============================
	crosshair = frame({
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 22, 0, 22),
		BackgroundTransparency = 1,
	}, gui)
	for _, def in ipairs({
		{ UDim2.new(0, 2, 0, 6), UDim2.new(0.5, -1, 0, 0) },
		{ UDim2.new(0, 2, 0, 6), UDim2.new(0.5, -1, 1, -6) },
		{ UDim2.new(0, 6, 0, 2), UDim2.new(0, 0, 0.5, -1) },
		{ UDim2.new(0, 6, 0, 2), UDim2.new(1, -6, 0.5, -1) },
	}) do
		frame({
			Size = def[1], Position = def[2],
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.25, BorderSizePixel = 0,
		}, crosshair)
	end

	hitmarker = frame({
		Name = "Hitmarker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 40, 0, 40),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	for _, rot in ipairs({ 45, 135, 225, 315 }) do
		frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 3, 0, 16),
			Rotation = rot,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
		}, hitmarker)
	end

	-- ============================ КОМБО ============================
	comboBox = frame({
		Name = "Combo",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -46),
		Size = UDim2.new(0, 150, 0, 48),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	comboText = label({
		Text = "0", Font = FONT_BLACK, TextSize = 30,
		TextColor3 = C.ultHot, TextStrokeTransparency = 0.25,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center,
	}, comboBox)
	label({
		Text = "КОМБО", Font = FONT_BLACK, TextSize = 11,
		TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeTransparency = 0.5,
		Position = UDim2.new(0, 0, 0, 32), Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, comboBox)

	-- ============================ БАННЕР ============================
	banner = label({
		Text = "", Font = FONT_BLACK, TextSize = 40,
		TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeTransparency = 0.2,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.new(0.8, 0, 0, 46),
		TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1,
		Visible = false, ZIndex = 5,
	}, gui)
	bannerSub = label({
		Text = "", Font = FONT, TextSize = 16,
		TextColor3 = Color3.fromRGB(230, 238, 250), TextStrokeTransparency = 0.4,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 140),
		Size = UDim2.new(0.8, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1,
		Visible = false, ZIndex = 5,
	}, gui)

	-- ========================= ЗАРЯД (полоса) =========================
	chargeBox = frame({
		Name = "Charge",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 58),
		Size = UDim2.new(0, 260, 0, 20),
		BackgroundColor3 = Color3.fromRGB(10, 12, 20),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	corner(chargeBox, 10)
	stroke(chargeBox, C.ult, 1.6, 0.3)
	chargeFill = frame({
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = C.ult,
		BorderSizePixel = 0,
	}, chargeBox)
	corner(chargeFill, 10)
	new("UIGradient", { Color = ColorSequence.new(C.ult, C.ultHot), Rotation = 0 }, chargeFill)
	chargeText = label({
		Text = "", Font = FONT_BLACK, TextSize = 13,
		TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeTransparency = 0.4,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Size = UDim2.new(1, -10, 1, 0), Position = UDim2.new(0, 5, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2,
	}, chargeBox)

	-- ========================= ПАНЕЛЬ ПОМОЩИ =========================
	helpBox = frame({
		Name = "Help",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.new(0, 330, 0, 24 * #Config.Help + 44),
		BackgroundColor3 = Color3.fromRGB(10, 12, 20),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	corner(helpBox, 12)
	stroke(helpBox, C.plasma, 1.4, 0.4)
	label({
		Text = "УПРАВЛЕНИЕ", Font = FONT_BLACK, TextSize = 15, TextColor3 = C.plasmaHot,
		Position = UDim2.new(0, 12, 0, 10), Size = UDim2.new(1, -24, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, helpBox)
	for i, line in ipairs(Config.Help) do
		label({
			Text = "• " .. line, Font = FONT, TextSize = 12,
			TextColor3 = Color3.fromRGB(225, 232, 245), TextWrapped = true,
			Position = UDim2.new(0, 12, 0, 30 + (i - 1) * 24),
			Size = UDim2.new(1, -24, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		}, helpBox)
	end

	-- ========================= ДИАГНОСТИКА =========================
	diagLabel = label({
		Text = "", Font = FONT, TextSize = 11,
		TextColor3 = Color3.fromRGB(150, 255, 190), TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -8),
		Size = UDim2.new(0, 420, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	}, gui)

	return true
end

-- ---------------------------------------------------------------------------
-- Обновление
-- ---------------------------------------------------------------------------
local comboScale = 1
local hitUntil = 0
local hitScale = 1
local bannerUntil = 0
local bannerLen = 1

function Hud.setDiag(text)
	if diagLabel then
		diagLabel.Text = text or ""
	end
end

function Hud.toggleDiag()
	if diagLabel then
		diagLabel.Visible = not diagLabel.Visible
	end
end

function Hud.toggleHelp()
	if helpBox then
		helpBox.Visible = not helpBox.Visible
	end
end

function Hud.setHelpVisible(v)
	if helpBox then
		helpBox.Visible = v and true or false
	end
end

function Hud.announce(text, sub, color, time, scale)
	if not banner then
		return
	end
	banner.Text = text or ""
	banner.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	banner.TextSize = math.floor(40 * (scale or 1))
	banner.TextTransparency = 0
	banner.Visible = true
	bannerSub.Text = sub or ""
	bannerSub.TextTransparency = 0
	bannerSub.Visible = (sub ~= nil and sub ~= "")
	bannerUntil = os.clock() + (time or 2)
	bannerLen = time or 2
end

function Hud.hitmarker(crit, kill)
	if not hitmarker then
		return
	end
	hitmarker.Visible = true
	hitUntil = os.clock() + 0.2
	hitScale = crit and 1.5 or 1
	local col = kill and Color3.fromRGB(255, 120, 120) or (crit and C.ultHot or Color3.fromRGB(255, 255, 255))
	for _, line in ipairs(hitmarker:GetChildren()) do
		if line:IsA("Frame") then
			line.BackgroundColor3 = col
			line.BackgroundTransparency = 0
		end
	end
end

function Hud.combo(streak)
	if not comboBox then
		return
	end
	if streak and streak > 1 then
		comboBox.Visible = true
		comboText.Text = tostring(streak)
		comboScale = 1.6
	end
end

function Hud.setCharge(show, frac, text)
	if not chargeBox then
		return
	end
	chargeBox.Visible = show and true or false
	if show then
		fracFill(chargeFill, frac)
		chargeText.Text = text or ""
	end
end

function Hud.update(dt, state)
	if not gui then
		return
	end
	state = state or {}
	local now = os.clock()

	-- жизнь
	local hpf = 0
	if (state.maxHealth or 0) > 0 then
		hpf = math.clamp((state.health or 0) / state.maxHealth, 0, 1)
	end
	fracFill(barHp, hpf)
	txtHp.Text = number(state.health or 0) .. " / " .. number(state.maxHealth or 0)
	if hpf < 0.35 then
		txtHp.TextColor3 = Color3.fromRGB(255, 200, 200)
	else
		txtHp.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	-- энергия
	fracFill(barEn, (state.energy or 0) / math.max(state.maxEnergy or 100, 1))

	-- ульта
	local ultF = math.clamp((state.ult or 0) / math.max(state.maxUlt or 100, 1), 0, 1)
	fracFill(barUlt, ultF)
	txtUlt.Text = "УЛЬТА " .. math.floor(ultF * 100) .. "%"
	local full = ultF >= 0.999
	if ultStroke then
		ultStroke.Color = full and C.ultHot or C.ult
		ultStroke.Thickness = full and (2.4 + 0.6 * math.sin(now * 6)) or 1.5
	end
	if full and not ultWasFull then
		Hud.announce("УЛЬТА ГОТОВА", "нажми X", C.ultHot, 1.6, 0.9)
	end
	ultWasFull = full

	-- способности
	local cds = state.cooldowns or {}
	for id, view in pairs(slotViews) do
		local def = Config.Abilities[id]
		local c = cds[id]
		local left = 0
		if c then
			if c.left then
				left = c.left
			elseif c.endT then
				left = math.max(0, c.endT - now)
			end
		end
		local total = (c and c.total) or (def and def.cooldown) or 1
		local cdFrac = (total > 0) and math.clamp(left / total, 0, 1) or 0
		local charged = true
		if id == "ult" then
			cdFrac = 1 - ultF
			charged = full
		elseif def and def.energy > 0 then
			charged = (state.energy or 0) >= def.energy
		end
		if view.fill.Parent then
			view.fill.Size = UDim2.new(1, 0, cdFrac, 0)
		end
		view.slot.BackgroundTransparency = charged and 0.15 or 0.45
		view.stroke.Color = charged and view.color or Color3.fromRGB(90, 95, 110)
		if left > 0.1 and not (id == "ult") then
			view.cd.Visible = true
			view.cd.Text = string.format("%.1f", left)
			view.name.Visible = false
		else
			view.cd.Visible = false
			view.name.Visible = true
		end
	end

	-- статистика
	statLine.Text = "УРОН " .. number(state.totalDamage or 0)
		.. "   ·   DPS " .. number(state.dps or 0)
		.. "   ·   МАКС " .. number(state.maxHit or 0)

	-- полёт
	if state.flying then
		flyTag.Text = "ПОЛЁТ  " .. number(state.speed or 0) .. "  ст/с" .. ((state.boost or 0) > 0.3 and "  ·  БУСТ" or "")
	else
		flyTag.Text = ""
	end

	-- комбо
	if comboBox.Visible then
		comboScale = comboScale + (1 - comboScale) * math.min(dt * 9, 1)
		comboBox.Size = UDim2.new(0, 150 * comboScale, 0, 48 * comboScale)
		if (state.comboTimer or 0) <= 0 then
			comboBox.Visible = false
		end
	end

	-- маркер попадания
	if hitmarker.Visible then
		local age = now - (hitUntil - 0.2)
		if age > 0.2 then
			hitmarker.Visible = false
		else
			local k = 1 - age / 0.2
			hitmarker.Size = UDim2.new(0, 40 * hitScale * (1 + k * 0.4), 0, 40 * hitScale * (1 + k * 0.4))
			for _, line in ipairs(hitmarker:GetChildren()) do
				if line:IsA("Frame") then
					line.BackgroundTransparency = 1 - k
				end
			end
		end
	end

	-- баннер
	if banner.Visible then
		local left = bannerUntil - now
		if left <= 0 then
			banner.Visible = false
			bannerSub.Visible = false
		elseif left < 0.4 then
			local t = left / 0.4
			banner.TextTransparency = 1 - t
			bannerSub.TextTransparency = 1 - t
		end
	end
end

return Hud
