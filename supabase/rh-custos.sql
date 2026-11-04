-- ════════════════════════════════════════════════════════════════
-- Gestão de Pessoas — custos de pessoal
-- Rodar DEPOIS do rh.sql, no SQL Editor do Supabase.
-- Pode ser executado de novo sem efeito colateral.
--
-- O que a folha aprovada gera além do salário líquido: INSS e FGTS
-- patronais, vale-transporte, plano de saúde e demais benefícios.
-- Nasce "A pagar" e vira "Pago" quando a SertCode quita — é daqui que
-- o Histórico de Pagamentos tira a linha de encargos e benefícios.
-- ════════════════════════════════════════════════════════════════

create table if not exists public.rh_custos (
  id           uuid primary key default gen_random_uuid(),
  folha_id     uuid references public.rh_folhas(id) on delete set null,
  competencia  text not null,                      -- AAAA-MM
  tipo         text not null,                      -- INSS | FGTS | IRRF | BENEFICIO | PROVISAO | OUTRO
  descricao    text not null,
  valor        numeric(12,2) not null default 0,
  status       text not null default 'A_PAGAR',    -- A_PAGAR | PAGO | PROVISIONADO
  vencimento   date,
  pago_em      timestamptz,
  pago_por     text,
  created_at   timestamptz not null default now()
);

create index if not exists rh_custos_competencia_idx on public.rh_custos (competencia);
create index if not exists rh_custos_status_idx      on public.rh_custos (status);

alter table public.rh_custos enable row level security;
drop policy if exists "gestor_gerencia_rh" on public.rh_custos;
create policy "gestor_gerencia_rh" on public.rh_custos
  for all to authenticated
  using (public.is_gestor()) with check (public.is_gestor());
