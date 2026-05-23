import { InferenceProviderError } from "@/lib/inference/providers";

export type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

export function ensureConfigured(
  configured: boolean,
  message = "Inference provider credentials are not configured.",
) {
  if (!configured) {
    throw new InferenceProviderError(message, {
      statusCode: 503,
      code: "missing_provider_credentials",
    });
  }
}

export function isSafeRemoteAssetURL(value: string) {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    return false;
  }

  if (parsed.protocol !== "https:") {
    return false;
  }

  const host = parsed.hostname.toLowerCase();
  return !(
    host === "localhost" ||
    host === "127.0.0.1" ||
    host === "::1" ||
    host.startsWith("10.") ||
    host.startsWith("192.168.") ||
    /^172\.(1[6-9]|2\d|3[0-1])\./.test(host)
  );
}
