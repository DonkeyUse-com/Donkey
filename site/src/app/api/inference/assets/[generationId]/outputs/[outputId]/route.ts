import { filenameForOutput } from "@/lib/inference/download-metadata";
import {
  getGenerationRecord,
  outputForID,
  storedGenerationForProvider,
} from "@/lib/inference/records";
import { createProviderRegistry } from "@/lib/inference/router";
import {
  requireInferenceClientId,
  validationErrorResponse,
} from "@/lib/inference/responses";
import { outputRouteParamsSchema } from "@/lib/inference/schemas";
import { withDonkeyAuth } from "@/lib/donkey-api-auth";

export const dynamic = "force-dynamic";

type RouteContext = {
  params: Promise<{
    generationId: string;
    outputId: string;
  }>;
};

export const GET = withDonkeyAuth(async (request, context: RouteContext) => {
  const client = requireInferenceClientId(request.donkey.clientId);
  if (!client.ok) {
    return client.response;
  }

  const parsedParams = outputRouteParamsSchema.safeParse(await context.params);
  if (!parsedParams.success) {
    return validationErrorResponse(parsedParams.error);
  }

  const record = await getGenerationRecord(
    parsedParams.data.generationId,
    client.clientId,
  );
  if (!record) {
    return Response.json({ error: "Not found" }, { status: 404 });
  }

  const output = outputForID(record, parsedParams.data.outputId);
  if (!output) {
    return Response.json({ error: "Output not found" }, { status: 404 });
  }

  const registry = createProviderRegistry();
  const response = await registry.downloadOutput({
    generation: storedGenerationForProvider(record),
    output,
  });

  const headers = new Headers(response.headers);
  headers.set(
    "Content-Disposition",
    `attachment; filename="${filenameForOutput(output).replace(/"/g, "")}"`,
  );
  if (output.contentType && !headers.has("Content-Type")) {
    headers.set("Content-Type", output.contentType);
  }

  return new Response(response.body, {
    status: response.status,
    headers,
  });
});
