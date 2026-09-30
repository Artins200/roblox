#!/usr/bin/env node
/**
 * Arena Roblox Bridge — локальный мост между плагином ArenaAgent (Roblox Studio)
 * и LLM-провайдерами. Ноль зависимостей, Node >= 18.
 *
 * Зачем он нужен:
 *  - API-ключи хранятся на компьютере (env / config.json), а не в Studio;
 *  - удобно подменять провайдера одним переключателем;
 *  - сюда же потом подключится нативный эндпоинт arena.ai, когда он появится
 *    (провайдер "arena" уже преднастроен, URL меняется в конфиге).
 *
 * Запуск:
 *   node server.mjs                        # конфиг из env
 *   node server.mjs --config config.json   # или из файла
 *
 * Плагин: провайдер "Arena bridge" → endpoint http://localhost:8787
 *
 * API:
 *   GET  /health  → { ok, version, providers, upstream }
 *   POST /v1/chat → { model?, temperature?, messages, system? }
 *                    ответ: { ok: true, text } | { ok: false, error }
 */

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const VERSION = "1.0.0";
const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------------
// Конфигурация: config.json -> env -> дефолты
// ---------------------------------------------------------------------
function loadConfig() {
  const defaults = {
    port: 8787,
    host: "127.0.0.1",
    provider: "openai", // openai | openrouter | anthropic | arena
    endpoint: "",
    apiKey: "",
    model: "",
    maxTokens: 8000,
    timeoutMs: 240000,
  };

  // 1) config.json (рядом с server.mjs или по --config)
  const argv = process.argv.slice(2);
  const cfgIdx = argv.indexOf("--config");
  const cfgPath =
    cfgIdx !== -1 && argv[cfgIdx + 1]
      ? path.resolve(argv[cfgIdx + 1])
      : path.join(__dirname, "config.json");

  let fileCfg = {};
  try {
    fileCfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
    console.log(`[arena-bridge] конфиг: ${cfgPath}`);
  } catch {
    console.log("[arena-bridge] config.json не найден — беру настройки из env");
  }

  const cfg = { ...defaults, ...fileCfg };

  // 2) env поверх файла
  const env = process.env;
  if (env.ARENA_BRIDGE_PORT) cfg.port = Number(env.ARENA_BRIDGE_PORT);
  if (env.ARENA_BRIDGE_HOST) cfg.host = env.ARENA_BRIDGE_HOST;
  if (env.ARENA_BRIDGE_PROVIDER) cfg.provider = env.ARENA_BRIDGE_PROVIDER;
  if (env.ARENA_BRIDGE_ENDPOINT) cfg.endpoint = env.ARENA_BRIDGE_ENDPOINT;
  if (env.ARENA_BRIDGE_MODEL) cfg.model = env.ARENA_BRIDGE_MODEL;
  if (env.OPENAI_API_KEY && !cfg.apiKey) {
    if (cfg.provider === "openai" || cfg.provider === "openrouter") cfg.apiKey = env.OPENAI_API_KEY;
  }
  if (env.OPENROUTER_API_KEY && cfg.provider === "openrouter") cfg.apiKey = env.OPENROUTER_API_KEY;
  if (env.ANTHROPIC_API_KEY && cfg.provider === "anthropic") cfg.apiKey = env.ANTHROPIC_API_KEY;
  if (env.ARENA_API_KEY && cfg.provider === "arena") cfg.apiKey = env.ARENA_API_KEY;
  if (env.ARENA_ENDPOINT && cfg.provider === "arena") cfg.endpoint = env.ARENA_ENDPOINT;
  if (env.ARENA_MODEL && cfg.provider === "arena") cfg.model = env.ARENA_MODEL;

  // 3) дефолтные эндпоинты провайдеров
  const providerDefaults = {
    openai: "https://api.openai.com/v1",
    openrouter: "https://openrouter.ai/api/v1",
    anthropic: "https://api.anthropic.com/v1",
    arena: "https://api.arena.ai/v1", // placeholder — правьте под актуальный API arena.ai
  };
  if (!cfg.endpoint) cfg.endpoint = providerDefaults[cfg.provider] || providerDefaults.openai;

  return cfg;
}

const cfg = loadConfig();

