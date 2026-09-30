local Config = {}

Config.PAYBACK_SECONDS = 120   -- окупаемость покупки
Config.MAX_ROCKETS = 9
Config.REPAIR_TIME = 45 -- сек до авторемонта сломанной ракеты
Config.COOLDOWN_TIME = 45
Config.PICKUP_DISTANCE = 6

-- income $/с за КАЖДУЮ ракету | speed множитель | damage макс. урон | radius | hp
-- resist шанс поглотить 75% урона | armor попаданий ПВО для сбития | evasion шанс увернуться от ракеты ПВО
Config.Tiers = {
	{ name = "RocketShip",     display = "Rocket Ship",      income = 5,   speed = 1.00, damage = 25,  radius = 25, hp = 100, resist = 0.00, armor = 1, evasion = 0.00 },
	{ name = "RocketShip1",    display = "Rocket Ship Mk.I", income = 12,  speed = 1.15, damage = 35,  radius = 30, hp = 150, resist = 0.10, armor = 1, evasion = 0.10 },
	{ name = "rocketpick",     display = "Rocket Pick",      income = 25,  speed = 1.35, damage = 45,  radius = 34, hp = 250, resist = 0.25, armor = 2, evasion = 0.15 },
	{ name = "rocketpick2",    display = "Rocket Pick II",   income = 45,  speed = 1.50, damage = 60,  radius = 38, hp = 350, resist = 0.35, armor = 2, evasion = 0.25 },
	{ name = "rocketguns",     display = "Rocket Guns",      income = 80,  speed = 1.70, damage = 90,  radius = 44, hp = 550, resist = 0.45, armor = 3, evasion = 0.30 },
	{ name = "rocketguns3000", display = "Rocket Guns 3000", income = 140, speed = 1.95, damage = 130, radius = 50, hp = 800, resist = 0.55, armor = 4, evasion = 0.40 },
}
for _, t in ipairs(Config.Tiers) do
	t.price = t.income * Config.PAYBACK_SECONDS
end

function Config.getExtraRocketPrice(tierIndex, owned)
	return Config.Tiers[tierIndex].price + (owned - 1) * 150
end

function Config.getUpgradePrice(tierIndex, count)
	local nxt = Config.Tiers[tierIndex + 1]
	if not nxt then return nil end
	return nxt.price * count
end

Config.Turret = {
	modelName = "Rocket Turret",
	price = 1500,
	range = 220,
	missileSpeed = 170,
	levels = {
		{ reaction = 1.50, reload = 120, upgradePrice = 0 },
		{ reaction = 1.20, reload = 108, upgradePrice = 2000 },
		{ reaction = 0.95, reload = 97,  upgradePrice = 3500 },
		{ reaction = 0.70, reload = 86,  upgradePrice = 5500 },
		{ reaction = 0.45, reload = 75,  upgradePrice = 8000 },
	},
}

return Config