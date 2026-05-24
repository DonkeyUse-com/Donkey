-- CreateTable
CREATE TABLE "user_credit_account" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "balanceMicros" BIGINT NOT NULL DEFAULT 0,
    "lifetimeGrantedMicros" BIGINT NOT NULL DEFAULT 0,
    "lifetimeChargedMicros" BIGINT NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_credit_account_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_credit_grant" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "sourceId" TEXT,
    "originalAmountMicros" BIGINT NOT NULL,
    "remainingAmountMicros" BIGINT NOT NULL,
    "expiresAt" TIMESTAMP(3),
    "periodStart" TIMESTAMP(3),
    "periodEnd" TIMESTAMP(3),
    "status" TEXT NOT NULL DEFAULT 'active',
    "description" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_credit_grant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_credit_ledger_entry" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "grantId" TEXT,
    "usageEventId" TEXT,
    "type" TEXT NOT NULL,
    "amountMicros" BIGINT NOT NULL,
    "balanceAfterMicros" BIGINT NOT NULL,
    "source" TEXT,
    "sourceId" TEXT,
    "description" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_credit_ledger_entry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inference_usage_event" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "clientId" TEXT,
    "route" TEXT NOT NULL,
    "requestKind" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "billingStatus" TEXT NOT NULL,
    "providerUsage" JSONB,
    "normalizedUsage" JSONB,
    "creditCostMicros" BIGINT NOT NULL DEFAULT 0,
    "rateId" TEXT,
    "rateVersion" INTEGER,
    "errorCode" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "inference_usage_event_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inference_credit_rate" (
    "id" TEXT NOT NULL,
    "route" TEXT,
    "provider" TEXT,
    "model" TEXT,
    "version" INTEGER NOT NULL DEFAULT 1,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "baseCostMicros" BIGINT NOT NULL DEFAULT 0,
    "inputTokenCostMicros" BIGINT NOT NULL DEFAULT 0,
    "outputTokenCostMicros" BIGINT NOT NULL DEFAULT 0,
    "totalTokenCostMicros" BIGINT NOT NULL DEFAULT 0,
    "characterCostMicros" BIGINT NOT NULL DEFAULT 0,
    "fallbackCostMicros" BIGINT NOT NULL DEFAULT 1000000,
    "validFrom" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "validUntil" TIMESTAMP(3),
    "description" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "inference_credit_rate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_credit_limit" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "scope" TEXT NOT NULL DEFAULT 'global',
    "route" TEXT,
    "provider" TEXT,
    "model" TEXT,
    "maxCreditsPerPeriodMicros" BIGINT,
    "periodStart" TIMESTAMP(3),
    "periodEnd" TIMESTAMP(3),
    "active" BOOLEAN NOT NULL DEFAULT true,
    "description" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_credit_limit_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "user_credit_account_userId_key" ON "user_credit_account"("userId");

-- CreateIndex
CREATE INDEX "user_credit_grant_accountId_idx" ON "user_credit_grant"("accountId");

-- CreateIndex
CREATE INDEX "user_credit_grant_userId_expiresAt_idx" ON "user_credit_grant"("userId", "expiresAt");

-- CreateIndex
CREATE INDEX "user_credit_grant_userId_status_idx" ON "user_credit_grant"("userId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "user_credit_grant_userId_source_sourceId_key" ON "user_credit_grant"("userId", "source", "sourceId");

-- CreateIndex
CREATE INDEX "user_credit_ledger_entry_accountId_createdAt_idx" ON "user_credit_ledger_entry"("accountId", "createdAt");

-- CreateIndex
CREATE INDEX "user_credit_ledger_entry_userId_createdAt_idx" ON "user_credit_ledger_entry"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "user_credit_ledger_entry_grantId_idx" ON "user_credit_ledger_entry"("grantId");

-- CreateIndex
CREATE INDEX "user_credit_ledger_entry_usageEventId_idx" ON "user_credit_ledger_entry"("usageEventId");

-- CreateIndex
CREATE INDEX "inference_usage_event_accountId_createdAt_idx" ON "inference_usage_event"("accountId", "createdAt");

-- CreateIndex
CREATE INDEX "inference_usage_event_userId_createdAt_idx" ON "inference_usage_event"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "inference_usage_event_route_createdAt_idx" ON "inference_usage_event"("route", "createdAt");

-- CreateIndex
CREATE INDEX "inference_usage_event_provider_model_createdAt_idx" ON "inference_usage_event"("provider", "model", "createdAt");

-- CreateIndex
CREATE INDEX "inference_credit_rate_active_route_provider_model_idx" ON "inference_credit_rate"("active", "route", "provider", "model");

-- CreateIndex
CREATE INDEX "inference_credit_rate_validFrom_validUntil_idx" ON "inference_credit_rate"("validFrom", "validUntil");

-- CreateIndex
CREATE INDEX "user_credit_limit_userId_active_idx" ON "user_credit_limit"("userId", "active");

-- CreateIndex
CREATE INDEX "user_credit_limit_route_provider_model_idx" ON "user_credit_limit"("route", "provider", "model");

-- AddForeignKey
ALTER TABLE "user_credit_account" ADD CONSTRAINT "user_credit_account_userId_fkey" FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_credit_grant" ADD CONSTRAINT "user_credit_grant_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "user_credit_account"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_credit_grant" ADD CONSTRAINT "user_credit_grant_userId_fkey" FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_credit_ledger_entry" ADD CONSTRAINT "user_credit_ledger_entry_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "user_credit_account"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_credit_ledger_entry" ADD CONSTRAINT "user_credit_ledger_entry_userId_fkey" FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_credit_ledger_entry" ADD CONSTRAINT "user_credit_ledger_entry_grantId_fkey" FOREIGN KEY ("grantId") REFERENCES "user_credit_grant"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_credit_ledger_entry" ADD CONSTRAINT "user_credit_ledger_entry_usageEventId_fkey" FOREIGN KEY ("usageEventId") REFERENCES "inference_usage_event"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inference_usage_event" ADD CONSTRAINT "inference_usage_event_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "user_credit_account"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inference_usage_event" ADD CONSTRAINT "inference_usage_event_userId_fkey" FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_credit_limit" ADD CONSTRAINT "user_credit_limit_userId_fkey" FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE ON UPDATE CASCADE;
