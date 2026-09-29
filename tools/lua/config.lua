--[[
	CombatConfig — единый конфиг ЭПИЧНОЙ БОЕВОЙ СИСТЕМЫ.
	Модуль лежит в ReplicatedStorage и используется и сервером, и клиентом,
	поэтому все правки баланса делаются ЗДЕСЬ и сразу действуют везде.

	Ничего не требует, ни к чему не обращается — чистая таблица данных.
]]

local Config = {}

Config.VERSION = "EPIC COMBAT v1.0"

-- ---------------------------------------------------------------------------
-- ЦВЕТА / СТИЛЬ
-- ---------------------------------------------------------------------------
Config.Colors = {
	plasma     = Color3.fromRGB(80, 220, 255),   -- голубая плазма (лазеры)
	plasmaHot  = Color3.fromRGB(235, 255, 255),  -- разогретый центр плазмы
	violet     = Color3.fromRGB(150, 90, 255),   -- фиолет (рывок/аура)
	ult        = Color3.fromRGB(255, 70, 200),   -- ульта: маджента
	ultHot     = Color3.fromRGB(255, 225, 120),  -- ульта: золото
	hit        = Color3.fromRGB(255, 235, 150),  -- вспышка попадания
	block      = Color3.fromRGB(110, 200, 255),  -- блок
	danger     = Color3.fromRGB(255, 70, 60),    -- урон по игроку
	energy     = Color3.fromRGB(90, 230, 255),   -- полоса энергии
	hp         = Color3.fromRGB(255, 90, 70),    -- полоса жизни
}

-- ---------------------------------------------------------------------------
-- БАЗОВЫЕ ХАРАКТЕРИСТИКИ БОЙЦА
-- ---------------------------------------------------------------------------
Config.Fighter = {
	health            = 2500,
	walkSpeed         = 20,
	jumpPower         = 55,
	respawnTime       = 3,
	regenDelay        = 4.5,   -- сек без урона до начала регенерации
	regenPerSecond    = 0.04,  -- % от максимума в секунду
	koTime            = 2.5,   -- сколько лежим «в нокауте» перед респавном
}

-- ---------------------------------------------------------------------------
-- ЭНЕРГИЯ И УЛЬТА
-- ---------------------------------------------------------------------------
Config.Energy = {
	max        = 100,
	regen      = 24,    -- в секунду
	regenDelay = 0.6,   -- пауза после траты
}

Config.Ult = {
	max            = 100,
	passive        = 0.9,   -- пассивный заряд в секунду
	perDamageDealt = 0.055, -- заряд за 1 нанесённого урона
	perDamageTaken = 0.10,  -- заряд за 1 полученного урона
	auraThreshold  = 100,   -- с этого значения бойца обволакивает аура «ульта готова»
}

-- ---------------------------------------------------------------------------
-- СПОСОБНОСТИ: урон, откаты, стоимость, зарядка ульты
-- ---------------------------------------------------------------------------
Config.Abilities = {
	punch   = { name = "УДАРЫ",   key = "ЛКМ",    cooldown = 0.26, energy = 0,  ult = 0.4,
	            hint = "ЛКМ — комбо из 5 ударов (последний — вертушка)" },
	kick    = { name = "ПИНОК",   key = "E",      cooldown = 1.05, energy = 9,  ult = 1.2,
	            hint = "E — пинок с подбросом, идеален на подлёте" },
	heavy   = { name = "ТЯЖЁЛЫЙ", key = "ПКМ",    cooldown = 1.35, energy = 17, ult = 2.4,
	            hint = "ПКМ (зажать) — заряженный удар, держи до 1.2 сек" },
	dash    = { name = "РЫВОК",   key = "Q",      cooldown = 0.62, energy = 11, ult = 0,
	            hint = "Q — рывок сквозь врагов (кратковременная неуязвимость)" },
	laser   = { name = "ЛАЗЕР",   key = "F",      cooldown = 1.45, energy = 24, ult = 2.0,
	            hint = "F — плазменный луч в прицел" },
	barrage = { name = "ЗАЛП",    key = "C",      cooldown = 0.2,  energy = 34, ult = 2.5,
	            hint = "C (зажать) — шквал лазерных выстрелов" },
	fly     = { name = "ПОЛЁТ",   key = "V",      cooldown = 0.35, energy = 0,  ult = 0,
	            hint = "V — полёт · пробел вверх · Shift вниз · F+Shift — буст" },
	block   = { name = "БЛОК",    key = "R",      cooldown = 0.25, energy = 0,  ult = 0,
	            hint = "R (зажать) — блок: -75% урона и отталкивание" },
	ult     = { name = "ОБЛИТЕРАЦИЯ", key = "X",  cooldown = 1,    energy = 0,  ult = 0,
	            hint = "X — УЛЬТА при 100% заряда" },
	taunt   = { name = "ПОЗА СИЛЫ", key = "Z",    cooldown = 2.0,  energy = 0,  ult = 1.5,
	            hint = "Z — поза силы + всплеск ауры" },
	reset   = { name = "МАНЕКЕНЫ", key = "T",     cooldown = 3.0,  energy = 0,  ult = 0,
	            hint = "T — восстановить все манекены" },
}

