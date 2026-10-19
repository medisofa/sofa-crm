import { supabaseServer } from "@/lib/supabase/server";

export type Membership = {
  organization_id: string;
  organization_name: string;
  role_code: string;
  kind: "operator" | "client";
};

export async function requireUser() {
  const supabase = await supabaseServer();
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) throw new Error("UNAUTHENTICATED");

  const { data, error: ctxError } = await supabase.rpc("my_context_v1");
  if (ctxError) throw ctxError;

  return {
    supabase,
    user,
    memberships: (data?.memberships ?? []) as Membership[]
  };
}
