local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

repeat task.wait() until _G.RocketSystem and _G.RocketSystem.Ready
local RS = _G.RocketSystem
RS.services = RS.services or {}
if RS.services.Round then
	warn("[Round] ❌ ДУБЛЬ! Отключён: " .. script:GetFullName())
	return
end
RS.services.Round = script:GetFullName()
local Config = RS.Config
local remotes = RS.remotes

local RC = {
	ROUND_TIME = 30 * 60,
	RESULTS_TIME = 12,
	LEADERBOARD_EVERY = 2,
	WARN_AT = { 600, 300, 60, 30, 10 },
}
Config.Round = RC

local RoundResult = remotes:FindFirstChild("RoundResult")
if not RoundResult then
	RoundResult = Instance.new("RemoteEvent")
	RoundResult.Name = "RoundResult"
	RoundResult.Parent = remotes
end

local function now()
	return Workspace:GetServerTimeNow()
end

RS.round = { number = 1, endAt = 0 }

local function snapshot()
	local list = {}
	for _, d in pairs(RS.players) do
		if d.player.Parent then
			table.insert(list, {
				name = d.player.Name,
				bot = d.bot or false,
				earned = d.earned or 0,
				kills = d.kills or 0,
				money = d.player:GetAttribute("Money") or 0,
				tier = Config.Tiers[d.tier].display,
				rockets = #d.rockets,
			})
		end
	end
	table.sort(list, function(a, b)
		if a.earned ~= b.earned then return a.earned > b.earned end
		return a.kills > b.kills
	end)
	return list
end

local function publishLeaderboard()
	local slim = {}
	for i, e in ipairs(snapshot()) do
		slim[i] = { n = e.name, b = e.bot, e = e.earned, k = e.kills }
	end
	remotes:SetAttribute("Leaderboard", HttpService:JSONEncode(slim))
end

local function startRound()
	RS.round.endAt = now() + RC.ROUND_TIME
	remotes:SetAttribute("RoundEnd", RS.round.endAt)
	remotes:SetAttribute("RoundNumber", RS.round.number)
	print("[Round] ▶ Раунд", RS.round.number, "начался")
end

local function endRound()
	local results = snapshot()
	local winner = results[1]
	RoundResult:FireAllClients({
		number = RS.round.number,
		results = results,
		winner = winner,
		showFor = RC.RESULTS_TIME
	})

	if winner then
		print(("[Round] 🏁 Раунд %d: победил %s (%d$, %d уничтожений)"):format(
			RS.round.number, winner.name, winner.earned, winner.kills
			))
	end

	for _, d in pairs(RS.players) do
		local ok, err = pcall(RS.resetBase, d)
		if not ok then warn("[Round] resetBase:", err) end
	end

	RS.round.number = RS.round.number + 1
	startRound()
	publishLeaderboard()
end

startRound()

task.spawn(function()
	local warned = {}
	while true do
		task.wait(0.5)
		local left = RS.round.endAt - now()

		for _, w in ipairs(RC.WARN_AT) do
			if left <= w and not warned[w] then
				warned[w] = true
				local msg = w >= 60 and ("⏱ До конца раунда %d мин"):format(w // 60) or ("⏱ До конца раунда %d сек!"):format(w)
				RS.broadcast(msg, true)
			end
		end

		if left <= 0 then
			endRound()
			warned = {}
		end
	end
end)

task.spawn(function()
	while true do
		publishLeaderboard()
		task.wait(RC.LEADERBOARD_EVERY)
	end
end)

print("[Round] ✅ Система раундов готова")