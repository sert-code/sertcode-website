-- ════════════════════════════════════════════════════════════════
-- Financeiro: faturas, recebimentos, pendências e reembolsos
-- Rodar no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
--
-- A tabela de faturas tinha valor, vencimento e pago/pendente. Para
-- chegar ao modelo do SertLink faltava número, competência, tipo de
-- contrato, desconto, forma de pagamento e o rastro da cobrança.
-- ════════════════════════════════════════════════════════════════

-- 1. Numeração ───────────────────────────────────────────────────
create sequence if not exists public.fatura_numero_seq start 1;

alter table public.invoices
  add column if not exists numero          bigint,
  add column if not exists tipo            text not null default 'PROJETO',
  add column if not exists competencia     text,          -- AAAA-MM
  add column if not exists desconto        numeric(12,2) not null default 0,
  add column if not exists forma_pagamento text,
  add column if not exists cobrado_em      timestamptz,
  add column if not exists cobrancas       int not null default 0,
  add column if not exists proxima_acao    text,
  add column if not exists observacao      text,
  add column if not exists updated_at      timestamptz default now();

alter table public.invoices
  alter column numero set default nextval('public.fatura_numero_seq');

with ordenados as (
  select id, row_number() over (order by created_at, due_date) as n
  from public.invoices where numero is null
)
update public.invoices i set numero = o.n
from ordenados o where i.id = o.id;

select setval('public.fatura_numero_seq',
  greatest(coalesce((select max(numero) from public.invoices), 0), 1));

create unique index if not exists invoices_numero_idx on public.invoices (numero);

-- Competência em branco acompanha o vencimento: é o mês a que a
-- cobrança se refere na maioria dos contratos.
update public.invoices
set competencia = to_char(due_date, 'YYYY-MM')
where competencia is null and due_date is not null;

-- 2. Vocabulário ─────────────────────────────────────────────────
-- A SertCode não vende assinatura por plano: o que ela fatura é
-- contrato de projeto, suporte mensal, hospedagem ou avulso.
alter table public.invoices drop constraint if exists invoices_tipo_check;
alter table public.invoices
  add constraint invoices_tipo_check
  check (tipo in ('PROJETO','SUPORTE','HOSPEDAGEM','AVULSO'));

update public.invoices set status = 'pendente' where status is null or status = 'pending';
update public.invoices set status = 'pago'     where status = 'paid';

alter table public.invoices drop constraint if exists invoices_status_check;
alter table public.invoices
  add constraint invoices_status_check
  check (status in ('pendente','pago','atrasado','cancelado','reembolsado'));

alter table public.invoices drop constraint if exists invoices_forma_check;
alter table public.invoices
  add constraint invoices_forma_check
  check (forma_pagamento is null
         or forma_pagamento in ('PIX','BOLETO','TRANSFERENCIA','CARTAO','DINHEIRO','OUTRO'));

-- 3. Reembolsos ──────────────────────────────────────────────────
create table if not exists public.fin_reembolsos (
  id          uuid primary key default gen_random_uuid(),
  invoice_id  uuid references public.invoices(id) on delete set null,
  client_id   uuid references public.profiles(id) on delete set null,
  valor       numeric(12,2) not null,
  motivo      text not null,
  data        date not null default current_date,
  situacao    text not null default 'SOLICITADO',   -- SOLICITADO | PAGO | RECUSADO
  responsavel text,
  decidido_em timestamptz,
  created_at  timestamptz not null default now()
);

alter table public.fin_reembolsos drop constraint if exists fin_reembolsos_situacao_check;
alter table public.fin_reembolsos
  add constraint fin_reembolsos_situacao_check
  check (situacao in ('SOLICITADO','PAGO','RECUSADO'));

-- 4. Rastro das cobranças ────────────────────────────────────────
-- "Última cobrança" e "próxima ação" só servem se houver registro de
-- quem cobrou e quando; senão viram um campo que ninguém confia.
create table if not exists public.fin_cobrancas (
  id         uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  canal      text,
  nota       text,
  por        text,
  created_at timestamptz not null default now()
);

create index if not exists fin_cobrancas_idx
  on public.fin_cobrancas (invoice_id, created_at desc);

-- 5. Atraso automático ───────────────────────────────────────────
-- Marcar atraso na mão sempre atrasa; o banco decide pela data.
create or replace function public.fatura_marca_atraso()
returns trigger language plpgsql as $$
begin
  if new.status = 'pendente' and new.due_date is not null and new.due_date < current_date then
    new.status := 'atrasado';
  elsif new.status = 'atrasado' and (new.due_date is null or new.due_date >= current_date) then
    new.status := 'pendente';
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists fatura_marca_atraso on public.invoices;
create trigger fatura_marca_atraso
  before insert or update on public.invoices
  for each row execute function public.fatura_marca_atraso();

update public.invoices set status = status where status in ('pendente','atrasado');

-- 6. Acesso ──────────────────────────────────────────────────────
alter table public.fin_reembolsos enable row level security;
alter table public.fin_cobrancas  enable row level security;

drop policy if exists "gestor_gerencia_reembolsos" on public.fin_reembolsos;
create policy "gestor_gerencia_reembolsos" on public.fin_reembolsos
  for all to authenticated
  using (public.is_gestor()) with check (public.is_gestor());

-- O cliente vê o reembolso dele no portal; quem decide é a SertCode.
drop policy if exists "cliente_le_reembolsos" on public.fin_reembolsos;
create policy "cliente_le_reembolsos" on public.fin_reembolsos
  for select to authenticated
  using (client_id = auth.uid());

drop policy if exists "gestor_gerencia_cobrancas" on public.fin_cobrancas;
create policy "gestor_gerencia_cobrancas" on public.fin_cobrancas
  for all to authenticated
  using (public.is_gestor()) with check (public.is_gestor());
