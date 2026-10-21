/** Preferencia personal de dashboard del cliente */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };

export async function getDashboardPreference(organizationId) {
  const { data, error } = await sb().from('user_dashboard_preferences')
    .select('dashboard_code')
    .eq('organization_id', organizationId)
    .maybeSingle();
  if (error) throw error;
  return data?.dashboard_code || 'ejecutivo';
}

export async function setDashboardPreference(organizationId, dashboardCode) {
  return must(await sb().from('user_dashboard_preferences')
    .upsert({
      user_id: (await sb().auth.getUser()).data.user.id,
      organization_id: organizationId,
      dashboard_code: dashboardCode,
      updated_at: new Date().toISOString()
    }, { onConflict: 'user_id,organization_id' })
    .select('dashboard_code')
    .single());
}
