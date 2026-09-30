local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

repeat task.wait() until _G.RocketSystem and _G.RocketSystem.Ready
local RS = _G.RocketSystem
RS.services = RS.services or {}
if RS.services.Alliance then
	warn("[Alliance] ❌ ДУБЛЬ! Отключён: " .. script:GetFullName())
	return
end
RS.services.Alliance = script:GetFullName()

local alliances = {}
local wars = {}

local function msg(p, text, ok)
	if typeof(p) == "Instance" and p.Parent then
		RS.remotes.ShopMessage:FireClient(p, text, ok)
	end
end

-- ===================== ПОЛУЧЕНИЕ СПИСКА ИГРОКОВ =====================
RS.remotes.GetPlayersList.OnServerInvoke = function(player)
	local list = {}
	for _, d in pairs(RS.players) do
		if d.player.Parent then
			local inAlliance = false
			for _, a in pairs(alliances) do
				if a.members[d.userId] then
					inAlliance = true
					break
				end
			end
			table.insert(list, {
				userId = d.userId,
				name = d.player.Name,
				isBot = d.bot or false,
				inAlliance = inAlliance,
			})
		end
	end
	return list
end

-- ===================== СОЗДАНИЕ СОЮЗА =====================
RS.remotes.CreateAlliance.OnServerEvent:Connect(function(player, targetId)
	local data = RS.players[player.UserId]
	local target = RS.players[targetId]
	if not data or not target then
		msg(player, "Игрок не найден", false)
		return
	end

	if data.userId == target.userId then
		msg(player, "Нельзя с самим собой", false)
		return
	end

	for _, a in pairs(alliances) do
		if a.members[data.userId] or a.members[target.userId] then
			msg(player, "Кто-то уже в союзе", false)
			return
		end
	end

	local id = #alliances + 1
	alliances[id] = {
		members = {
			[data.userId] = true,
			[target.userId] = true,
		},
		leader = data.userId,
		created = tick(),
		betrayals = {},
	}

	data.allianceId = id
	target.allianceId = id

	msg(player, "🤝 Союз создан с " .. target.player.Name, true)
	msg(target.player, "🤝 " .. player.Name .. " создал союз с вами", true)
	RS.broadcast("🤝 " .. player.Name .. " и " .. target.player.Name .. " создали союз!", false)
end)

-- ===================== ОБЪЯВЛЕНИЕ ВОЙНЫ =====================
RS.remotes.DeclareWar.OnServerEvent:Connect(function(player, targetId)
	local data = RS.players[player.UserId]
	local target = RS.players[targetId]
	if not data or not target then
		msg(player, "Игрок не найден", false)
		return
	end

	for _, a in pairs(alliances) do
		if a.members[data.userId] and a.members[target.userId] then
			msg(player, "Нельзя объявлять войну союзнику!", false)
			return
		end
	end

	local warId = #wars + 1
	wars[warId] = {
		attacker = data.userId,
		defender = target.userId,
		started = tick(),
		ended = false,
	}

	msg(player, "⚔️ Вы объявили войну " .. target.player.Name, true)
	msg(target.player, "⚔️ " .. player.Name .. " объявил вам войну!", false)
	RS.broadcast("⚔️ " .. player.Name .. " объявил войну " .. target.player.Name .. "!", false)

	if target.bot and target.ai then
		target.ai.nextAttack = tick() + 10
		target.ai.revengeTarget = data.userId
	end
end)

-- ===================== ПРЕДАТЕЛЬСТВО =====================
RS.remotes.BetrayAlliance.OnServerEvent:Connect(function(player)
	local userId = player.UserId
	local found = false

	for id, a in pairs(alliances) do
		if a.members[userId] then
			a.betrayals[userId] = (a.betrayals[userId] or 0) + 1
			a.members[userId] = nil

			if data and data.allianceId then
				data.allianceId = nil
			end

			if a.leader == userId then
				alliances[id] = nil
				RS.broadcast("💔 Союз распался из-за предательства лидера!", false)
			else
				for uid, d in pairs(RS.players) do
					if d.bot and a.members[uid] and d.ai then
						d.ai.revengeTarget = userId
						d.ai.nextAttack = tick() + 5
						msg(d.player, "😡 " .. player.Name .. " предал союз! Мстим!", false)
					end
				end
				msg(player, "😡 Вы предали союз! Боты будут мстить!", false)
				RS.broadcast("💔 " .. player.Name .. " предал союз!", false)
			end
			found = true
			break
		end
	end

	if not found then
		msg(player, "Вы не в союзе", false)
	end
end)

-- ===================== ПРОВЕРКА ВОЙН =====================
local RunService = game:GetService("RunService")
RunService.Heartbeat:Connect(function()
	for id, war in pairs(wars) do
		if war.ended then continue end

		local attacker = RS.players[war.attacker]
		local defender = RS.players[war.defender]

		if not attacker or not defender then
			war.ended = true
			continue
		end

		if attacker.kills - defender.kills > 5 then
			war.ended = true
			RS.broadcast("⚔️ " .. attacker.player.Name .. " победил в войне с " .. defender.player.Name, true)
			msg(attacker.player, "🏆 Вы победили в войне!", true)
			msg(defender.player, "💀 Вы проиграли войну!", false)
		elseif defender.kills - attacker.kills > 5 then
			war.ended = true
			RS.broadcast("⚔️ " .. defender.player.Name .. " победил в войне с " .. attacker.player.Name, true)
			msg(defender.player, "🏆 Вы победили в войне!", true)
			msg(attacker.player, "💀 Вы проиграли войну!", false)
		end
	end
end)

print("[Alliance] ✅ Система союзов и войн готова")