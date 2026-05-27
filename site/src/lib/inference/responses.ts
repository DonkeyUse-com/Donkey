import { NextResponse } from "next/server";
import { ZodError } from "zod";

import { InferenceProviderError } from "@/lib/inference/providers";

export function requireInferenceClientId(clientId: string | null) {
  if (clientId) {
    return {
      ok: true as const,
      clientId,
    };
  }

  return {
    ok: false as const,
    response: NextResponse.json(
      {
        error: "Missing client id",
        message: "The x-donkey-client-id header is required for inference APIs.",
      },
      { status: 400 },
    ),
  };
}

export function validationErrorResponse(error: ZodError) {
  return NextResponse.json(
    {
      error: "Invalid request",
      issues: error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    },
    { status: 400 },
  );
}

export function inferenceErrorCode(error: unknown) {
  return error instanceof InferenceProviderError
    ? error.code
    : "unexpected_error";
}

export function inferenceProviderErrorResponse(error: InferenceProviderError) {
  return NextResponse.json(
    {
      error: error.code,
      message: error.message,
      details: error.details,
    },
    { status: error.statusCode },
  );
}
