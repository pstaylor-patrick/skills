import { NextRequest, NextResponse } from "next/server";

export function withAuth(
  handler: (req: NextRequest) => Promise<NextResponse>,
): (req: NextRequest) => Promise<NextResponse> {
  return async (req: NextRequest) => {
    const apiKey = req.headers.get("x-api-key");
    const expectedKey = process.env.PST_CONTEXT_API_KEY;

    if (!expectedKey) {
      return NextResponse.json(
        { error: "Server misconfigured: PST_CONTEXT_API_KEY not set" },
        { status: 500 },
      );
    }

    if (!apiKey || apiKey !== expectedKey) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    return handler(req);
  };
}