// ---------------------------------------------------------------------
// Вызов провайдера
// ---------------------------------------------------------------------
async function callProvider({ model, temperature, messages, system }) {
  const provider = cfg.provider;

  let url;
  const headers = { "Content-Type": "application/json" };
  let body;

  if (provider === "anthropic") {
    url = cfg.endpoint.replace(/\/$/, "") + "/messages";
    headers["x-api-key"] = cfg.apiKey;
    headers["anthropic-version"] = "2023-06-01";
    const chatMessages = (messages || []).filter((m) => m.role !== "system");
    body = {
      model: model || cfg.model,
      max_tokens: cfg.maxTokens,
      temperature: temperature ?? 0.3,
      system: system || messages?.find?.((m) => m.role === "system")?.content || undefined,
      messages: chatMessages,
    };
  } else {
    // openai-совместимые: openai / openrouter / arena / локальные
    url = cfg.endpoint.replace(/\/$/, "") + "/chat/completions";
    if (cfg.apiKey) headers["Authorization"] = `Bearer ${cfg.apiKey}`;
    if (provider === "openrouter" || url.includes("openrouter")) {
      headers["HTTP-Referer"] = "https://arena.ai";
      headers["X-Title"] = "Arena Roblox Agent";
    }
    const msgs = (messages || []).map((m) => ({ role: m.role, content: m.content }));
    if (system && !msgs.some((m) => m.role === "system")) {
      msgs.unshift({ role: "system", content: system });
    }
    body = {
      model: model || cfg.model,
      temperature: temperature ?? 0.3,
      messages: msgs,
    };
  }

  if (!body.model) {
    throw new Error("не задана модель: укажите её в Studio или в config.json (model)");
  }

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), cfg.timeoutMs);
  try {
    const res = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      signal: ctrl.signal,
    });
    const text = await res.text();
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}: ${text.slice(0, 600)}`);
    }
    let data;
    try {
      data = JSON.parse(text);
    } catch {
      throw new Error(`ответ не JSON: ${text.slice(0, 300)}`);
    }

    if (provider === "anthropic") {
      const parts = (data.content || [])
        .filter((b) => b.type === "text")
        .map((b) => b.text);
      if (!parts.length) throw new Error(`пустой ответ Anthropic: ${text.slice(0, 300)}`);
      return parts.join("\n");
    }

    const choice = data.choices?.[0];
    const out = choice?.message?.content ?? choice?.text ?? "";
    if (!out) throw new Error(`пустой ответ модели: ${text.slice(0, 300)}`);
    return out;
  } finally {
    clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------
// HTTP-сервер
// ---------------------------------------------------------------------
function readBody(req, limitBytes = 25 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (c) => {
      size += c.length;
      if (size > limitBytes) {
        reject(new Error("тело запроса слишком большое"));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function send(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  });
  res.end(body);
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    res.end();
    return;
  }

  if (req.method === "GET" && req.url.startsWith("/health")) {
    send(res, 200, {
      ok: true,
      version: VERSION,
      providers: ["openai", "openrouter", "anthropic", "arena"],
      upstream: { provider: cfg.provider, endpoint: cfg.endpoint, model: cfg.model || "(из Studio)", key: cfg.apiKey ? "установлен" : "НЕТ КЛЮЧА" },
    });
    return;
  }

  if (req.method === "POST" && req.url.startsWith("/v1/chat")) {
    try {
      const raw = await readBody(req);
      const payload = JSON.parse(raw);
      const text = await callProvider(payload);
      send(res, 200, { ok: true, text });
    } catch (err) {
      const msg = err?.name === "AbortError" ? `таймаут провайдера (${cfg.timeoutMs} мс)` : String(err?.message || err);
      console.error(`[arena-bridge] ошибка: ${msg}`);
      send(res, 200, { ok: false, error: msg });
    }
    return;
  }

  send(res, 404, { ok: false, error: "неизвестный путь (есть GET /health и POST /v1/chat)" });
});

server.listen(cfg.port, cfg.host, () => {
  console.log(`[arena-bridge] v${VERSION} слушает http://${cfg.host}:${cfg.port}`);
  console.log(`[arena-bridge] провайдер: ${cfg.provider} → ${cfg.endpoint}`);
  console.log(`[arena-bridge] ключ: ${cfg.apiKey ? "установлен" : "НЕТ — укажите apiKey в config.json или env"}`);
  console.log(`[arena-bridge] модель по умолчанию: ${cfg.model || "(берётся из Studio)"}`);
  console.log("[arena-bridge] В Studio: провайдер «Arena bridge», endpoint http://localhost:" + cfg.port);
});