-- Комбо-цепочка: 1..5 (сколько ударов, что за удар, урон)
Config.Combo = {
	window    = 0.95,   -- сколько ждём следующий удар, иначе комбо сбрасывается
	chainTime = 0.55,   -- с какого момента удара можно начинать следующий
	names     = { "punch1", "punch2", "punch3", "punch4", "punch5" },
	damage    = { 38, 44, 56, 92, 150 },
	reach     = { 8.0, 8.0, 9.0, 8.5, 11.0 },
	radius    = { 4.6, 4.6, 6.2, 5.4, 9.0 },  -- радиус «кулака»
	knock     = { 14, 15, 20, 34, 78 },
	ult       = { 0.9, 1.0, 1.3, 2.0, 3.2 },
}

Config.Damage = {
	kick        = 135,
	kickRadius  = 6.4,
	kickReach   = 9.0,
	kickKnock   = 42,
	kickLauncher = 58,   -- вертикальный подброс

	heavyMin    = 170,   -- минимальный заряд
	heavyMax    = 470,   -- максимальный заряд
	heavyRadius = 11.0,
	heavyReach  = 11.5,
	heavyKnock  = 105,

	laser       = 230,
	laserRadius = 3.4,
	laserRange  = 700,

	barrage     = 40,
	barrageRadius = 3.0,
	barrageRange = 400,

	tauntShock  = 40,
	tauntRadius = 16,

	ultBolt      = 300,
	ultBoltRadius = 13,
	ultBoltCount = 14,
	ultBoltRange = 140,
	ultBeam      = 1500,
	ultBeamRadius = 26,
	ultBeamRange = 700,
	ultFinalNova = 700,
	ultNovaRadius = 70,
}

Config.Crit = {
	chance   = 0.16,  -- шанс критического удара
	mult     = 2.0,
	killMult = 1.25,
}

-- ---------------------------------------------------------------------------
-- ДИСТАНЦИИ / ФИЗИКА
-- ---------------------------------------------------------------------------
Config.Move = {
	dashSpeed      = 78,
	dashTime       = 0.22,
	dashUp         = 8,
	doubleJumpUp   = 62,
	doubleJumpAhead = 26,
	flySpeed       = 108,
	flyBoost       = 190,
	flyAccel       = 9.5,
	flyDamp        = 6.5,
	flyUpSpeed     = 78,
	flyDownSpeed   = 72,
	flyBoostCost   = 16,   -- энергия в секунду на буст
	flyMinHeight   = -30,
	fallResetY     = -55,  -- ниже этой высоты — телепорт на арену
	afterimageStep = 0.075,-- как часто оставлять «призраков» в полёте
}

Config.Dummy = {
	types = {
		normal = { label = "МАНЕКЕН",         health = 1600,  scale = 1.0,  color = Color3.fromRGB(255, 255, 255) },
		heavy  = { label = "ТЯЖЁЛЫЙ МАНЕКЕН", health = 7000,  scale = 1.25, color = Color3.fromRGB(255, 255, 255) },
		titan  = { label = "ТИТАН-МАНЕКЕН",   health = 30000, scale = 1.75, color = Color3.fromRGB(255, 255, 255) },
	},
	respawnTime = 2.6,
	resetCooldown = 3.0,
	maxFlingDistance = 90,  -- улетел дальше — возвращаем на пост
	maxDownTime = 9,        -- столько лежит сбитый с ног манекен, потом встаём
}

