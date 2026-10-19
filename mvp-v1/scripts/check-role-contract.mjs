import fs from "node:fs";

function assert(ok, message) {
  if (!ok) {
    console.error("ROLE CONTRACT FAIL:", message);
    process.exitCode = 1;
  } else {
    console.log("PASS:", message);
  }
}

const permissions = fs.readFileSync("../js/utils/permissions.js", "utf8");
const adminUsers = fs.readFileSync("../supabase/functions/admin-users/index.ts", "utf8");

assert(/billing:\s*\{\s*name:\s*'Facturación y Radicación'/.test(permissions),
  "billing is named Facturación y Radicación");
assert(/glosas:\s*\{\s*name:\s*'Cobros, Conciliación y Glosas'/.test(permissions),
  "glosas owns collections/conciliation");
assert(/BILLING_ROUTES[\s\S]*?'radicaciones'/.test(permissions),
  "billing can reach radicaciones");
assert(/'payments\.create':\s*\['super_admin',\s*'admin',\s*'glosas'\]/.test(permissions),
  "payment creation belongs to glosas/admin, not billing");
assert(!/'payments\.create':\s*\[[^\]]*'billing'/.test(permissions),
  "billing cannot create ARS payments");
assert(/ASSIGNABLE_ROLES[\s\S]*'capturer'/.test(adminUsers),
  "capturer is assignable in admin-users");
assert(!/ASSIGNABLE_ROLES\s*=\s*\[[^\]]*'prospect'/.test(adminUsers),
  "prospect is not assignable as organization membership");
assert(/Prospecto NO es asignable aquí/.test(adminUsers),
  "prospect onboarding rule is documented");
assert(/AUTH_REDIRECT_URL/.test(adminUsers),
  "admin-users supports configurable auth redirect");
assert(!/\/login\.html/.test(adminUsers),
  "admin-users no longer hardcodes legacy login.html");
assert(/\/login/.test(adminUsers),
  "admin-users falls back to the Next.js /login route");

if (process.exitCode) process.exit(process.exitCode);
console.log("Role contract validated.");
