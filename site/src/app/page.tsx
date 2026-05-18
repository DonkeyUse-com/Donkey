import {
  ArrowRight,
  CheckCircle2,
  Database,
  Server,
  Sparkles,
} from "lucide-react";
import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";

const stackItems = [
  {
    label: "Next.js",
    detail: "App Router, TypeScript, Tailwind, Vercel-ready build scripts",
    icon: Server,
  },
  {
    label: "Prisma",
    detail: "Generated client, Supabase Postgres connection, sample model",
    icon: Database,
  },
  {
    label: "shadcn/ui",
    detail: "Component registry, design tokens, button primitive, utility helper",
    icon: Sparkles,
  },
];

export default function Home() {
  return (
    <main className="min-h-screen bg-background text-foreground">
      <section className="mx-auto flex min-h-screen w-full max-w-6xl flex-col px-6 py-8 sm:px-8 lg:px-10">
        <nav className="flex items-center justify-between border-b border-border pb-5">
          <Link href="/" className="text-sm font-semibold tracking-wide">
            Site
          </Link>
          <Link
            className={buttonVariants({ size: "sm", variant: "outline" })}
            href="/api/health"
          >
            API health
            <ArrowRight />
          </Link>
        </nav>

        <div className="grid flex-1 items-center gap-10 py-12 lg:grid-cols-[1.05fr_0.95fr]">
          <div className="max-w-2xl">
            <div className="mb-6 inline-flex items-center gap-2 rounded-md border border-emerald-200 bg-emerald-50 px-3 py-1.5 text-sm font-medium text-emerald-900">
              <CheckCircle2 className="size-4" />
              Ready for Vercel and Supabase
            </div>
            <h1 className="text-4xl font-semibold leading-tight text-balance sm:text-5xl">
              A clean Next.js foundation for the site and API.
            </h1>
            <p className="mt-5 max-w-xl text-base leading-7 text-muted-foreground sm:text-lg">
              TypeScript, Prisma, shadcn/ui, and Supabase configuration are
              wired together so the project can move straight into product
              work.
            </p>
            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <Link
                className={buttonVariants({ size: "lg" })}
                href="/api/health"
              >
                Check API
                <ArrowRight />
              </Link>
              <a
                className={buttonVariants({ size: "lg", variant: "outline" })}
                href="https://vercel.com/new"
                rel="noreferrer"
                target="_blank"
              >
                Deploy
              </a>
            </div>
          </div>

          <div className="grid gap-3">
            {stackItems.map((item) => {
              const Icon = item.icon;

              return (
                <div
                  className="rounded-lg border border-border bg-card p-5 text-card-foreground shadow-sm"
                  key={item.label}
                >
                  <div className="flex items-start gap-4">
                    <div className="rounded-md bg-emerald-100 p-2 text-emerald-900">
                      <Icon className="size-5" />
                    </div>
                    <div>
                      <h2 className="text-base font-semibold">{item.label}</h2>
                      <p className="mt-1 text-sm leading-6 text-muted-foreground">
                        {item.detail}
                      </p>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </section>
    </main>
  );
}
