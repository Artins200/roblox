--[[
	CombatActions — библиотека процедурных анимаций боёвки.

	Каждое действие — набор ключевых поз (t = 0..1) и событий (звук/трейл/вспышка
	в нужный момент). Аниматор берёт позу на текущем времени, смешивает с
	передвижением и накладывает на шарниры рига.

	Как сделаны «лютые» удары:
	  * замах (anticipation) — 10–20% времени, тело уходит В ПРОТИВОПОЛОЖНУЮ сторону;
	  * кадр удара — резкий (ease = "snap"), с полным разворотом корпуса и бёдер;
	  * проводка и оседание — рука/нога летит дальше цели и расслабляется;
	  * голова (neck) всегда смотрит на цель, ноги переставляются.

	Углы в ГРАДУСАХ (см. pose.lua):
	  p>0 — конечность/корпус вперёд, y — поворот/скрутка, r>0 — в сторону +X,
	  bend — сгиб локтя/колена (работает на R15, на R6 просто игнорируется).
]]

local Pose = require(script.Parent:WaitForChild("CombatPose"))

local Actions = {}
local ACT = {}
Actions.ACT = ACT

-- ---------------------------------------------------------------------------
-- Помощники
-- ---------------------------------------------------------------------------

-- Компенсация наклона корпуса для «стоячих» поз: углы ног указываются
-- относительно земли, а не относительно торса (иначе наклон утаскивает ноги).
local function plant(t)
	local body = t.body or {}
	local bp = body.p or 0
	local br = body.r or 0
	local ll = t.ll or {}
	local rl = t.rl or {}
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	out.ll = { p = (ll.p or 0) - bp, y = ll.y, r = (ll.r or 0) - br, bend = ll.bend }
	out.rl = { p = (rl.p or 0) - bp, y = rl.y, r = (rl.r or 0) - br, bend = rl.bend }
	return out
end

local function ease(k, kind)
	if kind == "linear" then
		return k
	elseif kind == "in" then
		return k * k * k
	elseif kind == "out" then
		return 1 - (1 - k) ^ 3
	elseif kind == "snap" then
		return 1 - (1 - k) ^ 6
	end
	return k * k * (3 - 2 * k)
end

