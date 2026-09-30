#!/usr/bin/env node
/**
 * test-client.mjs — проверка bridge без Roblox Studio.
 *
 * Отправляет демо-промпт через bridge на провайдера, печатает сырой ответ
 * и распарсенный JSON агента {reply, ops, done} — то же самое, что получил
 * бы плагин в Studio.
 *
 * Запуск:            node test-client.mjs
 * С фейковым сервером (без ключа):  node mock-server.mjs & node test-client.mjs
 */

const BRIDGE = process.env.ARENA_BRIDGE_URL || "http://localhost:8787";

const DEMO_PROMPT = `Сделай в ServerScriptService скрипт-заготовку менеджера раунда:
папка ArenaBuilds, внутри Script RoundManager, который печатает "Раунд начался" при старте.`;

const SYSTEM = `Ты — Arena Agent в Roblox Studio. Отвечай РОВНО одним JSON-объектом:
{"reply":"...","ops":[...],"done":true}
Пример op: {"op":"upsert_script","path":"ServerScriptService/ArenaBuilds/RoundManager","class":"Script","source":"print('Раунд начался')"}`;

async function main() {
  console.log(`[test-client] bridge: ${BRIDGE}`);

  const health = await fetch(`${BRIDGE}/health`).then((r) => r.json());
  console.log("[test-client] health:", JSON.stringify(health, null, 2));
  if (!health.ok) process.exit(1);

  console.log("\n[test-client] отправляю демо-запрос...");
  const res = await fetch(`${BRIDGE}/v1/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: process.env.ARENA_BRIDGE_MODEL || undefined,
      messages: [{ role: "user", content: DEMO_PROMPT }],
      system: SYSTEM,
      temperature: 0.2,
    }),
  }).then((r) => r.json());

  if (!res.ok) {
    console.error("[test-client] ОШИБКА:", res.error);
    process.exit(1);
  }

  console.log("\n[test-client] сырой ответ модели:\n" + "-".repeat(60));
  console.log(res.text.slice(0, 2000));
  console.log("-".repeat(60));

  // тот же разбор, что в плагине: от первой { до парной }
  const a = res.text.indexOf("{");
  let depth = 0;
  let end = -1;
  for (let i = a; i >= 0 && i < res.text.length; i++) {
    const ch = res.text[i];
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  if (a === -1 || end === -1) {
    console.error("[test-client] модель вернула не-JSON");
    process.exit(1);
  }
  const agent = JSON.parse(res.text.slice(a, end + 1));
  console.log("\n[test-client] ответ агента:");
  console.log("  reply:", agent.reply);
  console.log("  done :", agent.done);
  console.log("  ops  :", agent.ops?.length ?? 0);
  for (const op of agent.ops || []) {
    console.log(`   - ${op.op} → ${op.path || "(без пути)"}`);
    if (op.source) console.log(`     код: ${op.source.length} симв.`);
  }
  console.log("\n[test-client] ✔ протокол работает — можно подключать Studio");
}

main().catch((e) => {
  console.error("[test-client] не удалось подключиться к bridge:", e.message);
  console.error("Запустите сервер: node server.mjs");
  process.exit(1);
});
