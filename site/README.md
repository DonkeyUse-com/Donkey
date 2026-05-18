# Site

Next.js site and API project for Vercel, backed by Supabase Postgres through Prisma.

## Getting Started

Install dependencies and generate the Prisma client:

```bash
npm install
npm run db:generate
```

Create a Supabase project, copy `.env.example` to `.env`, and set:

```bash
DATABASE_URL="postgresql://postgres:[PASSWORD]@[PROJECT-REF].pooler.supabase.com:6543/postgres?pgbouncer=true&connection_limit=1"
NEXT_PUBLIC_SUPABASE_URL="https://[PROJECT-REF].supabase.co"
NEXT_PUBLIC_SUPABASE_ANON_KEY="[SUPABASE-ANON-KEY]"
```

Run the development server:

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). The public health route is available at [http://localhost:3000/api/health](http://localhost:3000/api/health).

## Stack

- Next.js App Router with TypeScript and Tailwind CSS.
- shadcn/ui initialized with the `base-nova` style and `@/components` aliases.
- Prisma 7 configured for Supabase Postgres.
- Supabase JS client helper for server-side use.
- Vercel-compatible `build`, `start`, and `postinstall` scripts.

## Guidelines

Read [Frontend and Next.js Guidelines](docs/frontend-nextjs-guidelines.md) before changing the site UI, routes, API handlers, or data access patterns.

## Database

Prisma is configured in `prisma/schema.prisma` and `prisma.config.ts`. The starter schema includes a `WaitlistEntry` model as a first writable table.

Do not commit `.env`. Set the same variables in Vercel before deploying. Use Supabase's pooled connection string for `DATABASE_URL` in serverless deployments.

## Scripts

- `npm run dev`: run the app locally.
- `npm run build`: build for production.
- `npm run start`: serve a production build.
- `npm run lint`: run ESLint.
- `npm run db:generate`: generate the Prisma client.
- `npm run db:pull`: introspect an existing Supabase database.

No migrations have been run. When you are ready to create tables, choose the migration workflow deliberately for the Supabase project.
