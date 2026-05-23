import {
  ApiError,
  Environment,
  GoogleGenAI,
  Type,
} from "@google/genai";
import type {
  Content,
  FunctionDeclaration,
  GenerateContentConfig,
  GenerateContentParameters,
  GoogleGenAIOptions,
  Tool,
} from "@google/genai";

import { ensureConfigured } from "@/lib/inference/http";
import {
  isJsonObject,
  toJsonObject,
  toJsonValue,
} from "@/lib/inference/json";
import {
  InferenceProviderError,
  type ChatCompletionRequest,
  type InferenceModality,
  type InferenceModel,
  type InferenceProvider,
  type JsonObject,
  type JsonValue,
  type ResponseCreateRequest,
  type ResponseCreateResult,
  type TextCompletionResult,
} from "@/lib/inference/providers";

type AdapterEnvironment = Record<string, string | undefined>;
type GeminiClient = Pick<GoogleGenAI, "models">;
type GeminiClientFactory = (options: GoogleGenAIOptions) => GeminiClient;

const providerID = "gemini-computer-use";
const geminiProviderID = "gemini";
const defaultResponsesModel = "gemini-2.5-flash";
const defaultComputerUseModel = "gemini-2.5-computer-use-preview-10-2025";
type GeminiProviderService = "vertex-ai" | "gemini-api";

export const geminiBrowserInteractionToolType = "donkey_gemini_browser_interaction";
export const geminiMacDesktopInteractionToolType = "donkey_gemini_mac_desktop_interaction";

const browserOnlyFunctionExclusions = [
  "drag_and_drop",
];

const macDesktopFunctionExclusions = [
  "open_web_browser",
  "search",
  "navigate",
  "go_back",
  "go_forward",
  "hover_at",
  "scroll_document",
  "drag_and_drop",
];

export function createGeminiComputerUseProvider(
  environment: AdapterEnvironment = process.env,
  clientFactory: GeminiClientFactory = (options) => new GoogleGenAI(options),
): InferenceProvider {
  const clientConfig = geminiClientConfig(environment);
  const configured = clientConfig.configured;

  async function listModels(modalities: InferenceModality[]) {
    const requested = modalities.length > 0 ? modalities : ["text"];
    if (!requested.includes("text") && !requested.includes("image")) {
      return [];
    }

    return [
      staticModel(geminiResponsesModel(environment), false),
      staticModel(geminiComputerUseModel(environment), true),
    ];
  }

  async function createResponse(
    request: ResponseCreateRequest,
  ): Promise<ResponseCreateResult> {
    ensureConfigured(configured);

    const registeredTools = registeredToolTypes(request.body.tools);
    if (hasExplicitUnsupportedTools(request.body.tools)) {
      throw new InferenceProviderError("Gemini Responses received unsupported tool declarations.", {
        statusCode: 400,
        code: "gemini_tool_unsupported",
        details: {
          supportedTools: [
            geminiBrowserInteractionToolType,
            geminiMacDesktopInteractionToolType,
          ],
        },
      });
    }

    const model = requestedModel(
      request.body,
      registeredTools.length > 0
        ? geminiComputerUseModel(environment)
        : geminiResponsesModel(environment),
    );
    const requestParameters = geminiGenerateContentParameters(
      request.body,
      registeredTools,
      model,
    );
    const client = clientFactory(clientConfig.options);

    let rawResponse: unknown;
    try {
      rawResponse = await client.models.generateContent(requestParameters);
    } catch (error) {
      throw geminiProviderError(error);
    }

    const rawBody = toJsonValue(rawResponse);
    const body = normalizedGeminiResponse(toJsonValue(rawBody), registeredTools);
    return {
      provider: geminiProviderID,
      model,
      body,
      usage: isJsonObject(body) ? body.usage : undefined,
      metadata: {
        provider: geminiProviderID,
        api: "google-genai-sdk",
        service: clientConfig.service,
        registeredTools,
      },
    };
  }

  async function completeText(
    request: ChatCompletionRequest,
  ): Promise<TextCompletionResult> {
    ensureConfigured(configured);

    const model = requestedChatModel(request, geminiResponsesModel(environment));
    const body = toJsonObject(request);
    const requestParameters: GenerateContentParameters = {
      model,
      contents: contentsFromInput(toJsonValue(request.messages)),
      config: generationConfigFromBody(body),
    };
    const client = clientFactory(clientConfig.options);

    let rawResponse: unknown;
    try {
      rawResponse = await client.models.generateContent(requestParameters);
    } catch (error) {
      throw geminiProviderError(error);
    }

    const rawBody = toJsonValue(rawResponse);
    const normalized = normalizedGeminiResponse(rawBody, []);
    const outputText = stringValue(normalized.output_text) ?? "";
    return {
      provider: geminiProviderID,
      model,
      body: chatCompletionBody(rawBody, model, outputText),
      usage: isJsonObject(rawBody) ? rawBody.usageMetadata ?? null : undefined,
      metadata: {
        provider: geminiProviderID,
        api: "google-genai-sdk",
        service: clientConfig.service,
      },
    };
  }

  return {
    id: providerID,
    configured,
    capabilities: ["text", "image"],
    responseProviderIDs: [geminiProviderID],
    canCreateResponse: (request) => {
      return !hasExplicitUnsupportedTools(request.body.tools);
    },
    listModels,
    completeText,
    createResponse,
  };
}

