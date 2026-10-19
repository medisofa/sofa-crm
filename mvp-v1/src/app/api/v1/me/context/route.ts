import { NextResponse } from "next/server";
import { requireUser } from "@/lib/auth/context";

export async function GET() {
  try {
    const { user, memberships } = await requireUser();
    return NextResponse.json({ data: { user_id: user.id, email: user.email, memberships } });
  } catch {
    return NextResponse.json({ error: "UNAUTHENTICATED" }, { status: 401 });
  }
}
