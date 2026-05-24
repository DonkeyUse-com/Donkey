import { NextResponse } from "next/server";

import { getCreditBalance } from "@/lib/credits/inference";
import { withDonkeyAuth } from "@/lib/donkey-api-auth";

export const dynamic = "force-dynamic";

export const GET = withDonkeyAuth(async (request) => {
  const balance = await getCreditBalance(request.donkey.userId);

  return NextResponse.json(balance);
});