function geminiGenerateContentParameters(
  body: JsonObject,
  registeredTools: string[],
  model: string,
): GenerateContentParameters {
  const tools = geminiTools(registeredTools, body.tools);
  const generationConfig = generationConfigFromBody(body);
  const systemInstruction = systemInstructionFromBody(body, registeredTools);
  const config: GenerateContentConfig = {
    ...generationConfig,
  };
  if (tools.length > 0) {
    config.tools = tools;
  }
  if (systemInstruction) {
    config.systemInstruction = systemInstruction;
  }

  return {
    model,
    contents: contentsFromInput(body.input),
    config,
  };
}

function geminiTools(registeredTools: string[], rawTools: JsonValue | undefined): Tool[] {
  const tools: Tool[] = [];
  const hasBrowser = registeredTools.includes(geminiBrowserInteractionToolType);
  const hasMacDesktop = registeredTools.includes(geminiMacDesktopInteractionToolType);

  if (hasBrowser || hasMacDesktop) {
    tools.push({
      computerUse: {
        environment: Environment.ENVIRONMENT_BROWSER,
        excludedPredefinedFunctions: excludedPredefinedFunctions(rawTools, [
          ...(hasBrowser ? browserOnlyFunctionExclusions : []),
          ...(hasMacDesktop ? macDesktopFunctionExclusions : []),
        ]),
      },
    });
  }

  if (hasMacDesktop) {
    tools.push({
      functionDeclarations: [macDesktopInteractionDeclaration()],
    });
  }

  return tools;
}

function macDesktopInteractionDeclaration(): FunctionDeclaration {
  return {
    name: geminiMacDesktopInteractionToolType,
    description: [
      "Request a guarded macOS desktop interaction through Donkey.",
      "Use this only for non-browser Mac desktop UI work.",
      "Coordinates are normalized integers from 0 to 1000 relative to the latest screenshot.",
      "The Mac client validates focus, safety, and permissions before execution.",
    ].join(" "),
    parameters: {
      type: Type.OBJECT,
      properties: {
        action: {
          type: Type.STRING,
          enum: [
            "open_app",
            "focus_app",
            "click_at",
            "type_text_at",
            "key_combination",
            "scroll_at",
            "wait_5_seconds",
            "observe",
          ],
        },
        app_name: {
          type: Type.STRING,
          description: "The visible app name when the action targets a specific Mac app.",
        },
        x: {
          type: Type.INTEGER,
          description: "Normalized x coordinate from 0 to 1000.",
        },
        y: {
          type: Type.INTEGER,
          description: "Normalized y coordinate from 0 to 1000.",
        },
        text: {
          type: Type.STRING,
          description: "Text to type for type_text_at.",
        },
        keys: {
          type: Type.ARRAY,
          items: { type: Type.STRING },
          description: "Key names for key_combination, such as COMMAND, SHIFT, A, or ENTER.",
        },
        direction: {
          type: Type.STRING,
          enum: ["up", "down", "left", "right"],
        },
        amount: {
          type: Type.INTEGER,
          description: "Scroll or movement amount in normalized units.",
        },
        reason: {
          type: Type.STRING,
          description: "Short reason for the requested desktop action.",
        },
      },
      required: ["action"],
    },
  };
}

