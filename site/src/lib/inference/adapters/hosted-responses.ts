import OpenAI, { APIError } from "openai";
import type { ResponseCreateParamsNonStreaming } from "openai/resources/responses/responses";

import {
  ensureConfigured,
  type FetchLike,
} from "@/lib/inference/http";
import { toJsonValue } from "@/lib/inference/json";
import {
  InferenceProviderError,
  type InferenceModality,
  type InferenceModel,
  type InferenceProvider,
  type JsonObject,
  type JsonValue,
  type ResponseCreateRequest,
  type ResponseCreateResult,
} from "@/lib/inference/providers";

type AdapterEnvironment = Record<string, string | undefined>;
type HostedResponsesProvider = "openai" | "openrouter";

const providerID = "hosted-responses";
const openAIBaseURL = "https://api.openai.com/v1";
const openRouterBaseURL = "https://openrouter.ai/api/v1";
const geminiComputerToolTypes = new Set([
  "donkey_gemini_browser_interaction",
  "donkey_gemini_mac_desktop_interaction",
]);

export function createHostedResponsesProvider(
  environment: AdapterEnvironment = process.env,
  fetcher: FetchLike = fetch,
): InferenceProvider {
  const openAIKey = environment.OPENAI_API_KEY?.trim() ?? "";
  const openRouterKey = environment.OPENROUTER_API_KEY?.trim() ?? "";
  const configured = openAIKey.length > 0 || openRouterKey.length > 0;

  async function listModels(modalities: InferenceModality[]) {
    const requested = modalities.length > 0 ? modalities : ["text"];
    if (!requested.includes("text")) {
      return [];
    }

    const models: InferenceModel[] = [];
    if (openAIKey) {
      models.push(staticModel("openai", openAIModel(environment), openAIBaseURL));
    }
    if (openRouterKey) {
      models.push(staticModel("openrouter", openRouterModel(environment), openRouterBaseURL));
    }
    return models;
  }

  async function createResponse(
    request: ResponseCreateRequest,
  ): Promise<ResponseCreateResult> {
    ensureConfigured(configured);

    const selected = selectedProvider(request, environment, {
      openAIKey,
      openRouterKey,
    });
    if (selected.provider === "openrouter" && isComputerToolRequest(request.body)) {
      throw new InferenceProviderError(
        "OpenRouter Responses computer use is not supported.",
        {
          statusCode: 400,
          code: "openrouter_computer_unsupported",
          details: {
            supportedProviders: ["gemini", "openai"],
            geminiTools: [...geminiComputerToolTypes],
          },
        },
      );
    }

    const client = new OpenAI({
      apiKey: selected.apiKey,
      baseURL: selected.baseURL,
      defaultHeaders: selected.defaultHeaders,
      fetch: fetcher,
    });

    try {
      const body = requestBody(request.body, selected.model);
      const response = await client.responses.create(
        body as unknown as ResponseCreateParamsNonStreaming,
      );
      const value = toJsonValue(response);
      return {
        provider: selected.provider,
        model: selected.model,
        body: value,
        usage: usageFromResponse(value),
        metadata: {
          provider: selected.provider,
          baseURL: selected.baseURL,
          store: String(body.store ?? false),
        },
      };
    } catch (error) {
      throw providerError("Responses API request failed.", error);
    }
  }

  return {
    id: providerID,
    configured,
    capabilities: ["text", "image"],
    responseProviderIDs: ["openai", "openrouter"],
    canCreateResponse: (request) => !isGeminiComputerToolRequest(request.body),
    listModels,
    createResponse,
  };
}

function selectedProvider(
  request: ResponseCreateRequest,
  environment: AdapterEnvironment,
  keys: { openAIKey: string; openRouterKey: string },
) {
  const requested = request.donkeyProvider ?? defaultProvider(environment, keys);
  if (requested === "openai") {
    ensureProviderKey("openai", keys.openAIKey);
    return {
      provider: "openai" as const,
      apiKey: keys.openAIKey,
      baseURL: openAIBaseURL,
      defaultHeaders: undefined,
      model: requestedModel(request.body, openAIModel(environment)),
    };
  }

  if (requested !== "openrouter") {
    throw new InferenceProviderError("Requested Responses provider is not supported by this adapter.", {
      statusCode: 400,
      code: "unsupported_responses_provider",
      details: { provider: requested },
    });
  }

  ensureProviderKey("openrouter", keys.openRouterKey);
  return {
    provider: "openrouter" as const,
    apiKey: keys.openRouterKey,
    baseURL: openRouterBaseURL,
    defaultHeaders: openRouterHeaders(environment),
    model: requestedModel(request.body, openRouterModel(environment)),
  };
}

