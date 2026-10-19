import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth/context";

export async function GET(req: NextRequest) {
  try {
    const { supabase } = await requireUser();
    const q = new URL(req.url).searchParams;
    const org = q.get("organization_id");
    const provider = q.get("provider_id");
    const ars = q.get("ars_id");
    const date = q.get("service_date");

    if (!org) return NextResponse.json({ error: "organization_id required" }, { status: 422 });

    if (provider && ars && date) {
      const { data, error } = await supabase
        .from("tariffs_v1")
        .select("id,amount,valid_from,valid_to,procedure:procedures_v1(id,internal_code,name,simon_code,cups_code)")
        .eq("organization_id", org)
        .eq("provider_id", provider)
        .eq("ars_id", ars)
        .eq("status", "active")
        .lte("valid_from", date)
        .or(`valid_to.is.null,valid_to.gte.${date}`);
      if (error) throw error;
      return NextResponse.json({ data: { tariffs: data ?? [] } });
    }

    const [providers, arss] = await Promise.all([
      supabase.from("providers_v1").select("id,full_name,specialty").eq("organization_id", org).eq("is_active", true).order("full_name"),
      supabase.from("ars_v1").select("id,code,name").eq("is_active", true).order("name")
    ]);
    if (providers.error) throw providers.error;
    if (arss.error) throw arss.error;
    return NextResponse.json({ data: { providers: providers.data ?? [], ars: arss.data ?? [] } });
  } catch {
    return NextResponse.json({ error: "REQUEST_FAILED" }, { status: 400 });
  }
}
