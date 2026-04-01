import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/db";
import { skillRuns } from "@/db/schema";
import { desc, eq } from "drizzle-orm";
import { withAuth } from "@/lib/auth";

export const GET = withAuth(async (req: NextRequest) => {
  const { searchParams } = new URL(req.url);
  const skill = searchParams.get("skill");
  const repo = searchParams.get("repo");
  const limit = Math.min(Number(searchParams.get("limit") ?? 50), 100);

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
  const body = await req.json();
  const { skill, repo, branch, prNumber, outcome, metadata } = body;

  if (!skill) {
    return NextResponse.json({ error: "skill is required" }, { status: 400 });
  }

  const db = getDb();
  const [row] = await db
    .insert(skillRuns)
    .values({
      skill,
      repo: repo ?? null,
      branch: branch ?? null,
      prNumber: prNumber ?? null,
      outcome: outcome ?? null,
      metadata: metadata ?? null,
    })
    .returning();

  return NextResponse.json(row, { status: 201 });
});
