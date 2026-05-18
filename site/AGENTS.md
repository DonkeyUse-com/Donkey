<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

Also read `docs/frontend-nextjs-guidelines.md` before changing the site UI, routes, API handlers, or data access patterns.

## Database Migrations

Database migrations must be handled manually by the developer. Agents are not allowed to run database migrations, including `prisma migrate`, `prisma db push`, or any command that applies schema changes to Supabase or another database.
