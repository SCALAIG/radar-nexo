-- =====================================================================
-- Radar NEXO — esquema de base de datos (Supabase / PostgreSQL)
-- Scala Industries Group S.A.S. · Programa NEXO (Cámara de Comercio de Bucaramanga)
--
-- CÓMO USARLO: en el panel de Supabase abre "SQL Editor" → "New query",
-- pega TODO este archivo y pulsa "Run". Es seguro ejecutarlo más de una vez.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. PERFILES (un perfil por usuario del equipo)
--    rol: 'admin' (Lucas) o 'consultor'.
--    activo: solo los usuarios activos pueden ver y guardar diagnósticos.
--    Todo usuario nuevo nace INACTIVO; el admin lo activa desde la vista
--    "Equipo" de la aplicación. Así, aunque alguien lograra registrarse,
--    no vería ningún dato.
-- ---------------------------------------------------------------------
create table if not exists public.perfiles (
  id        uuid primary key references auth.users(id) on delete cascade,
  email     text not null,
  nombre    text,
  rol       text not null default 'consultor' check (rol in ('admin','consultor')),
  activo    boolean not null default false,
  creado_en timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfiles (id, email, nombre)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Funciones auxiliares de permisos (security definer para evitar recursión en RLS)
create or replace function public.es_miembro()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.perfiles where id = auth.uid() and activo);
$$;

create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.perfiles where id = auth.uid() and activo and rol = 'admin');
$$;

-- ---------------------------------------------------------------------
-- 2. EMPRESAS (un registro por NIT; el diagnóstico completo va en "data")
-- ---------------------------------------------------------------------
create table if not exists public.empresas (
  nit                   text primary key check (nit ~ '^[0-9]{3,15}$'),
  nombre                text not null,
  data                  jsonb not null default '{}'::jsonb,
  creado_en             timestamptz not null default now(),
  actualizado_en        timestamptz not null default now(),
  actualizado_por       uuid references auth.users(id) on delete set null,
  actualizado_por_email text
);

create or replace function public.empresas_sellar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.actualizado_en := now();
  new.actualizado_por := auth.uid();
  new.actualizado_por_email := (select email from public.perfiles where id = auth.uid());
  return new;
end;
$$;

drop trigger if exists empresas_sellar_tg on public.empresas;
create trigger empresas_sellar_tg
  before insert or update on public.empresas
  for each row execute function public.empresas_sellar();

-- ---------------------------------------------------------------------
-- 3. HISTORIAL (cada cambio queda registrado; permite recuperar versiones)
-- ---------------------------------------------------------------------
create table if not exists public.empresas_historial (
  id                bigint generated always as identity primary key,
  nit               text not null,
  operacion         text not null,
  data              jsonb,
  cambiado_en       timestamptz not null default now(),
  cambiado_por      uuid,
  cambiado_por_email text
);

create or replace function public.empresas_registrar_historial()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'DELETE') then
    insert into public.empresas_historial (nit, operacion, data, cambiado_por, cambiado_por_email)
    values (old.nit, tg_op, old.data, auth.uid(), (select email from public.perfiles where id = auth.uid()));
    return old;
  else
    insert into public.empresas_historial (nit, operacion, data, cambiado_por, cambiado_por_email)
    values (new.nit, tg_op, new.data, auth.uid(), (select email from public.perfiles where id = auth.uid()));
    return new;
  end if;
end;
$$;

drop trigger if exists empresas_historial_tg on public.empresas;
create trigger empresas_historial_tg
  after insert or update or delete on public.empresas
  for each row execute function public.empresas_registrar_historial();

-- ---------------------------------------------------------------------
-- 4. USO DE IA (control de consumo del análisis automático)
-- ---------------------------------------------------------------------
create table if not exists public.uso_ia (
  id        bigint generated always as identity primary key,
  user_id   uuid,
  email     text,
  tipo      text,
  creado_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 5. SEGURIDAD POR FILAS (RLS): nadie ve nada sin ser miembro activo
-- ---------------------------------------------------------------------
alter table public.perfiles           enable row level security;
alter table public.empresas           enable row level security;
alter table public.empresas_historial enable row level security;
alter table public.uso_ia             enable row level security;

drop policy if exists perfiles_ver     on public.perfiles;
drop policy if exists perfiles_editar  on public.perfiles;
create policy perfiles_ver    on public.perfiles for select to authenticated
  using (id = auth.uid() or public.es_admin());
create policy perfiles_editar on public.perfiles for update to authenticated
  using (public.es_admin()) with check (public.es_admin());

drop policy if exists empresas_ver       on public.empresas;
drop policy if exists empresas_crear     on public.empresas;
drop policy if exists empresas_editar    on public.empresas;
drop policy if exists empresas_eliminar  on public.empresas;
create policy empresas_ver      on public.empresas for select to authenticated using (public.es_miembro());
create policy empresas_crear    on public.empresas for insert to authenticated with check (public.es_miembro());
create policy empresas_editar   on public.empresas for update to authenticated
  using (public.es_miembro()) with check (public.es_miembro());
create policy empresas_eliminar on public.empresas for delete to authenticated using (public.es_admin());

drop policy if exists historial_ver on public.empresas_historial;
create policy historial_ver on public.empresas_historial for select to authenticated using (public.es_admin());

drop policy if exists uso_ia_ver on public.uso_ia;
create policy uso_ia_ver on public.uso_ia for select to authenticated using (public.es_admin());

-- ---------------------------------------------------------------------
-- 6. FUNCIÓN DE GUARDADO (la usa la aplicación)
--    p_reemplazar = true  → reemplaza todo el documento
--    p_reemplazar = false → mezcla campos de primer nivel (entrada, salida, ...)
-- ---------------------------------------------------------------------
create or replace function public.guardar_empresa(
  p_nit        text,
  p_nombre     text,
  p_patch      jsonb,
  p_reemplazar boolean default false
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  resultado jsonb;
begin
  if not public.es_miembro() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  insert into public.empresas (nit, nombre, data)
  values (p_nit, coalesce(nullif(p_nombre, ''), p_nit), coalesce(p_patch, '{}'::jsonb))
  on conflict (nit) do update
    set nombre = coalesce(nullif(p_nombre, ''), public.empresas.nombre),
        data   = case when p_reemplazar then coalesce(p_patch, '{}'::jsonb)
                      else public.empresas.data || coalesce(p_patch, '{}'::jsonb) end
  returning data into resultado;

  return resultado;
end;
$$;

grant execute on function public.guardar_empresa(text, text, jsonb, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 7. PRIMER ADMINISTRADOR
--    Después de crear tu usuario en Authentication → Users, ejecuta esto
--    (cambia el correo por el tuyo) para activarte como administrador:
--
--    update public.perfiles
--       set rol = 'admin', activo = true
--     where email = 'TU_CORREO@scala.com.co';
-- ---------------------------------------------------------------------
