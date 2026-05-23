import { NextResponse } from "next/server";

import { createProviderRegistry } from "@/lib/inference/router";
import {
  requireInferenceClientId,
  validationErrorResponse,
} from "@/lib/inference/responses";
import { responseCreateRequestSchema } from "@/lib/inference/schemas";
import { InferenceProviderError } from "@/lib/inference/providers";
import { withDonkeyAuth } from "@/lib/donkey-api-auth";

export const dynamic = "force-dynamic";

export const POST = withDonkeyAuth(async (request) => {
  const client = requireInferenceClientId(request.donkey.clientId);
  if (!client.ok) {
    return client.response;
  }

  const parsed = responseCreateRequestSchema.safeParse(await request.json());
  if (!parsed.success) {
    return validationErrorResponse(parsed.error);
  }

  try {
    const registry = createProviderRegistry();
    const provider = registry.responsesProvider(parsed.data);
    const result = await provider.createResponse?.(parsed.data);
    if (!result) {
      return NextResponse.json(
        {
          error: "Responses unavailable",
        },
        { status: 503 },
      );
    }

    return NextResponse.json(result.body, {
      headers: {
        "X-Donkey-Inference-Provider": result.provider,
        "X-Donkey-Inference-Model": result.model,
      },
    });
  } catch (error) {
    if (error instanceof InferenceProviderError) {
      return NextResponse.json(
        {
          error: error.code,
          message: error.message,
          details: error.details,
        },
        { status: error.statusCode },
      );
    }

    throw error;
  }
});
