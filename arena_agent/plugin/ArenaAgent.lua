--[=[
	═══════════════════════════════════════════════════════════════════
	 ARENA AGENT — ИИ-агент прямо в Roblox Studio
	═══════════════════════════════════════════════════════════════════
	 Чат с ИИ внутри Studio: агент сам создаёт и правит скрипты, объекты
	 и свойства в открытом месте (place). Всё генерируется сразу в
	 Roblox-файле, с поддержкой Undo через ChangeHistoryService.

	 Установка:
	   1. Скопируйте этот файл в папку локальных плагинов Studio:
	      Windows: %LOCALAPPDATA%\Roblox\Plugins\ArenaAgent.lua
	      macOS:   ~/Documents/Roblox/Plugins/ArenaAgent.lua
	   2. Перезапустите Studio → тулбар «Arena AI» → кнопка «Arena Agent».
	   3. ⚙ Настройки → выберите провайдера и вставьте API-ключ.

	 Провайдеры: OpenRouter / OpenAI / Anthropic / Ollama / LM Studio /
	 локальный bridge (см. bridge/server.mjs в репозитории) / Arena.ai (beta).

	 Версия: 1.0.0
]=]

local plugin = plugin
if not plugin then
	error("[ArenaAgent] Это плагин Roblox Studio: положите файл в папку Plugins и ПОЛНОСТЬЮ перезапустите Studio (см. arena_agent/README.md).")
end

---------------------------------------------------------------------
-- Сервисы и константы
---------------------------------------------------------------------
local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local VERSION = "1.0.1"
local WAYPOINT_NAME = "Arena Agent"
local MAX_OPS_PER_TURN = 150
local MAX_INSTANCES_PER_TURN = 800
local MAX_SCRIPT_SOURCE = 200000      -- символов на один скрипт
local MAX_BUBBLES = 160
local HISTORY_MAX_ENTRIES = 30
local HISTORY_MAX_CHARS = 150000

-- Тема оформления
local THEME = {
	bg       = Color3.fromRGB(15, 17, 21),
	panel    = Color3.fromRGB(22, 26, 33),
	panel2   = Color3.fromRGB(26, 31, 40),
	border   = Color3.fromRGB(44, 50, 64),
	accent   = Color3.fromRGB(114, 87, 252),
	accent2  = Color3.fromRGB(196, 68, 244),
	user     = Color3.fromRGB(43, 48, 66),
	agent    = Color3.fromRGB(26, 31, 40),
	sys      = Color3.fromRGB(24, 28, 36),
	err      = Color3.fromRGB(66, 26, 30),
	okText   = Color3.fromRGB(120, 220, 150),
	errText  = Color3.fromRGB(255, 120, 120),
	text     = Color3.fromRGB(228, 231, 240),
	textDim  = Color3.fromRGB(150, 158, 178),
	textFaint= Color3.fromRGB(105, 112, 132),
}

-- Провайдеры: kind = openai | anthropic | bridge
local PROVIDERS = {
	{ id = "openrouter", label = "OpenRouter",        kind = "openai",    endpoint = "https://openrouter.ai/api/v1",   model = "anthropic/claude-sonnet-4.5", hint = "Ключ с openrouter.ai/keys" },
	{ id = "openai",     label = "OpenAI",            kind = "openai",    endpoint = "https://api.openai.com/v1",      model = "gpt-4.1-mini",                hint = "Ключ с platform.openai.com" },
	{ id = "anthropic",  label = "Anthropic",         kind = "anthropic", endpoint = "https://api.anthropic.com/v1",   model = "claude-sonnet-4-5",           hint = "Ключ с console.anthropic.com" },
	{ id = "ollama",     label = "Ollama (локально)", kind = "openai",    endpoint = "http://localhost:11434/v1",      model = "qwen2.5-coder:7b",            hint = "Без ключа. ollama serve" },
	{ id = "lmstudio",   label = "LM Studio (лок.)",  kind = "openai",    endpoint = "http://localhost:1234/v1",       model = "local-model",                 hint = "Без ключа. Server → Start" },
	{ id = "bridge",     label = "Arena bridge",      kind = "bridge",    endpoint = "http://localhost:8787",          model = "",                            hint = "bridge/server.mjs — ключи живут там" },
	{ id = "arena",      label = "Arena.ai (beta)",   kind = "openai",    endpoint = "https://api.arena.ai/v1",        model = "arena-agent",                 hint = "Пресет на будущее: правьте URL под API arena.ai" },
}

print("[ArenaAgent] v" .. VERSION .. ": загрузка…")

-- Тулбар создаём СРАЗУ: кнопка появится в меню Plugins, даже если дальше
-- при инициализации что-то упадёт — тогда причина будет видна в Output.
local toolbar = plugin:CreateToolbar("Arena AI")
local toggleBtn = toolbar:CreateButton(
	"Arena Agent",
	"Открыть ИИ-агента (чат → генерация кода и объектов в открытом place)",
	"rbxasset://textures/animationEditor/icon_play.png"
)
toggleBtn.ClickableWhenViewportHidden = true

local widgetRef = nil
toggleBtn.Click:Connect(function()
	if widgetRef then
		widgetRef.Enabled = not widgetRef.Enabled
	else
		warn("[ArenaAgent] инициализация не завершилась — смотрите ошибку [ArenaAgent] в Output.")
	end
end)

