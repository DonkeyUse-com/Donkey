import { createHash } from "crypto";

import { Prisma } from "@/generated/prisma/client";
import { withDownloadPath } from "@/lib/inference/download-metadata";
import { toJsonObject, toJsonValue } from "@/lib/inference/json";
import {
  type AssetGenerationKind,
  type AssetGenerationProviderResult,
  type AssetGenerationRequest,
  type GenerationOutputRef,
  type GenerationStatus,
  type JsonObject,
  type JsonValue,
  type StoredGenerationForProvider,
} from "@/lib/inference/providers";
import { prisma } from "@/lib/prisma";

type InferenceGenerationDatabaseRecord = {
  id: string;
  clientId: string;
  kind: string;
  status: string;
  provider: string;
  model: string;
  providerJobId: string | null;
  providerGenerationId: string | null;
  providerPollingUrl: string | null;
  promptPreview: string;
  requestHash: string;
  request: Prisma.JsonValue;
  outputs: Prisma.JsonValue | null;
  usage: Prisma.JsonValue | null;
  error: Prisma.JsonValue | null;
  metadata: Prisma.JsonValue;
  createdAt: Date;
  updatedAt: Date;
  completedAt: Date | null;
};

export async function createGenerationRecord(input: {
  clientId: string;
  provider: string;
  request: AssetGenerationRequest;
}) {
  return prisma.inferenceGeneration.create({
    data: {
      clientId: input.clientId,
      kind: input.request.kind,
      status: "pending",
      provider: input.provider,
      model: input.request.model,
      promptPreview: input.request.prompt.slice(0, 500),
      requestHash: requestHash(input.request),
      request: toPrismaJSON(input.request),
      metadata: toPrismaJSON(input.request.metadata ?? {}),
    },
  });
}

export async function updateGenerationFromProvider(
  id: string,
  result: AssetGenerationProviderResult,
) {
  return prisma.inferenceGeneration.update({
    where: { id },
    data: {
      status: result.status,
      provider: result.provider,
      model: result.model,
      providerJobId: result.providerJobId,
      providerGenerationId: result.providerGenerationId,
      providerPollingUrl: result.providerPollingUrl,
      outputs: toPrismaJSON(sanitizeOutputsForStorage(result.outputs)),
      usage: result.usage === undefined ? undefined : toPrismaJSON(result.usage),
      error: result.error === undefined ? undefined : toPrismaJSON(result.error),
      metadata: toPrismaJSON(result.metadata ?? {}),
      completedAt: terminalStatus(result.status) ? new Date() : null,
    },
  });
}

export async function markGenerationFailed(input: {
  id: string;
  provider: string;
  model: string;
  error: JsonValue;
}) {
  return prisma.inferenceGeneration.update({
    where: { id: input.id },
    data: {
      status: "failed",
      provider: input.provider,
      model: input.model,
      error: toPrismaJSON(input.error),
      completedAt: new Date(),
    },
  });
}

export async function listGenerationRecords(clientId: string) {
  return prisma.inferenceGeneration.findMany({
    where: { clientId },
    orderBy: { createdAt: "desc" },
    take: 50,
  });
}

export async function getGenerationRecord(id: string, clientId: string) {
  return prisma.inferenceGeneration.findFirst({
    where: {
      id,
      clientId,
    },
  });
}

export function generationResponse(
  record: InferenceGenerationDatabaseRecord,
  options: {
    inlineOutputs?: GenerationOutputRef[];
  } = {},
) {
  const outputs = (options.inlineOutputs ?? storedOutputs(record.outputs)).map((output) => {
    return withDownloadPath(record.id, output);
  });

  return {
    id: record.id,
    clientId: record.clientId,
    kind: record.kind,
    status: record.status,
    provider: record.provider,
    model: record.model,
    providerJobId: record.providerJobId,
    providerGenerationId: record.providerGenerationId,
    providerPollingUrl: record.providerPollingUrl,
    promptPreview: record.promptPreview,
    requestHash: record.requestHash,
    outputs,
    usage: record.usage,
    error: record.error,
    metadata: record.metadata,
    createdAt: record.createdAt.toISOString(),
    updatedAt: record.updatedAt.toISOString(),
    completedAt: record.completedAt?.toISOString() ?? null,
  };
}

export function storedGenerationForProvider(
  record: InferenceGenerationDatabaseRecord,
): StoredGenerationForProvider {
  return {
    id: record.id,
    kind: record.kind as AssetGenerationKind,
    provider: record.provider,
    model: record.model,
    providerJobId: record.providerJobId,
    providerGenerationId: record.providerGenerationId,
    providerPollingUrl: record.providerPollingUrl,
    outputs: storedOutputs(record.outputs),
    metadata: toJsonObject(record.metadata),
  };
}

export function outputForID(
  record: InferenceGenerationDatabaseRecord,
  outputId: string,
) {
  return storedOutputs(record.outputs).find((output) => output.id === outputId) ?? null;
}

function storedOutputs(value: Prisma.JsonValue | null): GenerationOutputRef[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((item) => {
    const object = toJsonObject(item);
    const id = typeof object.id === "string" ? object.id : null;
    const kind = typeof object.kind === "string" ? object.kind : null;
    if (!id || !kind) {
      return [];
    }

    const output: GenerationOutputRef = {
      id,
      kind: kind as GenerationOutputRef["kind"],
      metadata: readObject(object.metadata),
    };

    assignString(output, "url", object.url);
    assignString(output, "contentType", object.contentType);
    assignString(output, "filename", object.filename);
    assignNumber(output, "byteCount", object.byteCount);

    return [output];
  });
}

function sanitizeOutputsForStorage(outputs: GenerationOutputRef[]) {
  return outputs.map((output) => {
    const sanitized: GenerationOutputRef = {
      id: output.id,
      kind: output.kind,
      metadata: output.metadata,
    };
    if (output.url) {
      sanitized.url = output.url;
    }
    if (output.contentType) {
      sanitized.contentType = output.contentType;
    }
    if (output.filename) {
      sanitized.filename = output.filename;
    }
    if (output.byteCount !== undefined) {
      sanitized.byteCount = output.byteCount;
    }
    return sanitized;
  });
}

function requestHash(request: AssetGenerationRequest) {
  return createHash("sha256").update(JSON.stringify(request)).digest("hex");
}

function terminalStatus(status: GenerationStatus) {
  return status === "completed" || status === "failed" || status === "cancelled";
}

function toPrismaJSON(value: unknown) {
  return toJsonValue(value) as Prisma.InputJsonValue;
}

function readObject(value: JsonValue | undefined): JsonObject | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }

  return value;
}

function assignString<T extends keyof GenerationOutputRef>(
  output: GenerationOutputRef,
  key: T,
  value: JsonValue | undefined,
) {
  if (typeof value === "string") {
    output[key] = value as GenerationOutputRef[T];
  }
}

function assignNumber<T extends keyof GenerationOutputRef>(
  output: GenerationOutputRef,
  key: T,
  value: JsonValue | undefined,
) {
  if (typeof value === "number") {
    output[key] = value as GenerationOutputRef[T];
  }
}
