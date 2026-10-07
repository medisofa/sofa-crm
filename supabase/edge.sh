# 1.7.7 · Edge Function market-intel con su nombre (desde una terminal con Supabase CLI e inicio de sesión)
supabase functions download super-endpoint --project-ref bpwjhgpzhzhiocoxrvzq
mv supabase/functions/super-endpoint supabase/functions/market-intel
supabase functions deploy market-intel --project-ref bpwjhgpzhzhiocoxrvzq --no-verify-jwt
# Probar el botón "Actualizar noticias" en Mercado. Si funciona, borrar las dos que sobran:
supabase functions delete super-endpoint --project-ref bpwjhgpzhzhiocoxrvzq
supabase functions delete index-ts --project-ref bpwjhgpzhzhiocoxrvzq
