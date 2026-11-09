-- ════════════════════════════════════════════════════════════════
-- Equipe: perfis de acesso, permissões e histórico
-- Rodar no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
--
-- O painel tinha dois níveis: gestor e colaborador. O modelo do
-- SertLink pede cinco perfis e permissões pessoa a pessoa.
-- ════════════════════════════════════════════════════════════════

-- 1. Perfil de acesso ────────────────────────────────────────────
-- `role` continua sendo o portão grosso que TODAS as policies já usam
-- (gestor / colaborador / client). O perfil fino entra numa coluna
-- nova, para não reescrever as regras de acesso de todas as tabelas.
alter table public.profiles
  add column if not exists perfil           text,
  add column if not exists duas_etapas      boolean not null default false,
  add column if not exists senha_provisoria boolean not null default false,
  add column if not exists ultimo_acesso    timestamptz,
  add column if not exists bloqueado_ate    timestamptz;

update public.profiles set perfil = case
  when role = 'gestor' then 'ADMINISTRADOR'
  when role = 'colaborador' then 'SUPORTE'
  else null
end
where perfil is null and role in ('gestor', 'colaborador');

alter table public.profiles drop constraint if exists profiles_perfil_check;
alter table public.profiles
  add constraint profiles_perfil_check
  check (perfil is null or perfil in ('ADMINISTRADOR','GESTOR','SUPORTE','FINANCEIRO','RH'));

-- Administrador é o único perfil que abre a porta toda; por isso ele, e
-- só ele, carrega role = 'gestor'.
create or replace function public.perfil_define_role()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.perfil is not null then
    new.role := case when new.perfil = 'ADMINISTRADOR' then 'gestor' else 'colaborador' end;
  end if;
  return new;
end $$;

drop trigger if exists perfil_define_role on public.profiles;
create trigger perfil_define_role
  before insert or update of perfil on public.profiles
  for each row execute function public.perfil_define_role();

-- 2. Permissões ──────────────────────────────────────────────────
-- Guarda só o que foge do padrão do perfil: uma linha por exceção.
create table if not exists public.equipe_permissoes (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  chave      text not null,
  permitido  boolean not null,
  definido_por text,
  updated_at timestamptz not null default now(),
  unique (profile_id, chave)
);

-- 3. Histórico de acessos ────────────────────────────────────────
create table if not exists public.equipe_acessos (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  pessoa     text,
  evento     text not null,
  detalhe    text,
  created_at timestamptz not null default now()
);

create index if not exists equipe_acessos_idx
  on public.equipe_acessos (created_at desc);

-- 4. Acesso ──────────────────────────────────────────────────────
alter table public.equipe_permissoes enable row level security;
alter table public.equipe_acessos    enable row level security;

drop policy if exists "gestor_gerencia_permissoes" on public.equipe_permissoes;
create policy "gestor_gerencia_permissoes" on public.equipe_permissoes
  for all to authenticated
  using (public.is_gestor()) with check (public.is_gestor());

-- Cada pessoa precisa ler as próprias permissões para o painel saber o
-- que mostrar; ler não é poder alterar.
drop policy if exists "equipe_le_proprias_permissoes" on public.equipe_permissoes;
create policy "equipe_le_proprias_permissoes" on public.equipe_permissoes
  for select to authenticated
  using (profile_id = auth.uid());

drop policy if exists "gestor_le_acessos" on public.equipe_acessos;
create policy "gestor_le_acessos" on public.equipe_acessos
  for select to authenticated
  using (public.is_gestor());

-- Qualquer pessoa da equipe registra o próprio evento: é assim que a
-- entrada no painel entra no histórico.
drop policy if exists "equipe_registra_acesso" on public.equipe_acessos;
create policy "equipe_registra_acesso" on public.equipe_acessos
  for insert to authenticated
  with check (profile_id = auth.uid() or public.is_gestor());

-- 5. Proteção do último administrador ────────────────────────────
-- Desligar o último administrador deixaria o painel sem quem libere
-- acessos, e ninguém de dentro conseguiria se promover de volta.
create or replace function public.protege_ultimo_admin()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  restantes int;
begin
  if old.perfil = 'ADMINISTRADOR'
     and (tg_op = 'DELETE' or new.perfil is distinct from 'ADMINISTRADOR' or new.status <> 'ativo') then
    select count(*) into restantes
    from public.profiles
    where perfil = 'ADMINISTRADOR' and status = 'ativo' and id <> old.id;

    if restantes = 0 then
      raise exception 'O último administrador não pode ser desligado nem trocar de perfil.';
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists protege_ultimo_admin on public.profiles;
create trigger protege_ultimo_admin
  before update or delete on public.profiles
  for each row execute function public.protege_ultimo_admin();