function contentsFromInput(input: JsonValue | undefined): Content[] {
  if (typeof input === "string") {
    return [
      {
        role: "user",
        parts: [{ text: input }],
      },
    ];
  }

  if (!Array.isArray(input)) {
    return [];
  }

  return input.map((item) => {
    if (!isJsonObject(item)) {
      return {
        role: "user",
        parts: [partFromValue(item)],
      };
    }

    return {
      role: geminiRole(stringValue(item.role)),
      parts: partsFromContent(item.content ?? item.parts ?? item),
    };
  }) as Content[];
}

function partsFromContent(content: JsonValue): JsonObject[] {
  if (Array.isArray(content)) {
    return content.map(partFromValue);
  }

  return [partFromValue(content)];
}

function partFromValue(value: JsonValue): JsonObject {
  if (typeof value === "string") {
    return { text: value };
  }

  if (!isJsonObject(value)) {
    return { text: JSON.stringify(value) };
  }

  if (isJsonObject(value.functionResponse)) {
    return { functionResponse: value.functionResponse };
  }

  if (isJsonObject(value.function_response)) {
    return { functionResponse: value.function_response };
  }

  if (isJsonObject(value.functionCall)) {
    return { functionCall: value.functionCall };
  }

  if (isJsonObject(value.function_call)) {
    return { functionCall: value.function_call };
  }

  if (value.type === "function_response") {
    return functionResponsePart(value);
  }

  if (value.type === "input_image" || value.type === "image") {
    return imagePart(value);
  }

  const text = stringValue(value.text);
  if (text) {
    return { text };
  }

  return { text: JSON.stringify(value) };
}

function imagePart(value: JsonObject): JsonObject {
  const mimeType = stringValue(value.mime_type) || stringValue(value.mimeType) || "image/png";
  const base64 = stringValue(value.image_base64) || stringValue(value.dataBase64);
  if (base64) {
    return {
      inlineData: {
        mimeType,
        data: base64,
      },
    };
  }

  const imageURL = stringValue(value.image_url) || stringValue(value.url);
  if (imageURL?.startsWith("data:")) {
    const inline = dataURLToInlineData(imageURL);
    if (inline) {
      return inline;
    }
  }

  if (imageURL) {
    return {
      fileData: {
        mimeType,
        fileUri: imageURL,
      },
    };
  }

  return { text: JSON.stringify(value) };
}

function functionResponsePart(value: JsonObject): JsonObject {
  const name = stringValue(value.name) || "unknown_function";
  const response = isJsonObject(value.response) ? value.response : {};
  const screenshotBase64 =
    stringValue(value.screenshotBase64) ||
    (isJsonObject(value.screenshot) ? stringValue(value.screenshot.base64) : undefined);
  const mimeType =
    stringValue(value.mimeType) ||
    stringValue(value.mime_type) ||
    (isJsonObject(value.screenshot) ? stringValue(value.screenshot.mimeType) : undefined) ||
    "image/png";

  const functionResponse: JsonObject = {
    name,
    response,
  };
  if (screenshotBase64) {
    functionResponse.parts = [
      {
        inlineData: {
          mimeType,
          data: screenshotBase64,
        },
      },
    ];
  }

  return { functionResponse };
}

