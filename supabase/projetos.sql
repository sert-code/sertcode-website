-- ════════════════════════════════════════════════════════════════
-- Projetos: pedido, tipo e histórico de situação
-- Rodar no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
-- ════════════════════════════════════════════════════════════════

-- 1. Dados de contato do cliente ─────────────────────────────────
-- Ficam no cadastro do cliente, não no projeto: um cliente tem vários
-- projetos e os dados de contato são sempre os mesmos.
alter table public.profiles
  add column if not exists phone2 text;

-- 2. Campos do pedido no projeto ─────────────────────────────────
alter table public.projects
  add column if not exists type         text,
  add column if not exists requested_at timestamptz default now(),
  add column if not exists started_at   timestamptz,
  add column if not exists finished_at  timestamptz,
  add column if not exists created_by   uuid;

-- Situações: cadastrado → andamento → concluido, podendo passar por
-- pausado ou terminar em cancelado.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'projects_status_check') then
    alter table public.projects
      add constraint projects_status_check
      check (status in ('cadastrado','andamento','pausado','cancelado','concluido'));
  end if;
end $$;

-- 3. Histórico de situação ───────────────────────────────────────
-- Cada mudança vira uma linha: quem mudou, quando e por quê. É o que
-- alimenta a linha do tempo na tela e o PDF do projeto.
create table if not exists public.project_history (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references public.projects(id) on delete cascade,
  status          text not null,
  note            text,
  changed_by      uuid,
  changed_by_name text,
  changed_at      timestamptz not null default now()
);

create index if not exists project_history_project_idx
  on public.project_history (project_id, changed_at);

-- 4. Quem lê e escreve ───────────────────────────────────────────
-- A equipe gerencia tudo; o cliente lê apenas o histórico dos projetos
-- dele, que é o mesmo que já enxerga no portal.
alter table public.project_history enable row level security;

drop policy if exists "equipe_gerencia_historico" on public.project_history;
create policy "equipe_gerencia_historico" on public.project_history
  for all to authenticated
  using (public.is_equipe()) with check (public.is_equipe());

drop policy if exists "cliente_le_historico" on public.project_history;
create policy "cliente_le_historico" on public.project_history
  for select to authenticated
  using (exists (
    select 1 from public.projects p
    where p.id = project_history.project_id and p.client_id = auth.uid()
  ));
