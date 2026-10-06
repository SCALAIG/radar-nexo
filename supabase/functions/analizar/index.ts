// Radar NEXO — Edge Function "analizar"
// Recibe el texto (prompt) armado por la aplicación y devuelve el análisis
// generado por la API de Anthropic. La clave de la API vive SOLO como secreto
// del servidor (ANTHROPIC_API_KEY); nunca llega al navegador.
//
// Seguridad:
//  - Solo usuarios con sesión válida Y perfil activo pueden usarla.
//  - Límite diario por usuario (LIMITE_DIARIO, por defecto 150 llamadas).
//  - Tamaño máximo del prompt y de la respuesta.

import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_PROMPT_CHARS = 24000;
const MAX_TOKENS = 1600;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY");
  const MODEL = Deno.env.get("ANTHROPIC_MODEL") || "claude-sonnet-5-5";
  const LIMITE_DIARIO = Number(Deno.env.get("LIMITE_DIARIO") || "150");

  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "Servidor mal configurado" }, 500);
  if (!ANTHROPIC_KEY) return json({ error: "Falta configurar la clave de la API de IA" }, 503);

  // 1) Identificar al usuario a partir de su sesión
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Sin sesión" }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data: userData, error: userErr } = await admin.auth.getUser(token);
  if (userErr || !userData?.user) return json({ error: "Sesión no válida" }, 401);
  const user = userData.user;

  // 2) Verificar que sea miembro activo del equipo
  const { data: perfil } = await admin
    .from("perfiles")
    .select("activo,email")
    .eq("id", user.id)
    .maybeSingle();
  if (!perfil || !perfil.activo) return json({ error: "Usuario no autorizado" }, 403);

  // 3) Validar la solicitud
  let body: { prompt?: string; tipo?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Solicitud inválida" }, 400);
  }
  const prompt = typeof body.prompt === "string" ? body.prompt : "";
  const tipo = body.tipo === "contexto" ? "contexto" : "analisis";
  if (!prompt.trim()) return json({ error: "Falta el texto a analizar" }, 400);
  if (prompt.length > MAX_PROMPT_CHARS) return json({ error: "El texto es demasiado largo" }, 413);

  // 4) Límite diario por usuario
  const desde = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count } = await admin
    .from("uso_ia")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("creado_en", desde);
  if ((count ?? 0) >= LIMITE_DIARIO) {
    return json({ error: "Se alcanzó el límite diario de análisis para este usuario" }, 429);
  }

  // 5) Llamar a la API de Anthropic
  let resp: Response;
  try {
    resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": ANTHROPIC_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: MAX_TOKENS,
        messages: [{ role: "user", content: prompt }],
      }),
    });
  } catch {
    return json({ error: "No se pudo contactar el servicio de IA" }, 502);
  }

  if (!resp.ok) {
    const detalle = await resp.text().catch(() => "");
    console.error("Anthropic error", resp.status, detalle.slice(0, 500));
    return json({ error: "El servicio de IA respondió con un error (" + resp.status + ")" }, 502);
  }

  const out = await resp.json();
  const text = Array.isArray(out?.content)
    ? out.content.filter((b: { type: string }) => b.type === "text").map((b: { text: string }) => b.text).join("\n")
    : "";
  if (!text) return json({ error: "Respuesta vacía del servicio de IA" }, 502);

  // 6) Registrar el uso (sin guardar el contenido)
  await admin.from("uso_ia").insert({ user_id: user.id, email: perfil.email, tipo });

  return json({ text });
});
