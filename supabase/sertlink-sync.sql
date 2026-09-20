-- ════════════════════════════════════════════════════════════════
-- Espelho dos clientes e chamados do SertLink
-- Rodar no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
--
-- Estas tabelas sao ESCRITAS apenas pelo SertLink, pela rotina de
-- sincronizacao que usa a chave service_role. Aqui no painel da
-- SertCode elas sao somente leitura.
-- ════════════════════════════════════════════════════════════════

-- 1. Clientes vindos do SertLink ─────────────────────────────────
create table if not exists public.sertlink_clients (
  id                    text primary key,   -- companies.id no SertLink
  name                  text not null,
  slug                  text,
  email                 text,
  phone                 text,
  owner_name            text,
  owner_nickname        text,

  -- Situacao consolidada, calculada pelo SertLink:
  -- teste | ativo | expirado | cancelado | excluindo
  status                text not null,
  plan                  text,               -- PRIME | ELITE | INFINITY
  plan_name             text,               -- Start | Plus | Ultra
  plan_price            numeric(10,2),
  cycle                 text,               -- MENSAL | ANUAL
  payment_method        text,               -- CARD | PIX

  subscribed            boolean not null default false,
  subscribed_at         timestamptz,
  trial_ends_at         timestamptz,
  trial_days_left       integer,
  period_end            timestamptz,
  cancelled_at          timestamptz,
  deletion_requested_at timestamptz,

  created_at            timestamptz,        -- cadastro no SertLink
  synced_at             timestamptz not null default now()
);

create index if not exists sertlink_clients_status_idx on public.sertlink_clients (status);

-- 2. Chamados abertos no SertLink ────────────────────────────────
create table if not exists public.sertlink_tickets (
  id             text primary key,
  company_id     text not null references public.sertlink_clients(id) on delete cascade,
  company_name   text,
  subject        text not null,
  category       text,
  description    text,
  status         text not null,   -- ABERTO | EM_ANDAMENTO | RESOLVIDO | CONCLUIDO
  messages_count integer not null default 0,
  last_message_at timestamptz,
  created_at     timestamptz,
  updated_at     timestamptz,
  synced_at      timestamptz not null default now()
);

create index if not exists sertlink_tickets_status_idx  on public.sertlink_tickets (status);
create index if not exists sertlink_tickets_company_idx on public.sertlink_tickets (company_id, created_at desc);

-- 3. Leitura para a equipe ───────────────────────────────────────
-- A chave service_role usada pelo SertLink ignora RLS e continua
-- podendo gravar; o painel, autenticado como gestor ou colaborador,
-- apenas le.
alter table public.sertlink_clients enable row level security;
alter table public.sertlink_tickets enable row level security;

drop policy if exists "equipe_le_clientes_sertlink" on public.sertlink_clients;
create policy "equipe_le_clientes_sertlink" on public.sertlink_clients
  for select to authenticated using (public.is_equipe());

drop policy if exists "equipe_le_chamados_sertlink" on public.sertlink_tickets;
create policy "equipe_le_chamados_sertlink" on public.sertlink_tickets
  for select to authenticated using (public.is_equipe());
