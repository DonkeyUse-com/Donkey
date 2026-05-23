import type {
  GenerationOutputRef,
  InferenceModality,
} from "@/lib/inference/providers";

const extensionByContentType: Record<string, string> = {
  "audio/mpeg": "mp3",
  "audio/mp3": "mp3",
  "audio/wav": "wav",
  "audio/x-wav": "wav",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "video/mp4": "mp4",
  "video/webm": "webm",
};

const defaultExtensionByKind: Record<InferenceModality, string> = {
  text: "txt",
  image: "png",
  video: "mp4",
  audio: "mp3",
  music: "mp3",
};

export function outputDownloadPath(generationId: string, outputId: string) {
  return `/api/inference/assets/${encodeURIComponent(generationId)}/outputs/${encodeURIComponent(outputId)}`;
}

export function withDownloadPath(
  generationId: string,
  output: GenerationOutputRef,
): GenerationOutputRef {
  if (output.dataBase64) {
    return output;
  }

  if (!output.url) {
    return output;
  }

  return {
    ...output,
    downloadUrl: outputDownloadPath(generationId, output.id),
  };
}

export function filenameForOutput(output: GenerationOutputRef) {
  const existing = output.filename?.trim();
  if (existing) {
    return safeFilename(existing);
  }

  const extension =
    extensionByContentType[(output.contentType ?? "").toLowerCase()] ??
    defaultExtensionByKind[output.kind] ??
    "bin";

  return `${safeFilename(output.id)}.${extension}`;
}

export function safeFilename(value: string) {
  const cleaned = value
    .replace(/[/\\?%*:|"<>]/g, "-")
    .replace(/\s+/g, " ")
    .trim();

  return cleaned.length > 0 ? cleaned.slice(0, 160) : "asset";
}
