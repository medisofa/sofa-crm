import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/auth/context";

const schema = z.object({
  organization_id: z.string().uuid(),
  ars_id: z.string().uuid(),
  paid_on: z.string().date(),
  amount: z.number().positive(),
  reference: z.string().trim().max(120).optional().nullable(),
  allocations: z.array(z.object({ claim_id: z.string().uuid(), amount: z.number().positive() })).min(1)
});

export async function POST(req: NextRequest) {
  try {
    const { supabase } = await requireUser();
    const parsed = schema.safeParse(await req.json());
    if (!parsed.success) return NextResponse.json({ error: "VALIDATION_ERROR", details: parsed.error.flatten() }, { status: 422 });
    const v = parsed.data;
    const { data, error } = await supabase.rpc("payment_register_v1", {
      p_org: v.organization_id, p_ars: v.ars_id, p_paid_on: v.paid_on,
      p_amount: v.amount, p_reference: v.reference ?? null, p_allocations: v.allocations
    });
    if (error) throw error;
    return NextResponse.json({ data }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "REQUEST_FAILED" }, { status: 400 });
  }
}
