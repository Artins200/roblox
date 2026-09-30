#!/usr/bin/env node
/**
 * mock-server.mjs — фейковый OpenAI-совместимый провайдер для проверки
 * связки «Studio-плагин → bridge» без реального API-ключа.
 *
 * Терминал 1:  node mock-server.mjs
 * Терминал 2:  ARENA_BRIDGE_PROVIDER=openai ARENA_BRIDGE_ENDPOINT=http://localhost:9charm...
 *
 * Короче:
 *   node mock-server.mjs
 *   ARENA_BRIDGE_PROVIDER=openai ARENA_BRIDGE_ENDPOINT=http://localhost:9999/v1 node server.mjs
 *   node test-client.mjs
 *
 * Слушает http://localhost:9999/v1/chat/completions и всегда отвечает
 * валидным JSON-планом агента с одним op (upsert_script).
 */

import http from "node:http";

const PORT = 9999;

const cannedReply = {
  reply: "Создал заготовку менеджера раунда в ServerScriptService/ArenaBuilds.",
  ops: [
    {
      op: "upsert_script",
      path: "ServerScriptService/ArenaBuilds/RoundManager",
      class: "Script",
      source: [
        "--[=[ Менеджер раунда (сгенерировано Arena Agent / mock) ]=]",
        "local Players = game:GetService('Players')",
        "",
        "local function startRound()",
        "\tprint('Раунд начался! Игроков:', #Players:GetPlayers())",
        "end",
        "",
        "startRound()",
      ].join("\n"),
    },
  ],
  done: true,
};

const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    console.log(`[mock] ${req.method} ${req.url}  (${body.length} байт)`);
    const out = JSON.stringify({
      choices: [
        {
          message: { role: "assistant", content: "```json\n" + JSON.stringify(cannedReply, null, 2) + "\n```" },
        },
      ],
    });
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(out);
  });
});

server.listen(PORT, () => {
  console.log(`[mock] фейковый OpenAI на http://localhost:${PORT}/v1/chat/completions`);
  console.log("[mock] запустите bridge так:");
  console.log(`[mock]   ARENA_BRIDGE_PROVIDER=openai ARENA_BRIDGE_ENDPOINT=http://localhost:${PORT}/v1 node server.mjs`);
});
