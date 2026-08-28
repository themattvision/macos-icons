const UPSTREAM_SEARCH_URL = "https://api.macosicons.com/api/search";
const MAX_BODY_BYTES = 16 * 1024;
const MAX_UPSTREAM_BYTES = 4 * 1024 * 1024;
const DEFAULT_CACHE_TTL_SECONDS = 3600;

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

export function createWorker({ fetchImpl = fetch } = {}) {
  return {
    async fetch(request, env = {}) {
      const url = new URL(request.url);

      if (url.pathname === "/health") {
        if (request.method !== "GET") {
          return methodNotAllowed("GET");
        }
        if (!(await isAuthorized(request, env.CLIENT_AUTH_TOKEN))) {
          return json({ error: "unauthorized" }, 401);
        }
        return json({ ok: true, version: 1 });
      }

      if (url.pathname === "/search") {
        if (request.method !== "POST") {
          return methodNotAllowed("POST");
        }
        if (!(await isAuthorized(request, env.CLIENT_AUTH_TOKEN))) {
          return json({ error: "unauthorized" }, 401);
        }
        return handleSearch(request, env, fetchImpl);
      }

      return json({ error: "not_found" }, 404);
    },
  };
}

async function handleSearch(request, env, fetchImpl) {
  if (!isNonEmptyString(env.MACOSICONS_API_KEY)) {
    return json({ error: "upstream_not_configured" }, 503);
  }

  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().startsWith("application/json")) {
    return json({ error: "content_type_must_be_json" }, 415);
  }

  let body;
  try {
    body = await readJson(request, MAX_BODY_BYTES);
  } catch (error) {
    if (error instanceof RequestTooLargeError) {
      return json({ error: "request_too_large" }, 413);
    }
    return json({ error: "invalid_json" }, 400);
  }

  const validation = validateSearchBody(body);
  if (!validation.ok) {
    return json({ error: "invalid_request", details: validation.errors }, 400);
  }

  const upstreamBody = validation.value;
  const cache = optionalCache(env.SEARCH_CACHE);
  const cacheKey = cache ? await makeCacheKey(upstreamBody) : null;

  if (cache && cacheKey) {
    try {
      const cached = await cache.get(cacheKey, "text");
      if (cached !== null) {
        return jsonText(cached, 200, "HIT");
      }
    } catch {
      // The cache is an optimization. A KV outage must not stop searches.
    }
  }

  let upstreamResponse;
  try {
    upstreamResponse = await fetchImpl(UPSTREAM_SEARCH_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": env.MACOSICONS_API_KEY,
      },
      body: JSON.stringify(upstreamBody),
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    return json({ error: "upstream_unavailable" }, 502);
  }

  if (!upstreamResponse.ok) {
    const status = normalizeUpstreamStatus(upstreamResponse.status);
    return json({ error: "upstream_request_failed" }, status);
  }

  let upstreamText;
  try {
    upstreamText = await readResponseText(upstreamResponse, MAX_UPSTREAM_BYTES);
    JSON.parse(upstreamText);
  } catch (error) {
    if (error instanceof ResponseTooLargeError) {
      return json({ error: "upstream_response_too_large" }, 502);
    }
    return json({ error: "upstream_invalid_response" }, 502);
  }

  if (cache && cacheKey) {
    try {
      await cache.put(cacheKey, upstreamText, {
        expirationTtl: cacheTtl(env.SEARCH_CACHE_TTL_SECONDS),
      });
    } catch {
      // Searches remain available when KV writes fail.
    }
  }

  return jsonText(upstreamText, 200, cache ? "MISS" : null);
}

async function isAuthorized(request, expectedToken) {
  if (!isNonEmptyString(expectedToken)) {
    return false;
  }

  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return false;
  }

  const suppliedToken = authorization.slice("Bearer ".length);
  if (!suppliedToken) {
    return false;
  }

  return constantTimeEqual(suppliedToken, expectedToken);
}

async function constantTimeEqual(left, right) {
  const encoder = new TextEncoder();
  const [leftHash, rightHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  const leftBytes = new Uint8Array(leftHash);
  const rightBytes = new Uint8Array(rightHash);
  let difference = 0;
  for (let index = 0; index < leftBytes.length; index += 1) {
    difference |= leftBytes[index] ^ rightBytes[index];
  }
  return difference === 0;
}

async function readJson(request, maximumBytes) {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new RequestTooLargeError();
  }

  const buffer = await request.arrayBuffer();
  if (buffer.byteLength > maximumBytes) {
    throw new RequestTooLargeError();
  }
  return JSON.parse(new TextDecoder().decode(buffer));
}

