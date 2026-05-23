import { NextResponse } from "next/server";

import {
  generationResponse,
  getGenerationRecord,
  storedGenerationForProvider,
  updateGenerationFromProvider,
} from "@/lib/inference/records";
import { createProviderRegistry } from "@/lib/inference/router";
import {
  requireInferenceClientId,
  validationErrorResponse,
} from "@/lib/inference/responses";
import { generationRouteParamsSchema } from "@/lib/inference/schemas";
import { withDonkeyAuth } from "@/lib/donkey-api-auth";

export const dynamic = "force-dynamic";

type RouteContext = {
  params: Promise<{
    generationId: string;
  }>;
};

export const GET = withDonkeyAuth(async (request, context: RouteContext) => {
  const client = requireInferenceClientId(request.donkey.clientId);
  if (!client.ok) {
    return client.response;
  }

  const parsedParams = generationRouteParamsSchema.safeParse(await context.params);
  if (!parsedParams.success) {
    return validationErrorResponse(parsedParams.error);
  }

  const record = await getGenerationRecord(
    parsedParams.data.generationId,
    client.clientId,
  );
  if (!record) {
    return NextResponse.json(
      {
        error: "Not found",
      },
      { status: 404 },
    );
  }

  if (record.status === "pending" || record.status === "in_progress") {
    const registry = createProviderRegistry();
    const refreshed = await registry.refresh(storedGenerationForProvider(record));
    if (refreshed) {
      const updated = await updateGenerationFromProvider(record.id, refreshed);
      return NextResponse.json(generationResponse(updated));
    }
  }

  return NextResponse.json(generationResponse(record));
});
