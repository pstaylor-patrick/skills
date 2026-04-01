import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/db";
import { artifacts } from "@/db/schema";
import { desc, eq } from "drizzle-orm";
import { withAuth } from "@/lib/auth";

export const GET = withAuth(async (req: NextRequest) => {
  const { searchParams } = new URL(req.url);
  const runId = searchParams.get("runId");
  const artifactType = searchParams.get("type");
  const limit = Math.min(Number(searchParams.get("limit") ?? 50), 100);

  const db = getDb();
  let query = db.select().from(artifacts).orderBy(desc(artifacts.createdAt));

  if (runId) {
    query = query.where(eq(artifacts.runId, runId)) as typeof query;
  }
  if (artifactType) {
    query = query.where(
      eq(artifacts.artifactType, artifactType),
    ) as typeof query;
  }

  const rows = await query.limit(limit);
  return NextResponse.json(rows);
});

export const POST = withAuth(async (req: NextRequest) => {
  const body = await req.json();
  const { runId, localPath, artifactType, description, metadata } = body;

  if (!localPath || !artifactType) {
    return NextResponse.json(
      { error: "localPath and artifactType are required" },
      { status: 400 },
    );
  }

  const db = getDb();
  const [row] = await db
    .insert(artifacts)
    .values({
      runId: runId ?? null,
      localPath,
      artifactType,
      description: description ?? null,
      metadata: metadata ?? null,
    })
    .returning();

  return NextResponse.json(row, { status: 201 });
});
