import assert from "node:assert/strict";
import test from "node:test";

import { createWorker } from "../src/index.js";

const ORIGIN = "https://worker.example";
const ENV = {
  CLIENT_AUTH_TOKEN: "client-token-for-tests",
  MACOSICONS_API_KEY: "upstream-key-for-tests",
};

function request(path, init = {}) {
  return new Request(`${ORIGIN}${path}`, init);
}

function authorizedHeaders(extra = {}) {
  return {
    authorization: `Bearer ${ENV.CLIENT_AUTH_TOKEN}`,
    ...extra,
  };
}

function searchRequest(body, extraHeaders = {}) {
  return request("/search", {
    method: "POST",
    headers: authorizedHeaders({ "content-type": "application/json", ...extraHeaders }),
    body: JSON.stringify(body),
  });
}

test("health requires the bearer token and returns the exact contract", async () => {
  const worker = createWorker();

  const missing = await worker.fetch(request("/health"), ENV);
  assert.equal(missing.status, 401);

  const incorrect = await worker.fetch(request("/health", {
    headers: { authorization: "Bearer incorrect" },
  }), ENV);
  assert.equal(incorrect.status, 401);

  const valid = await worker.fetch(request("/health", {
    headers: authorizedHeaders(),
  }), ENV);
  assert.equal(valid.status, 200);
  assert.deepEqual(await valid.json(), { ok: true, version: 1 });
  assert.equal(valid.headers.has("access-control-allow-origin"), false);
});

test("search rejects missing authentication before reading the body", async () => {
  let calls = 0;
  const worker = createWorker({ fetchImpl: async () => {
    calls += 1;
    return Response.json({ hits: [] });
  } });

  const response = await worker.fetch(request("/search", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "not-json",
  }), ENV);

  assert.equal(response.status, 401);
  assert.equal(calls, 0);
});

test("search validates content type, fields, bounds, and body size", async () => {
  const worker = createWorker({ fetchImpl: async () => {
    assert.fail("validation errors must not reach the upstream");
  } });

  const wrongType = await worker.fetch(request("/search", {
    method: "POST",
    headers: authorizedHeaders({ "content-type": "text/plain" }),
    body: "{}",
  }), ENV);
  assert.equal(wrongType.status, 415);

  const clientKey = await worker.fetch(searchRequest({
    apiKey: "must-not-be-accepted",
    query: "Safari",
    searchOptions: {},
  }), ENV);
  assert.equal(clientKey.status, 400);
  assert.match((await clientKey.json()).details.join(" "), /unknown_field_apiKey/);

  const invalidOptions = await worker.fetch(searchRequest({
    query: "Safari",
    searchOptions: { hitsPerPage: 101, page: 0, filters: new Array(21).fill("x") },
  }), ENV);
  assert.equal(invalidOptions.status, 400);
  assert.equal((await invalidOptions.json()).details.length, 3);

  const oversized = await worker.fetch(request("/search", {
    method: "POST",
    headers: authorizedHeaders({ "content-type": "application/json" }),
    body: JSON.stringify({ query: "x".repeat(17_000), searchOptions: {} }),
  }), ENV);
  assert.equal(oversized.status, 413);
});

test("search uses only the server-side upstream key and forwards validated options", async () => {
  let captured;
  const upstreamPayload = { hits: [{ appName: "Safari" }], totalHits: 1 };
  const worker = createWorker({ fetchImpl: async (url, init) => {
    captured = { url, init };
    return Response.json(upstreamPayload);
  } });

  const response = await worker.fetch(searchRequest({
    query: "  Safari  ",
    searchOptions: {
      hitsPerPage: 50,
      page: 2,
      offset: 50,
      filters: ["category:Browser"],
      sort: ["downloads:desc"],
    },
  }), ENV);

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), upstreamPayload);
  assert.equal(captured.url, "https://api.macosicons.com/api/search");
  assert.equal(captured.init.headers["x-api-key"], ENV.MACOSICONS_API_KEY);
  assert.equal(captured.init.headers.authorization, undefined);
  assert.deepEqual(JSON.parse(captured.init.body), {
    query: "Safari",
    searchOptions: {
      hitsPerPage: 50,
      page: 2,
      offset: 50,
      filters: ["category:Browser"],
      sort: ["downloads:desc"],
    },
  });
  assert.doesNotMatch(captured.init.body, /upstream-key-for-tests|client-token-for-tests/);
  assert.equal(response.headers.has("access-control-allow-origin"), false);
});

test("search works without KV and maps upstream failures without exposing their body", async () => {
  const worker = createWorker({ fetchImpl: async () => new Response("secret diagnostic", { status: 429 }) });
  const response = await worker.fetch(searchRequest({ query: "Safari", searchOptions: {} }), ENV);
  assert.equal(response.status, 429);
  assert.deepEqual(await response.json(), { error: "upstream_request_failed" });
});

test("optional KV caches successful JSON responses", async () => {
  const values = new Map();
  const writes = [];
  const cache = {
    async get(key) {
      return values.get(key) ?? null;
    },
    async put(key, value, options) {
      values.set(key, value);
      writes.push({ key, value, options });
    },
  };
  let upstreamCalls = 0;
  const worker = createWorker({ fetchImpl: async () => {
    upstreamCalls += 1;
    return Response.json({ hits: [], call: upstreamCalls });
  } });
  const env = { ...ENV, SEARCH_CACHE: cache, SEARCH_CACHE_TTL_SECONDS: "600" };

  const first = await worker.fetch(searchRequest({ query: "Finder", searchOptions: {} }), env);
  assert.equal(first.headers.get("x-cache"), "MISS");
  assert.deepEqual(await first.json(), { hits: [], call: 1 });
  assert.equal(writes.length, 1);
  assert.equal(writes[0].options.expirationTtl, 600);

  const second = await worker.fetch(searchRequest({ query: "Finder", searchOptions: {} }), env);
  assert.equal(second.headers.get("x-cache"), "HIT");
  assert.deepEqual(await second.json(), { hits: [], call: 1 });
  assert.equal(upstreamCalls, 1);
});