-- ---------------------------------------------------------------------------
-- АНИМАЦИИ ИЗ ТУЛБОКСА (необязательно!)
--
-- Хочешь фирменные анимации вместо процедурных? Вставь ID из Toolbox
-- (правый клик по анимации → Copy Asset ID) в нужную строку ниже, например:
--     punch1 = "rbxassetid://1234567890",
-- Тогда система будет проигрывать твою анимацию через Animator, а процедурная
-- поза для этого действия отключится (см. Animator.lua).
-- ---------------------------------------------------------------------------
Config.ToolboxAnims = {
	punch1  = "",
	punch2  = "",
	punch3  = "",
	punch4  = "",
	punch5  = "",
	kick    = "",
	heavy   = "",
	laser   = "",
	barrage = "",
	dash    = "",
	block   = "",
	hit     = "",
	ko      = "",
	fly     = "",
	taunt   = "",
	ultCharge = "",
	ultBurst  = "",
	ultFire   = "",
}

-- ---------------------------------------------------------------------------
-- ЗВУКИ (встроенные Roblox — работают без загрузки ассетов)
-- ---------------------------------------------------------------------------
Config.Sfx = {
	whoosh    = { id = "rbxasset://sounds/swordslash.wav",        volume = 0.45, pitch = 1.25 },
	whooshBig = { id = "rbxasset://sounds/swordlunge.wav",        volume = 0.65, pitch = 0.95 },
	hit       = { id = "rbxasset://sounds/snap.wav",              volume = 0.85, pitch = 1.05 },
	hitHeavy  = { id = "rbxasset://sounds/bass.wav",              volume = 0.95, pitch = 1.35 },
	boom      = { id = "rbxasset://sounds/bass.wav",              volume = 1.0,  pitch = 0.7  },
	laser     = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.8, pitch = 1.5 },
	laserBig  = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 1.0, pitch = 0.65 },
	charge    = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.55, pitch = 0.8 },
	dash      = { id = "rbxasset://sounds/action_swim.mp3",       volume = 0.55, pitch = 1.5 },
	fly       = { id = "rbxasset://sounds/action_swim.mp3",       volume = 0.35, pitch = 1.2, loop = true },
	block     = { id = "rbxasset://sounds/switch.wav",            volume = 0.5,  pitch = 1.3 },
	ko        = { id = "rbxasset://sounds/uuhhh.mp3",             volume = 0.9,  pitch = 1.0 },
	land      = { id = "rbxasset://sounds/action_jump_land.mp3",  volume = 0.5,  pitch = 1.1 },
	ultCharge = { id = "rbxasset://sounds/switch3.wav",           volume = 0.8,  pitch = 0.75 },
	ultFire   = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 1.0, pitch = 0.5 },
	ready     = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 2.0 },
}

Config.Sfx.maxDistance = 420

-- ---------------------------------------------------------------------------
-- КЛАВИШИ (используются клиентом; каждая строка показывается в подсказках)
-- ---------------------------------------------------------------------------
Config.Help = {
	{ "ЛКМ",     "комбо ударов (5-й — вертушка)" },
	{ "ПКМ",     "зажать → заряженный удар" },
	{ "E",       "пинок с подбросом" },
	{ "Q",       "рывок" },
	{ "F",       "лазер" },
	{ "C",       "зажать → лазерный залп" },
	{ "X",       "УЛЬТА «ОБЛИТЕРАЦИЯ» (100%)" },
	{ "R",       "блок" },
	{ "V",       "полёт · пробел/Shift — вверх/вниз" },
	{ "Пробел×2","двойной прыжок" },
	{ "Shift",   "бег / буст в полёте" },
	{ "Z",       "поза силы" },
	{ "T",       "восстановить манекены" },
	{ "H",       "скрыть/показать эту панель" },
}

return Config