function dataURLToInlineData(value: string): JsonObject | null {
  const match = /^data:([^;,]+);base64,(.+)$/u.exec(value);
  if (!match) {
    return null;
  }

  return {
    inlineData: {
      mimeType: match[1],
      data: match[2],
    },
  };
}

function generationConfigFromBody(body: JsonObject): Partial<GenerateContentConfig> {
  const config: Partial<GenerateContentConfig> = {};
  const temperature = numberValue(body.temperature);
  if (temperature !== undefined) {
    config.temperature = temperature;
  }

  const topP = numberValue(body.top_p) ?? numberValue(body.topP);
  if (topP !== undefined) {
    config.topP = topP;
  }

  const maxOutputTokens = numberValue(body.max_output_tokens) ?? numberValue(body.maxOutputTokens);
  if (maxOutputTokens !== undefined) {
    config.maxOutputTokens = maxOutputTokens;
  }
  const responseFormat = responseFormatFromBody(body);
  if (responseFormat?.json) {
    config.responseMimeType = "application/json";
    if (responseFormat.schema) {
      config.responseJsonSchema = responseFormat.schema;
    }
  }

  return config;
}

function responseFormatFromBody(body: JsonObject): { json: boolean; schema?: JsonObject } | null {
  const format =
    isJsonObject(body.text) && isJsonObject(body.text.format)
      ? body.text.format
      : isJsonObject(body.response_format)
        ? body.response_format
        : null;
  if (!format) {
    return null;
  }

  const type = stringValue(format.type);
  if (type === "json_schema") {
    return {
      json: true,
      schema: isJsonObject(format.schema) ? format.schema : undefined,
    };
  }
  if (type === "json_object") {
    return { json: true };
  }

  return null;
}

function systemInstructionFromBody(
  body: JsonObject,
  registeredTools: string[],
): string | undefined {
  const instruction = [
    stringValue(body.instructions),
    registeredTools.includes(geminiMacDesktopInteractionToolType)
      ? [
          "When operating Mac desktop apps, use the donkey_gemini_mac_desktop_interaction function.",
          "Do not assume the action was executed; the Mac client will return function responses after guarded execution.",
        ].join(" ")
      : undefined,
  ].filter(Boolean).join("\n\n");

  if (!instruction) {
    return undefined;
  }

  return instruction;
}

function normalizedGeminiResponse(
  raw: JsonValue,
  registeredTools: string[],
): JsonObject {
  const candidates = isJsonObject(raw) && Array.isArray(raw.candidates)
    ? raw.candidates
    : [];
  const firstCandidate = candidates.find(isJsonObject);
  const parts =
    firstCandidate &&
    isJsonObject(firstCandidate.content) &&
    Array.isArray(firstCandidate.content.parts)
      ? firstCandidate.content.parts
      : [];
  const textParts = parts
    .filter(isJsonObject)
    .map((part) => stringValue(part.text))
    .filter((part): part is string => Boolean(part));
  const calls = parts
    .filter(isJsonObject)
    .map(functionCallFromPart)
    .filter((part): part is JsonObject => Boolean(part));

  return {
    id: stringValue(isJsonObject(raw) ? raw.responseId : undefined) ?? `gemini-${Date.now()}`,
    object: "response",
    output_text: textParts.join("\n").trim(),
    output: [
      {
        type: "message",
        role: "assistant",
        content: textParts.map((text) => ({
          type: "output_text",
          text,
        })),
      },
      ...calls.map((call) => ({
        type: "function_call",
        ...call,
      })),
    ],
    computer_use: {
      registered_tools: registeredTools,
      calls,
    },
    provider_output: raw,
    usage: isJsonObject(raw) ? raw.usageMetadata ?? null : null,
  };
}