local initOK, initErr = pcall(function()

---------------------------------------------------------------------
-- Состояние и настройки
---------------------------------------------------------------------
local state = {
	running = false,
	stopRequested = false,
	history = {},        -- {role, content} без system (он строится заново каждый ход)
	order = 0,
}

local function defaultSettings()
	local p = PROVIDERS[1]
	return {
		providerIndex = 1,
		endpoint = p.endpoint,
		model = p.model,
		apiKey = "",
		temperature = 0.3,
		maxIter = 6,
		jsonMode = false,
		showRaw = false,
		contextEnabled = true,
		mode = "agent",
	}
end

local settings = defaultSettings()

local function saveSettings()
	pcall(function()
		plugin:SetSetting("ArenaAgentSettings_v1", settings)
	end)
end

local function loadSettings()
	local ok, saved = pcall(function()
		return plugin:GetSetting("ArenaAgentSettings_v1")
	end)
	if ok and type(saved) == "table" then
		for k, v in pairs(saved) do
			if settings[k] ~= nil or k == "apiKey" or k == "endpoint" or k == "model" then
				settings[k] = v
			end
		end
		if settings.maxIter < 1 then settings.maxIter = 1 end
		if settings.maxIter > 12 then settings.maxIter = 12 end
	end
end

local function saveChat()
	pcall(function()
		local h = state.history
		local cut = math.max(1, #h - 40)
		local trimmed = {}
		for i = cut, #h do trimmed[#trimmed + 1] = h[i] end
		if #trimmed > 0 then
			plugin:SetSetting("ArenaAgentChat_v1", trimmed)
		end
	end)
end

local function loadChat()
	local ok, saved = pcall(function()
		return plugin:GetSetting("ArenaAgentChat_v1")
	end)
	if ok and type(saved) == "table" then
		for _, m in ipairs(saved) do
			if type(m) == "table" and type(m.role) == "string" and type(m.content) == "string" then
				state.history[#state.history + 1] = { role = m.role, content = m.content }
			end
		end
	end
end

loadSettings()

---------------------------------------------------------------------
-- Утилиты
---------------------------------------------------------------------
local function preview(s, n)
	s = tostring(s or "")
	if #s > n then return s:sub(1, n) .. " …(обрезано)" end
	return s
end

local function escapeRich(s)
	s = tostring(s or "")
	s = s:gsub("&", "&amp;")
	s = s:gsub("<", "&lt;")
	s = s:gsub(">", "&gt;")
	s = s:gsub('"', "&quot;")
	return s
end

local function num(v, default)
	local n = tonumber(v)
	if n == nil then return default or 0 end
	return n
end

local function trim(s)
	if type(s) ~= "string" then return tostring(s) end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---------------------------------------------------------------------
-- Пути и поиск по DataModel
---------------------------------------------------------------------
local function splitPath(path)
	if type(path) ~= "string" then return nil end
	path = trim(path)
	path = path:gsub("^game/", ""):gsub("^Game/", "")
	path = path:gsub("^workspace/", "Workspace/"):gsub("^Workspace//", "Workspace/")
	local parts = {}
	for token in path:gmatch("[^/]+") do
		local clean = trim(token)
		if clean ~= "" then parts[#parts + 1] = clean end
	end
	if #parts == 0 then return nil end
	return parts
end

local function getRootService(name)
	if name == "StarterPlayerScripts" or name == "StarterCharacterScripts" then
		local sp = game:FindFirstChild("StarterPlayer")
		if sp then return sp:FindFirstChild(name) end
		return nil
	end
	return game:FindFirstChild(name)
end

-- Разрешить путь "Сервис/А/Б" в существующий экземпляр
local function resolvePath(path)
	local parts = splitPath(path)
	if not parts then return nil, "пустой путь" end
	local cur = getRootService(parts[1])
	if not cur then return nil, "нет сервиса '" .. tostring(parts[1]) .. "'" end
	for i = 2, #parts do
		local nxt = cur:FindFirstChild(parts[i])
		if not nxt then
			return nil, "не найден путь '" .. table.concat(parts, "/", 1, i) .. "'"
		end
		cur = nxt
	end
	return cur
end

local function safeFullName(inst)
	local ok, full = pcall(function() return inst:GetFullName() end)
	if ok and full and full ~= "" then return full end
	return inst.Name
end

-- Вернуть родителя для пути, создав недостающие промежуточные Folder.
-- pathParts включает последний сегмент (сам объект).
local function ensureContainer(pathParts)
	local cur = getRootService(pathParts[1])
	if not cur then return nil, "нет сервиса '" .. tostring(pathParts[1]) .. "'" end
	for i = 2, #pathParts - 1 do
		local nxt = cur:FindFirstChild(pathParts[i])
		if not nxt then
			nxt = Instance.new("Folder")
			nxt.Name = pathParts[i]
			nxt.Parent = cur
		end
		cur = nxt
	end
	return cur
end

local function pathFromParts(parts)
	return table.concat(parts, "/")
end

---------------------------------------------------------------------
-- Кодирование / разбор значений свойств
---------------------------------------------------------------------
local function parseEnumString(str, currentEnumItem)
	if type(str) ~= "string" then return nil end
	local s = str:gsub("^Enum%.", "")
	local a, b = s:match("^([%w_]+)%.([%w_]+)$")
	if a and b then
		local ok, enumType = pcall(function() return Enum[a] end)
		if ok and enumType then
			local ok2, item = pcall(function() return enumType[b] end)
			if ok2 and item then return item end
		end
		return nil
	end
	-- просто "Neon" — используем тип энума текущего значения
	if currentEnumItem then
		local ok, et = pcall(function() return currentEnumItem.EnumType end)
		if ok and et then
			local ok2, item = pcall(function() return et[str] end)
			if ok2 and item then return item end
		end
	end
	return nil
end

-- Значение из модели (JSON) → значение Roblox с учётом текущего типа свойства
-- Возвращает: true, value  |  false, ошибка
local function coerceValue(inst, prop, value)
	local hasCurrent, current = pcall(function() return inst[prop] end)
	local curType = "nil"
	if hasCurrent then curType = typeof(current) end

	-- 1) Тегированные значения {"__t": "...", "v": [...]}
	if type(value) == "table" and value.__t ~= nil then
		local t = tostring(value.__t)
		local v = value.v
		if t == "Vector3" then
			return true, Vector3.new(num(v[1]), num(v[2]), num(v[3]))
		elseif t == "Vector2" then
			return true, Vector2.new(num(v[1]), num(v[2]))
		elseif t == "Color3" then
			if type(value.hex) == "string" then
				local okH, c = pcall(function() return Color3.fromHex(value.hex) end)
				if okH and c then return true, c end
				return false, "плохой hex: " .. tostring(value.hex)
			end
			local r, g, b = num(v[1]), num(v[2]), num(v[3])
			if r > 1 or g > 1 or b > 1 then
				return true, Color3.fromRGB(r, g, b)
			end
			return true, Color3.new(r, g, b)
		elseif t == "UDim" then
			return true, UDim.new(num(v[1]), num(v[2]))
		elseif t == "UDim2" then
			return true, UDim2.new(num(v[1]), num(v[2]), num(v[3]), num(v[4]))
		elseif t == "CFrame" then
			if type(v) ~= "table" then return false, "CFrame: нужен массив чисел" end
			if #v >= 12 then
				return true, CFrame.new(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12])
			elseif #v >= 3 then
				return true, CFrame.new(v[1], v[2], v[3])
			end
			return false, "CFrame: нужно 3 или 12 чисел"
		elseif t == "Enum" then
			local okE, et = pcall(function() return Enum[value.e] end)
			if not okE or not et then return false, "нет Enum." .. tostring(value.e) end
			local okI, item = pcall(function() return et[value.v] end)
			if not okI or not item then return false, "нет Enum." .. tostring(value.e) .. "." .. tostring(value.v) end
			return true, item
		elseif t == "BrickColor" then
			if type(value.v) == "number" then
				return true, BrickColor.new(value.v)
			end
			local okB, bc = pcall(function() return BrickColor.new(tostring(value.v)) end)
			if not okB then return false, "нет цвета BrickColor: " .. tostring(value.v) end
			return true, bc
		elseif t == "NumberRange" then
			return true, NumberRange.new(num(v[1]), num(v[2]))
		elseif t == "Rect" then
			return true, Rect.new(num(v[1]), num(v[2]), num(v[3]), num(v[4]))
		elseif t == "Instance" or t == "Object" then
			local p = value.v or value.path
			local ref, err = resolvePath(p)
			if not ref then return false, "объект не найден: " .. tostring(p) .. (err and (" (" .. err .. ")") or "") end
			return true, ref
		else
			return false, "неизвестный __t: " .. t
		end
	end

	-- 2) Короткие массивы, если знаем текущий тип
	if type(value) == "table" and curType ~= nil then
		if curType == "Vector3" and #value >= 3 then
			return true, Vector3.new(num(value[1]), num(value[2]), num(value[3]))
		elseif curType == "Vector2" and #value >= 2 then
			return true, Vector2.new(num(value[1]), num(value[2]))
		elseif curType == "Color3" and #value >= 3 then
			local r, g, b = num(value[1]), num(value[2]), num(value[3])
			if r > 1 or g > 1 or b > 1 then return true, Color3.fromRGB(r, g, b) end
			return true, Color3.new(r, g, b)
		elseif curType == "UDim" and #value >= 2 then
			return true, UDim.new(num(value[1]), num(value[2]))
		elseif curType == "UDim2" and #value >= 4 then
			return true, UDim2.new(num(value[1]), num(value[2]), num(value[3]), num(value[4]))
		elseif curType == "NumberRange" and #value >= 2 then
			return true, NumberRange.new(num(value[1]), num(value[2]))
		elseif curType == "Rect" and #value >= 4 then
			return true, Rect.new(num(value[1]), num(value[2]), num(value[3]), num(value[4]))
		elseif curType == "CFrame" and #value >= 12 then
			return true, CFrame.new(value[1], value[2], value[3], value[4], value[5], value[6], value[7], value[8], value[9], value[10], value[11], value[12])
		elseif curType == "CFrame" and #value >= 3 then
			return true, CFrame.new(value[1], value[2], value[3])
		end
	end

	-- 3) Энумы
	if curType == "EnumItem" then
		local item = parseEnumString(value, current)
		if item then return true, item end
		return false, "не похоже на энум: " .. tostring(value)
	end

	-- 4) Ссылки на объекты
	if curType == "Instance" and type(value) == "string" then
		local ref, err = resolvePath(value)
		if not ref then return false, "объект не найден: " .. value .. (err and (" (" .. err .. ")") or "") end
		return true, ref
	end

	-- 5) BrickColor по имени/числу
	if curType == "BrickColor" then
		local okB, bc = pcall(function() return BrickColor.new(value) end)
		if not okB then return false, "плохой BrickColor: " .. tostring(value) end
		return true, bc
	end

	-- 6) Скаляры
	if type(value) == "number" or type(value) == "boolean" then
		return true, value
	end
	if type(value) == "string" then
		if curType == "number" then
			local n = tonumber(value)
			if n then return true, n end
			return false, "ожидалось число, получено: " .. value
		end
		if curType == "boolean" then
			if value == "true" then return true, true end
			if value == "false" then return true, false end
			return false, "ожидалось true/false"
		end
		-- строка в нетекстовое свойство (Vector3, Color3, ...) — не конвертим вслепую
		if curType ~= "string" and curType ~= "nil" then
			return false, "ожидался тип " .. curType .. ", получена строка: " .. value
		end
		return true, value
	end

	return false, "не могу разобрать значение (используйте __t-формат)"
end

