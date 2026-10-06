# Radar NEXO — Guía de puesta en marcha

**Para:** Lucas Rodríguez · Scala Industries Group S.A.S.
**Tiempo:** ~30 minutos, de los cuales solo ~10 son trabajo tuyo en el navegador; el resto lo hace el instalador.

**Qué logras:** que tú y 2–4 consultores ingresen con usuario y contraseña, guarden los diagnósticos en una base de datos común y entreguen el análisis con IA al empresario al terminar cada sesión.

**Alcance:** meta contractual **24** diagnósticos de entrada y **12** de salida; el sistema está dimensionado para **30** (6 de reserva para pruebas, reprogramaciones y reemplazos).

---

## Cómo está armado

| Pieza | Qué hace | Dónde vive |
|---|---|---|
| Aplicación (`app/`) | Ingreso, diagnóstico, ficha, consolidado, equipo | https://scalaig.github.io/radar-nexo/app/ |
| Base de datos (Supabase) | Empresas, diagnósticos, historial de cambios, usuarios | Tu proyecto Supabase (plan Pro) |
| Función `analizar` | Pide el análisis a la API de Anthropic | Tu proyecto Supabase |
| Clave de Anthropic | Autoriza la IA y genera el costo | Solo como secreto de Supabase |

La **vista previa pública** (https://scalaig.github.io/radar-nexo/) no cambia: sin ingreso y sin guardar nada; es la que enlaza la propuesta.

> **Regla de oro:** las cuentas, los pagos y las claves los manejas **tú**. Nunca pegues la clave de Anthropic ni la clave secreta de Supabase en un archivo del repositorio ni en un chat. El instalador las pide en la terminal sin mostrarlas y no las escribe en ningún archivo.

---

## Parte A — Lo que haces tú en el navegador (~10 min)

1. **Supabase:** crea tu cuenta en https://supabase.com → **New project** → nombre `radar-nexo` → región **South America (São Paulo)** → una contraseña de base de datos larga (guárdala en tu gestor de contraseñas).
2. **Plan Pro:** Organization → Billing → **Pro** (ya contratado el 06/10/2026). Incluye respaldos diarios y que el proyecto no se pause por inactividad. Deja activado el **Spend cap** para evitar cobros inesperados. Verifica condiciones y precios vigentes en https://supabase.com/pricing.
3. **Referencia del proyecto:** Project Settings → General → **Reference ID** (20 letras minúsculas). Cópiala.
4. **Anthropic:** https://console.anthropic.com → **API Keys → Create key** (nómbrala `radar-nexo`). En **Limits / Billing** fija un **límite mensual de gasto** (ej. USD 20–30; el consumo real es de centavos por análisis, verifica los precios vigentes). Copia la clave: la pegarás en el instalador.

## Parte B — Lo hace el instalador (~10 min)

En la Terminal de tu Mac:

```bash
cd "/Users/lucasrodriguez/Documents/02_Clientes/INV. BUCARAMANGA /radar-nexo"
./scripts/instalar.sh
```

(Si dice «permission denied»: `chmod +x scripts/*.sh` y vuelve a correrlo.)

El instalador, paso a paso: abre el navegador para que autorices Supabase → aplica las tablas y reglas de seguridad → guarda tu clave de Anthropic como secreto del servidor → publica la función `analizar` → desactiva el registro público y fija la dirección de recuperación de contraseña → llena `app/config.js` con la URL y la clave **pública** → crea tu usuario administrador con una contraseña temporal que se muestra una sola vez.

Si algún paso automático falla, el instalador te dice cuál y cómo hacerlo a mano (ver «Plan B»).

## Parte C — Publicar (~2 min)

El instalador termina imprimiendo estos comandos:

```bash
git add app supabase docs scripts .gitignore README.md
git commit -m "Radar NEXO: version para el equipo"
git push origin main
```

Espera 1–2 minutos y abre https://scalaig.github.io/radar-nexo/app/ .

## Parte D — Equipo

Por cada consultor:

```bash
./scripts/crear_usuario.sh correo@dominio.com "Nombre Apellido" consultor
```

Crea el usuario ya **activo** y muestra una contraseña temporal aleatoria (entrégala por un canal seguro; cada quien puede cambiarla con «Olvidé mi contraseña»). Desde la app, en **Equipo**, puedes desactivar o cambiar el rol de cualquiera.

## Parte E — Prueba de humo (obligatoria antes de la primera sesión real)

La aplicación se probó con un simulador de Supabase (24/24 verificaciones) y los scripts contra un servidor simulado, **no contra tus servicios reales**. Esta prueba lo confirma:

- [ ] Ingresas como admin → ves **Equipo**.
- [ ] Creas un consultor de prueba → ingresa → **no** ve Equipo.
- [ ] Con el consultor: diagnóstico completo de una empresa ficticia (NIT 900000001) → **Ver diagnóstico** → queda guardado.
- [ ] Con otro usuario/navegador: buscas ese NIT y aparece la ficha con «Fase I aplicada por …».
- [ ] **Generar análisis** responde en menos de ~30 s. Si falla: Supabase → Edge Functions → `analizar` → Logs.
- [ ] **Consolidado** lista la empresa y **Exportar CSV** abre bien en Excel (tildes correctas).
- [ ] Un intento de crear cuenta desde la pantalla de ingreso no es posible (no hay registro).
- [ ] Borras la empresa de prueba (Supabase → Table Editor → `empresas`).

---

## Operación diaria

**Sesión virtual de ~60 min:** 5 min contexto y consentimiento · 10 min percepción del empresario · 30–35 min rúbrica de 7 dimensiones · 5 min brecha e indicador · 5–10 min lectura del análisis con el empresario. (Detalle en `MANUAL_CONSULTOR.md`.)

- El análisis con IA se genera en la ficha al terminar; se guarda y se puede regenerar.
- Quien aplica cada diagnóstico queda registrado (Fase I y Fase IV).
- Dos consultores no deben editar la misma empresa a la vez (gana el último en guardar; cada cambio queda en `empresas_historial`).
- **Capacidad del plan:** 8 días para la Fase I; 24 empresas = 3 por día, 30 = ~4 por día. Con 2–4 consultores son 1–2 sesiones por consultor por día; agenda con holgura.

## Respaldo

- El plan Pro hace respaldos diarios automáticos; `respaldar.sh` es un respaldo adicional, tuyo e independiente de Supabase.
- Además, al final de cada jornada: `./scripts/respaldar.sh` guarda una copia completa (empresas, historial, usuarios, uso de IA) en `respaldos/` (excluida de GitHub). Esa carpeta contiene datos personales: guárdala solo en tu equipo/nube privada.
- No borres usuarios ni tablas en Supabase sin respaldar antes.

## Datos personales (Ley 1581 de 2012)

- Usa `docs/AVISO_PRIVACIDAD_Y_CONSENTIMIENTO.md` al inicio de cada sesión (verbal o por correo previo) y conserva evidencia.
- El análisis con IA envía a la API de Anthropic: razón social, sector, niveles por dimensión, notas del consultor, brecha, indicador y lo que dijo el empresario. **No** envía NIT, contacto ni cargo. Pide a los consultores no escribir datos personales de terceros en las notas.
- Pide a un abogado que revise el texto definitivo y confirma si el CCB exige su propio formato de autorización.

## Pendientes que no dependen de la app

1. **Propuesta técnica del ejecutor de asistencia técnica:** cuando la subas, se ajustan dimensiones, criterio de «cerrabilidad» (8 h + voucher de $5.000.000), candidatas a producto mínimo viable y guía de calibración.
2. **Revocar el token de GitHub** que quedó visible en capturas de terminal (GitHub → Settings → Developer settings → Personal access tokens) y crear uno nuevo con el mínimo de permisos.
3. Convocatoria de empresas: cierra el **12 de octubre de 2026**.

---

## Plan B — Hacerlo a mano si el instalador falla en algún paso

1. **Tablas:** Supabase → SQL Editor → New query → pega `supabase/schema.sql` → Run.
2. **Registro y recuperación:** Authentication → Sign In / Providers → desactiva *Allow new users to sign up*. Authentication → URL Configuration → Site URL y Redirect URL = `https://scalaig.github.io/radar-nexo/app/`.
3. **Usuarios:** Authentication → Users → Add user → Create new user (marca *Auto Confirm User*). Luego, en SQL Editor, activa y asigna rol:
   ```sql
   update public.perfiles set rol = 'admin', activo = true where email = 'TU_CORREO@scala.com.co';
   ```
4. **IA:** Edge Functions → Secrets → `ANTHROPIC_API_KEY`. Edge Functions → Deploy a new function → Via Editor → nombre `analizar` → pega `supabase/functions/analizar/index.ts` → en sus ajustes desactiva *Enforce JWT verification*.
5. **Conexión:** Project Settings → API → copia *Project URL* y la clave pública *anon/publishable* en `app/config.js`.

## Si algo falla

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| «Falta configurar la conexión» | `app/config.js` con valores de ejemplo | Parte B o Plan B-5, y `git push` |
| «Correo o contraseña incorrectos» | Usuario no creado | Parte D |
| «Pendiente de activación» | Usuario inactivo | Admin → Equipo → activar |
| Análisis: «Falta configurar la clave…» | Falta el secreto | Repite `./scripts/instalar.sh` o Plan B-4 |
| Análisis: «Invalid JWT» / 401 | JWT enforcement activo | Plan B-4 (desactivarlo) |
| Análisis: 429 | Límite diario por usuario | Cambiar `LIMITE_DIARIO` en Edge Functions → Secrets |
| No guarda / «permission denied» | Esquema no aplicado o usuario inactivo | Plan B-1 y B-3 |
