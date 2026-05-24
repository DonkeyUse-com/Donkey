import { NextResponse } from "next/server";

import { Prisma, type PrismaClient } from "@/generated/prisma/client";
import { prisma } from "@/lib/prisma";
import {
  creditMicrosToString,
  creditStringToMicros,
  zeroCreditMicros,
} from "@/lib/credits/amounts";
import { isJsonObject, toJsonValue } from "@/lib/inference/json";
import type { JsonObject, JsonValue } from "@/lib/inference/providers";

export const inferenceUsageRoutes = {
  assets: "/api/inference/assets/",
  assetsRefresh: "/api/inference/assets/refresh/",
  chatCompletions: "/api/inference/chat/completions/",
  responses: "/api/inference/responses/",
} as const;

type CreditsDatabase = PrismaClient | Prisma.TransactionClient;

type CreditRateSnapshot = {
  id: string | null;
  version: number | null;
  baseCostMicros: bigint;
  inputTokenCostMicros: bigint;
  outputTokenCostMicros: bigint;
  totalTokenCostMicros: bigint;
  characterCostMicros: bigint;
  fallbackCostMicros: bigint;
};

type NormalizedUsage = {
  inputTokens: bigint;
  outputTokens: bigint;
  totalTokens: bigint;
  characterCost: bigint;
};

type InferenceUsageStatus = "failed" | "succeeded";

type InferenceUsageInput = {
  userId: string;
  clientId: string | null;
  route: string;
  requestKind: string;
  provider: string;
  model: string;
  status: InferenceUsageStatus;
  usage?: JsonValue;
  errorCode?: string;
  metadata?: JsonObject;
};

type CreditPreflightInput = {
  userId: string;
  route: string;
  provider?: string;
  model?: string;
};

export type RecordedInferenceUsage = {
  usageEventId: string;
  creditCostMicros: bigint;
  remainingBalanceMicros: bigint;
};

export class InsufficientCreditsError extends Error {
  public constructor(public readonly balanceMicros: bigint) {
    super("Insufficient credits");
    this.name = "InsufficientCreditsError";
  }
}

export class CreditLimitExceededError extends Error {
  public constructor(
    public readonly limitId: string,
    public readonly maxCreditsPerPeriodMicros: bigint,
  ) {
    super("Credit limit exceeded");
    this.name = "CreditLimitExceededError";
  }
}

export async function ensureCreditAccount(userId: string) {
  const account = await ensureCreditAccountRecord(prisma, userId);
  const initialGrantMicros = initialFreeCreditMicros();
  if (initialGrantMicros > zeroCreditMicros) {
    await grantCredits({
      userId,
      amountMicros: initialGrantMicros,
      source: "free",
      sourceId: `first-use:${userId}`,
      description: "Initial free credits",
    });
  }

  return account;
}

export async function grantCredits(input: {
  userId: string;
  amountMicros: bigint;
  source: string;
  sourceId?: string;
  expiresAt?: Date;
  periodStart?: Date;
  periodEnd?: Date;
  description?: string;
  metadata?: JsonObject;
}) {
  if (input.amountMicros <= zeroCreditMicros) {
    throw new Error("Credit grants must be positive.");
  }

  if (input.sourceId) {
    const existing = await prisma.userCreditGrant.findFirst({
      where: {
        source: input.source,
        sourceId: input.sourceId,
        userId: input.userId,
      },
    });
    if (existing) {
      return existing;
    }
  }

  try {
    return await prisma.$transaction(
      async (tx) => {
        const account = await ensureCreditAccountRecord(tx, input.userId);
        const updatedAccount = await tx.userCreditAccount.update({
          data: {
            balanceMicros: {
              increment: input.amountMicros,
            },
            lifetimeGrantedMicros: {
              increment: input.amountMicros,
            },
          },
          where: {
            id: account.id,
          },
        });

        const grant = await tx.userCreditGrant.create({
          data: {
            accountId: account.id,
            description: input.description,
            expiresAt: input.expiresAt,
            metadata: prismaJson(input.metadata),
            originalAmountMicros: input.amountMicros,
            periodEnd: input.periodEnd,
            periodStart: input.periodStart,
            remainingAmountMicros: input.amountMicros,
            source: input.source,
            sourceId: input.sourceId,
            userId: input.userId,
          },
        });

        await tx.userCreditLedgerEntry.create({
          data: {
            accountId: account.id,
            amountMicros: input.amountMicros,
            balanceAfterMicros: updatedAccount.balanceMicros,
            description: input.description,
            grantId: grant.id,
            metadata: prismaJson(input.metadata),
            source: input.source,
            sourceId: input.sourceId,
            type: "grant",
            userId: input.userId,
          },
        });

        return grant;
      },
      {
        isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
      },
    );
  } catch (error) {
    if (
      input.sourceId &&
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2002"
    ) {
      const existing = await prisma.userCreditGrant.findFirst({
        where: {
          source: input.source,
          sourceId: input.sourceId,
          userId: input.userId,
        },
      });
      if (existing) {
        return existing;
      }
    }

    throw error;
  }
}

