import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/db";
import { artifacts } from "@/db/schema";
import { desc, eq } from "drizzle-orm";
import { withAuth } from "@/middleware/auth";
import { parseLimit } from "@/lib/query";
import { validateArtifactInput } from "@/lib/validation";

export const GET = withAuth(async (req: NextRequest) => {
  const { searchParams } = new URL(req.url);
  const runId = searchParams.get("runId");
  const artifactType = searchParams.get("type");
  const limit = parseLimit(searchParams.get("limit"));

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
  let body;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const result = validateArtifactInput(body);
  if (!result.valid) {
    return NextResponse.json({ error: result.error }, { status: 400 });
  }

  const db = getDb();
  const [row] = await db.insert(artifacts).values(result.data).returning();

  return NextResponse.json(row, { status: 201 });
});