async function readResponseText(response, maximumBytes) {
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new ResponseTooLargeError();
  }

  const buffer = await response.arrayBuffer();
  if (buffer.byteLength > maximumBytes) {
    throw new ResponseTooLargeError();
  }
  return new TextDecoder().decode(buffer);
}

function validateSearchBody(body) {
  const errors = [];
  if (!isPlainObject(body)) {
    return { ok: false, errors: ["body_must_be_an_object"] };
  }

  rejectUnknownKeys(body, ["query", "searchOptions"], "body", errors);

  let query = "";
  if (typeof body.query !== "string") {
    errors.push("query_must_be_a_string");
  } else {
    query = body.query.trim();
    if (query.length > 200) {
      errors.push("query_is_too_long");
    }
  }

  let searchOptions = {};
  if (body.searchOptions !== undefined) {
    if (!isPlainObject(body.searchOptions)) {
      errors.push("searchOptions_must_be_an_object");
    } else {
      searchOptions = validateSearchOptions(body.searchOptions, errors);
    }
  }

  if (errors.length > 0) {
    return { ok: false, errors };
  }
  return { ok: true, value: { query, searchOptions } };
}

function validateSearchOptions(options, errors) {
  const allowedKeys = ["hitsPerPage", "page", "offset", "filters", "sort"];
  rejectUnknownKeys(options, allowedKeys, "searchOptions", errors);

  const result = {};
  copyBoundedInteger(options, result, "hitsPerPage", 1, 100, errors);
  copyBoundedInteger(options, result, "page", 1, 1000, errors);
  copyBoundedInteger(options, result, "offset", 0, 100_000, errors);
  copyStringArray(options, result, "filters", 20, 200, errors);
  copyStringArray(options, result, "sort", 5, 100, errors);
  return result;
}

function copyBoundedInteger(source, destination, key, minimum, maximum, errors) {
  if (source[key] === undefined) {
    return;
  }
  if (!Number.isInteger(source[key]) || source[key] < minimum || source[key] > maximum) {
    errors.push(`${key}_must_be_an_integer_between_${minimum}_and_${maximum}`);
    return;
  }
  destination[key] = source[key];
}

function copyStringArray(source, destination, key, maximumItems, maximumLength, errors) {
  if (source[key] === undefined) {
    return;
  }
  const value = source[key];
  if (!Array.isArray(value) || value.length > maximumItems) {
    errors.push(`${key}_must_be_an_array_with_at_most_${maximumItems}_items`);
    return;
  }
  if (value.some((item) => typeof item !== "string" || item.length > maximumLength)) {
    errors.push(`${key}_items_must_be_strings_up_to_${maximumLength}_characters`);
    return;
  }
  destination[key] = value;
}

function rejectUnknownKeys(object, allowedKeys, prefix, errors) {
  const allowed = new Set(allowedKeys);
  for (const key of Object.keys(object)) {
    if (!allowed.has(key)) {
      errors.push(`${prefix}_contains_unknown_field_${key}`);
    }
  }
}

function optionalCache(candidate) {
  return candidate && typeof candidate.get === "function" && typeof candidate.put === "function"
    ? candidate
    : null;
}

async function makeCacheKey(body) {
  const serialized = JSON.stringify(body);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(serialized));
  const hex = [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return `search:v1:${hex}`;
}

function cacheTtl(value) {
  const parsed = Number(value);
  if (Number.isInteger(parsed) && parsed >= 60 && parsed <= 86_400) {
    return parsed;
  }
  return DEFAULT_CACHE_TTL_SECONDS;
}

function normalizeUpstreamStatus(status) {
  return Number.isInteger(status) && status >= 400 && status <= 599 ? status : 502;
}

function methodNotAllowed(allowedMethod) {
  const response = json({ error: "method_not_allowed" }, 405);
  response.headers.set("allow", allowedMethod);
  return response;
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS });
}

function jsonText(value, status, cacheStatus) {
  const headers = new Headers(JSON_HEADERS);
  if (cacheStatus) {
    headers.set("x-cache", cacheStatus);
  }
  return new Response(value, { status, headers });
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.length > 0;
}

class RequestTooLargeError extends Error {}
class ResponseTooLargeError extends Error {}

export default createWorker();