export async function expireCredits(userId: string, now = new Date()) {
  await prisma.$transaction(
    async (tx) => {
      const account = await ensureCreditAccountRecord(tx, userId);
      await expireCreditsForAccount(tx, account.id, userId, account.balanceMicros, now);
    },
    {
      isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
    },
  );
}

export async function assertCanUseInference(input: CreditPreflightInput) {
  await ensureCreditAccount(input.userId);
  await expireCredits(input.userId);

  const account = await prisma.userCreditAccount.findUniqueOrThrow({
    where: {
      userId: input.userId,
    },
  });

  if (account.balanceMicros <= zeroCreditMicros) {
    throw new InsufficientCreditsError(account.balanceMicros);
  }

  await assertWithinConfiguredLimits(input);

  return account;
}

export async function requireInferenceCredits(input: CreditPreflightInput) {
  try {
    await assertCanUseInference(input);
    return {
      ok: true as const,
    };
  } catch (error) {
    const response = creditErrorResponse(error);
    if (response) {
      return {
        ok: false as const,
        response,
      };
    }

    throw error;
  }
}

export async function recordInferenceUsage(input: InferenceUsageInput) {
  return prisma.$transaction(
    async (tx): Promise<RecordedInferenceUsage> => {
      const account = await ensureCreditAccountRecord(tx, input.userId);
      const balanceAfterExpiry = await expireCreditsForAccount(
        tx,
        account.id,
        input.userId,
        account.balanceMicros,
        new Date(),
      );
      const rate = input.status === "succeeded"
        ? await resolveCreditRate(tx, input.route, input.provider, input.model)
        : zeroCreditRate();
      const normalizedUsage = normalizeProviderUsage(input.usage);
      const creditCostMicros = input.status === "succeeded"
        ? costForUsage(rate, normalizedUsage)
        : zeroCreditMicros;
      const billingStatus = billingStatusFor(input.status, creditCostMicros);
      const usageEvent = await tx.inferenceUsageEvent.create({
        data: {
          accountId: account.id,
          billingStatus,
          clientId: input.clientId,
          creditCostMicros,
          errorCode: input.errorCode,
          metadata: prismaJson(input.metadata),
          model: input.model,
          normalizedUsage: prismaJson(normalizedUsageJson(normalizedUsage)),
          provider: input.provider,
          providerUsage: prismaJson(input.usage),
          rateId: rate.id,
          rateVersion: rate.version,
          requestKind: input.requestKind,
          route: input.route,
          status: input.status,
          userId: input.userId,
        },
      });

      if (creditCostMicros <= zeroCreditMicros) {
        return {
          creditCostMicros,
          remainingBalanceMicros: balanceAfterExpiry,
          usageEventId: usageEvent.id,
        };
      }

      await debitGrants(tx, account.id, creditCostMicros);
      const updatedAccount = await tx.userCreditAccount.update({
        data: {
          balanceMicros: {
            decrement: creditCostMicros,
          },
          lifetimeChargedMicros: {
            increment: creditCostMicros,
          },
        },
        where: {
          id: account.id,
        },
      });

      await tx.userCreditLedgerEntry.create({
        data: {
          accountId: account.id,
          amountMicros: -creditCostMicros,
          balanceAfterMicros: updatedAccount.balanceMicros,
          source: "inference",
          sourceId: usageEvent.id,
          type: "usage",
          usageEventId: usageEvent.id,
          userId: input.userId,
        },
      });

      return {
        creditCostMicros,
        remainingBalanceMicros: updatedAccount.balanceMicros,
        usageEventId: usageEvent.id,
      };
    },
    {
      isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
    },
  );
}

