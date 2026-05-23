import { NextResponse } from "next/server";

import { createProviderRegistry } from "@/lib/inference/router";
import {
  requireInferenceClientId,
  validationErrorResponse,
} from "@/lib/inference/responses";
import { chatCompletionRequestSchema } from "@/lib/inference/schemas";
import { withDonkeyAuth } from "@/lib/donkey-api-auth";

export const dynamic = "force-dynamic";

export const POST = withDonkeyAuth(async (request) => {
  const client = requireInferenceClientId(request.donkey.clientId);
  if (!client.ok) {
    return client.response;
  }

  const parsed = chatCompletionRequestSchema.safeParse(await request.json());
  if (!parsed.success) {
    return validationErrorResponse(parsed.error);
  }

  if (
    parsed.data.stream &&
    parsed.data.modalities?.some((modality) => modality !== "text")
  ) {
    return NextResponse.json(
      {
        error: "Unsupported stream",
        message: "Streaming is supported for text completions only.",
      },
      { status: 400 },
    );
  }

  const registry = createProviderRegistry();
  const provider = registry.textProvider(parsed.data.stream);

  if (parsed.data.stream) {
    const result = await provider.streamCompletion?.(parsed.data);
    if (!result) {
      return NextResponse.json(
        {
          error: "Streaming unavailable",
        },
        { status: 503 },
      );
    }

    return new Response(result.response.body, {
      status: result.response.status,
      headers: {
        "Content-Type":
          result.response.headers.get("content-type") ?? "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
        "X-Donkey-Inference-Provider": result.provider,
      },
    });
  }

  const result = await provider.completeText?.(parsed.data);
  if (!result) {
    return NextResponse.json(
      {
        error: "Completion unavailable",
      },
      { status: 503 },
    );
  }

  return NextResponse.json(result.body);
});