local function keys(list)
	local out = {}
	for i = 1, #list do
		local entry = list[i]
		out[#out + 1] = { t = entry[1], pose = Pose.deg(plant(entry[2])), ease = entry[3] }
	end
	table.sort(out, function(a, b)
		return a.t < b.t
	end)
	return out
end

-- Ключи для воздушных/полётных поз (без компенсации — тело само рулит ногами)
local function airKeys(list)
	local out = {}
	for i = 1, #list do
		local entry = list[i]
		out[#out + 1] = { t = entry[1], pose = Pose.deg(entry[2]), ease = entry[3] }
	end
	table.sort(out, function(a, b)
		return a.t < b.t
	end)
	return out
end

local function act(name, dur, opts)
	opts = opts or {}
	opts.name = name
	opts.duration = dur
	if opts.loop == nil then
		opts.loop = false
	end
	if opts.chain == nil then
		opts.chain = dur * 0.5
	end
	if opts.weight == nil then
		opts.weight = 1
	end
	if opts.outFade == nil then
		opts.outFade = 0.13
	end
	if opts.keys then
		local fn = opts.air and airKeys or keys
		opts.pose = fn(opts.keys)
		opts.keys = nil
	end
	opts.fx = opts.fx or {}
	ACT[name] = opts
	return opts
end

-- ---------------------------------------------------------------------------
-- СТОЙКА
-- ---------------------------------------------------------------------------
Actions.STANCE = Pose.deg(plant({
	body = { p = 7, y = -5 },
	neck = { p = -5 },
	la = { p = 70, y = 14, r = -24, bend = 55 },
	ra = { p = 76, y = -14, r = 22, bend = 50 },
	ll = { p = -11, r = -7 },
	rl = { p = 12, r = 7 },
}))

-- ===========================================================================
-- 1. КОМБО: ДЖЕБ — прямой правой
-- ===========================================================================
act("punch1", 0.32, {
	chain = 0.15,
	keys = {
		{ 0.00, { body = { p = 6, y = -14 }, neck = { p = -4, y = 8 },
		         la = { p = 88, y = 18, r = -26, bend = 62 }, ra = { p = 62, y = -26, r = 26, bend = 70 },
		         ll = { p = -8, r = -8 }, rl = { p = 10, r = 8 } } },
		{ 0.10, { body = { p = 4, y = -26 }, neck = { p = -2, y = 13 },
		         la = { p = 92, y = 22, r = -24, bend = 70 }, ra = { p = 48, y = -38, r = 34, bend = 88 },
		         ll = { p = -12, r = -8 }, rl = { p = 16, r = 8 } }, "in" },
		{ 0.30, { body = { p = 14, y = 30 }, neck = { p = 2, y = -10 }, bob = -0.05,
		         la = { p = 52, y = -24, r = -18, bend = 58 }, ra = { p = 104, y = -2, r = 4, bend = 0 },
		         ll = { p = 14, r = -6 }, rl = { p = -16, r = 6 } }, "snap" },
		{ 0.46, { body = { p = 10, y = 18 }, neck = { p = -2, y = -4 },
		         la = { p = 66, y = 2, r = -24, bend = 62 }, ra = { p = 90, y = -8, r = 12, bend = 26 },
		         ll = { p = 4, r = -7 }, rl = { p = -4, r = 7 } } },
		{ 1.00, { body = { p = 6, y = -14 }, neck = { p = -4, y = 8 },
		         la = { p = 88, y = 18, r = -26, bend = 62 }, ra = { p = 62, y = -26, r = 26, bend = 70 },
		         ll = { p = -8, r = -8 }, rl = { p = 10, r = 8 } } },
	},
	fx = {
		{ t = 0.06, e = "whoosh" },
		{ t = 0.28, e = "fist", hand = "ra", shake = 0.45, hitStop = 0.045 },
	},
})

-- ===========================================================================
-- 2. КОМБО: КРОСС — левый хук через корпус
-- ===========================================================================
act("punch2", 0.34, {
	chain = 0.16,
	keys = {
		{ 0.00, { body = { p = 10, y = 16 }, neck = { p = -2, y = -6 },
		         la = { p = 62, y = 8, r = -22, bend = 60 }, ra = { p = 88, y = -12, r = 14, bend = 26 },
		         ll = { p = 8, r = -6 }, rl = { p = -10, r = 6 } } },
		{ 0.11, { body = { p = 6, y = 36 }, neck = { p = -2, y = -18 },
		         la = { p = 44, y = 40, r = -40, bend = 84 }, ra = { p = 96, y = -16, r = 12, bend = 45 },
		         ll = { p = -10, r = -8 }, rl = { p = 14, r = 8 } }, "in" },
		{ 0.32, { body = { p = 12, y = -40 }, neck = { p = 2, y = 16 }, bob = -0.08,
		         la = { p = 86, y = -30, r = 48, bend = 14 }, ra = { p = 56, y = 18, r = -14, bend = 72 },
		         ll = { p = 16, r = -4 }, rl = { p = -20, r = 10 } }, "snap" },
		{ 0.50, { body = { p = 8, y = -22 }, neck = { p = -4, y = 8 },
		         la = { p = 76, y = -10, r = 20, bend = 46 }, ra = { p = 68, y = -6, r = 6, bend = 66 },
		         ll = { p = 6, r = -6 }, rl = { p = -6, r = 8 } } },
		{ 1.00, { body = { p = 10, y = 16 }, neck = { p = -2, y = -6 },
		         la = { p = 62, y = 8, r = -22, bend = 60 }, ra = { p = 88, y = -12, r = 14, bend = 26 },
		         ll = { p = 8, r = -6 }, rl = { p = -10, r = 6 } } },
	},
	fx = {
		{ t = 0.06, e = "whoosh", pitch = 1.15 },
		{ t = 0.30, e = "fist", hand = "la", shake = 0.7, hitStop = 0.06 },
	},
})

-- ===========================================================================
-- 3. КОМБО: АППЕРКОТ — приседание и выстрел вверх
-- ===========================================================================
act("punch3", 0.42, {
	chain = 0.20,
	keys = {
		{ 0.00, { body = { p = 14, y = -18 }, neck = { p = 4, y = 6 }, bob = -0.12,
		         la = { p = 74, y = -8, r = 16, bend = 46 }, ra = { p = 72, y = -4, r = 8, bend = 62 },
		         ll = { p = 6, r = -6 }, rl = { p = -6, r = 8 } } },
		{ 0.14, { body = { p = 28, y = -30 }, neck = { p = 8, y = 10 }, bob = -0.36,
		         la = { p = 70, y = 22, r = -32, bend = 84 }, ra = { p = 18, y = -30, r = 30, bend = 96 },
		         ll = { p = 30, r = -10, bend = -42 }, rl = { p = -4, r = 10, bend = -46 } }, "in" },
		{ 0.34, { body = { p = -22, y = 16 }, neck = { p = 10, y = -8 }, bob = 0.26,
		         la = { p = 40, y = -22, r = -30, bend = 86 }, ra = { p = 166, y = -4, r = -4, bend = 6 },
		         ll = { p = -14, r = -6 }, rl = { p = 22, r = 6, bend = -18 } }, "snap" },
		{ 0.54, { body = { p = -10, y = 8 }, neck = { p = 4 }, bob = 0.04,
		         la = { p = 54, y = -6, r = -22, bend = 70 }, ra = { p = 128, y = -10, r = 10, bend = 26 },
		         ll = { p = -8, r = -7 }, rl = { p = 12, r = 7 } } },
		{ 1.00, { body = { p = 14, y = -18 }, neck = { p = 4, y = 6 }, bob = -0.12,
		         la = { p = 74, y = -8, r = 16, bend = 46 }, ra = { p = 72, y = -4, r = 8, bend = 62 },
		         ll = { p = 6, r = -6 }, rl = { p = -6, r = 8 } } },
	},
	fx = {
		{ t = 0.08, e = "whoosh", pitch = 0.9 },
		{ t = 0.32, e = "heavyFist", hand = "ra", shake = 1.1, hitStop = 0.09, flash = 0.22, sound = "hitHeavy" },
	},
})

-- ===========================================================================
-- 4. КОМБО: ВЕРТУШКА — разворот на 360° с ударом ногой
-- ===========================================================================
act("punch4", 0.66, {
	chain = 0.30,
	outFade = 0.07,
	keys = {
		{ 0.00, { body = { p = 10, y = 0 }, neck = { p = 0 },
		         la = { p = 70, y = 10, r = -40, bend = 40 }, ra = { p = 70, y = -10, r = 40, bend = 40 },
		         ll = { p = -8, r = -8 }, rl = { p = 8, r = 8 } } },
		{ 0.16, { body = { p = 4, y = 62 }, neck = { p = -6, y = -40 }, bob = -0.22,
		         la = { p = 46, y = -18, r = -18, bend = 96 }, ra = { p = 52, y = 34, r = 62, bend = 92 },
		         ll = { p = 24, r = -10, bend = -46 }, rl = { p = -8, r = 12, bend = -52 } }, "in" },
		{ 0.36, { body = { p = -6, y = -176 }, neck = { p = 6, y = 26 }, bob = 0.14,
		         la = { p = 58, y = -10, r = -96, bend = 18 }, ra = { p = 58, y = 10, r = 86, bend = 18 },
		         ll = { p = -12, r = -6, bend = -14 }, rl = { p = 150, y = 8, r = 34, bend = 0 } }, "snap" },
		{ 0.56, { body = { p = 6, y = -300 }, neck = { p = 0, y = 10 }, bob = 0.02,
		         la = { p = 62, y = 8, r = -74, bend = 24 }, ra = { p = 62, y = -8, r = 74, bend = 24 },
		         ll = { p = -10, r = -8 }, rl = { p = 92, y = 6, r = 30, bend = -30 } } },
		{ 0.74, { body = { p = 14, y = -360 }, neck = { p = -4 }, bob = -0.3,
		         la = { p = 60, y = 6, r = -46, bend = 40 }, ra = { p = 60, y = -6, r = 46, bend = 40 },
		         ll = { p = 6, r = -18, bend = -24 }, rl = { p = 6, r = 18, bend = -24 } }, "out" },
		{ 1.00, { body = { p = 10, y = -360 }, neck = { p = -2 }, bob = -0.06,
		         la = { p = 64, y = 10, r = -34, bend = 48 }, ra = { p = 64, y = -10, r = 34, bend = 48 },
		         ll = { p = -4, r = -12 }, rl = { p = 4, r = 12 } } },
	},
	fx = {
		{ t = 0.10, e = "whoosh", pitch = 0.85 },
		{ t = 0.22, e = "spin" },
		{ t = 0.34, e = "kickTrail", hand = "rl", shake = 1.4, hitStop = 0.1, sound = "hitHeavy", flash = 0.2 },
	},
})

-- ===========================================================================
-- ПИНОК (F) — замах с коленом и выстрел ногой вперёд-вверх
-- ===========================================================================
act("kick", 0.60, {
	chain = 0.32,
	keys = {
		{ 0.00, { body = { p = 8, y = -4 }, neck = { p = -4 },
		         la = { p = 70, r = -26, bend = 50 }, ra = { p = 74, r = 24, bend = 48 },
		         ll = { p = -10, r = -8 }, rl = { p = 10, r = 8 } } },
		{ 0.16, { body = { p = -8, y = 6 }, neck = { p = 6 }, bob = 0.06,
		         la = { p = 24, y = -14, r = -48, bend = 40 }, ra = { p = 30, y = 14, r = 48, bend = 40 },
		         ll = { p = -6, r = -8 }, rl = { p = 104, r = 6, bend = -98 } }, "in" },
		{ 0.38, { body = { p = -34, y = -4 }, neck = { p = 14 }, bob = 0.16,
		         la = { p = -40, y = -20, r = -52, bend = 22 }, ra = { p = -40, y = 20, r = 52, bend = 22 },
		         ll = { p = -14, r = -8 }, rl = { p = 150, r = 4, bend = 0 } }, "snap" },
		{ 0.56, { body = { p = -20, y = -2 }, neck = { p = 8 }, bob = 0.02,
		         la = { p = -6, y = -10, r = -44, bend = 40 }, ra = { p = -6, y = 10, r = 44, bend = 40 },
		         ll = { p = -12, r = -8 }, rl = { p = 128, r = 4, bend = -20 } } },
		{ 1.00, { body = { p = 8, y = -4 }, neck = { p = -4 },
		         la = { p = 70, r = -26, bend = 50 }, ra = { p = 74, r = 24, bend = 48 },
		         ll = { p = -10, r = -8 }, rl = { p = 10, r = 8 } } },
	},
	fx = {
		{ t = 0.10, e = "whoosh", pitch = 0.9 },
		{ t = 0.36, e = "kickTrail", hand = "rl", shake = 1.0, hitStop = 0.075, sound = "hitHeavy" },
	},
})

-- ===========================================================================
-- ЛАЗЕР (R): заряд ладоней и выстрел лучом
-- ===========================================================================
act("laserCharge", 0.34, {
	chain = 0.2,
	keys = {
		{ 0.00, { body = { p = 6 }, neck = { p = -2 },
		         la = { p = 72, y = 10, r = -26, bend = 55 }, ra = { p = 74, y = -10, r = 26, bend = 52 },
		         ll = { p = -10, r = -7 }, rl = { p = 10, r = 7 } } },
		{ 0.55, { body = { p = -10 }, neck = { p = 4 }, bob = 0.03,
		         la = { p = 70, y = 16, r = -32, bend = 62 }, ra = { p = 70, y = -16, r = 32, bend = 62 },
		         ll = { p = -12, r = -10 }, rl = { p = 6, r = 10 } } },
		{ 1.00, { body = { p = -6 }, neck = { p = 2 }, bob = -0.02,
		         la = { p = 86, y = 8, r = -38, bend = 28 }, ra = { p = 86, y = -8, r = 38, bend = 28 },
		         ll = { p = -14, r = -14 }, rl = { p = 2, r = 14 } } },
	},
	fx = {
		{ t = 0.05, e = "chargeStart" },
		{ t = 0.55, e = "chargeLoop", sound = "charge" },
	},
})

act("laser", 0.48, {
	chain = 0.22,
	keys = {
		{ 0.00, { body = { p = -6 }, neck = { p = 2 }, bob = -0.02,
		         la = { p = 86, y = 8, r = -38, bend = 28 }, ra = { p = 86, y = -8, r = 38, bend = 28 },
		         ll = { p = -14, r = -14 }, rl = { p = 2, r = 14 } } },
		{ 0.12, { body = { p = -16 }, neck = { p = 8 }, bob = -0.07,
		         la = { p = 94, y = 6, r = -18, bend = 0 }, ra = { p = 94, y = -6, r = 18, bend = 0 },
		         ll = { p = -20, r = -16 }, rl = { p = -20, r = 16 } }, "snap" },
		{ 0.46, { body = { p = -8 }, neck = { p = 2 }, bob = -0.02,
		         la = { p = 88, y = 6, r = -30, bend = 14 }, ra = { p = 88, y = -6, r = 30, bend = 14 },
		         ll = { p = -14, r = -12 }, rl = { p = -6, r = 12 } } },
		{ 1.00, { body = { p = 6 }, neck = { p = -2 },
		         la = { p = 72, y = 10, r = -26, bend = 55 }, ra = { p = 74, y = -10, r = 26, bend = 52 },
		         ll = { p = -10, r = -7 }, rl = { p = 10, r = 7 } } },
	},
	fx = {
		{ t = 0.12, e = "laserFire", shake = 1.2, hitStop = 0.05, sound = "laser" },
	},
})

-- ===========================================================================
-- УЛЬТА: зарядка → нова → луч → приземление
-- ===========================================================================
act("ultCharge", 1.05, {
	chain = 1.0,
	keys = {
		{ 0.00, { body = { p = 8 }, neck = { p = -4 },
		         la = { p = 70, r = -24, bend = 55 }, ra = { p = 76, r = 22, bend = 50 },
		         ll = { p = -10, r = -8 }, rl = { p = 10, r = 8 } } },
		{ 0.34, { body = { p = 24 }, neck = { p = 10 }, bob = -0.40,
		         la = { p = 62, y = 40, r = 26, bend = 112 }, ra = { p = 62, y = -40, r = -26, bend = 112 },
		         ll = { p = 32, r = -10, bend = -46 }, rl = { p = 32, r = 10, bend = -46 } }, "out" },
		{ 0.72, { body = { p = -18, y = 6 }, neck = { p = 16 }, bob = 0.34,
		         la = { p = 84, y = 14, r = -66, bend = 20 }, ra = { p = 84, y = -14, r = 66, bend = 20 },
		         ll = { p = -8, r = -20, bend = -12 }, rl = { p = -8, r = 20, bend = -12 } }, "out" },
		{ 1.00, { body = { p = -26 }, neck = { p = 22 }, bob = 0.5,
		         la = { p = 70, y = 44, r = 30, bend = 122 }, ra = { p = 70, y = -44, r = -30, bend = 122 },
		         ll = { p = -14, r = -14, bend = -30 }, rl = { p = -14, r = 14, bend = -30 } }, "in" },
	},
	fx = {
		{ t = 0.05, e = "chargeStart" },
		{ t = 0.34, e = "auraBurst" },
		{ t = 0.66, e = "ultChargeLoop", shake = 0.6 },
		{ t = 0.88, e = "ultChargeLoop", shake = 0.9 },
	},
})

act("ultBurst", 0.52, {
	chain = 0.2,
	keys = {
		{ 0.00, { body = { p = -26 }, neck = { p = 22 }, bob = 0.5,
		         la = { p = 70, y = 44, r = 30, bend = 122 }, ra = { p = 70, y = -44, r = -30, bend = 122 },
		         ll = { p = -14, r = -14, bend = -30 }, rl = { p = -14, r = 14, bend = -30 } } },
		{ 0.16, { body = { p = -36 }, neck = { p = 26 }, bob = 0.44,
		         la = { p = -22, y = -10, r = -74, bend = 6 }, ra = { p = -22, y = 10, r = 74, bend = 6 },
		         ll = { p = -16, r = -28 }, rl = { p = -16, r = 28 } }, "snap" },
		{ 0.60, { body = { p = -18 }, neck = { p = 14 }, bob = 0.26,
		         la = { p = 20, y = -6, r = -60, bend = 24 }, ra = { p = 20, y = 6, r = 60, bend = 24 },
		         ll = { p = -12, r = -22 }, rl = { p = -12, r = 22 } } },
		{ 1.00, { body = { p = -14 }, neck = { p = 10 }, bob = 0.2,
		         la = { p = 40, y = 8, r = -50, bend = 40 }, ra = { p = 40, y = -8, r = 50, bend = 40 },
		         ll = { p = -10, r = -18 }, rl = { p = -10, r = 18 } } },
	},
	fx = {
		{ t = 0.16, e = "ultNova", shake = 2.2, flash = 0.75, sound = "ultFire" },
	},
})

act("ultBeam", 0.95, {
	loop = true,
	chain = 0.2,
	keys = {
		{ 0.00, { body = { p = -16 }, neck = { p = 12 }, bob = 0.18,
		         la = { p = 92, y = 12, r = -16, bend = 0 }, ra = { p = 92, y = -12, r = 16, bend = 0 },
		         ll = { p = -12, r = -18 }, rl = { p = -12, r = 18 } } },
		{ 0.55, { body = { p = -20 }, neck = { p = 14 }, bob = 0.24,
		         la = { p = 98, y = 14, r = -10, bend = 0 }, ra = { p = 98, y = -14, r = 10, bend = 0 },
		         ll = { p = -16, r = -20 }, rl = { p = -16, r = 20 } } },
		{ 1.00, { body = { p = -16 }, neck = { p = 12 }, bob = 0.18,
		         la = { p = 92, y = 12, r = -16, bend = 0 }, ra = { p = 92, y = -12, r = 16, bend = 0 },
		         ll = { p = -12, r = -18 }, rl = { p = -12, r = 18 } } },
	},
	fx = {
		{ t = 0.04, e = "ultBeamLoop", shake = 2.0 },
		{ t = 0.55, e = "beamPulse", shake = 1.4 },
	},
})

act("ultSlam", 0.66, {
	chain = 0.3,
	keys = {
		{ 0.00, { body = { p = -4 }, neck = { p = 6 }, bob = 0.1,
		         la = { p = 60, y = 10, r = -40, bend = 30 }, ra = { p = 60, y = -10, r = 40, bend = 30 },
		         ll = { p = 20, r = -12, bend = -50 }, rl = { p = 10, r = 12, bend = -40 } } },
		{ 0.18, { body = { p = 46 }, neck = { p = 20 }, bob = -0.78,
		         la = { p = 152, y = -10, r = -30, bend = 26 }, ra = { p = 152, y = 10, r = 30, bend = 26 },
		         ll = { p = 26, r = -22, bend = -64 }, rl = { p = 26, r = 22, bend = -64 } }, "snap" },
		{ 0.52, { body = { p = 26 }, neck = { p = 10 }, bob = -0.42,
		         la = { p = 120, y = -6, r = -36, bend = 40 }, ra = { p = 120, y = 6, r = 36, bend = 40 },
		         ll = { p = 20, r = -16, bend = -52 }, rl = { p = 20, r = 16, bend = -52 } } },
		{ 1.00, { body = { p = 8 }, neck = { p = -4 },
		         la = { p = 70, r = -24, bend = 55 }, ra = { p = 76, r = 22, bend = 50 },
		         ll = { p = -10, r = -8 }, rl = { p = 10, r = 8 } } },
	},
	fx = {
		{ t = 0.18, e = "landDust", shake = 2.4, flash = 0.3, sound = "hitHeavy" },
		{ t = 0.18, e = "scorch" },
	},
})

-- ===========================================================================
-- Прыжок, сальто, приземление
-- ===========================================================================
act("jump", 0.36, {
	chain = 0.1,
	keys = {
		{ 0.00, { body = { p = 6 }, neck = { p = -2 },
		         la = { p = 76, r = -26, bend = 50 }, ra = { p = 80, r = 24, bend = 48 },
		         ll = { p = -6, r = -8 }, rl = { p = 6, r = 8 } } },
		{ 0.35, { body = { p = -10 }, neck = { p = 10 }, bob = 0.05,
		         la = { p = 130, r = -30, bend = 40 }, ra = { p = 134, r = 28, bend = 40 },
		         ll = { p = 44, r = -10, bend = -56 }, rl = { p = 26, r = 10, bend = -40 } }, "out" },
		{ 1.00, { body = { p = -4 }, neck = { p = 4 },
		         la = { p = 112, r = -28, bend = 44 }, ra = { p = 116, r = 26, bend = 44 },
		         ll = { p = 20, r = -10, bend = -30 }, rl = { p = 10, r = 10, bend = -22 } } },
	},
	fx = {
		{ t = 0.05, e = "whoosh", pitch = 1.5, vol = 0.6 },
	},
})

act("flip", 0.64, {
	air = true,
	chain = 0.2,
	keys = {
		{ 0.00, { body = { p = 10 }, neck = { p = -6 },
		         la = { p = 90, r = -30, bend = 40 }, ra = { p = 94, r = 28, bend = 40 },
		         ll = { p = 18, r = -10, bend = -30 }, rl = { p = 14, r = 10, bend = -26 } } },
		{ 0.22, { body = { p = 96 }, neck = { p = -30 }, bob = 0.1,
		         la = { p = 148, r = -22, bend = 70 }, ra = { p = 152, r = 20, bend = 70 },
		         ll = { p = 88, r = -12, bend = -110 }, rl = { p = 80, r = 12, bend = -104 } }, "in" },
		{ 0.60, { body = { p = 300 }, neck = { p = -20 }, bob = 0.06,
		         la = { p = 120, r = -26, bend = 60 }, ra = { p = 124, r = 24, bend = 60 },
		         ll = { p = 70, r = -12, bend = -94 }, rl = { p = 64, r = 12, bend = -88 } } },
		{ 0.78, { body = { p = 360 }, neck = { p = -8 }, bob = -0.06,
		         la = { p = 100, r = -30, bend = 40 }, ra = { p = 104, r = 28, bend = 40 },
		         ll = { p = 30, r = -12, bend = -44 }, rl = { p = 24, r = 12, bend = -38 } }, "out" },
		{ 1.00, { body = { p = 356 }, neck = { p = -4 },
		         la = { p = 104, r = -28, bend = 40 }, ra = { p = 108, r = 26, bend = 40 },
		         ll = { p = 22, r = -10, bend = -32 }, rl = { p = 16, r = 10, bend = -26 } } },
	},
	fx = {
		{ t = 0.06, e = "whoosh", pitch = 1.35 },
		{ t = 0.3, e = "flipBurst", hand = "la" },
	},
})

act("land", 0.42, {
	chain = 0.12,
	keys = {
		{ 0.00, { body = { p = -6 }, neck = { p = 6 }, bob = 0.06,
		         la = { p = 120, r = -46, bend = 30 }, ra = { p = 124, r = 44, bend = 30 },
		         ll = { p = 26, r = -12, bend = -40 }, rl = { p = 20, r = 12, bend = -34 } } },
		{ 0.22, { body = { p = 30 }, neck = { p = -16 }, bob = -0.5,
		         la = { p = 34, r = -54, bend = 60 }, ra = { p = 38, r = 52, bend = 60 },
		         ll = { p = 34, r = -14, bend = -60 }, rl = { p = 34, r = 14, bend = -60 } }, "snap" },
		{ 0.60, { body = { p = 16 }, neck = { p = -8 }, bob = -0.2,
		         la = { p = 56, r = -34, bend = 54 }, ra = { p = 60, r = 32, bend = 54 },
		         ll = { p = 12, r = -10, bend = -28 }, rl = { p = 14, r = 10, bend = -28 } } },
		{ 1.00, { body = { p = 8 }, neck = { p = -4 },
		         la = { p = 70, r = -24, bend = 55 }, ra = { p = 76, r = 22, bend = 50 },
		         ll = { p = -10, r = -8 }, rl = { p = 10, r = 8 } } },
	},
	fx = {
		{ t = 0.2, e = "landDust", shake = 0.8, sound = "land" },
	},
})

-- ===========================================================================
-- Реакции на попадание (берётся от направления удара) и нокдаун
-- ===========================================================================
act("hitFront", 0.34, {
	weight = 1,
	keys = {
		{ 0.00, { body = { p = -16 }, neck = { p = 18 },
		         la = { p = -30, r = -40, bend = 60 }, ra = { p = -30, r = 40, bend = 60 },
		         ll = { p = -6, r = -8 }, rl = { p = 6, r = 8 } } },
		{ 0.35, { body = { p = -22 }, neck = { p = 24 }, bob = -0.16,
		         la = { p = -46, r = -56, bend = 70 }, ra = { p = -46, r = 56, bend = 70 },
		         ll = { p = -12, r = -12, bend = -20 }, rl = { p = -12, r = 12, bend = -20 } }, "out" },
		{ 1.00, { body = { p = -8 }, neck = { p = 6 },
		         la = { p = -6, r = -30, bend = 60 }, ra = { p = -6, r = 30, bend = 60 },
		         ll = { p = -4, r = -8 }, rl = { p = 4, r = 8 } } },
	},
	fx = {},
})

act("hitBack", 0.34, {
	keys = {
		{ 0.00, { body = { p = 24 }, neck = { p = -18 },
		         la = { p = 40, r = -50, bend = 70 }, ra = { p = 40, r = 50, bend = 70 },
		         ll = { p = 12, r = -8 }, rl = { p = 12, r = 8 } } },
		{ 0.35, { body = { p = 34 }, neck = { p = -24 }, bob = -0.14,
		         la = { p = 78, r = -58, bend = 80 }, ra = { p = 78, r = 58, bend = 80 },
		         ll = { p = 20, r = -12, bend = -26 }, rl = { p = 18, r = 12, bend = -24 } }, "out" },
		{ 1.00, { body = { p = 12 }, neck = { p = -6 },
		         la = { p = 30, r = -30, bend = 60 }, ra = { p = 30, r = 30, bend = 60 },
		         ll = { p = 4, r = -8 }, rl = { p = 6, r = 8 } } },
	},
	fx = {},
})

local function sideHit(sign)
	return {
		{ 0.00, { body = { p = -8, r = 16 * sign }, neck = { p = 10, y = -12 * sign },
		         la = { p = 10, r = -30 * sign, bend = 60 }, ra = { p = 20, r = -20 * sign, bend = 60 },
		         ll = { p = -4, r = -10 }, rl = { p = 4, r = 10 } } },
		{ 0.35, { body = { p = -12, r = 26 * sign }, neck = { p = 14, y = -20 * sign }, bob = -0.12,
		         la = { p = 4, r = -48 * sign, bend = 76 }, ra = { p = 14, r = -36 * sign, bend = 76 },
		         ll = { p = -8, r = -16, bend = -18 }, rl = { p = 8, r = 16, bend = -18 } }, "out" },
		{ 1.00, { body = { p = -4, r = 8 * sign }, neck = { p = 4, y = -6 * sign },
		         la = { p = -2, r = -26 * sign, bend = 60 }, ra = { p = 8, r = -16 * sign, bend = 60 },
		         ll = { p = -2, r = -8 }, rl = { p = -2, r = 8 } } },
	}
end

act("hitSideL", 0.34, { keys = sideHit(1), fx = {} })
act("hitSideR", 0.34, { keys = sideHit(-1), fx = {} })

act("ko", 0.9, {
	loop = true,
	keys = {
		{ 0.00, { body = { p = 30 }, neck = { p = -20 },
		         la = { p = 60, r = -50, bend = 40 }, ra = { p = 60, r = 50, bend = 40 },
		         ll = { p = 24, r = -14, bend = -40 }, rl = { p = 24, r = 14, bend = -40 } } },
		{ 0.5, { body = { p = 84, r = 8 }, neck = { p = -30 },
		         la = { p = 120, r = -40, bend = 30 }, ra = { p = 124, r = 40, bend = 30 },
		         ll = { p = 60, r = -16, bend = -70 }, rl = { p = 56, r = 16, bend = -70 } } },
		{ 1.00, { body = { p = 88, r = 10 }, neck = { p = -32 },
		         la = { p = 128, r = -38, bend = 26 }, ra = { p = 132, r = 38, bend = 26 },
		         ll = { p = 64, r = -16, bend = -74 }, rl = { p = 60, r = 16, bend = -74 } } },
	},
	fx = {},
})

-- ===========================================================================
-- Статические позы (полёт, падение, прыжок)
-- ===========================================================================
Actions.POSES = {
	--[[ ПОЛЁТ: тело ложится плашмя (p отрицательный = прогиб назад, голова
	     уходит вперёд), руки-крылья отведены назад, ноги вытянуты. ]]
	flyCruise = Pose.deg({
		body = { p = -84 }, neck = { p = 46 },
		la = { p = -24, y = -6, r = -17, bend = 6 }, ra = { p = -24, y = 6, r = 17, bend = 6 },
		ll = { p = 4, r = -5 }, rl = { p = 4, r = 5 },
	}),
	flyBoost = Pose.deg({
		body = { p = -91 }, neck = { p = 54 },
		la = { p = -38, r = -9, bend = 2 }, ra = { p = -38, r = 9, bend = 2 },
		ll = { p = 1, r = -2 }, rl = { p = 1, r = 2 },
	}),
	flyHover = Pose.deg({
		body = { p = -14 }, neck = { p = 10 },
		la = { p = 88, y = 8, r = -58, bend = 52 }, ra = { p = 88, y = -8, r = 58, bend = 52 },
		ll = { p = 16, r = -13, bend = -34 }, rl = { p = 12, r = 13, bend = -30 },
	}),
	flyDive = Pose.deg({
		body = { p = -97 }, neck = { p = 58 },
		la = { p = -52, r = -6, bend = 10 }, ra = { p = -52, r = 6, bend = 10 },
		ll = { p = -3, r = -3 }, rl = { p = -3, r = 3 },
	}),
	-- Позы прыжка/падения
	jump = Pose.deg(plant({
		body = { p = -8 }, neck = { p = 6 },
		la = { p = 138, r = -26, bend = 40 }, ra = { p = 142, r = 24, bend = 40 },
		ll = { p = 44, r = -8, bend = -56 }, rl = { p = 22, r = 8, bend = -36 },
	})),
	fall = Pose.deg(plant({
		body = { p = 5, r = 3 }, neck = { p = -4 },
		la = { p = 122, r = -58, bend = 44 }, ra = { p = 128, r = 54, bend = 44 },
		ll = { p = 20, r = -14, bend = -30 }, rl = { p = -16, r = 12, bend = -20 },
	})),
	land = Pose.deg(plant({
		body = { p = 26 }, neck = { p = -14 },
		la = { p = 34, r = -54, bend = 58 }, ra = { p = 38, r = 52, bend = 58 },
		ll = { p = 32, r = -12, bend = -58 }, rl = { p = 32, r = 12, bend = -58 }, bob = -0.44,
	})),
}

-- ===========================================================================
-- Параметры передвижения
-- ===========================================================================
Actions.LOCO = {
	walkAmp   = 34,
	walkArms  = 26,
	runAmp    = 54,
	runArms   = 42,
	runLean   = 14,
	sway      = 5,
	stepFreq  = 1.0,
	bobAmp    = 0.08,
}

-- ---------------------------------------------------------------------------
-- Выборка позы по прогрессу
-- ---------------------------------------------------------------------------
function Actions.sample(action, t)
	local keyset = action.pose
	if not keyset or #keyset == 0 then
		return Actions.STANCE
	end
	if action.loop then
		t = t - math.floor(t)
	end
	if t <= keyset[1].t then
		return keyset[1].pose
	end
	local last = keyset[#keyset]
	if t >= last.t then
		return last.pose
	end
	for i = 1, #keyset - 1 do
		local a, b = keyset[i], keyset[i + 1]
		if t >= a.t and t <= b.t then
			local span = b.t - a.t
			local k = span > 0 and (t - a.t) / span or 0
			return Pose.mix(a.pose, b.pose, ease(k, b.ease))
		end
	end
	return last.pose
end

function Actions.get(name)
	return ACT[name]
end

-- Сколько «процентов» действия должно пройти, чтобы можно было сцепить следующее
function Actions.chainTime(name)
	local a = ACT[name]
	return a and a.chain or 0.2
end

Actions.getEase = ease

return Actions
