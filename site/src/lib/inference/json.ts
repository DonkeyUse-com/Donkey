import type { JsonObject, JsonValue } from "@/lib/inference/providers";

export function toJsonValue(value: unknown): JsonValue {
  if (value === undefined) {
    return null;
  }

  return JSON.parse(JSON.stringify(value)) as JsonValue;
}

export function toJsonObject(value: unknown): JsonObject {
  const json = toJsonValue(value);
  if (json && typeof json === "object" && !Array.isArray(json)) {
    return json;
  }

  return {};
}

export function isJsonObject(value: JsonValue): value is JsonObject {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

export async function readJson(response: Response): Promise<JsonValue> {
  const text = await response.text();
  if (!text) {
    return {};
  }

  try {
    return toJsonValue(JSON.parse(text));
  } catch {
    return {
      raw: text.slice(0, 4_000),
    };
  }
}

export async function readProviderError(response: Response): Promise<JsonValue> {
  const body = await readJson(response);
  return {
    status: response.status,
    statusText: response.statusText,
    body,
  };
}