-- Значение Roblox → JSON-совместимая таблица (для чтения агентом)
local function encodeValue(v)
	local t = type(v)
	if t == "Instance" then
		return safeFullName(v)
	elseif t == "EnumItem" then
		return tostring(v)
	elseif t == "Vector3" then
		return { __t = "Vector3", v = { v.X, v.Y, v.Z } }
	elseif t == "Vector2" then
		return { __t = "Vector2", v = { v.X, v.Y } }
	elseif t == "Color3" then
		return { __t = "Color3", v = { math.floor(v.R * 1000 + 0.5) / 1000, math.floor(v.G * 1000 + 0.5) / 1000, math.floor(v.B * 1000 + 0.5) / 1000 } }
	elseif t == "UDim" then
		return { __t = "UDim", v = { v.Scale, v.Offset } }
	elseif t == "UDim2" then
		return { __t = "UDim2", v = { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } }
	elseif t == "CFrame" then
		local comps = { v:GetComponents() }
		local arr = {}
		for i, c in ipairs(comps) do arr[i] = math.floor(c * 1000 + 0.5) / 1000 end
		return { __t = "CFrame", v = arr }
	elseif t == "BrickColor" then
		return { __t = "BrickColor", v = v.Name }
	elseif t == "NumberRange" then
		return { __t = "NumberRange", v = { v.Min, v.Max } }
	elseif t == "Rect" then
		return { __t = "Rect", v = { v.Min.X, v.Min.Y, v.Max.X, v.Max.Y } }
	elseif t == "table" then
		return tostring(v)
	else
		return v
	end
end

local function isScriptLike(inst)
	return inst.ClassName == "Script" or inst.ClassName == "LocalScript" or inst.ClassName == "ModuleScript"
end

---------------------------------------------------------------------
-- Снимок места (контекст для агента)
---------------------------------------------------------------------
local function nodeToTable(inst, depth, budget)
	local node = { n = inst.Name, c = inst.ClassName }
	budget.nodes = budget.nodes + 1
	if budget.nodes > budget.max then
		node.cut = true
		return node
	end
	if depth > 0 then
		local ch = {}
		local listed = 0
		for _, child in ipairs(inst:GetChildren()) do
			listed = listed + 1
			if listed > 40 then
				ch[#ch + 1] = { n = "…", c = "обрезано" }
				break
			end
			if child.ClassName == "Camera" then
				-- не засоряем контекст
			else
				ch[#ch + 1] = nodeToTable(child, depth - 1, budget)
			end
			if budget.nodes > budget.max then
				ch[#ch + 1] = { n = "…", c = "лимит снимка" }
				break
			end
		end
		if #ch > 0 then node.ch = ch end
	end
	return node
end

local function buildSnapshot()
	local budget = { nodes = 0, max = 320 }
	local data = {}
	local services = {
		{ name = "Workspace", depth = 3 },
		{ name = "ReplicatedStorage", depth = 2 },
		{ name = "ServerScriptService", depth = 3 },
		{ name = "ServerStorage", depth = 2 },
		{ name = "StarterGui", depth = 2 },
		{ name = "StarterPack", depth = 1 },
		{ name = "StarterPlayer", depth = 3 },
		{ name = "Lighting", depth = 1 },
		{ name = "SoundService", depth = 1 },
		{ name = "Teams", depth = 1 },
		{ name = "TextChatService", depth = 1 },
	}
	for _, s in ipairs(services) do
		local root = getRootService(s.name)
		if root then
			data[#data + 1] = nodeToTable(root, s.depth, budget)
		end
	end
	local ok, json = pcall(function() return HttpService:JSONEncode(data) end)
	if ok then return json end
	return "[]"
end

local function buildSelectionText(includeSources)
	local sel = Selection:Get()
	if #sel == 0 then return "(ничего не выделено)" end
	local lines = {}
	for i, inst in ipairs(sel) do
		if i > 10 then
			lines[#lines + 1] = "… и ещё " .. tostring(#sel - i + 1)
			break
		end
		lines[#lines + 1] = "- " .. safeFullName(inst) .. " [" .. inst.ClassName .. "]"
		if includeSources and isScriptLike(inst) then
			local src = ""
			pcall(function() src = inst.Source end)
			if #src > 0 then
				if #src > 6000 then src = src:sub(1, 6000) .. "\n-- …(обрезано)" end
				lines[#lines + 1] = "SOURCE:\n" .. src .. "\n/SOURCE"
			end
		end
	end
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------
-- Системный промпт
---------------------------------------------------------------------
local SYSTEM_PROMPT = [==[
Ты — Arena Agent: ИИ-агент, встроенный в Roblox Studio через плагин. Ты работаешь СРАЗУ в открытом у пользователя месте (place) и меняешь его операциями (ops), которые плагин выполняет в DataModel.

ФОРМАТ ОТВЕТА (строго):
Отвечай РОВНО ОДНИМ валидным JSON-объектом, без markdown-заборов и текста вне JSON:
{"reply":"короткий ответ пользователю на его языке (по умолчанию русский)","ops":[...],"done":true}
- "reply" — краткое человеческое пояснение, что сделано/делается.
- "ops" — список операций (может быть пустым, если менять ничего не нужно).
- "done": true — задача завершена, ждёшь нового указания; false — после применения ops пришлёшь продолжение.
Плагин применит ops и пришлёт результат сообщением пользователя вида "ARENA_RESULT: {...}". Если в errors есть ошибки — исправь их новой порцией ops (done=false). Если всё чисто и задача завершена — done=true.

ОПЕРАЦИИ (ops):
1) Создать/обновить скрипт (создаст недостающие папки-предки как Folder):
{"op":"upsert_script","path":"ServerScriptService/Game/RoundManager","class":"Script","source":"-- ПОЛНЫЙ код скрипта"}
   class: "Script" (сервер) | "LocalScript" (клиент) | "ModuleScript" (общий код). Можно "disabled": true.
2) Создать экземпляр (имя = последний сегмент пути; у детей имя в "name"):
{"op":"create_instance","path":"Workspace/ArenaBuilds/Tower","class":"Model","properties":{},"children":[{"name":"Roof","class":"Part","properties":{"Size":{"__t":"Vector3","v":[4,1,2]},"Anchored":true}}]}
3) Свойства существующего: {"op":"set_properties","path":"Workspace/Boss","properties":{"Health":500,"Material":"Material.Neon"}}
4) Удалить: {"op":"delete_instance","path":"Workspace/Old"}
5) Переименовать: {"op":"rename_instance","path":"...","name":"НовоеИмя"}
   Переместить: {"op":"move_instance","path":"Workspace/X","to":"ReplicatedStorage/X"}
6) Прочитать код: {"op":"get_source","path":"ServerScriptService/Game/Main"}
7) Прочитать свойства: {"op":"get_properties","path":"Workspace/Boss","properties":["Health","Position"]}
8) Дети объекта: {"op":"list_children","path":"Workspace/ArenaBuilds"}
9) Атрибут: {"op":"set_attribute","path":"Workspace/Boss","name":"Level","value":3}

ФОРМАТ ЗНАЧЕНИЙ СВОЙСТВ:
- числа/строки/bool — как есть. Строки-энумы: "Material.Neon" или "Enum.Material.Neon".
- Vector3: {"__t":"Vector3","v":[x,y,z]}   · Vector2 аналогично
- Color3: {"__t":"Color3","v":[r,g,b]} (0..1) или {"__t":"Color3","hex":"FF8800"}
- UDim2: {"__t":"UDim2","v":[scaleX,offsetX,scaleY,offsetY]}  · UDim: {"__t":"UDim","v":[scale,offset]}
- CFrame: {"__t":"CFrame","v":[x,y,z]} (позиция) или 12 чисел
- BrickColor: {"__t":"BrickColor","v":"Really red"}  · Enum: {"__t":"Enum","e":"Material","v":"Neon"}
- ссылка на объект: строка-путь "Workspace/Door" (для свойств-ObjectValue)
- В properties можно и короткие массивы, если тип свойства очевиден: "Size":[4,1,2].

ПРАВИЛА:
- Пиши ПОЛНЫЙ код скриптов (без "-- остальное без изменений").
- Прежде чем переписывать существующий скрипт, посмотри его через get_source.
- Клиентский код — LocalScript в StarterPlayer/StarterPlayerScripts или StarterGui; серверный — Script в ServerScriptService; общий — ModuleScript в ReplicatedStorage.
- Свои постройки складывай в Workspace/ArenaBuilds/..., если пользователь не сказал иного.
- Не трогай то, чего не касалась задача. Не удаляй чужие объекты без явной просьбы.
- Один op = один скрипт/объект. Большую систему лучше собрать за несколько итераций (done=false), чем прислать обрезанный код.
- В source экранируй кавычки по правилам JSON (\").
- Если данных не хватает — задай вопрос в "reply" с пустыми ops и done=true.
- Учитывай снимок места и выделение в Studio ниже (выделение — вероятная цель действия, если уместно).
- Отвечай "reply" на языке пользователя (обычно русский), кратко.

СНИМОК МЕСТА (актуален на момент запроса):
@@SNAPSHOT@@

ВЫДЕЛЕНО В STUDIO (с исходниками скриптов):
@@SELECTION@@
]==]

