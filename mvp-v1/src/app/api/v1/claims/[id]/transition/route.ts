import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth/context";
import { claimTransitionSchema } from "@/lib/validation/claims";

export async function POST(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await ctx.params;
    const { supabase } = await requireUser();
    const parsed = claimTransitionSchema.safeParse(await req.json());
    if (!parsed.success) {
      return NextResponse.json({ error: "VALIDATION_ERROR", details: parsed.error.flatten() }, { status: 422 });
    }

    const { data, error } = await supabase.rpc("claim_transition_v1", {
      p_claim: id,
      p_to_status: parsed.data.to_status,
      p_note: parsed.data.note ?? null
    });
    if (error) throw error;
    return NextResponse.json({ data });
  } catch (e) {
    const message = e instanceof Error ? e.message : "UNKNOWN";
    if (message === "UNAUTHENTICATED") return NextResponse.json({ error: message }, { status: 401 });
    return NextResponse.json({ error: "REQUEST_FAILED" }, { status: 400 });
  }
}