export async function getCreditBalance(userId: string) {
  await ensureCreditAccount(userId);
  await expireCredits(userId);

  const account = await prisma.userCreditAccount.findUniqueOrThrow({
    where: {
      userId,
    },
  });
  const now = new Date();
  const recentSince = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const [grants, limits, recentUsageEvents] = await Promise.all([
    prisma.userCreditGrant.findMany({
      orderBy: [
        {
          expiresAt: "asc",
        },
        {
          createdAt: "asc",
        },
      ],
      take: 50,
      where: {
        remainingAmountMicros: {
          gt: zeroCreditMicros,
        },
        status: "active",
        userId,
        OR: [
          {
            expiresAt: null,
          },
          {
            expiresAt: {
              gt: now,
            },
          },
        ],
      },
    }),
    prisma.userCreditLimit.findMany({
      orderBy: {
        createdAt: "desc",
      },
      where: {
        active: true,
        userId,
        AND: [
          {
            OR: [
              {
                periodStart: null,
              },
              {
                periodStart: {
                  lte: now,
                },
              },
            ],
          },
          {
            OR: [
              {
                periodEnd: null,
              },
              {
                periodEnd: {
                  gt: now,
                },
              },
            ],
          },
        ],
      },
    }),
    prisma.inferenceUsageEvent.findMany({
      orderBy: {
        createdAt: "desc",
      },
      select: {
        creditCostMicros: true,
        createdAt: true,
        model: true,
        provider: true,
        route: true,
        status: true,
      },
      take: 100,
      where: {
        createdAt: {
          gte: recentSince,
        },
        userId,
      },
    }),
  ]);

  return {
    balance: creditMicrosToString(account.balanceMicros),
    balanceMicros: account.balanceMicros.toString(),
    lifetimeCharged: creditMicrosToString(account.lifetimeChargedMicros),
    lifetimeGranted: creditMicrosToString(account.lifetimeGrantedMicros),
    activeGrants: grants.map((grant) => ({
      id: grant.id,
      source: grant.source,
      sourceId: grant.sourceId,
      remaining: creditMicrosToString(grant.remainingAmountMicros),
      originalAmount: creditMicrosToString(grant.originalAmountMicros),
      expiresAt: grant.expiresAt?.toISOString() ?? null,
      periodStart: grant.periodStart?.toISOString() ?? null,
      periodEnd: grant.periodEnd?.toISOString() ?? null,
    })),
    currentLimits: limits.map((limit) => ({
      id: limit.id,
      scope: limit.scope,
      route: limit.route,
      provider: limit.provider,
      model: limit.model,
      maxCreditsPerPeriod: limit.maxCreditsPerPeriodMicros === null
        ? null
        : creditMicrosToString(limit.maxCreditsPerPeriodMicros),
      periodStart: limit.periodStart?.toISOString() ?? null,
      periodEnd: limit.periodEnd?.toISOString() ?? null,
    })),
    recentUsageTotals: recentUsageTotals(recentUsageEvents),
  };
}

export function creditUsageHeaders(recorded: RecordedInferenceUsage) {
  return {
    "X-Donkey-Credits-Charged": creditMicrosToString(recorded.creditCostMicros),
    "X-Donkey-Credits-Remaining": creditMicrosToString(recorded.remainingBalanceMicros),
  };
}

