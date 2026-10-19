import { NextResponse } from "next/server";

export async function GET() {
  return NextResponse.json({
    ok: true,
    service: "sofa-mvp-v1",
    time: new Date().toISOString()
  });
}
