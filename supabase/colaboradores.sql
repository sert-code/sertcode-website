-- ════════════════════════════════════════════════════════════════
-- Acesso da equipe SertCode (colaboradores)
-- Rodar uma vez no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
-- ════════════════════════════════════════════════════════════════

-- 1. Dados de cadastro do colaborador ─────────────────────────────
-- Contas já existentes recebem status 'ativo' e continuam entrando normalmente.
alter table public.profiles
  add column if not exists email      text,
  add column if not exists nickname   text,
  add column if not exists birth_date date,
  add column if not exists phone      text,
  add column if not exists status     text not null default 'ativo',
  add column if not exists created_at timestamptz not null default now();

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_status_check') then
    alter table public.profiles
      add constraint profiles_status_check
      check (status in ('pendente', 'ativo', 'recusado', 'inativo'));
  end if;
end $$;


-- 2. Quem é da equipe ────────────────────────────────────────────
create or replace function public.is_gestor()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'gestor' and status = 'ativo'
  );
$$;

create or replace function public.is_equipe()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('gestor', 'colaborador') and status = 'ativo'
  );
$$;


-- 3. Cadastro pelo site cria o perfil como PENDENTE ───────────────
-- O papel é fixado aqui: nada que venha do formulário consegue virar gestor.
create or replace function public.handle_new_colaborador()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  if meta->>'signup_type' = 'colaborador' then
    insert into public.profiles (id, email, name, nickname, birth_date, phone, role, status)
    values (
      new.id,
      new.email,
      meta->>'name',
      meta->>'nickname',
      nullif(meta->>'birth_date', '')::date,
      meta->>'phone',
      'colaborador',
      'pendente'
    )
    on conflict (id) do update set
      email = excluded.email, name = excluded.name, nickname = excluded.nickname,
      birth_date = excluded.birth_date, phone = excluded.phone,
      role = 'colaborador', status = 'pendente';
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_created_colaborador on auth.users;
create trigger on_auth_user_created_colaborador
  after insert on auth.users
  for each row execute function public.handle_new_colaborador();


-- 4. Só gestor muda papel ou status ──────────────────────────────
-- Vale para qualquer requisição feita pelo site, independente das policies.
-- O SQL Editor e a chave service_role continuam podendo alterar.
create or replace function public.protect_profile_access()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_user in ('anon', 'authenticated') and not public.is_gestor() then
    if tg_op = 'INSERT' and new.role in ('gestor', 'colaborador') then
      raise exception 'Somente um gestor pode criar acessos da equipe.';
    end if;
    if tg_op = 'UPDATE' and (new.role is distinct from old.role or new.status is distinct from old.status) then
      raise exception 'Somente um gestor pode alterar papel ou status de acesso.';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists protect_profile_access on public.profiles;
create trigger protect_profile_access
  before insert or update on public.profiles
  for each row execute function public.protect_profile_access();


-- 5. Permissões de leitura e escrita ─────────────────────────────
alter table public.profiles enable row level security;

drop policy if exists "perfil_proprio_ou_equipe_le" on public.profiles;
create policy "perfil_proprio_ou_equipe_le" on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_equipe());

drop policy if exists "gestor_atualiza_perfis" on public.profiles;
create policy "gestor_atualiza_perfis" on public.profiles
  for update to authenticated
  using (public.is_gestor()) with check (public.is_gestor());

-- Colaboradores atendem chamados e acompanham projetos e arquivos dos clientes.
-- Financeiro, depoimentos e feedbacks continuam restritos ao gestor.
drop policy if exists "equipe_gerencia_chamados" on public.tickets;
create policy "equipe_gerencia_chamados" on public.tickets
  for all to authenticated using (public.is_equipe()) with check (public.is_equipe());

drop policy if exists "equipe_gerencia_projetos" on public.projects;
create policy "equipe_gerencia_projetos" on public.projects
  for all to authenticated using (public.is_equipe()) with check (public.is_equipe());

drop policy if exists "equipe_gerencia_arquivos" on public.files;
create policy "equipe_gerencia_arquivos" on public.files
  for all to authenticated using (public.is_equipe()) with check (public.is_equipe());


-- ════════════════════════════════════════════════════════════════
-- Conferência (opcional): policies existentes que ainda só aceitam
-- role = 'gestor' e podem precisar incluir colaboradores.
-- select tablename, policyname, qual from pg_policies
-- where schemaname = 'public' and qual ilike '%gestor%';
-- ════════════════════════════════════════════════════════════════
