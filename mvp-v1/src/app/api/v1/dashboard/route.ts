import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth/context";

export async function GET(req: NextRequest) {
  try {
    const { supabase } = await requireUser();
    const org = new URL(req.url).searchParams.get("organization_id");
    if (!org) return NextResponse.json({ error: "organization_id required" }, { status: 422 });
    const { data, error } = await supabase.rpc("dashboard_v1", { p_org: org });
    if (error) throw error;
    return NextResponse.json({ data });
  } catch {
    return NextResponse.json({ error: "REQUEST_FAILED" }, { status: 400 });
  }
}