function defaultProvider(
  environment: AdapterEnvironment,
  keys: { openAIKey: string; openRouterKey: string },
): HostedResponsesProvider {
  const configured = environment.DONKEY_RESPONSES_PROVIDER?.trim().toLowerCase();
  if (configured === "openai" || configured === "openrouter") {
    return configured;
  }
  return keys.openAIKey ? "openai" : "openrouter";
}

function ensureProviderKey(provider: HostedResponsesProvider, apiKey: string) {
  if (apiKey) {
    return;
  }
  throw new InferenceProviderError("Requested Responses provider is not configured.", {
    statusCode: 503,
    code: "missing_provider_credentials",
    details: { provider },
  });
}

function requestBody(body: JsonObject, model: string): JsonObject {
  return {
    ...body,
    model,
    stream: false,
    store: boolValue(body.store, false),
  };
}

function requestedModel(body: JsonObject, fallback: string) {
  const model = body.model;
  return typeof model === "string" && model.trim() ? model : fallback;
}

function openAIModel(environment: AdapterEnvironment) {
  return (
    environment.DONKEY_OPENAI_RESPONSES_MODEL?.trim() ||
    environment.DONKEY_RESPONSES_MODEL?.trim() ||
    "gpt-5.5"
  );
}

function openRouterModel(environment: AdapterEnvironment) {
  return (
    environment.DONKEY_OPENROUTER_RESPONSES_MODEL?.trim() ||
    environment.DONKEY_RESPONSES_MODEL?.trim() ||
    "openai/gpt-5.5"
  );
}

function openRouterHeaders(environment: AdapterEnvironment) {
  const headers: Record<string, string> = {};
  const referer = environment.DONKEY_INFERENCE_HTTP_REFERER?.trim();
  const title = environment.DONKEY_INFERENCE_TITLE?.trim();
  if (referer) {
    headers["HTTP-Referer"] = referer;
  }
  if (title) {
    headers["X-Title"] = title;
  }
  return Object.keys(headers).length > 0 ? headers : undefined;
}

function staticModel(
  provider: HostedResponsesProvider,
  model: string,
  baseURL: string,
): InferenceModel {
  return {
    id: model,
    name: model,
    provider,
    inputModalities: ["text", "image"],
    outputModalities: ["text"],
    contextLength: null,
    pricing: null,
    metadata: {
      provider,
      baseURL,
      api: "responses",
    },
  };
}

function isComputerToolRequest(body: JsonObject) {
  const tools = body.tools;
  if (!Array.isArray(tools)) {
    return false;
  }

  return tools.some((tool) => {
    if (!isJsonObject(tool)) {
      return false;
    }
    return (
      tool.type === "computer" ||
      tool.type === "computer_use_preview" ||
      (typeof tool.type === "string" && geminiComputerToolTypes.has(tool.type))
    );
  });
}

function isGeminiComputerToolRequest(body: JsonObject) {
  const tools = body.tools;
  if (!Array.isArray(tools)) {
    return false;
  }

  return tools.some((tool) => {
    return (
      isJsonObject(tool) &&
      typeof tool.type === "string" &&
      geminiComputerToolTypes.has(tool.type)
    );
  });
}

function usageFromResponse(value: JsonValue): JsonValue | undefined {
  if (!isJsonObject(value)) {
    return undefined;
  }
  return value.usage;
}

function boolValue(value: JsonValue | undefined, fallback: boolean) {
  return typeof value === "boolean" ? value : fallback;
}

function isJsonObject(value: JsonValue): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function providerError(message: string, error: unknown) {
  if (error instanceof APIError) {
    return new InferenceProviderError(message, {
      statusCode: error.status ?? 502,
      code: error.code ?? "provider_error",
      details: {
        body: toJsonValue(error.error ?? {}),
        requestID: error.requestID ?? null,
        status: error.status ?? null,
        type: error.type ?? null,
      },
    });
  }

  return new InferenceProviderError(message, {
    details: {
      message: error instanceof Error ? error.message : "Unknown error",
    },
  });
}
