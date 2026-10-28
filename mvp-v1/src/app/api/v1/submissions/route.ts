import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/auth/context";

const schema = z.object({ claim_ids: z.array(z.string().uuid()).min(1).max(500) });

export async function POST(req: NextRequest) {
  try {
    const { supabase } = await requireUser();
    const parsed = schema.safeParse(await req.json());
    if (!parsed.success) return NextResponse.json({ error: "VALIDATION_ERROR", details: parsed.error.flatten() }, { status: 422 });
    const { data, error } = await supabase.rpc("submission_create_v1", { p_claims: parsed.data.claim_ids });
    if (error) throw error;
    return NextResponse.json({ data }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "REQUEST_FAILED" }, { status: 400 });
  }
}
