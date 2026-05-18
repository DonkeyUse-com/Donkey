import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export function GET() {
  return NextResponse.json({
    ok: true,
    services: {
      databaseUrlConfigured: Boolean(process.env.DATABASE_URL),
      supabaseUrlConfigured: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
      supabaseAnonKeyConfigured: Boolean(
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
      ),
    },
  });
}