export function creditErrorResponse(error: unknown) {
  if (error instanceof InsufficientCreditsError) {
    return NextResponse.json(
      {
        error: "insufficient_credits",
        message: "You do not have enough credits to run hosted inference.",
        balance: creditMicrosToString(error.balanceMicros),
      },
      {
        status: 402,
      },
    );
  }

  if (error instanceof CreditLimitExceededError) {
    return NextResponse.json(
      {
        error: "credit_limit_exceeded",
        message: "This account has reached a configured credit limit.",
        limitId: error.limitId,
        maxCreditsPerPeriod: creditMicrosToString(error.maxCreditsPerPeriodMicros),
      },
      {
        status: 402,
      },
    );
  }

  return null;
}

async function ensureCreditAccountRecord(db: CreditsDatabase, userId: string) {
  return db.userCreditAccount.upsert({
    create: {
      userId,
    },
    update: {},
    where: {
      userId,
    },
  });
}

async function expireCreditsForAccount(
  tx: Prisma.TransactionClient,
  accountId: string,
  userId: string,
  startingBalanceMicros: bigint,
  now: Date,
) {
  let balanceMicros = startingBalanceMicros;
  const expiringGrants = await tx.userCreditGrant.findMany({
    orderBy: {
      expiresAt: "asc",
    },
    where: {
      accountId,
      expiresAt: {
        lte: now,
      },
      remainingAmountMicros: {
        gt: zeroCreditMicros,
      },
      status: "active",
    },
  });

  for (const grant of expiringGrants) {
    const expiredMicros = grant.remainingAmountMicros;
    balanceMicros -= expiredMicros;
    await tx.userCreditGrant.update({
      data: {
        remainingAmountMicros: zeroCreditMicros,
        status: "expired",
      },
      where: {
        id: grant.id,
      },
    });
    await tx.userCreditAccount.update({
      data: {
        balanceMicros: {
          decrement: expiredMicros,
        },
      },
      where: {
        id: accountId,
      },
    });
    await tx.userCreditLedgerEntry.create({
      data: {
        accountId,
        amountMicros: -expiredMicros,
        balanceAfterMicros: balanceMicros,
        grantId: grant.id,
        source: grant.source,
        sourceId: grant.sourceId,
        type: "expiration",
        userId,
      },
    });
  }

  return balanceMicros;
}

async function debitGrants(
  tx: Prisma.TransactionClient,
  accountId: string,
  creditCostMicros: bigint,
) {
  let remainingCostMicros = creditCostMicros;
  const grants = await tx.userCreditGrant.findMany({
    orderBy: [
      {
        expiresAt: {
          sort: "asc",
          nulls: "last",
        },
      },
      {
        createdAt: "asc",
      },
    ],
    where: {
      accountId,
      remainingAmountMicros: {
        gt: zeroCreditMicros,
      },
      status: "active",
    },
  });

  for (const grant of grants) {
    if (remainingCostMicros <= zeroCreditMicros) {
      return;
    }

    const debitMicros = grant.remainingAmountMicros < remainingCostMicros
      ? grant.remainingAmountMicros
      : remainingCostMicros;
    const nextRemainingMicros = grant.remainingAmountMicros - debitMicros;
    await tx.userCreditGrant.update({
      data: {
        remainingAmountMicros: nextRemainingMicros,
        status: nextRemainingMicros === zeroCreditMicros ? "exhausted" : "active",
      },
      where: {
        id: grant.id,
      },
    });
    remainingCostMicros -= debitMicros;
  }

}

async function assertWithinConfiguredLimits(input: CreditPreflightInput) {
  const now = new Date();
  const limits = await prisma.userCreditLimit.findMany({
    where: {
      active: true,
      userId: input.userId,
      maxCreditsPerPeriodMicros: {
        not: null,
      },
      AND: [
        {
          OR: [
            {
              periodStart: null,
            },
            {
              periodStart: {
                lte: now,
              },
            },
          ],
        },
        {
          OR: [
            {
              periodEnd: null,
            },
            {
              periodEnd: {
                gt: now,
              },
            },
          ],
        },
      ],
    },
  });

  for (const limit of limits) {
    if (!limitMatchesPreflight(limit, input)) {
      continue;
    }

    const charged = await prisma.inferenceUsageEvent.aggregate({
      _sum: {
        creditCostMicros: true,
      },
      where: {
        userId: input.userId,
        route: limit.route ?? undefined,
        provider: limit.provider ?? undefined,
        model: limit.model ?? undefined,
        createdAt: {
          gte: limit.periodStart ?? undefined,
          lt: limit.periodEnd ?? undefined,
        },
        status: "succeeded",
      },
    });
    const chargedMicros = charged._sum.creditCostMicros ?? zeroCreditMicros;
    if (
      limit.maxCreditsPerPeriodMicros !== null &&
      chargedMicros >= limit.maxCreditsPerPeriodMicros
    ) {
      throw new CreditLimitExceededError(limit.id, limit.maxCreditsPerPeriodMicros);
    }
  }
}

