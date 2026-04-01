import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/db";
import { skillRuns } from "@/db/schema";
import { desc, eq } from "drizzle-orm";
import { withAuth } from "@/middleware/auth";
import { parseLimit } from "@/lib/query";
import { validateRunInput } from "@/lib/validation";

export const GET = withAuth(async (req: NextRequest) => {
  const { searchParams } = new URL(req.url);
  const skill = searchParams.get("skill");
  const repo = searchParams.get("repo");
  const limit = parseLimit(searchParams.get("limit"));

  const db = getDb();
  let query = db.select().from(skillRuns).orderBy(desc(skillRuns.startedAt));

  if (skill) {
    query = query.where(eq(skillRuns.skill, skill)) as typeof query;
  }
  if (repo) {
    query = query.where(eq(skillRuns.repo, repo)) as typeof query;
  }

  const rows = await query.limit(limit);
  return NextResponse.json(rows);
});

export const POST = withAuth(async (req: NextRequest) => {
  let body;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const result = validateRunInput(body);
  if (!result.valid) {
    return NextResponse.json({ error: result.error }, { status: 400 });
  }

  const db = getDb();
  const [row] = await db.insert(skillRuns).values(result.data).returning();

  return NextResponse.json(row, { status: 201 });
});
