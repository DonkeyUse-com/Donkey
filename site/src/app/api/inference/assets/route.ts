import { NextResponse } from "next/server";

import {
  createGenerationRecord,
  generationResponse,
  listGenerationRecords,
  markGenerationFailed,
  updateGenerationFromProvider,
} from "@/lib/inference/records";
import { createProviderRegistry } from "@/lib/inference/router";
import {
  requireInferenceClientId,
  validationErrorResponse,
} from "@/lib/inference/responses";
import { assetGenerationRequestSchema } from "@/lib/inference/schemas";
import { toJsonValue } from "@/lib/inference/json";
import { InferenceProviderError } from "@/lib/inference/providers";
import { withDonkeyAuth } from "@/lib/donkey-api-auth";

export const dynamic = "force-dynamic";

export const GET = withDonkeyAuth(async (request) => {
  const client = requireInferenceClientId(request.donkey.clientId);
  if (!client.ok) {
    return client.response;
  }

  const records = await listGenerationRecords(client.clientId);
  return NextResponse.json({
    data: records.map((record) => generationResponse(record)),
  });
});

export const POST = withDonkeyAuth(async (request) => {
  const client = requireInferenceClientId(request.donkey.clientId);
  if (!client.ok) {
    return client.response;
  }

  const parsed = assetGenerationRequestSchema.safeParse(await request.json());
  if (!parsed.success) {
    return validationErrorResponse(parsed.error);
  }

  const registry = createProviderRegistry();
  const provider = registry.assetProvider(parsed.data);
  const record = await createGenerationRecord({
    clientId: client.clientId,
    provider: provider.id,
    request: parsed.data,
  });

  try {
    const result = await provider.generateAsset?.({
      generationId: record.id,
      request: parsed.data,
    });

    if (!result) {
      throw new InferenceProviderError("Provider cannot generate assets.", {
        statusCode: 400,
        code: "asset_generation_unavailable",
      });
    }

    const updated = await updateGenerationFromProvider(record.id, result);
    return NextResponse.json(
      generationResponse(updated, { inlineOutputs: result.outputs }),
      { status: 201 },
    );
  } catch (error) {
    const failed = await markGenerationFailed({
      id: record.id,
      provider: provider.id,
      model: parsed.data.model,
      error: toJsonValue(
        error instanceof InferenceProviderError
          ? {
              code: error.code,
              message: error.message,
              details: error.details,
            }
          : {
              message: error instanceof Error ? error.message : "Unknown error",
            },
      ),
    });

    if (error instanceof InferenceProviderError) {
      return NextResponse.json(
        {
          ...generationResponse(failed),
          error: {
            code: error.code,
            message: error.message,
            details: error.details,
          },
        },
        { status: error.statusCode },
      );
    }

    throw error;
  }
});