function limitMatchesPreflight(
  limit: {
    route: string | null;
    provider: string | null;
    model: string | null;
  },
  input: CreditPreflightInput,
) {
  if (limit.route && limit.route !== input.route) {
    return false;
  }
  if (limit.provider && limit.provider !== input.provider) {
    return false;
  }
  if (limit.model && limit.model !== input.model) {
    return false;
  }

  return true;
}

async function resolveCreditRate(
  tx: Prisma.TransactionClient,
  route: string,
  provider: string,
  model: string,
): Promise<CreditRateSnapshot> {
  const now = new Date();
  const rates = await tx.inferenceCreditRate.findMany({
    orderBy: [
      {
        version: "desc",
      },
      {
        createdAt: "desc",
      },
    ],
    where: {
      active: true,
      validFrom: {
        lte: now,
      },
      OR: [
        {
          validUntil: null,
        },
        {
          validUntil: {
            gt: now,
          },
        },
      ],
      AND: [
        {
          OR: [
            {
              route,
              provider,
              model,
            },
            {
              route: null,
              provider,
              model,
            },
            {
              route: null,
              provider: null,
              model: null,
            },
          ],
        },
      ],
    },
  });

  const exactRate = rates.find((rate) => {
    return rate.route === route && rate.provider === provider && rate.model === model;
  });
  const providerModelRate = rates.find((rate) => {
    return rate.route === null && rate.provider === provider && rate.model === model;
  });
  const globalRate = rates.find((rate) => {
    return rate.route === null && rate.provider === null && rate.model === null;
  });

  return rateSnapshot(
    exactRate ?? providerModelRate ?? globalRate,
    defaultCreditRate(route),
  );
}

function rateSnapshot(
  rate: {
    id: string;
    version: number;
    baseCostMicros: bigint;
    inputTokenCostMicros: bigint;
    outputTokenCostMicros: bigint;
    totalTokenCostMicros: bigint;
    characterCostMicros: bigint;
    fallbackCostMicros: bigint;
  } | undefined,
  fallback: CreditRateSnapshot,
) {
  if (!rate) {
    return fallback;
  }

  return {
    id: rate.id,
    version: rate.version,
    baseCostMicros: rate.baseCostMicros,
    inputTokenCostMicros: rate.inputTokenCostMicros,
    outputTokenCostMicros: rate.outputTokenCostMicros,
    totalTokenCostMicros: rate.totalTokenCostMicros,
    characterCostMicros: rate.characterCostMicros,
    fallbackCostMicros: rate.fallbackCostMicros,
  };
}

function defaultCreditRate(route: string): CreditRateSnapshot {
  const defaultRequestMicros = route === inferenceUsageRoutes.assetsRefresh
    ? zeroCreditMicros
    : creditStringToMicros("1");

  return {
    id: null,
    version: null,
    baseCostMicros: defaultRequestMicros,
    inputTokenCostMicros: zeroCreditMicros,
    outputTokenCostMicros: zeroCreditMicros,
    totalTokenCostMicros: zeroCreditMicros,
    characterCostMicros: zeroCreditMicros,
    fallbackCostMicros: defaultRequestMicros,
  };
}

function zeroCreditRate(): CreditRateSnapshot {
  return {
    id: null,
    version: null,
    baseCostMicros: zeroCreditMicros,
    inputTokenCostMicros: zeroCreditMicros,
    outputTokenCostMicros: zeroCreditMicros,
    totalTokenCostMicros: zeroCreditMicros,
    characterCostMicros: zeroCreditMicros,
    fallbackCostMicros: zeroCreditMicros,
  };
}

