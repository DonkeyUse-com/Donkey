import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export function GET() {
  return NextResponse.json({
    ok: true,
    services: {
      databaseUrlConfigured: Boolean(process.env.DATABASE_URL),
      directUrlConfigured: Boolean(process.env.DIRECT_URL),
    },
  });
}