function functionCallFromPart(part: JsonObject): JsonObject | null {
  const value = isJsonObject(part.functionCall)
    ? part.functionCall
    : isJsonObject(part.function_call)
      ? part.function_call
      : null;
  if (!value) {
    return null;
  }

  return {
    id: stringValue(value.id) ?? `call-${Math.random().toString(36).slice(2)}`,
    name: stringValue(value.name) ?? "unknown_function",
    arguments: isJsonObject(value.args) ? value.args : {},
  };
}

function registeredToolTypes(tools: JsonValue | undefined): string[] {
  if (!Array.isArray(tools)) {
    return [];
  }

  const registered = new Set<string>();
  for (const tool of tools) {
    if (!isJsonObject(tool)) {
      continue;
    }
    if (tool.type === geminiBrowserInteractionToolType) {
      registered.add(geminiBrowserInteractionToolType);
    }
    if (tool.type === geminiMacDesktopInteractionToolType) {
      registered.add(geminiMacDesktopInteractionToolType);
    }
  }
  return [...registered];
}

function excludedPredefinedFunctions(rawTools: JsonValue | undefined, defaults: string[]) {
  const excluded = new Set(defaults);
  if (Array.isArray(rawTools)) {
    for (const tool of rawTools) {
      if (!isJsonObject(tool)) {
        continue;
      }
      const values = Array.isArray(tool.excludedPredefinedFunctions)
        ? tool.excludedPredefinedFunctions
        : Array.isArray(tool.excluded_predefined_functions)
          ? tool.excluded_predefined_functions
          : [];
      for (const value of values) {
        if (typeof value === "string" && value.trim()) {
          excluded.add(value.trim());
        }
      }
    }
  }
  return [...excluded];
}

function geminiRole(value: string | undefined) {
  return value === "assistant" || value === "model" ? "model" : "user";
}

function requestedModel(body: JsonObject, fallback: string) {
  const model = body.model;
  return typeof model === "string" && model.trim() ? model : fallback;
}

function requestedChatModel(request: ChatCompletionRequest, fallback: string) {
  return request.model?.trim() || request.models?.[0]?.trim() || fallback;
}

function geminiResponsesModel(environment: AdapterEnvironment) {
  return (
    environment.GEMINI_RESPONSES_MODEL?.trim() ||
    defaultResponsesModel
  );
}

function geminiComputerUseModel(environment: AdapterEnvironment) {
  return (
    environment.GEMINI_COMPUTER_MODEL?.trim() ||
    defaultComputerUseModel
  );
}

function geminiAPIKey(environment: AdapterEnvironment) {
  return (
    environment.GEMINI_API_KEY?.trim() ||
    environment.GOOGLE_API_KEY?.trim() ||
    ""
  );
}

function geminiClientConfig(environment: AdapterEnvironment): {
  configured: boolean;
  options: GoogleGenAIOptions;
  service: GeminiProviderService;
} {
  const apiVersion = environment.GEMINI_API_VERSION?.trim() || undefined;
  const timeout = numberFromString(environment.GEMINI_TIMEOUT_MS);
  const httpOptions: GoogleGenAIOptions["httpOptions"] | undefined =
    timeout === undefined ? undefined : { timeout };
  const project =
    environment.GOOGLE_CLOUD_PROJECT?.trim() ||
    environment.GCLOUD_PROJECT?.trim() ||
    undefined;
  const location =
    environment.GOOGLE_CLOUD_LOCATION?.trim() ||
    environment.GOOGLE_CLOUD_REGION?.trim() ||
    undefined;
  const apiKey = geminiAPIKey(environment);
  const service = geminiProviderService(environment, {
    hasAPIKey: apiKey.length > 0,
    hasVertexSignal: Boolean(project || location),
  });

  if (service === "vertex-ai") {
    const options: GoogleGenAIOptions = {
      vertexai: true,
    };
    if (project) {
      options.project = project;
    }
    if (location) {
      options.location = location;
    }
    if (apiVersion) {
      options.apiVersion = apiVersion;
    }
    if (httpOptions) {
      options.httpOptions = httpOptions;
    }

    return {
      configured: Boolean(project && location),
      options,
      service: "vertex-ai",
    };
  }

  const options: GoogleGenAIOptions = {};
  if (apiKey) {
    options.apiKey = apiKey;
  }
  if (apiVersion) {
    options.apiVersion = apiVersion;
  }
  if (httpOptions) {
    options.httpOptions = httpOptions;
  }
  return {
    configured: apiKey.length > 0,
    options,
    service: "gemini-api",
  };
}