function costForUsage(rate: CreditRateSnapshot, usage: NormalizedUsage) {
  const hasBillableUsage =
    usage.inputTokens > zeroCreditMicros ||
    usage.outputTokens > zeroCreditMicros ||
    usage.totalTokens > zeroCreditMicros ||
    usage.characterCost > zeroCreditMicros;
  if (!hasBillableUsage) {
    return rate.fallbackCostMicros;
  }

  return (
    rate.baseCostMicros +
    usage.inputTokens * rate.inputTokenCostMicros +
    usage.outputTokens * rate.outputTokenCostMicros +
    usage.totalTokens * rate.totalTokenCostMicros +
    usage.characterCost * rate.characterCostMicros
  );
}

function normalizeProviderUsage(usage: JsonValue | undefined): NormalizedUsage {
  if (!usage || !isJsonObject(usage)) {
    return emptyNormalizedUsage();
  }

  return {
    inputTokens: bigintFromJson(
      usage.input_tokens,
      usage.inputTokens,
      usage.promptTokenCount,
      usage.prompt_tokens,
    ),
    outputTokens: bigintFromJson(
      usage.output_tokens,
      usage.outputTokens,
      usage.candidatesTokenCount,
      usage.completion_tokens,
    ),
    totalTokens: bigintFromJson(
      usage.total_tokens,
      usage.totalTokens,
      usage.totalTokenCount,
    ),
    characterCost: bigintFromJson(
      usage.characterCost,
      usage.character_cost,
      usage.characters,
    ),
  };
}

function emptyNormalizedUsage(): NormalizedUsage {
  return {
    characterCost: zeroCreditMicros,
    inputTokens: zeroCreditMicros,
    outputTokens: zeroCreditMicros,
    totalTokens: zeroCreditMicros,
  };
}

function normalizedUsageJson(usage: NormalizedUsage): JsonObject {
  return {
    characterCost: usage.characterCost.toString(),
    inputTokens: usage.inputTokens.toString(),
    outputTokens: usage.outputTokens.toString(),
    totalTokens: usage.totalTokens.toString(),
  };
}

function bigintFromJson(...values: (JsonValue | undefined)[]) {
  for (const value of values) {
    if (typeof value === "number" && Number.isSafeInteger(value) && value >= 0) {
      return BigInt(value);
    }

    if (typeof value === "string" && /^\d+$/u.test(value)) {
      return BigInt(value);
    }
  }

  return zeroCreditMicros;
}

function billingStatusFor(status: InferenceUsageStatus, creditCostMicros: bigint) {
  if (status === "failed") {
    return "failed";
  }

  return creditCostMicros > zeroCreditMicros ? "charged" : "zero_cost";
}

function initialFreeCreditMicros() {
  return creditStringToMicros(process.env.DONKEY_INITIAL_FREE_CREDITS);
}

function prismaJson(value: JsonValue | undefined): Prisma.InputJsonValue | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }

  return toJsonValue(value) as Prisma.InputJsonValue;
}

function recentUsageTotals(
  events: {
    creditCostMicros: bigint;
    model: string;
    provider: string;
    route: string;
    status: string;
  }[],
) {
  const byKey = new Map<string, {
    count: number;
    creditCostMicros: bigint;
    failedCount: number;
    model: string;
    provider: string;
    route: string;
  }>();

  for (const event of events) {
    const key = [event.route, event.provider, event.model].join("\u0000");
    const current = byKey.get(key) ?? {
      count: 0,
      creditCostMicros: zeroCreditMicros,
      failedCount: 0,
      model: event.model,
      provider: event.provider,
      route: event.route,
    };
    current.count += 1;
    current.creditCostMicros += event.creditCostMicros;
    if (event.status === "failed") {
      current.failedCount += 1;
    }
    byKey.set(key, current);
  }

  return [...byKey.values()].map((total) => ({
    count: total.count,
    creditsCharged: creditMicrosToString(total.creditCostMicros),
    failedCount: total.failedCount,
    model: total.model,
    provider: total.provider,
    route: total.route,
  }));
}
