import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

type CookieWrite = {
  name: string;
  value: string;
  options?: any;
};

export async function supabaseServer() {
  const store = await cookies();
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) throw new Error("Supabase environment is not configured.");

  return createServerClient(url, key, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (values: CookieWrite[]) => {
        try {
          values.forEach(({ name, value, options }) => store.set(name, value, options));
        } catch {
          // Server Components may be read-only. Route handlers can persist cookies.
        }
      }
    }
  });
}