local CHAT_PROMPT = [==[
Ты — Arena Agent, ИИ-ассистент внутри Roblox Studio (плагин). Сейчас режим "Только чат": отвечай обычным текстом (без JSON и ops). Ты эксперт по Roblox/Luau. Отвечай на языке пользователя (обычно русский), кратко и по делу, с примерами кода, где уместно.

СНИМОК МЕСТА:
@@SNAPSHOT@@

ВЫДЕЛЕНО В STUDIO (с исходниками скриптов):
@@SELECTION@@
]==]

local function buildSystemPrompt()
	local tpl = (settings.mode == "chat") and CHAT_PROMPT or SYSTEM_PROMPT
	local snapshot = "(выключено в настройках)"
	if settings.contextEnabled then
		snapshot = buildSnapshot()
		if #snapshot > 16000 then
			snapshot = snapshot:sub(1, 16000) .. ' {"n":"…","c":"снимок обрезан"}'
		end
	end
	local selText = buildSelectionText(true)
	local p = tpl:gsub("@@SNAPSHOT@@", function() return snapshot end)
	p = p:gsub("@@SELECTION@@", function() return selText end)
	return p
end

---------------------------------------------------------------------
-- Извлечение JSON из ответа модели
---------------------------------------------------------------------
local function decodeJSON(str)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, str)
	if ok then return data end
	return nil
end

local function looksLikeAgentJSON(data)
	return type(data) == "table" and (data.ops ~= nil or data.reply ~= nil or data.done ~= nil)
end

local function extractJSON(text)
	if type(text) ~= "string" or text == "" then return nil end
	local t = text
	t = t:gsub("^%s*```[a-zA-Z0-9]*%s*", "")
	t = t:gsub("```%s*$", "")

	local data = decodeJSON(trim(t))
	if looksLikeAgentJSON(data) then return data end

	local a = t:find("{")
	if not a then return nil end
	-- сканер с учётом строк и вложенности: от первой { до парной }
	local depth = 0
	local inStr = false
	local esc = false
	for i = a, #t do
		local ch = t:sub(i, i)
		if esc then
			esc = false
		elseif inStr and ch == "\\" then
			esc = true
		elseif ch == '"' then
			inStr = not inStr
		elseif not inStr then
			if ch == "{" then
				depth = depth + 1
			elseif ch == "}" then
				depth = depth - 1
				if depth == 0 then
					local cand = decodeJSON(t:sub(a, i))
					if cand then
						if looksLikeAgentJSON(cand) then return cand end
						if data == nil then data = cand end
					end
				end
			end
		end
	end
	return data
end