function geminiProviderService(
  environment: AdapterEnvironment,
  availability: {
    hasAPIKey: boolean;
    hasVertexSignal: boolean;
  },
): GeminiProviderService {
  const explicitMode = environment.GEMINI_PROVIDER_MODE?.trim().toLowerCase();
  if (
    explicitMode === "api-key" ||
    explicitMode === "gemini-api" ||
    isDisabled(environment.GOOGLE_GENAI_USE_VERTEXAI)
  ) {
    return "gemini-api";
  }

  if (
    explicitMode === "vertex-ai" ||
    explicitMode === "vertex" ||
    isEnabled(environment.GOOGLE_GENAI_USE_VERTEXAI) ||
    availability.hasVertexSignal
  ) {
    return "vertex-ai";
  }

  return availability.hasAPIKey ? "gemini-api" : "vertex-ai";
}

function geminiProviderError(error: unknown) {
  if (error instanceof ApiError) {
    return new InferenceProviderError("Gemini request failed.", {
      statusCode: error.status,
      code: "provider_error",
      details: {
        status: error.status,
        message: error.message,
      },
    });
  }

  return new InferenceProviderError("Gemini request failed.", {
    details: {
      message: error instanceof Error ? error.message : "Unknown error",
    },
  });
}

function chatCompletionBody(
  raw: JsonValue,
  model: string,
  outputText: string,
): JsonObject {
  return {
    id: stringValue(isJsonObject(raw) ? raw.responseId : undefined) ?? `gemini-${Date.now()}`,
    object: "chat.completion",
    model,
    choices: [
      {
        index: 0,
        message: {
          role: "assistant",
          content: outputText,
        },
        finish_reason: "stop",
      },
    ],
    usage: isJsonObject(raw) ? raw.usageMetadata ?? null : null,
    provider_output: raw,
  };
}

function hasExplicitUnsupportedTools(
  tools: JsonValue | undefined,
) {
  if (!Array.isArray(tools)) {
    return false;
  }

  return tools.some((tool) => {
    if (!isJsonObject(tool)) {
      return true;
    }
    return tool.type !== geminiBrowserInteractionToolType &&
      tool.type !== geminiMacDesktopInteractionToolType;
  });
}

function staticModel(model: string, computerUse: boolean): InferenceModel {
  return {
    id: model,
    name: model,
    provider: geminiProviderID,
    inputModalities: ["text", "image"],
    outputModalities: ["text"],
    contextLength: 128_000,
    pricing: null,
    metadata: {
      provider: geminiProviderID,
      api: "generateContent",
      ...(computerUse
        ? {
            computerUse,
            registeredTools: [
              geminiBrowserInteractionToolType,
              geminiMacDesktopInteractionToolType,
            ],
          }
        : { structuredOutputs: true }),
    },
  };
}

function stringValue(value: JsonValue | undefined): string | undefined {
  return typeof value === "string" && value.trim() ? value : undefined;
}

function numberValue(value: JsonValue | undefined): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function numberFromString(value: string | undefined): number | undefined {
  if (!value?.trim()) {
    return undefined;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : undefined;
}

function isEnabled(value: string | undefined) {
  return value?.trim().toLowerCase() === "true";
}

function isDisabled(value: string | undefined) {
  return value?.trim().toLowerCase() === "false";
}
