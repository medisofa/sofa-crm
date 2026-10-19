import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/auth/context";

const schema = z.object({
  claim_id: z.string().uuid(),
  reason: z.string().trim().min(3).max(500),
  reason_code: z.string().trim().max(40).optional().nullable(),
  amount: z.number().nonnegative().optional().nullable()
});

export async function POST(req: NextRequest) {
  try {
    const { supabase } = await requireUser();
    const parsed = schema.safeParse(await req.json());
    if (!parsed.success) return NextResponse.json({ error: "VALIDATION_ERROR", details: parsed.error.flatten() }, { status: 422 });
    const { data, error } = await supabase.rpc("denial_create_v1", {
      p_claim: parsed.data.claim_id,
      p_reason: parsed.data.reason,
      p_reason_code: parsed.data.reason_code ?? null,
      p_amount: parsed.data.amount ?? null
    });
    if (error) throw error;
    return NextResponse.json({ data }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "REQUEST_FAILED" }, { status: 400 });
  }
}
