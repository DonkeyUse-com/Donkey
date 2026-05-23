import { z } from "zod";

const metadataSchema = z.record(z.string().min(1).max(64), z.string().max(512));
const jsonObjectSchema = z.record(z.string(), z.unknown());

export const inferenceModalitySchema = z.enum([
  "text",
  "image",
  "video",
  "audio",
  "music",
]);

export const assetGenerationKindSchema = z.enum(["image", "video", "music"]);

export const modelsQuerySchema = z.object({
  output_modalities: z.string().optional(),
});

export const chatCompletionRequestSchema = z
  .object({
    messages: z.array(jsonObjectSchema).min(1),
    model: z.string().min(1).max(256).optional(),
    models: z.array(z.string().min(1).max(256)).min(1).optional(),
    stream: z.boolean().optional().default(false),
    modalities: z.array(z.enum(["text", "image", "audio"])).optional(),
    provider: jsonObjectSchema.optional(),
    metadata: metadataSchema.optional(),
  })
  .passthrough()
  .superRefine((value, context) => {
    if (!value.model && !value.models?.length) {
      context.addIssue({
        code: "custom",
        message: "Either model or models is required.",
        path: ["model"],
      });
    }
  });

export const assetGenerationRequestSchema = z.object({
  kind: assetGenerationKindSchema,
  provider: z.string().min(1).max(100).optional(),
  model: z.string().min(1).max(256),
  prompt: z.string().min(1).max(20_000),
  inputs: jsonObjectSchema.optional(),
  parameters: jsonObjectSchema.optional(),
  metadata: metadataSchema.optional(),
});

export const generationRouteParamsSchema = z.object({
  generationId: z.string().min(1).max(128),
});

export const outputRouteParamsSchema = generationRouteParamsSchema.extend({
  outputId: z.string().min(1).max(128),
});

export function parseRequestedModalities(value: string | null) {
  if (!value) {
    return ["text"] as const;
  }

  if (value === "all") {
    return ["text", "image", "video", "audio", "music"] as const;
  }

  return value
    .split(",")
    .map((item) => item.trim())
    .filter((item): item is z.infer<typeof inferenceModalitySchema> => {
      return inferenceModalitySchema.safeParse(item).success;
    });
}
