-- ════════════════════════════════════════════════════════════════
-- GESTÃO DE PESSOAS — INSTALAÇÃO COMPLETA
--
-- Junta, na ordem certa, os quatro arquivos do módulo:
--   1. rh.sql              — cargos, colaboradores, benefícios, folha
--   2. rh-complemento.sql  — dependentes, documentos, endereço
--   3. rh-custos.sql       — custos de pessoal (encargos e provisões)
--   4. rh-meurh.sql        — o colaborador vê os próprios dados
--
-- Rodar uma vez no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
-- ════════════════════════════════════════════════════════════════



-- ═══════════ rh.sql ═══════════

-- ════════════════════════════════════════════════════════════════
-- Gestão de Pessoas da SertCode
-- Rodar no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
--
-- Separado do financeiro dos clientes: aqui ficam os colaboradores da
-- SertCode, cargos, folha de pagamento e custos da equipe.
--
-- Acesso restrito ao gestor. Colaborador comum não enxerga salário,
-- documento nem folha — por isso as regras usam is_gestor(), e não
-- is_equipe() como no resto do painel.
-- ════════════════════════════════════════════════════════════════

-- 1. Cargos ──────────────────────────────────────────────────────
create table if not exists public.rh_cargos (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  cbo         text,
  setor       text,
  salario_min numeric(12,2),
  salario_max numeric(12,2),
  descricao   text,
  ativo       boolean not null default true,
  created_at  timestamptz not null default now()
);

