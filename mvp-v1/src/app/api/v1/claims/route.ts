import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth/context";
import { claimCreateSchema } from "@/lib/validation/claims";

export async function GET(req: NextRequest) {
  try {
    const { supabase } = await requireUser();
    const url = new URL(req.url);
    const org = url.searchParams.get("organization_id");
    const status = url.searchParams.get("status");
    const page = Math.max(Number(url.searchParams.get("page") || "0"), 0);
    const pageSize = Math.min(Math.max(Number(url.searchParams.get("page_size") || "25"), 1), 100);

    let q = supabase
      .from("claims_v1")
      .select("id,folio,organization_id,provider_id,ars_id,service_date,patient_name,member_number,authorization_number,procedure_id,quantity,unit_amount,amount,status,created_at,updated_at", { count: "exact" })
      .order("created_at", { ascending: false })
      .range(page * pageSize, page * pageSize + pageSize - 1);

    if (org) q = q.eq("organization_id", org);
    if (status) q = q.eq("status", status);

    const { data, error, count } = await q;
    if (error) throw error;

    return NextResponse.json({ data, page, page_size: pageSize, total: count ?? 0 });
  } catch (e) {
    return apiError(e);
  }
}

export async function POST(req: NextRequest) {
  try {
    const { supabase } = await requireUser();
    const parsed = claimCreateSchema.safeParse(await req.json());
    if (!parsed.success) {
      return NextResponse.json({ error: "VALIDATION_ERROR", details: parsed.error.flatten() }, { status: 422 });
    }

    const { data, error } = await supabase.rpc("claim_create_v1", { p_input: parsed.data });
    if (error) throw error;
    return NextResponse.json({ data }, { status: 201 });
  } catch (e) {
    return apiError(e);
  }
}

function apiError(e: unknown) {
  const message = e instanceof Error ? e.message : "UNKNOWN";
  if (message === "UNAUTHENTICATED") return NextResponse.json({ error: message }, { status: 401 });
  return NextResponse.json({ error: "REQUEST_FAILED" }, { status: 400 });
}
