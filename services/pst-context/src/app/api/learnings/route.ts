import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/db";
import { learnings } from "@/db/schema";
import { desc, eq, ilike } from "drizzle-orm";
import { withAuth } from "@/lib/auth";

export const GET = withAuth(async (req: NextRequest) => {
  const { searchParams } = new URL(req.url);
  const topic = searchParams.get("topic");
  const sourceRepo = searchParams.get("sourceRepo");
  const search = searchParams.get("search");
  const limit = Math.min(Number(searchParams.get("limit") ?? 50), 100);

  const db = getDb();
  let query = db.select().from(learnings).orderBy(desc(learnings.updatedAt));

  if (topic) {
    query = query.where(eq(learnings.topic, topic)) as typeof query;
  }
  if (sourceRepo) {
    query = query.where(eq(learnings.sourceRepo, sourceRepo)) as typeof query;
  }
  if (search) {
    const escaped = search.replace(/[%_\\]/g, "\\$&");
    query = query.where(
      ilike(learnings.content, `%${escaped}%`),
    ) as typeof query;
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
  const { topic, content, sourceRepo, sourceRunId, metadata } = body;

  if (!topic || !content) {
    return NextResponse.json(
      { error: "topic and content are required" },
      { status: 400 },
    );
  }

  const db = getDb();
  const [row] = await db
    .insert(learnings)
    .values({
      topic,
      content,
      sourceRepo: sourceRepo ?? null,
      sourceRunId: sourceRunId ?? null,
      metadata: metadata ?? null,
    })
    .returning();

  return NextResponse.json(row, { status: 201 });
});