-- 2. Colaboradores ───────────────────────────────────────────────
create table if not exists public.rh_colaboradores (
  id               uuid primary key default gen_random_uuid(),
  nome             text not null,
  apelido          text,
  cpf              text,
  rg               text,
  data_nascimento  date,
  email            text,
  telefone         text,
  -- Endereço
  endereco         text,
  numero           text,
  complemento      text,
  bairro           text,
  cidade           text,
  estado           text,
  cep              text,
  -- Vínculo
  cargo_id         uuid references public.rh_cargos(id) on delete set null,
  setor            text,
  vinculo          text not null default 'CLT',    -- CLT | PJ | ESTAGIO | AUTONOMO | TEMPORARIO
  data_admissao    date,
  data_desligamento date,
  tipo_desligamento text,                          -- PEDIDO | SEM_JUSTA_CAUSA | JUSTA_CAUSA | FIM_CONTRATO | ACORDO | OUTRO
  motivo_desligamento text,
  pode_recontratar text,                           -- SIM | NAO | AVALIAR
  situacao         text not null default 'ATIVO',  -- ATIVO | FERIAS | AFASTADO | DESLIGADO
  -- Remuneração
  salario_base     numeric(12,2) not null default 0,
  periodicidade    text not null default 'MENSAL', -- MENSAL | QUINZENAL | SEMANAL
  dia_pagamento    integer,
  dependentes      integer not null default 0,
  banco            text,
  agencia          text,
  conta            text,
  chave_pix        text,
  observacoes      text,
  -- Acesso ao painel, quando a pessoa também for da equipe
  profile_id       uuid references public.profiles(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists rh_colaboradores_situacao_idx on public.rh_colaboradores (situacao);

-- 3. Histórico salarial ──────────────────────────────────────────
create table if not exists public.rh_salarios (
  id              uuid primary key default gen_random_uuid(),
  colaborador_id  uuid not null references public.rh_colaboradores(id) on delete cascade,
  salario_antigo  numeric(12,2) not null,
  salario_novo    numeric(12,2) not null,
  vigencia        date not null,
  motivo          text,
  autor           text,
  created_at      timestamptz not null default now()
);

-- 4. Benefícios ──────────────────────────────────────────────────
create table if not exists public.rh_beneficios (
  id              uuid primary key default gen_random_uuid(),
  nome            text not null,
  tipo            text not null default 'OUTRO',  -- VALE_TRANSPORTE | VALE_ALIMENTACAO | VALE_REFEICAO | PLANO_SAUDE | PLANO_ODONTO | OUTRO
  valor_padrao    numeric(12,2) not null default 0,
  desconto_percent numeric(5,2) not null default 0,
  ativo           boolean not null default true,
  created_at      timestamptz not null default now()
);

create table if not exists public.rh_colaborador_beneficios (
  id             uuid primary key default gen_random_uuid(),
  colaborador_id uuid not null references public.rh_colaboradores(id) on delete cascade,
  beneficio_id   uuid not null references public.rh_beneficios(id) on delete cascade,
  valor          numeric(12,2) not null default 0,
  desconto       numeric(12,2) not null default 0,
  created_at     timestamptz not null default now(),
  unique (colaborador_id, beneficio_id)
);

-- 5. Férias e afastamentos ───────────────────────────────────────
create table if not exists public.rh_afastamentos (
  id             uuid primary key default gen_random_uuid(),
  colaborador_id uuid not null references public.rh_colaboradores(id) on delete cascade,
  tipo           text not null,  -- FERIAS | ATESTADO | LICENCA_MATERNIDADE | LICENCA_PATERNIDADE | AFASTAMENTO | OUTRO
  inicio         date not null,
  fim            date not null,
  status         text not null default 'PROGRAMADO',  -- PROGRAMADO | CANCELADO
  observacoes    text,
  autor          text,
  created_at     timestamptz not null default now()
);

create index if not exists rh_afastamentos_periodo_idx on public.rh_afastamentos (inicio, fim);

-- 6. Documentos e contratos ──────────────────────────────────────
create table if not exists public.rh_documentos (
  id             uuid primary key default gen_random_uuid(),
  colaborador_id uuid not null references public.rh_colaboradores(id) on delete cascade,
  tipo           text not null,  -- CONTRATO | DOCUMENTO_PESSOAL | COMPROVANTE | ATESTADO | TERMO | OUTRO
  nome           text not null,
  caminho        text not null,  -- objeto no bucket rh-documentos
  tamanho        integer,
  valido_ate     date,
  autor          text,
  created_at     timestamptz not null default now()
);

-- 7. Folha de pagamento ──────────────────────────────────────────
create table if not exists public.rh_folhas (
  id             uuid primary key default gen_random_uuid(),
  competencia    text not null unique,   -- AAAA-MM
  status         text not null default 'RASCUNHO',  -- RASCUNHO | AGUARDANDO_APROVACAO | APROVADA | PAGA | CANCELADA
  vencimento     date not null,
  observacoes    text,
  criada_por     text,
  aprovada_por   text,
  aprovada_em    timestamptz,
  paga_em        timestamptz,
  motivo_reabertura text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table if not exists public.rh_folha_itens (
  id                uuid primary key default gen_random_uuid(),
  folha_id          uuid not null references public.rh_folhas(id) on delete cascade,
  colaborador_id    uuid not null references public.rh_colaboradores(id) on delete cascade,
  colaborador_nome  text not null,
  cargo_nome        text,
  vinculo           text,
  salario_base      numeric(12,2) not null default 0,
  proventos         numeric(12,2) not null default 0,
  salario_bruto     numeric(12,2) not null default 0,
  inss              numeric(12,2) not null default 0,
  irrf              numeric(12,2) not null default 0,
  desconto_beneficios numeric(12,2) not null default 0,
  outros_descontos  numeric(12,2) not null default 0,
  salario_liquido   numeric(12,2) not null default 0,
  fgts              numeric(12,2) not null default 0,
  encargos          numeric(12,2) not null default 0,
  custo_beneficios  numeric(12,2) not null default 0,
  provisoes         numeric(12,2) not null default 0,
  custo_total       numeric(12,2) not null default 0,
  status_pagamento  text not null default 'PENDENTE',  -- PENDENTE | PAGO
  pago_em           timestamptz,
  forma_pagamento   text,
  pago_por          text,
  observacoes       text,
  unique (folha_id, colaborador_id)
);

-- Correção feita depois da aprovação, sempre registrada.
create table if not exists public.rh_folha_ajustes (
  id          uuid primary key default gen_random_uuid(),
  folha_id    uuid not null references public.rh_folhas(id) on delete cascade,
  item_id     uuid,
  descricao   text not null,
  autor       text,
  created_at  timestamptz not null default now()
);

-- 8. Parâmetros de cálculo (INSS, IRRF, encargos) ────────────────
-- Uma linha só, com as faixas em JSON: as tabelas mudam todo ano e
-- guardar em JSON evita recriar colunas a cada mudança da legislação.
create table if not exists public.rh_config (
  id         integer primary key default 1,
  parametros jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint rh_config_linha_unica check (id = 1)
);

insert into public.rh_config (id) values (1) on conflict (id) do nothing;

-- 9. Auditoria de acesso a dados sensíveis ───────────────────────
create table if not exists public.rh_auditoria (
  id          uuid primary key default gen_random_uuid(),
  autor_id    uuid,
  autor_nome  text,
  acao        text not null,   -- VISUALIZOU | CRIOU | ALTEROU | EXCLUIU
  alvo        text not null,
  detalhe     text,
  created_at  timestamptz not null default now()
);

create index if not exists rh_auditoria_data_idx on public.rh_auditoria (created_at desc);

-- 10. Acesso: somente gestor ─────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array[
    'rh_cargos','rh_colaboradores','rh_salarios','rh_beneficios',
    'rh_colaborador_beneficios','rh_afastamentos','rh_documentos',
    'rh_folhas','rh_folha_itens','rh_folha_ajustes','rh_config','rh_auditoria'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "gestor_gerencia_rh" on public.%I', t);
    execute format(
      'create policy "gestor_gerencia_rh" on public.%I for all to authenticated using (public.is_gestor()) with check (public.is_gestor())', t);
  end loop;
end $$;


-- ═══════════ rh-complemento.sql ═══════════

-- ════════════════════════════════════════════════════════════════
-- Gestão de Pessoas — complemento do cadastro
-- Rodar DEPOIS do rh.sql, no SQL Editor do Supabase.
-- Pode ser executado de novo sem efeito colateral.
-- ════════════════════════════════════════════════════════════════

-- 1. Observações do vínculo ──────────────────────────────────────
alter table public.rh_colaboradores
  add column if not exists observacoes_vinculo text,
  add column if not exists banco_agencia text,
  add column if not exists banco_conta text;

-- 2. Dependentes ─────────────────────────────────────────────────
-- Cadastro de controle interno. Marcar um dependente aqui não cria
-- direito a benefício: serve para a folha saber quem conta no IRRF e
-- para o RH acompanhar auxílio-creche e salário-família.
create table if not exists public.rh_dependentes (
  id              uuid primary key default gen_random_uuid(),
  colaborador_id  uuid not null references public.rh_colaboradores(id) on delete cascade,
  nome            text not null,
  parentesco      text,
  data_nascimento date,
  cpf             text,
  auxilio_creche   boolean not null default false,
  salario_familia  boolean not null default false,
  dependente_irrf  boolean not null default false,
  observacoes     text,
  created_at      timestamptz not null default now()
);

create index if not exists rh_dependentes_colab_idx
  on public.rh_dependentes (colaborador_id);

alter table public.rh_dependentes enable row level security;
drop policy if exists "gestor_gerencia_rh" on public.rh_dependentes;
create policy "gestor_gerencia_rh" on public.rh_dependentes
  for all to authenticated
  using (public.is_gestor()) with check (public.is_gestor());

-- 3. Arquivo dos documentos ──────────────────────────────────────
-- Bucket privado: contrato e documento pessoal não podem ficar
-- acessíveis por link direto. O painel baixa gerando um link curto.
insert into storage.buckets (id, name, public)
values ('rh-documentos', 'rh-documentos', false)
on conflict (id) do nothing;

drop policy if exists "gestor_le_documentos_rh"    on storage.objects;
drop policy if exists "gestor_envia_documentos_rh" on storage.objects;
drop policy if exists "gestor_apaga_documentos_rh" on storage.objects;

create policy "gestor_le_documentos_rh" on storage.objects
  for select to authenticated
  using (bucket_id = 'rh-documentos' and public.is_gestor());

create policy "gestor_envia_documentos_rh" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'rh-documentos' and public.is_gestor());

create policy "gestor_apaga_documentos_rh" on storage.objects
  for delete to authenticated
  using (bucket_id = 'rh-documentos' and public.is_gestor());

-- 4. Auditoria por colaborador ───────────────────────────────────
-- A aba Histórico do cadastro mostra o que aconteceu com aquela
-- pessoa; sem esta coluna seria preciso filtrar por nome, que muda.
alter table public.rh_auditoria
  add column if not exists colaborador_id uuid references public.rh_colaboradores(id) on delete cascade;

create index if not exists rh_auditoria_colab_idx
  on public.rh_auditoria (colaborador_id, created_at desc);


-- ═══════════ rh-custos.sql ═══════════

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


-- ═══════════ rh-meurh.sql ═══════════

-- ════════════════════════════════════════════════════════════════
-- Meu RH — o colaborador vê os próprios dados
-- Rodar DEPOIS do rh.sql e do rh-complemento.sql.
-- Pode ser executado de novo sem efeito colateral.
--
-- Até aqui o RH era fechado ao gestor. Estas regras abrem uma fresta
-- para cada pessoa: a própria ficha e os próprios demonstrativos, e
-- nada além disso.
-- ════════════════════════════════════════════════════════════════

-- 1. A própria ficha ─────────────────────────────────────────────
drop policy if exists "colaborador_le_propria_ficha" on public.rh_colaboradores;
create policy "colaborador_le_propria_ficha" on public.rh_colaboradores
  for select to authenticated
  using (profile_id = auth.uid());

-- 2. Os próprios demonstrativos ──────────────────────────────────
-- Só de folha aprovada ou paga: rascunho ainda muda, e holerite que
-- muda depois de visto gera mais dúvida do que informação.
drop policy if exists "colaborador_le_proprio_holerite" on public.rh_folha_itens;
create policy "colaborador_le_proprio_holerite" on public.rh_folha_itens
  for select to authenticated
  using (exists (
    select 1
    from public.rh_colaboradores c
    join public.rh_folhas f on f.id = rh_folha_itens.folha_id
    where c.id = rh_folha_itens.colaborador_id
      and c.profile_id = auth.uid()
      and f.status in ('APROVADA', 'PAGA')
  ));

-- 3. A competência da folha, para nomear o demonstrativo ─────────
drop policy if exists "colaborador_le_folha_do_holerite" on public.rh_folhas;
create policy "colaborador_le_folha_do_holerite" on public.rh_folhas
  for select to authenticated
  using (
    status in ('APROVADA', 'PAGA')
    and exists (
      select 1
      from public.rh_folha_itens i
      join public.rh_colaboradores c on c.id = i.colaborador_id
      where i.folha_id = rh_folhas.id and c.profile_id = auth.uid()
    )
  );

-- 4. O cargo que aparece na ficha ────────────────────────────────
drop policy if exists "equipe_le_cargos" on public.rh_cargos;
create policy "equipe_le_cargos" on public.rh_cargos
  for select to authenticated
  using (public.is_equipe());
