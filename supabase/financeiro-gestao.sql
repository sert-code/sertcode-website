-- ════════════════════════════════════════════════════════════════
-- Financeiro completo: cobranças, pagamentos, assinaturas,
-- movimentações, documentos e parâmetros
-- Rodar no Supabase DEPOIS de financeiro.sql e projetos-gestao.sql.
-- Pode ser executado de novo sem efeito colateral.
--
-- Três decisões estruturam o resto:
--
-- 1. O pagamento vira tabela própria, e não um campo na cobrança. É o
--    que permite pagamento parcial e mantém o histórico imutável:
--    estorno não apaga nada, cria uma linha negativa.
-- 2. A situação da cobrança é calculada pela soma dos pagamentos, por
--    gatilho. Ninguém digita "pago" — o banco conclui.
-- 3. Competência e caixa são datas diferentes. Uma diz a que mês o
--    valor pertence; a outra, quando o dinheiro entrou ou saiu.
-- ════════════════════════════════════════════════════════════════

-- 1. Contas financeiras e categorias ─────────────────────────────
create table if not exists public.fin_contas (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  tipo       text not null default 'BANCO',   -- BANCO | CAIXA | GATEWAY
  banco      text,
  agencia    text,
  conta      text,
  saldo_inicial numeric(14,2) not null default 0,
  ativa      boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.fin_categorias (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  natureza   text not null,                   -- RECEITA | DESPESA
  ativa      boolean not null default true,
  created_at timestamptz not null default now(),
  unique (nome, natureza)
);

alter table public.fin_categorias drop constraint if exists fin_categorias_natureza_check;
alter table public.fin_categorias
  add constraint fin_categorias_natureza_check check (natureza in ('RECEITA','DESPESA'));

-- Categorias que a especificação lista. `on conflict do nothing` deixa o
-- script repetível e preserva o que a SertCode criar depois.
insert into public.fin_categorias (nome, natureza) values
  ('Recebimento de projeto', 'RECEITA'),
  ('Mensalidade de manutenção', 'RECEITA'),
  ('Assinatura SaaS', 'RECEITA'),
  ('Serviço adicional', 'RECEITA'),
  ('Consultoria', 'RECEITA'),
  ('Hospedagem e servidores', 'DESPESA'),
  ('Domínios', 'DESPESA'),
  ('APIs e ferramentas', 'DESPESA'),
  ('Licenças de software', 'DESPESA'),
  ('Marketing e publicidade', 'DESPESA'),
  ('Prestadores de serviço', 'DESPESA'),
  ('Despesas administrativas', 'DESPESA'),
  ('Impostos e taxas', 'DESPESA'),
  ('Pessoal', 'DESPESA'),
  ('Outras despesas operacionais', 'DESPESA')
on conflict (nome, natureza) do nothing;

insert into public.fin_contas (nome, tipo)
select 'Conta principal', 'BANCO'
where not exists (select 1 from public.fin_contas);

-- Anotação da gestão sobre a situação financeira do cliente. Fica em
-- tabela à parte, e não numa coluna de `profiles`: o cliente lê a
-- própria linha de profiles no portal, e a observação é interna.
create table if not exists public.fin_cliente_notas (
  client_id  uuid primary key references public.profiles(id) on delete cascade,
  texto      text,
  autor_nome text,
  updated_at timestamptz not null default now()
);

-- 2. Cobranças (contas a receber) ────────────────────────────────
alter table public.invoices
  add column if not exists parcela_num   int,
  add column if not exists parcela_total int,
  add column if not exists juros         numeric(12,2) not null default 0,
  add column if not exists multa         numeric(12,2) not null default 0,
  add column if not exists recebido      numeric(12,2) not null default 0,
  add column if not exists emitida_em    date,
  add column if not exists etapa_id      uuid references public.projeto_etapas(id) on delete set null,
  add column if not exists marco         text,
  add column if not exists assinatura_id uuid,
  add column if not exists comprovante   text,
  add column if not exists comprovante_em timestamptz,
  add column if not exists comprovante_validado boolean not null default false;

update public.invoices set emitida_em = coalesce(emitida_em, created_at::date, due_date);

-- Vocabulário da especificação.
alter table public.invoices drop constraint if exists invoices_status_check;

update public.invoices set status = case status
  when 'pendente'    then 'AGUARDANDO'
  when 'pago'        then 'PAGO'
  when 'atrasado'    then 'ATRASADO'
  when 'cancelado'   then 'CANCELADO'
  when 'reembolsado' then 'ESTORNADO'
  else status
end
where status in ('pendente','pago','atrasado','cancelado','reembolsado');

update public.invoices set status = 'AGUARDANDO'
where status is null or status not in
  ('AGUARDANDO','PARCIAL','PAGO','ATRASADO','CANCELADO','ESTORNADO');

alter table public.invoices
  add constraint invoices_status_check
  check (status in ('AGUARDANDO','PARCIAL','PAGO','ATRASADO','CANCELADO','ESTORNADO'));

-- O que já estava marcado como pago passa a ter o recebido preenchido,
-- senão a soma dos pagamentos diria que ninguém pagou.
update public.invoices
set recebido = amount - coalesce(desconto, 0)
where status = 'PAGO' and recebido = 0;

-- 3. Pagamentos ──────────────────────────────────────────────────
-- Linha nunca editada: correção e estorno entram como novo registro.
create table if not exists public.fin_pagamentos (
  id          uuid primary key default gen_random_uuid(),
  invoice_id  uuid not null references public.invoices(id) on delete cascade,
  client_id   uuid references public.profiles(id) on delete set null,
  valor       numeric(12,2) not null,
  data        date not null default current_date,
  competencia text,
  forma       text,
  conta_id    uuid references public.fin_contas(id) on delete set null,
  comprovante text,
  observacao  text,
  registrado_por text,
  estorno_de  uuid references public.fin_pagamentos(id) on delete set null,
  created_at  timestamptz not null default now()
);

create index if not exists fin_pagamentos_idx
  on public.fin_pagamentos (invoice_id, data desc);

-- 4. Situação da cobrança vem da soma ────────────────────────────
create or replace function public.cobranca_recalcula(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  i public.invoices;
  pago numeric(12,2);
  devido numeric(12,2);
begin
  select * into i from public.invoices where id = p_invoice;
  if not found then return; end if;
  -- Cancelada ou estornada é decisão humana: a soma não a desfaz.
  if i.status in ('CANCELADO','ESTORNADO') then return; end if;

  select coalesce(sum(valor), 0) into pago
  from public.fin_pagamentos where invoice_id = p_invoice;

  devido := i.amount - coalesce(i.desconto, 0) + coalesce(i.juros, 0) + coalesce(i.multa, 0);

  update public.invoices set
    recebido = pago,
    paid_at = case when pago >= devido then coalesce(paid_at, now()) else null end,
    status = case
      when pago >= devido and devido > 0 then 'PAGO'
      when pago > 0                      then 'PARCIAL'
      when due_date is not null and due_date < current_date then 'ATRASADO'
      else 'AGUARDANDO'
    end,
    updated_at = now()
  where id = p_invoice;
end $$;

create or replace function public.pagamento_mexe_cobranca()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.cobranca_recalcula(coalesce(new.invoice_id, old.invoice_id));
  return coalesce(new, old);
end $$;

drop trigger if exists pagamento_mexe_cobranca on public.fin_pagamentos;
create trigger pagamento_mexe_cobranca
  after insert or update or delete on public.fin_pagamentos
  for each row execute function public.pagamento_mexe_cobranca();

-- O gatilho de atraso de financeiro.sql usava o vocabulário antigo.
create or replace function public.fatura_marca_atraso()
returns trigger language plpgsql as $$
begin
  if new.status = 'AGUARDANDO' and new.due_date is not null and new.due_date < current_date then
    new.status := 'ATRASADO';
  elsif new.status = 'ATRASADO' and (new.due_date is null or new.due_date >= current_date) then
    new.status := 'AGUARDANDO';
  end if;
  new.updated_at := now();
  return new;
end $$;

update public.invoices set status = status where status in ('AGUARDANDO','ATRASADO');

-- 5. Assinaturas SaaS ────────────────────────────────────────────
create table if not exists public.fin_assinaturas (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid references public.profiles(id) on delete set null,
  produto       text not null default 'SertCode One',
  plano         text not null,
  valor         numeric(12,2) not null,
  periodicidade text not null default 'MENSAL',   -- MENSAL | TRIMESTRAL | SEMESTRAL | ANUAL
  contratada_em date not null default current_date,
  vencimento_dia int,
  proxima_cobranca date,
  situacao      text not null default 'ATIVA',
  desconto      numeric(12,2) not null default 0,
  condicoes     text,
  cancelada_em  date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.fin_assinaturas drop constraint if exists fin_assinaturas_situacao_check;
alter table public.fin_assinaturas
  add constraint fin_assinaturas_situacao_check
  check (situacao in ('ATIVA','AGUARDANDO','ATRASADA','SUSPENSA','CANCELADA','TESTE'));

alter table public.fin_assinaturas drop constraint if exists fin_assinaturas_periodicidade_check;
alter table public.fin_assinaturas
  add constraint fin_assinaturas_periodicidade_check
  check (periodicidade in ('MENSAL','TRIMESTRAL','SEMESTRAL','ANUAL'));

-- A cobrança de assinatura aponta para ela; a chave só pode ser criada
-- agora, depois que a tabela existe.
alter table public.invoices drop constraint if exists invoices_assinatura_fk;
alter table public.invoices
  add constraint invoices_assinatura_fk
  foreign key (assinatura_id) references public.fin_assinaturas(id) on delete set null;

-- Assinatura entra como tipo de contrato ao lado dos projetos.
alter table public.invoices drop constraint if exists invoices_tipo_check;
alter table public.invoices
  add constraint invoices_tipo_check
  check (tipo in ('PROJETO','SUPORTE','HOSPEDAGEM','AVULSO','ASSINATURA'));

-- 6. Movimentações (entradas e saídas) ───────────────────────────
create table if not exists public.fin_movimentacoes (
  id           uuid primary key default gen_random_uuid(),
  tipo         text not null,                 -- ENTRADA | SAIDA
  categoria_id uuid references public.fin_categorias(id) on delete set null,
  categoria_nome text,
  descricao    text not null,
  valor        numeric(14,2) not null,
  competencia  text not null,                 -- AAAA-MM
  data_caixa   date,                          -- quando o dinheiro andou
  conta_id     uuid references public.fin_contas(id) on delete set null,
  forma        text,
  documento    text,
  invoice_id   uuid references public.invoices(id) on delete set null,
  project_id   uuid references public.projects(id) on delete set null,
  registrado_por text,
  created_at   timestamptz not null default now()
);

alter table public.fin_movimentacoes drop constraint if exists fin_movimentacoes_tipo_check;
alter table public.fin_movimentacoes
  add constraint fin_movimentacoes_tipo_check check (tipo in ('ENTRADA','SAIDA'));

create index if not exists fin_movimentacoes_idx
  on public.fin_movimentacoes (competencia, tipo);

-- Todo recebimento vira entrada no caixa, sem ninguém lançar duas vezes.
create or replace function public.pagamento_vira_movimentacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  i public.invoices;
begin
  select * into i from public.invoices where id = new.invoice_id;
  insert into public.fin_movimentacoes
    (tipo, categoria_nome, descricao, valor, competencia, data_caixa,
     conta_id, forma, invoice_id, project_id, registrado_por)
  values (
    case when new.valor >= 0 then 'ENTRADA' else 'SAIDA' end,
    case when new.estorno_de is not null then 'Estorno de recebimento'
         else 'Recebimento de projeto' end,
    coalesce(i.description, 'Cobrança') ||
      case when new.estorno_de is not null then ' (estorno)' else '' end,
    abs(new.valor),
    coalesce(new.competencia, to_char(new.data, 'YYYY-MM')),
    new.data, new.conta_id, new.forma, new.invoice_id, i.project_id,
    new.registrado_por);
  return new;
end $$;

drop trigger if exists pagamento_vira_movimentacao on public.fin_pagamentos;
create trigger pagamento_vira_movimentacao
  after insert on public.fin_pagamentos
  for each row execute function public.pagamento_vira_movimentacao();

-- 7. Documentos financeiros ──────────────────────────────────────
create table if not exists public.fin_documentos (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid references public.profiles(id) on delete set null,
  invoice_id  uuid references public.invoices(id) on delete set null,
  assinatura_id uuid references public.fin_assinaturas(id) on delete set null,
  tipo        text not null default 'COMPROVANTE',
  nome        text not null,
  caminho     text not null,
  tamanho     bigint,
  publico     boolean not null default true,
  enviado_por text,
  enviado_tipo text not null default 'EQUIPE',
  created_at  timestamptz not null default now()
);

alter table public.fin_documentos drop constraint if exists fin_documentos_tipo_check;
alter table public.fin_documentos
  add constraint fin_documentos_tipo_check
  check (tipo in ('CONTRATO','PROPOSTA','RECIBO','NOTA','COMPROVANTE','DEMONSTRATIVO','ADITIVO'));

create index if not exists fin_documentos_idx
  on public.fin_documentos (client_id, created_at desc);

-- 8. Parâmetros ──────────────────────────────────────────────────
create table if not exists public.fin_config (
  id            int primary key default 1,
  moeda         text not null default 'BRL',
  instrucoes    text,                                 -- como pagar, mostrado ao cliente
  juros_mes     numeric(6,3) not null default 1.0,    -- % ao mês
  multa_atraso  numeric(6,3) not null default 2.0,    -- % sobre o valor
  prazo_padrao  int not null default 30,              -- dias até o vencimento
  formas        text not null default 'PIX,BOLETO,TRANSFERENCIA,CARTAO,DINHEIRO,OUTRO',
  condicoes     text,
  updated_at    timestamptz not null default now(),
  constraint fin_config_linha_unica check (id = 1)
);

insert into public.fin_config (id) values (1) on conflict (id) do nothing;

-- 9. Histórico financeiro ────────────────────────────────────────
create table if not exists public.fin_historico (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid references public.profiles(id) on delete set null,
  invoice_id  uuid references public.invoices(id) on delete set null,
  project_id  uuid references public.projects(id) on delete set null,
  evento      text not null,
  descricao   text,
  valor       numeric(14,2),
  publico     boolean not null default true,
  autor_nome  text,
  created_at  timestamptz not null default now()
);

create index if not exists fin_historico_idx
  on public.fin_historico (client_id, created_at desc);

-- Emissão e pagamento entram na linha do tempo sozinhos.
create or replace function public.cobranca_vira_historico()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.fin_historico (client_id, invoice_id, project_id, evento, descricao, valor)
    values (new.client_id, new.id, new.project_id, 'Cobrança emitida',
            coalesce(new.description, 'Cobrança'), new.amount - coalesce(new.desconto, 0));
  elsif new.status is distinct from old.status then
    insert into public.fin_historico (client_id, invoice_id, project_id, evento, descricao, valor)
    values (new.client_id, new.id, new.project_id,
            case new.status
              when 'PAGO'      then 'Parcela quitada'
              when 'PARCIAL'   then 'Pagamento parcial registrado'
              when 'ATRASADO'  then 'Cobrança em atraso'
              when 'CANCELADO' then 'Cobrança cancelada'
              when 'ESTORNADO' then 'Cobrança estornada'
              else 'Cobrança atualizada' end,
            coalesce(new.description, 'Cobrança'), new.recebido);
  end if;
  return new;
end $$;

drop trigger if exists cobranca_vira_historico on public.invoices;
create trigger cobranca_vira_historico
  after insert or update on public.invoices
  for each row execute function public.cobranca_vira_historico();

-- 10. Comprovantes do cliente ────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('financeiro', 'financeiro', false)
on conflict (id) do nothing;

drop policy if exists "equipe_le_financeiro"      on storage.objects;
drop policy if exists "equipe_envia_financeiro"   on storage.objects;
drop policy if exists "cliente_le_financeiro"     on storage.objects;
drop policy if exists "cliente_envia_financeiro"  on storage.objects;

create policy "equipe_le_financeiro" on storage.objects
  for select to authenticated
  using (bucket_id = 'financeiro' and public.is_equipe());

create policy "equipe_envia_financeiro" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'financeiro' and public.is_equipe());

create policy "cliente_le_financeiro" on storage.objects
  for select to authenticated
  using (bucket_id = 'financeiro' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "cliente_envia_financeiro" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'financeiro' and (storage.foldername(name))[1] = auth.uid()::text);

-- 11. Acesso ─────────────────────────────────────────────────────
alter table public.fin_contas        enable row level security;
alter table public.fin_categorias    enable row level security;
alter table public.fin_pagamentos    enable row level security;
alter table public.fin_assinaturas   enable row level security;
alter table public.fin_movimentacoes enable row level security;
alter table public.fin_documentos    enable row level security;
alter table public.fin_config        enable row level security;
alter table public.fin_historico     enable row level security;
alter table public.fin_cliente_notas enable row level security;

do $$
declare t text;
begin
  foreach t in array array['fin_contas','fin_categorias','fin_pagamentos','fin_assinaturas',
                           'fin_movimentacoes','fin_documentos','fin_config','fin_historico',
                           'fin_cliente_notas']
  loop
    execute format('drop policy if exists "gestor_gerencia_%1$s" on public.%1$I', t);
    execute format('create policy "gestor_gerencia_%1$s" on public.%1$I
                      for all to authenticated
                      using (public.is_gestor()) with check (public.is_gestor())', t);
  end loop;
end $$;

-- Prazos, juros e condições de pagamento o cliente precisa ler: são as
-- instruções que aparecem na cobrança dele. A tabela não guarda nada
-- sensível além disso.
drop policy if exists "todos_leem_config_fin" on public.fin_config;
create policy "todos_leem_config_fin" on public.fin_config
  for select to authenticated using (true);

-- O cliente vê só o que é dele, e nada de custo ou anotação interna.
drop policy if exists "cliente_le_pagamentos" on public.fin_pagamentos;
create policy "cliente_le_pagamentos" on public.fin_pagamentos
  for select to authenticated using (client_id = auth.uid());

drop policy if exists "cliente_le_assinatura" on public.fin_assinaturas;
create policy "cliente_le_assinatura" on public.fin_assinaturas
  for select to authenticated using (client_id = auth.uid());

drop policy if exists "cliente_le_documentos_fin" on public.fin_documentos;
create policy "cliente_le_documentos_fin" on public.fin_documentos
  for select to authenticated using (publico and client_id = auth.uid());

drop policy if exists "cliente_envia_comprovante" on public.fin_documentos;
create policy "cliente_envia_comprovante" on public.fin_documentos
  for insert to authenticated
  with check (client_id = auth.uid() and enviado_tipo = 'CLIENTE' and tipo = 'COMPROVANTE');

drop policy if exists "cliente_le_historico_fin" on public.fin_historico;
create policy "cliente_le_historico_fin" on public.fin_historico
  for select to authenticated using (publico and client_id = auth.uid());

-- Movimentação é contabilidade da SertCode: o cliente não vê.
-- Cobrança o cliente já lia por invoices, de projetos.sql.

-- Enviar comprovante NÃO confirma o pagamento: marca que chegou, e a
-- gestão valida. Por isso o cliente escreve só estes dois campos.
drop policy if exists "cliente_anexa_comprovante_cobranca" on public.invoices;
create policy "cliente_anexa_comprovante_cobranca" on public.invoices
  for update to authenticated
  using (client_id = auth.uid())
  with check (client_id = auth.uid());

create or replace function public.cobranca_cliente_so_comprovante()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  caminho text;
begin
  if current_user in ('anon','authenticated')
     and not public.is_equipe()
     and old.client_id = auth.uid() then
    caminho := new.comprovante;
    new := old;
    new.comprovante := caminho;
    new.comprovante_em := now();
    new.comprovante_validado := false;
  end if;
  return new;
end $$;

drop trigger if exists cobranca_cliente_so_comprovante on public.invoices;
create trigger cobranca_cliente_so_comprovante
  before update on public.invoices
  for each row execute function public.cobranca_cliente_so_comprovante();
