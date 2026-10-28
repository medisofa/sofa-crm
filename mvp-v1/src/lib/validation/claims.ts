import { z } from "zod";

export const claimCreateSchema = z.object({
  organization_id: z.string().uuid(),
  provider_id: z.string().uuid(),
  ars_id: z.string().uuid(),
  service_date: z.string().date(),
  patient_name: z.string().trim().min(2).max(150),
  member_number: z.string().trim().min(2).max(60),
  authorization_number: z.string().trim().max(80).optional().nullable(),
  procedure_id: z.string().uuid(),
  quantity: z.number().int().min(1).max(99).default(1),
  unit_amount: z.number().nonnegative().max(100000000),
  notes: z.string().trim().max(500).optional().nullable()
});

export const claimTransitionSchema = z.object({
  to_status: z.enum([
    "captured","received","validated","submitted","observed",
    "denied","paid","closed"
  ]),
  note: z.string().trim().max(500).optional().nullable()
});
