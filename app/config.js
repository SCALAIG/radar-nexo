// Radar NEXO — configuración de la aplicación.
// El instalador (scripts/instalar.sh) llena SUPABASE_URL y SUPABASE_ANON_KEY por ti.
// Si lo haces a mano: Supabase → Project Settings → API → "Project URL" y clave pública "anon / publishable".
// NUNCA pegues aquí la clave "service_role"/"secret" ni la clave de Anthropic.
window.NEXO_CONFIG = {
  SUPABASE_URL: "https://bcvuezerjanaransmzek.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjdnVlemVyamFuYXJhbnNtemVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEyOTQ3OTcsImV4cCI6MjEwNjg3MDc5N30.gvOdQ5IBjtxNxBaZHDnA3FHk0RAylfZqDn11d3yKcVA",
  META_ENTRADA: 24,   // meta contractual (invitación CCB). El cupo de trabajo es 30: 6 de reserva para pruebas y reemplazos.
  META_SALIDA: 12
};