---------------------------------------------------------------------
-- Выполнение операций над DataModel
---------------------------------------------------------------------
local function setProps(inst, props, warnings)
	local okCount = 0
	local names = {}
	for name in pairs(props) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local value = props[name]
		local okC, v = coerceValue(inst, name, value)
		if not okC then
			warnings[#warnings + 1] = name .. ": " .. tostring(v)
		else
			local okS, err = pcall(function() inst[name] = v end)
			if okS then
				okCount = okCount + 1
			else
				warnings[#warnings + 1] = name .. ": " .. tostring(err)
			end
		end
	end
	return okCount
end

local function buildChildren(children, parent, budget, warnings)
	for _, spec in ipairs(children or {}) do
		budget.instances = budget.instances + 1
		if budget.instances > MAX_INSTANCES_PER_TURN then
			return "достигнут лимит экземпляров за ход"
		end
		if type(spec) ~= "table" then
			warnings[#warnings + 1] = "ребёнок не является объектом"
		else
			local cls = tostring(spec.class or "Folder")
			local okC, inst = pcall(Instance.new, cls)
			if not okC or not inst then
				warnings[#warnings + 1] = "неизвестный класс " .. cls
			else
				inst.Name = tostring(spec.name or "Instance")
				if type(spec.properties) == "table" then
					setProps(inst, spec.properties, warnings)
				end
				inst.Parent = parent
				if type(spec.children) == "table" and #spec.children > 0 then
					local err = buildChildren(spec.children, inst, budget, warnings)
					if err then return err end
				end
			end
		end
	end
	return nil
end

-- Возвращает: true (успех) | false, сообщение об ошибке
local function execOp(op, res, budget)
	if type(op) ~= "table" or type(op.op) ~= "string" then
		return false, "op не является объектом с полем op"
	end
	local kind = op.op
	local warnings = res.warnings

	if kind == "upsert_script" then
		local parts = splitPath(op.path)
		if not parts or #parts < 2 then return false, "upsert_script: плохой путь " .. tostring(op.path) end
		local cls = tostring(op.class or "Script")
		if cls ~= "Script" and cls ~= "LocalScript" and cls ~= "ModuleScript" then
			return false, "upsert_script: class должен быть Script/LocalScript/ModuleScript"
		end
		local parent, err = ensureContainer(parts)
		if not parent then return false, err end
		local leaf = parts[#parts]
		local source = tostring(op.source or "")
		if #source > MAX_SCRIPT_SOURCE then
			return false, "source слишком большой (" .. tostring(#source) .. " символов) — разбей на модули"
		end
		local existing = parent:FindFirstChild(leaf)
		if existing then
			if not isScriptLike(existing) then
				return false, "путь занят экземпляром класса " .. existing.ClassName .. ": " .. pathFromParts(parts)
			end
			if existing.Source == source then
				res.applied[#res.applied + 1] = "upsert_script → " .. pathFromParts(parts) .. " (без изменений)"
				return true
			end
			existing.Source = source
			if op.disabled == true or op.disabled == false then existing.Disabled = (op.disabled == true) end
			res.applied[#res.applied + 1] = "upsert_script → " .. pathFromParts(parts) .. " (обновлён, " .. tostring(#source) .. " симв.)"
			return true
		end
		local inst = Instance.new(cls)
		inst.Name = leaf
		inst.Source = source
		if op.disabled == true then inst.Disabled = true end
		inst.Parent = parent
		res.applied[#res.applied + 1] = "upsert_script → " .. pathFromParts(parts) .. " (создан " .. cls .. ")"
		return true

	elseif kind == "create_instance" then
		local parts = splitPath(op.path)
		if not parts or #parts < 2 then return false, "create_instance: плохой путь " .. tostring(op.path) end
		local parent, err = ensureContainer(parts)
		if not parent then return false, err end
		local leaf = parts[#parts]
		local existing = parent:FindFirstChild(leaf)
		if existing then
			if op.replace == true then
				existing:Destroy()
			else
				return false, "уже существует: " .. pathFromParts(parts) .. " (можно replace:true)"
			end
		end
		local cls = tostring(op.class or "Folder")
		local okC, inst = pcall(Instance.new, cls)
		if not okC or not inst then return false, "неизвестный класс " .. cls end
		inst.Name = leaf
		budget.instances = budget.instances + 1
		if type(op.properties) == "table" then
			setProps(inst, op.properties, warnings)
		end
		inst.Parent = parent
		if type(op.children) == "table" and #op.children > 0 then
			local berr = buildChildren(op.children, inst, budget, warnings)
			if berr then
				res.applied[#res.applied + 1] = "create_instance → " .. pathFromParts(parts) .. " (создан, но обрезан: " .. berr .. ")"
				return true
			end
		end
		res.applied[#res.applied + 1] = "create_instance → " .. pathFromParts(parts) .. " (" .. cls .. ")"
		return true

	elseif kind == "set_properties" then
		local inst, err = resolvePath(op.path)
		if not inst then return false, "set_properties: " .. tostring(err) end
		if type(op.properties) ~= "table" then return false, "set_properties: нет properties" end
		local okCount = setProps(inst, op.properties, warnings)
		if okCount == 0 then return false, "ни одно свойство не применилось" end
		res.applied[#res.applied + 1] = "set_properties → " .. safeFullName(inst) .. " (" .. tostring(okCount) .. " свойств)"
		return true

	elseif kind == "set_attribute" then
		local inst, err = resolvePath(op.path)
		if not inst then return false, "set_attribute: " .. tostring(err) end
		if type(op.name) ~= "string" or op.name == "" then return false, "set_attribute: пустое name" end
		local okA, aerr = pcall(function() inst:SetAttribute(op.name, op.value) end)
		if not okA then return false, "set_attribute: " .. tostring(aerr) end
		res.applied[#res.applied + 1] = "set_attribute " .. op.name .. " → " .. safeFullName(inst)
		return true

	elseif kind == "delete_instance" then
		local inst, err = resolvePath(op.path)
		if not inst then return false, "delete_instance: " .. tostring(err) end
		local name = safeFullName(inst)
		inst:Destroy()
		res.applied[#res.applied + 1] = "delete_instance → " .. name
		return true

	elseif kind == "rename_instance" then
		local inst, err = resolvePath(op.path)
		if not inst then return false, "rename_instance: " .. tostring(err) end
		if type(op.name) ~= "string" or op.name == "" then return false, "rename_instance: пустое name" end
		inst.Name = op.name
		res.applied[#res.applied + 1] = "rename_instance → " .. op.name
		return true

	elseif kind == "move_instance" then
		local inst, err = resolvePath(op.path)
		if not inst then return false, "move_instance: " .. tostring(err) end
		local to, err2 = resolvePath(op.to)
		if not to then return false, "move_instance: куда — " .. tostring(err2) end
		if to == inst or to:IsDescendantOf(inst) then
			return false, "нельзя переместить объект внутрь его самого"
		end
		inst.Parent = to
		res.applied[#res.applied + 1] = "move_instance → " .. safeFullName(inst)
		return true

	elseif kind == "get_source" then
		local inst, err = resolvePath(op.path)
		if not inst then return false, "get_source: " .. tostring(err) end
		if not isScriptLike(inst) then return false, "get_source: это не скрипт (" .. inst.ClassName .. ")" end
		local src = ""
		pcall(function() src = inst.Source end)
		local key = pathFromParts(splitPath(op.path) or { op.path })
		res.sources[key] = preview(src, 30000)
		res.applied[#res.applied + 1] = "get_source → " .. key
		return true

	elseif kind == "get_properties" then
		local inst, err = resolvePath(op.path)
		if not inst then return false, "get_properties: " .. tostring(err) end
		local key = safeFullName(inst)
		local out = {}
		local names = op.properties
		if type(names) ~= "table" or #names == 0 then
			names = {}
			for name in pairs(op.properties or {}) do names[#names + 1] = name end
		end
		for _, name in ipairs(names) do
			local okR, v = pcall(function() return inst[name] end)
			if okR then
				out[name] = encodeValue(v)
			else
				out[name] = "(нет такого свойства)"
			end
		end
		res.properties[key] = out
		res.applied[#res.applied + 1] = "get_properties → " .. key
		return true

	elseif kind == "list_children" then
		local inst, err = resolvePath(op.path)
		if not inst then return false, "list_children: " .. tostring(err) end
		local arr = {}
		for _, ch in ipairs(inst:GetChildren()) do
			arr[#arr + 1] = { name = ch.Name, class = ch.ClassName }
			if #arr >= 200 then
				arr[#arr + 1] = { name = "…", class = "обрезано" }
				break
			end
		end
		res.children[safeFullName(inst)] = arr
		res.applied[#res.applied + 1] = "list_children → " .. safeFullName(inst) .. " (" .. tostring(#arr) .. ")"
		return true
	end

	return false, "неизвестная операция: " .. kind
end

local function applyOps(ops, res)
	local budget = { instances = 0 }
	local done = 0
	for _, op in ipairs(ops) do
		done = done + 1
		if done > MAX_OPS_PER_TURN then
			res.errors[#res.errors + 1] = { op = "limit", error = "слишком много ops за один ход (макс " .. tostring(MAX_OPS_PER_TURN) .. ")" }
			break
		end
		local ok, r1, r2 = pcall(execOp, op, res, budget)
		if not ok then
			res.errors[#res.errors + 1] = { op = "?", path = "", error = "внутренняя ошибка: " .. tostring(r1) }
		elseif r1 == false then
			res.errors[#res.errors + 1] = { op = tostring(type(op) == "table" and op.op or "?"), path = tostring(type(op) == "table" and op.path or ""), error = tostring(r2) }
		end
	end
end

---------------------------------------------------------------------
-- Вызов модели
---------------------------------------------------------------------
local function errorHint(text)
	local t = tostring(text)
	if t:find("401") or t:find("403") then
		return "Подсказка: проверьте API-ключ в настройках (⚙)."
	elseif t:find("404") then
		return "Подсказка: проверьте Endpoint и название модели."
	elseif t:find("429") then
		return "Подсказка: лимит запросов или закончился баланс."
	elseif t:find("5%d%d") then
		return "Подсказка: проблема на стороне провайдера, попробуйте позже."
	elseif t:find("localhost") or t:find("Connection") or t:find("connect") then
		return "Подсказка: сервер недоступен. Для локальных моделей запустите Ollama/LM Studio/bridge."
	end
	return ""
end

local function callModel(messages, sysText, s)
	local p = PROVIDERS[s.providerIndex] or PROVIDERS[1]
	local kind = p.kind
	local url, headers, bodyObj

	if kind == "anthropic" then
		url = trim(s.endpoint) .. "/messages"
		local msgs = {}
		for _, m in ipairs(messages) do
			if m.role ~= "system" then
				msgs[#msgs + 1] = { role = m.role, content = m.content }
			end
		end
		bodyObj = {
			model = s.model,
			max_tokens = 8000,
			temperature = s.temperature,
			system = sysText,
			messages = msgs,
		}
		headers = {
			["Content-Type"] = "application/json",
			["x-api-key"] = s.apiKey,
			["anthropic-version"] = "2023-06-01",
		}
	elseif kind == "bridge" then
		url = trim(s.endpoint) .. "/v1/chat"
		bodyObj = {
			model = s.model,
			temperature = s.temperature,
			messages = messages,
			system = sysText,
		}
		headers = { ["Content-Type"] = "application/json" }
	else
		url = trim(s.endpoint) .. "/chat/completions"
		bodyObj = {
			model = s.model,
			temperature = s.temperature,
			messages = messages,
		}
		if s.jsonMode and settings.mode == "agent" then
			bodyObj.response_format = { type = "json_object" }
		end
		headers = { ["Content-Type"] = "application/json" }
		if trim(s.apiKey) ~= "" then
			headers["Authorization"] = "Bearer " .. s.apiKey
		end
		if url:find("openrouter", 1, true) then
			headers["HTTP-Referer"] = "https://arena.ai"
			headers["X-Title"] = "Arena Roblox Agent"
		end
	end

	local bodyStr = HttpService:JSONEncode(bodyObj)
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = headers,
			Body = bodyStr,
		})
	end)
	if not ok then
		return false, "сеть недоступна: " .. tostring(res)
	end
	if not res.Success then
		return false, "HTTP " .. tostring(res.StatusCode) .. ": " .. preview(res.Body or "", 600)
	end

	local decOK, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
	if not decOK then
		return false, "ответ не JSON: " .. preview(res.Body or "", 300)
	end

	if kind == "anthropic" then
		local parts = {}
		for _, blk in ipairs(data.content or {}) do
			if type(blk) == "table" and blk.type == "text" and type(blk.text) == "string" then
				parts[#parts + 1] = blk.text
			end
		end
		if #parts == 0 then
			return false, "пустой ответ Anthropic: " .. preview(res.Body, 300)
		end
		return true, table.concat(parts, "\n")
	elseif kind == "bridge" then
		if data.ok == false then
			return false, tostring(data.error or "ошибка bridge")
		end
		return true, tostring(data.text or "")
	else
		local choices = data.choices
		if type(choices) ~= "table" or type(choices[1]) ~= "table" then
			-- некоторые провайдеры кладут ошибку в body
			local emsg = ""
			if type(data.error) == "table" and data.error.message then emsg = tostring(data.error.message)
			elseif type(data.error) == "string" then emsg = data.error end
			return false, "нет choices в ответе. " .. (emsg ~= "" and emsg or preview(res.Body, 300))
		end
		local msg = choices[1].message
		local text = ""
		if type(msg) == "table" and type(msg.content) == "string" then
			text = msg.content
		elseif type(choices[1].text) == "string" then
			text = choices[1].text
		end
		if text == "" then
			return false, "пустой ответ модели: " .. preview(res.Body, 300)
		end
		return true, text
	end
end

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------
local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			pcall(function() inst[k] = v end)
		end
	end
	inst.Parent = parent
	return inst
end

local function addCorner(parent, r)
	mk("UICorner", { CornerRadius = UDim.new(0, r or 8) }, parent)
end

local widget = plugin:CreateDockWidgetPluginGui(
	"ArenaAgentDock_v1",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 440, 640, 340, 460)
)
widget.Name = "ArenaAgentDock"
widget.Title = "Arena Agent — ИИ для Roblox Studio"
widget.BindingActivated:Connect(function()
	widget.Enabled = true
end)

local root = mk("Frame", {
	Name = "Root",
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = THEME.bg,
	BorderSizePixel = 0,
}, widget)

-- ── Шапка ────────────────────────────────────────────────────────────
local header = mk("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundColor3 = THEME.panel,
	BorderSizePixel = 0,
}, root)
mk("Frame", { Name = "Sep", Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = THEME.border, BorderSizePixel = 0 }, header)

local logo = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(1, -110, 1, 0),
	Font = Enum.Font.GothamBlack,
	Text = "✦ ARENA AGENT",
	TextSize = 15,
	TextColor3 = THEME.text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)
mk("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, THEME.accent),
		ColorSequenceKeypoint.new(1, THEME.accent2),
	}),
}, logo)

local statusDot = mk("Frame", {
	Size = UDim2.new(0, 9, 0, 9),
	Position = UDim2.new(1, -86, 0, 18),
	BackgroundColor3 = Color3.fromRGB(120, 220, 150),
	BorderSizePixel = 0,
}, header)
addCorner(statusDot, 5)

local statusLabel = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(1, -72, 0, 0),
	Size = UDim2.new(0, 60, 1, 0),
	Font = Enum.Font.Gotham,
	Text = "Готов",
	TextSize = 11,
	TextColor3 = THEME.textDim,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, header)

local gearBtn = mk("TextButton", {
	Size = UDim2.new(0, 34, 0, 30),
	Position = UDim2.new(0, 6, 0, 7),
	BackgroundColor3 = THEME.panel2,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "⚙",
	TextSize = 16,
	TextColor3 = THEME.textDim,
	AutoButtonColor = true,
}, header)
addCorner(gearBtn, 6)
-- логотип сдвинем правее шестерёнки
logo.Position = UDim2.new(0, 48, 0, 0)
logo.Size = UDim2.new(1, -130, 1, 0)

-- ── Быстрые действия ────────────────────────────────────────────────
local quickbar = mk("Frame", {
	Name = "Quickbar",
	Size = UDim2.new(1, 0, 0, 34),
	Position = UDim2.new(0, 0, 0, 44),
	BackgroundColor3 = THEME.bg,
	BorderSizePixel = 0,
}, root)

local function quickButton(text, xPos, width)
	return mk("TextButton", {
		Size = UDim2.new(0, width, 1, -10),
		Position = UDim2.new(0, xPos, 0, 5),
		BackgroundColor3 = THEME.panel2,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextSize = 11,
		TextColor3 = THEME.textDim,
		AutoButtonColor = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, quickbar)
end

local explainBtn = quickButton("✨ Объяснить", 10, 96)
local fixBtn = quickButton("🛠 Починить", 110, 96)
local modeBtn = quickButton("Режим: Агент", 210, 96)
local newChatBtn = quickButton("🗑 Новый чат", 310, 96)
for _, b in ipairs({ explainBtn, fixBtn, modeBtn, newChatBtn }) do
	addCorner(b, 6)
end
mk("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = THEME.border, BorderSizePixel = 0 }, quickbar)

-- ── Область чата ────────────────────────────────────────────────────
local CONTENT_TOP = 78
local INPUT_H = 108

local chatScroll = mk("ScrollingFrame", {
	Name = "Chat",
	Position = UDim2.new(0, 0, 0, CONTENT_TOP),
	Size = UDim2.new(1, 0, 1, -(CONTENT_TOP + INPUT_H)),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = THEME.border,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, root)
mk("UIListLayout", {
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, chatScroll)
mk("UIPadding", {
	PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
}, chatScroll)

-- ── Настройки (панель поверх чата) ──────────────────────────────────
local settingsFrame = mk("ScrollingFrame", {
	Name = "Settings",
	Position = UDim2.new(0, 0, 0, CONTENT_TOP),
	Size = UDim2.new(1, 0, 1, -(CONTENT_TOP + INPUT_H)),
	BackgroundColor3 = THEME.bg,
	BorderSizePixel = 0,
	Visible = false,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, root)
mk("UIPadding", {
	PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
}, settingsFrame)
mk("UIListLayout", {
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, settingsFrame)

local inputArea = mk("Frame", {
	Name = "Input",
	Position = UDim2.new(0, 0, 1, -INPUT_H),
	Size = UDim2.new(1, 0, 0, INPUT_H),
	BackgroundColor3 = THEME.panel,
	BorderSizePixel = 0,
}, root)
mk("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = THEME.border, BorderSizePixel = 0 }, inputArea)

local promptBox = mk("TextBox", {
	Position = UDim2.new(0, 10, 0, 10),
	Size = UDim2.new(1, -20, 0, 56),
	BackgroundColor3 = THEME.bg,
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	Text = "",
	PlaceholderText = "Опиши, что сделать. Enter — отправить, Shift+Enter — новая строка",
	PlaceholderColor3 = THEME.textFaint,
	TextSize = 13,
	TextColor3 = THEME.text,
	TextWrapped = true,
	MultiLine = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ClearTextOnFocus = false,
}, inputArea)
addCorner(promptBox, 8)
mk("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, promptBox)

local sendBtn = mk("TextButton", {
	Position = UDim2.new(1, -102, 0, 74),
	Size = UDim2.new(0, 92, 0, 26),
	BackgroundColor3 = THEME.accent,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "Отправить ▶",
	TextSize = 12,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	AutoButtonColor = true,
}, inputArea)
addCorner(sendBtn, 6)

local stopBtn = mk("TextButton", {
	Position = UDim2.new(1, -102, 0, 74),
	Size = UDim2.new(0, 92, 0, 26),
	BackgroundColor3 = Color3.fromRGB(120, 40, 46),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "■ Стоп",
	TextSize = 12,
	TextColor3 = Color3.fromRGB(255, 210, 210),
	Visible = false,
	AutoButtonColor = true,
}, inputArea)
addCorner(stopBtn, 6)

local hintLabel = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 74),
	Size = UDim2.new(1, -120, 0, 26),
	Font = Enum.Font.Gotham,
	Text = "",
	TextSize = 10,
	TextColor3 = THEME.textFaint,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, inputArea)

---------------------------------------------------------------------
-- Пузыри чата
---------------------------------------------------------------------
local function scrollToBottom()
	chatScroll.CanvasPosition = Vector2.new(0, math.max(0, chatScroll.AbsoluteCanvasSize.Y))
end

local BUBBLE_STYLE = {
	user    = { bg = THEME.user,    bar = THEME.accent,   title = "Вы",    titleColor = Color3.fromRGB(150, 160, 200) },
	agent   = { bg = THEME.agent,   bar = THEME.accent2,  title = "Arena", titleColor = THEME.accent2 },
	sys     = { bg = THEME.sys,     bar = THEME.border,   title = "система", titleColor = THEME.textFaint },
	err     = { bg = THEME.err,     bar = Color3.fromRGB(200, 70, 70), title = "ошибка", titleColor = THEME.errText },
	ops     = { bg = THEME.sys,     bar = Color3.fromRGB(90, 200, 140), title = "применено", titleColor = THEME.okText },
}

local function trimBubbles()
	local kids = {}
	for _, ch in ipairs(chatScroll:GetChildren()) do
		if ch:IsA("Frame") and ch.Name == "Bubble" then
			kids[#kids + 1] = ch
		end
	end
	while #kids > MAX_BUBBLES do
		kids[1]:Destroy()
		table.remove(kids, 1)
	end
end

local function addBubble(kind, text, plainFont)
	local style = BUBBLE_STYLE[kind] or BUBBLE_STYLE.sys
	state.order = state.order + 1

	local frame = mk("Frame", {
		Name = "Bubble",
		BackgroundColor3 = style.bg,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = state.order,
	}, chatScroll)
	addCorner(frame, 8)
	mk("UIPadding", {
		PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10),
	}, frame)
	mk("Frame", {
		BackgroundColor3 = style.bar,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
	}, frame)

	mk("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 13),
		Font = Enum.Font.GothamBold,
		Text = string.upper(style.title),
		TextSize = 9,
		TextColor3 = style.titleColor,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)

	mk("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 15),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = plainFont and Enum.Font.Code or Enum.Font.Gotham,
		Text = text,
		RichText = not plainFont,
		TextSize = 12,
		TextColor3 = kind == "err" and THEME.errText or THEME.text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)

	trimBubbles()
	scrollToBottom()
	return frame
end

local function addSys(text) addBubble("sys", text, false) end

local function addOpsBubble(res)
	local lines = {}
	for _, a in ipairs(res.applied or {}) do
		lines[#lines + 1] = "✔ " .. a
	end
	for _, e in ipairs(res.errors or {}) do
		lines[#lines + 1] = "✘ " .. tostring(e.path ~= "" and (e.path .. ": ") or "") .. tostring(e.error)
	end
	for _, w in ipairs(res.warnings or {}) do
		lines[#lines + 1] = "… " .. tostring(w)
	end
	if #lines == 0 then return end
	local txt = table.concat(lines, "\n")
	-- plainFont (моно) и без RichText — чтобы пути читались
	local frame = addBubble("ops", txt, true)
	frame.Name = "Bubble"
	scrollToBottom()
end

---------------------------------------------------------------------
-- История и системный промпт → запросы
---------------------------------------------------------------------
local function trimHistory()
	local h = state.history
	local startIdx = math.max(1, #h - HISTORY_MAX_ENTRIES + 1)
	local total = 0
	for i = #h, startIdx, -1 do
		total = total + #tostring(h[i].content)
		if total > HISTORY_MAX_CHARS then
			startIdx = math.max(1, i)
			break
		end
	end
	local out = {}
	for i = startIdx, #h do out[#out + 1] = h[i] end
	return out
end

local function buildResultJSON(res)
	local json = HttpService:JSONEncode(res)
	if #json <= 45000 then return json end
	-- слишком жирно — убираем тяжёлые поля
	local light = {
		ok = res.ok,
		applied = res.applied,
		errors = res.errors,
		warnings = res.warnings,
		sources = {},
		properties = res.properties,
		children = res.children,
	}
	for k, v in pairs(res.sources or {}) do
		light.sources[k] = "(источник длиной " .. tostring(#v) .. " символов — уже был получен выше)"
	end
	return HttpService:JSONEncode(light)
end

---------------------------------------------------------------------
-- Основной цикл агента
---------------------------------------------------------------------
local function setStatus(text, kind)
	statusLabel.Text = text
	local c = Color3.fromRGB(120, 220, 150)
	if kind == "busy" then c = THEME.accent end
	if kind == "err" then c = Color3.fromRGB(230, 90, 90) end
	statusDot.BackgroundColor3 = c
end

local provider = PROVIDERS[settings.providerIndex] or PROVIDERS[1]

local function refreshHint()
	hintLabel.Text = provider.label .. " · " .. tostring(settings.model ~= "" and settings.model or "(модель из настроек bridge)")
end

local function sendTurn(userText)
	if state.running then return end
	if trim(userText) == "" then return end

	state.running = true
	state.stopRequested = false
	sendBtn.Visible = false
	stopBtn.Visible = true

	addBubble("user", escapeRich(userText))
	state.history[#state.history + 1] = { role = "user", content = userText }

	task.spawn(function()
		local maxIter = settings.maxIter
		local iter = 0
		local aborted = false

		while iter < maxIter do
			iter = iter + 1
			setStatus("Думаю " .. tostring(iter) .. "/" .. tostring(maxIter) .. "…", "busy")
			if state.stopRequested then
				aborted = true
				break
			end

			local sysText = buildSystemPrompt()
			local messages = { { role = "system", content = sysText } }
			for _, m in ipairs(trimHistory()) do
				messages[#messages + 1] = { role = m.role, content = m.content }
			end

			local ok, text = callModel(messages, sysText, settings)

			if state.stopRequested then
				aborted = true
				break
			end
			if not ok then
				addBubble("err", "Ошибка запроса: " .. escapeRich(preview(text, 700)) .. "\n" .. errorHint(text))
				setStatus("Ошибка", "err")
				break
			end

			if settings.showRaw then
				addSys("RAW ответ модели:\n" .. preview(text, 1200))
			end

			-- Режим «Только чат»
			if settings.mode == "chat" then
				addBubble("agent", escapeRich(text))
				state.history[#state.history + 1] = { role = "assistant", content = text }
				break
			end

			local data = extractJSON(text)

			if not data then
				addBubble("err", "Модель вернула не-JSON (нужен {\"reply\", \"ops\", \"done\"}). Сырой ответ:\n" .. escapeRich(preview(text, 800)))
				state.history[#state.history + 1] = { role = "assistant", content = text }
				state.history[#state.history + 1] = { role = "user", content = 'ARENA_RESULT: {"error":"твой предыдущий ответ был не валидным JSON. Отвечай РОВНО одним JSON-объектом {reply, ops, done} без markdown и текста вокруг."}' }
				setStatus("Ретрай JSON…", "busy")
				-- продолжим цикл (новая итерация)
			else
				local reply = tostring(data.reply or "")
				if reply ~= "" then
					addBubble("agent", escapeRich(reply))
				end
				state.history[#state.history + 1] = { role = "assistant", content = text }

				local res = { ok = true, applied = {}, errors = {}, warnings = {}, sources = {}, properties = {}, children = {} }
				local ops = {}
				if type(data.ops) == "table" and #data.ops > 0 then ops = data.ops end

				if #ops > 0 then
					setStatus("Применяю правки…", "busy")
					local applyOK, applyErr = pcall(applyOps, ops, res)
					if not applyOK then
						res.errors[#res.errors + 1] = { op = "apply", error = "краш при применении: " .. tostring(applyErr) }
					end
					addOpsBubble(res)
					pcall(function() ChangeHistoryService:SetWaypoint(WAYPOINT_NAME) end)
				end

				local resJSON = buildResultJSON(res)
				state.history[#state.history + 1] = { role = "user", content = "ARENA_RESULT:\n" .. resJSON }

				local noOpsAndNoDone = (#ops == 0 and data.done == nil)
				local done = (data.done == true) or noOpsAndNoDone

				if state.stopRequested then
					aborted = true
					break
				end
				if done then break end
				if iter >= maxIter then
					addSys("Лимит авто-итераций (" .. tostring(maxIter) .. "). Напишите «продолжай» или увеличьте лимит в ⚙.")
					break
				end
				setStatus("Продолжаю…", "busy")
			end

			task.wait(0.05)
		end

		if aborted then
			addSys("⏹ Остановлено.")
		end
		state.running = false
		state.stopRequested = false
		stopBtn.Visible = false
		sendBtn.Visible = true
		setStatus("Готов", "ok")	end)
end

---------------------------------------------------------------------
-- Панель настроек
---------------------------------------------------------------------
local function settingsRow(title)
	local row = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = state.order + 1000,
	}, settingsFrame)
	state.order = state.order + 1
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.42, 0, 1, 0),
		Font = Enum.Font.GothamMedium,
		Text = title,
		TextSize = 12,
		TextColor3 = THEME.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	return row
end

local function settingsInput(row, placeholder, onChanged)
	local box = mk("TextBox", {
		Position = UDim2.new(0.42, 0, 0, 0),
		Size = UDim2.new(0.58, 0, 1, 0),
		BackgroundColor3 = THEME.panel2,
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		Text = "",
		PlaceholderText = placeholder or "",
		PlaceholderColor3 = THEME.textFaint,
		TextSize = 11,
		TextColor3 = THEME.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
	addCorner(box, 5)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, box)
	box.FocusLost:Connect(function()
		onChanged(box.Text)
	end)
	return box
end

-- заголовок
mk("TextLabel", {
	Size = UDim2.new(1, 0, 0, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "НАСТРОЙКИ · v" .. VERSION,
	TextSize = 12,
	TextColor3 = THEME.text,
	TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder = 1,
}, settingsFrame)

-- провайдер: ◀ [label] ▶
local provRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = 2 }, settingsFrame)
local provPrev = mk("TextButton", { Size = UDim2.new(0, 24, 1, 0), BackgroundColor3 = THEME.panel2, BorderSizePixel = 0, Font = Enum.Font.GothamBold, Text = "◀", TextSize = 11, TextColor3 = THEME.textDim }, provRow)
addCorner(provPrev, 5)
local provLabel = mk("TextLabel", { Position = UDim2.new(0, 28, 0, 0), Size = UDim2.new(1, -56, 1, 0), BackgroundColor3 = THEME.panel2, BorderSizePixel = 0, Font = Enum.Font.GothamBold, Text = provider.label, TextSize = 12, TextColor3 = THEME.text }, provRow)
addCorner(provLabel, 5)
local provNext = mk("TextButton", { Position = UDim2.new(1, -24, 0, 0), Size = UDim2.new(0, 24, 1, 0), BackgroundColor3 = THEME.panel2, BorderSizePixel = 0, Font = Enum.Font.GothamBold, Text = "▶", TextSize = 11, TextColor3 = THEME.textDim }, provRow)
addCorner(provNext, 5)

local provHint = mk("TextLabel", {
	Size = UDim2.new(1, 0, 0, 14),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = provider.hint,
	TextSize = 10,
	TextColor3 = THEME.textFaint,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	LayoutOrder = 3,
}, settingsFrame)

local endpointRow = settingsRow("Endpoint")
local endpointBox = settingsInput(endpointRow, "https://…/v1", function(v)
	settings.endpoint = trim(v)
	saveSettings()
end)

local modelRow = settingsRow("Модель")
local modelBox = settingsInput(modelRow, "модель", function(v)
	settings.model = trim(v)
	saveSettings()
	refreshHint()
end)

local keyRow = settingsRow("API-ключ")
local keyBox = settingsInput(keyRow, "не хранится нигде кроме Studio", function(v)
	settings.apiKey = trim(v)
	saveSettings()
end)

local tempRow = settingsRow("Температура")
local tempBox = settingsInput(tempRow, "0.3", function(v)
	settings.temperature = math.clamp(tonumber(v) or 0.3, 0, 2)
	saveSettings()
end)

local iterRow = settingsRow("Макс. итераций")
local iterBox = settingsInput(iterRow, "6", function(v)
	settings.maxIter = math.clamp(math.floor(tonumber(v) or 6), 1, 12)
	saveSettings()
end)

local function makeCheckbox(title, getOrder, onToggle)
	local btn = mk("TextButton", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = THEME.panel2,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Text = title,
		TextSize = 11,
		TextColor3 = THEME.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = getOrder(),
	}, settingsFrame)
	addCorner(btn, 5)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 8) }, btn)
	btn.MouseButton1Click:Connect(function()
		onToggle(btn)
	end)
	return btn
end

local ctxBtn = makeCheckbox("[x] Контекст: снимок места", function() return 10 end, function(btn)
	settings.contextEnabled = not settings.contextEnabled
	btn.Text = settings.contextEnabled and "[x] Контекст: снимок места" or "[  ] Контекст: снимок места"
	saveSettings()
end)
local jsonBtn = makeCheckbox("[  ] JSON-mode запроса (OpenAI-совм.)", function() return 11 end, function(btn)
	settings.jsonMode = not settings.jsonMode
	btn.Text = settings.jsonMode and "[x] JSON-mode запроса (OpenAI-совм.)" or "[  ] JSON-mode запроса (OpenAI-совм.)"
	saveSettings()
end)
local rawBtn = makeCheckbox("[  ] Показывать сырой ответ модели", function() return 12 end, function(btn)
	settings.showRaw = not settings.showRaw
	btn.Text = settings.showRaw and "[x] Показывать сырой ответ модели" or "[  ] Показывать сырой ответ модели"
	saveSettings()
end)

mk("TextLabel", {
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Ключ хранится локально в настройках Studio (plugin:SetSetting) и уходит только на выбранный провайдер. Undo правок агента — Ctrl+Z.",
	TextSize = 10,
	TextColor3 = THEME.textFaint,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	LayoutOrder = 13,
}, settingsFrame)

local function applyProviderPreset()
	provider = PROVIDERS[settings.providerIndex] or PROVIDERS[1]
	settings.endpoint = provider.endpoint
	settings.model = provider.model
	provLabel.Text = provider.label
	provHint.Text = provider.hint
	endpointBox.Text = settings.endpoint
	modelBox.Text = settings.model
	refreshHint()
	saveSettings()
end

provPrev.MouseButton1Click:Connect(function()
	settings.providerIndex = ((settings.providerIndex - 2) % #PROVIDERS) + 1
	applyProviderPreset()
end)
provNext.MouseButton1Click:Connect(function()
	settings.providerIndex = (settings.providerIndex % #PROVIDERS) + 1
	applyProviderPreset()
end)

local function syncSettingsUI()
	provider = PROVIDERS[settings.providerIndex] or PROVIDERS[1]
	provLabel.Text = provider.label
	provHint.Text = provider.hint
	endpointBox.Text = settings.endpoint
	modelBox.Text = settings.model
	keyBox.Text = settings.apiKey
	tempBox.Text = tostring(settings.temperature)
	iterBox.Text = tostring(settings.maxIter)
	ctxBtn.Text = settings.contextEnabled and "[x] Контекст: снимок места" or "[  ] Контекст: снимок места"
	jsonBtn.Text = settings.jsonMode and "[x] JSON-mode запроса (OpenAI-совм.)" or "[  ] JSON-mode запроса (OpenAI-совм.)"
	rawBtn.Text = settings.showRaw and "[x] Показывать сырой ответ модели" or "[  ] Показывать сырой ответ модели"
	modeBtn.Text = settings.mode == "agent" and "Режим: Агент" or "Режим: Чат"
	refreshHint()
end

---------------------------------------------------------------------
-- События UI
---------------------------------------------------------------------
local settingsVisible = false
gearBtn.MouseButton1Click:Connect(function()
	settingsVisible = not settingsVisible
	settingsFrame.Visible = settingsVisible
	chatScroll.Visible = not settingsVisible
	if settingsVisible then syncSettingsUI() end
end)

sendBtn.MouseButton1Click:Connect(function()
	local text = promptBox.Text
	promptBox.Text = ""
	sendTurn(text)
end)

stopBtn.MouseButton1Click:Connect(function()
	state.stopRequested = true
	setStatus("Останавливаюсь…", "busy")
end)

promptBox.FocusLost:Connect(function(enterPressed)
	if enterPressed and not game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.LeftShift) then
		local text = promptBox.Text
		promptBox.Text = ""
		sendTurn(text)
	end
end)

modeBtn.MouseButton1Click:Connect(function()
	settings.mode = (settings.mode == "agent") and "chat" or "agent"
	modeBtn.Text = settings.mode == "agent" and "Режим: Агент" or "Режим: Чат"
	saveSettings()
	addSys(settings.mode == "agent"
		and "Режим АГЕНТ: модель отвечает JSON-планом и правит место."
		or "Режим ЧАТ: просто болтаем и советуем, без правок места.")
end)

newChatBtn.MouseButton1Click:Connect(function()
	if state.running then
		addSys("Нельзя очищать чат, пока агент работает.")
		return
	end
	state.history = {}
	for _, ch in ipairs(chatScroll:GetChildren()) do
		if ch:IsA("Frame") and ch.Name == "Bubble" then ch:Destroy() end
	end
	pcall(function() plugin:SetSetting("ArenaAgentChat_v1", nil) end)
	addSys("🗑 Новый диалог. История очищена, место не тронуто.")
end)

explainBtn.MouseButton1Click:Connect(function()
	sendTurn("Объясни, что делает выделенное в Studio (объекты и код скриптов). Кратко и по делу.")
end)

fixBtn.MouseButton1Click:Connect(function()
	sendTurn("Проверь выделенные скрипты: найди баги, логические ошибки и утечки; исправь их, не переписывая лишнего. Сначала посмотри код через get_source.")
end)

---------------------------------------------------------------------
-- Запуск
---------------------------------------------------------------------
widgetRef = widget
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleBtn:SetActive(widget.Enabled)
end)

local unloadingConn = plugin.Unloading:Connect(function()
	saveSettings()
	saveChat()
end)

-- Приветствие / восстановление сессии
loadChat()
if #state.history == 0 then
	addSys("✦ Arena Agent " .. VERSION .. " готов.\n\n1. Нажмите ⚙ и выберите провайдера + API-ключ.\n2. Опишите задачу: «сделай магазин на GUI», «добавь двойной прыжок», «построй спавн с партами».\n3. Агент сам создаст скрипты и объекты прямо в этом месте (Undo — Ctrl+Z).\n\nКнопки сверху: Объяснить / Починить выделенное, режим Агент↔Чат.")
else
	addSys("Восстановлен прошлый диалог (" .. tostring(#state.history) .. " сообщений). «Новый чат» — чтобы начать с чистого листа.")
	for _, m in ipairs(state.history) do
		if m.role == "user" and not m.content:find("^ARENA_RESULT") then
			addBubble("user", escapeRich(preview(m.content, 400)))
		end
	end
	addSys("История восстановлена. Продолжайте или начните новый диалог.")
end

syncSettingsUI()
refreshHint()
setStatus("Готов", "ok")

if rawget(_G, "ARENA_TEST_HOOK") then
	_G.ArenaTest = {
		splitPath = splitPath, resolvePath = resolvePath,
		coerceValue = coerceValue, encodeValue = encodeValue,
		extractJSON = extractJSON, execOp = execOp, applyOps = applyOps,
		buildSnapshot = buildSnapshot, buildSystemPrompt = buildSystemPrompt,
		buildSelectionText = buildSelectionText, callModel = callModel,
		sendTurn = sendTurn, trimHistory = trimHistory,
		settings = settings, state = state, PROVIDERS = PROVIDERS,
	}
end
end) -- конец pcall: инициализация под защитой

if initOK then
	print("[ArenaAgent] v" .. VERSION .. ": готов. Кнопка — вкладка Plugins, секция «Arena AI» → «Arena Agent». Если панели нет — см. Output.")
else
	warn("[ArenaAgent] v" .. VERSION .. ": ОШИБКА ИНИЦИАЛИЗАЦИИ → " .. tostring(initErr))
end
