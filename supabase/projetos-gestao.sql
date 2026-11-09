-- ════════════════════════════════════════════════════════════════
-- Projetos: etapas, tarefas, aprovações, documentos e comunicação
-- Rodar no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
--
-- O projeto era uma linha com nome, progresso e fase escritos à mão. O
-- progresso agora vem das etapas, e cada etapa tem responsável, prazo e
-- histórico. Nada avança sozinho: quem registra é a equipe.
-- ════════════════════════════════════════════════════════════════

-- 0. Cadastro da empresa cliente ─────────────────────────────────
-- O portal passa a ter "Meu Perfil"; esses campos vinham faltando.
alter table public.profiles
  add column if not exists cnpj     text,
  add column if not exists cargo    text,
  add column if not exists cep      text,
  add column if not exists endereco text,
  add column if not exists bairro   text,
  add column if not exists cidade   text,
  add column if not exists estado   text;

-- O cliente mantém os próprios dados. Papel e situação continuam
-- protegidos pelo gatilho protect_profile_access, de colaboradores.sql.
drop policy if exists "cliente_atualiza_proprio_perfil" on public.profiles;
create policy "cliente_atualiza_proprio_perfil" on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- 1. Campos do projeto ───────────────────────────────────────────
create sequence if not exists public.projeto_numero_seq start 1;

alter table public.projects
  add column if not exists numero            bigint,
  add column if not exists codigo            text,
  add column if not exists categoria         text,
  add column if not exists servico           text,
  add column if not exists objetivo          text,
  add column if not exists prioridade        text not null default 'NORMAL',
  add column if not exists responsavel_id    uuid,
  add column if not exists responsavel_nome  text,
  add column if not exists equipe            text,
  add column if not exists previsao_inicio   date,
  add column if not exists previsao_entrega  date,
  add column if not exists valor             numeric(12,2),
  add column if not exists contratacao       text,
  add column if not exists contrato_link     text,
  add column if not exists observacoes_internas text,
  add column if not exists motivo_espera     text,
  add column if not exists espera_desde      date,
  add column if not exists atualizado_em     timestamptz default now();

alter table public.projects
  alter column numero set default nextval('public.projeto_numero_seq');

with ordenados as (
  select id, row_number() over (order by created_at) as n
  from public.projects where numero is null
)
update public.projects p set numero = o.n
from ordenados o where p.id = o.id;

-- O terceiro argumento `false` diz que o valor ainda não foi usado: assim
-- o próximo projeto recebe max+1, e numa tabela vazia recebe 1.
select setval('public.projeto_numero_seq',
  coalesce((select max(numero) from public.projects), 0) + 1, false);

-- Código legível, do tipo SC-2026-001: é o que cliente e equipe citam.
update public.projects
set codigo = 'SC-' || to_char(coalesce(created_at, now()), 'YYYY') || '-'
             || lpad(numero::text, 3, '0')
where codigo is null;

create unique index if not exists projects_codigo_idx on public.projects (codigo);

-- 2. Situação do projeto ─────────────────────────────────────────
-- A regra antiga sai ANTES da conversão. Convertendo primeiro, cada
-- linha que vira 'SOLICITACAO' bate na regra velha, que só aceitava
-- cadastrado/andamento/pausado/cancelado/concluido, e o script inteiro
-- volta atrás.
alter table public.projects drop constraint if exists projects_status_check;

update public.projects set status = case status
  when 'cadastrado' then 'SOLICITACAO'
  when 'andamento'  then 'ANDAMENTO'
  when 'pausado'    then 'PAUSADO'
  when 'cancelado'  then 'CANCELADO'
  when 'concluido'  then 'CONCLUIDO'
  else status
end
where status in ('cadastrado','andamento','pausado','cancelado','concluido');

update public.projects set status = 'SOLICITACAO'
where status is null or status not in (
  'SOLICITACAO','DIAGNOSTICO','AGUARDANDO_APROVACAO','AGUARDANDO_INICIO','ANDAMENTO',
  'AGUARDANDO_CLIENTE','PAUSADO','HOMOLOGACAO','CONCLUIDO','CANCELADO');

alter table public.projects
  add constraint projects_status_check
  check (status in (
    'SOLICITACAO','DIAGNOSTICO','AGUARDANDO_APROVACAO','AGUARDANDO_INICIO','ANDAMENTO',
    'AGUARDANDO_CLIENTE','PAUSADO','HOMOLOGACAO','CONCLUIDO','CANCELADO'));

alter table public.projects drop constraint if exists projects_prioridade_check;
alter table public.projects
  add constraint projects_prioridade_check
  check (prioridade in ('BAIXA','NORMAL','ALTA','URGENTE'));

-- 3. Etapas ──────────────────────────────────────────────────────
create table if not exists public.projeto_etapas (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid not null references public.projects(id) on delete cascade,
  ordem         int not null default 0,
  fase          text not null,              -- DIAGNOSTICO .. SUPORTE
  nome          text not null,
  descricao     text,
  status        text not null default 'NAO_INICIADO',
  progresso     int  not null default 0,
  peso          int  not null default 1,
  responsavel_id   uuid,
  responsavel_nome text,
  inicio        date,
  prazo         date,
  conclusao     date,
  observacoes_internas text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.projeto_etapas drop constraint if exists projeto_etapas_status_check;
alter table public.projeto_etapas
  add constraint projeto_etapas_status_check
  check (status in ('NAO_INICIADO','ANDAMENTO','REVISAO','AGUARDANDO_CLIENTE','PAUSADO','CONCLUIDO','CANCELADO'));

alter table public.projeto_etapas drop constraint if exists projeto_etapas_progresso_check;
alter table public.projeto_etapas
  add constraint projeto_etapas_progresso_check
  check (progresso between 0 and 100);

create index if not exists projeto_etapas_idx on public.projeto_etapas (project_id, ordem);

-- Concluída com 60% seria mentira na tela do cliente; o banco fecha a
-- conta em vez de confiar em quem digitou.
create or replace function public.etapa_coerente()
returns trigger language plpgsql as $$
begin
  if new.status = 'CONCLUIDO' then
    new.progresso := 100;
    new.conclusao := coalesce(new.conclusao, current_date);
  elsif new.status = 'NAO_INICIADO' then
    new.progresso := 0;
    new.conclusao := null;
  elsif new.progresso = 100 and new.status not in ('CANCELADO','REVISAO','AGUARDANDO_CLIENTE') then
    new.status := 'CONCLUIDO';
    new.conclusao := coalesce(new.conclusao, current_date);
  end if;

  if new.status <> 'NAO_INICIADO' and new.inicio is null then
    new.inicio := current_date;
  end if;

  new.updated_at := now();
  return new;
end $$;

drop trigger if exists etapa_coerente on public.projeto_etapas;
create trigger etapa_coerente
  before insert or update on public.projeto_etapas
  for each row execute function public.etapa_coerente();

-- 4. Tarefas ─────────────────────────────────────────────────────
create table if not exists public.projeto_tarefas (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects(id) on delete cascade,
  etapa_id    uuid references public.projeto_etapas(id) on delete cascade,
  titulo      text not null,
  responsavel_nome text,
  prazo       date,
  concluida   boolean not null default false,
  concluida_em timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists projeto_tarefas_idx on public.projeto_tarefas (project_id, etapa_id);

-- 5. Atualizações ────────────────────────────────────────────────
-- `publica` separa o que o cliente lê do que fica só para a equipe. É a
-- mesma linha do tempo, com duas leituras.
create table if not exists public.projeto_atualizacoes (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects(id) on delete cascade,
  etapa_id    uuid references public.projeto_etapas(id) on delete set null,
  titulo      text not null,
  descricao   text,
  publica     boolean not null default true,
  anexo       text,
  autor_nome  text,
  created_at  timestamptz not null default now()
);

create index if not exists projeto_atualizacoes_idx
  on public.projeto_atualizacoes (project_id, created_at desc);

-- 6. Histórico ───────────────────────────────────────────────────
create table if not exists public.projeto_historico (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects(id) on delete cascade,
  etapa_id    uuid references public.projeto_etapas(id) on delete set null,
  etapa_nome  text,
  campo       text not null,
  valor_antes text,
  valor_depois text,
  descricao   text,
  autor_nome  text,
  created_at  timestamptz not null default now()
);

create index if not exists projeto_historico_idx
  on public.projeto_historico (project_id, created_at desc);

-- 7. Aprovações ──────────────────────────────────────────────────
create table if not exists public.projeto_aprovacoes (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects(id) on delete cascade,
  etapa_id    uuid references public.projeto_etapas(id) on delete set null,
  tipo        text not null,              -- ESCOPO | DESIGN | CONTEUDO | ...
  titulo      text not null,
  descricao   text,
  anexo       text,
  prazo       date,
  situacao    text not null default 'PENDENTE',   -- PENDENTE | APROVADA | AJUSTES
  resposta    text,
  respondido_por text,
  respondido_em  timestamptz,
  solicitado_por text,
  created_at  timestamptz not null default now()
);

alter table public.projeto_aprovacoes drop constraint if exists projeto_aprovacoes_situacao_check;
alter table public.projeto_aprovacoes
  add constraint projeto_aprovacoes_situacao_check
  check (situacao in ('PENDENTE','APROVADA','AJUSTES'));

create index if not exists projeto_aprovacoes_idx
  on public.projeto_aprovacoes (project_id, created_at desc);

-- 8. Documentos ──────────────────────────────────────────────────
create table if not exists public.projeto_documentos (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects(id) on delete cascade,
  client_id   uuid references public.profiles(id) on delete set null,
  pasta       text not null default 'DESENVOLVIMENTO',
  nome        text not null,
  caminho     text not null,
  tamanho     bigint,
  publico     boolean not null default true,
  enviado_por text,
  enviado_tipo text not null default 'EQUIPE',   -- EQUIPE | CLIENTE
  created_at  timestamptz not null default now()
);

create index if not exists projeto_documentos_idx
  on public.projeto_documentos (project_id, created_at desc);

-- 9. Comunicação ─────────────────────────────────────────────────
-- Conversa por projeto, e não uma caixa única: assuntos de projetos
-- diferentes misturados é o que leva o cliente de volta ao WhatsApp.
create table if not exists public.projeto_mensagens (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects(id) on delete cascade,
  autor_id    uuid,
  autor_nome  text,
  autor_tipo  text not null default 'EQUIPE',    -- EQUIPE | CLIENTE
  mensagem    text not null,
  anexo       text,
  created_at  timestamptz not null default now()
);

create index if not exists projeto_mensagens_idx
  on public.projeto_mensagens (project_id, created_at);

-- 10. Anexos dos projetos ────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('projeto-arquivos', 'projeto-arquivos', false)
on conflict (id) do nothing;

drop policy if exists "equipe_le_projeto_arquivos"    on storage.objects;
drop policy if exists "equipe_envia_projeto_arquivos" on storage.objects;
drop policy if exists "cliente_le_projeto_arquivos"   on storage.objects;
drop policy if exists "cliente_envia_projeto_arquivos" on storage.objects;

create policy "equipe_le_projeto_arquivos" on storage.objects
  for select to authenticated
  using (bucket_id = 'projeto-arquivos' and public.is_equipe());

create policy "equipe_envia_projeto_arquivos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'projeto-arquivos' and public.is_equipe());

-- O caminho começa com o id do projeto; o cliente só alcança os projetos
-- que são dele.
create policy "cliente_le_projeto_arquivos" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'projeto-arquivos'
    and exists (
      select 1 from public.projects p
      where p.id::text = (storage.foldername(name))[1] and p.client_id = auth.uid()
    )
  );

create policy "cliente_envia_projeto_arquivos" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'projeto-arquivos'
    and exists (
      select 1 from public.projects p
      where p.id::text = (storage.foldername(name))[1] and p.client_id = auth.uid()
    )
  );

-- 11. Acesso ─────────────────────────────────────────────────────
alter table public.projeto_etapas        enable row level security;
alter table public.projeto_tarefas       enable row level security;
alter table public.projeto_atualizacoes  enable row level security;
alter table public.projeto_historico     enable row level security;
alter table public.projeto_aprovacoes    enable row level security;
alter table public.projeto_documentos    enable row level security;
alter table public.projeto_mensagens     enable row level security;

create or replace function public.meu_projeto(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.projects where id = p and client_id = auth.uid());
$$;

-- A equipe gerencia tudo.
do $$
declare t text;
begin
  foreach t in array array['projeto_etapas','projeto_tarefas','projeto_atualizacoes',
                           'projeto_historico','projeto_aprovacoes','projeto_documentos',
                           'projeto_mensagens']
  loop
    execute format('drop policy if exists "equipe_gerencia_%1$s" on public.%1$I', t);
    execute format('create policy "equipe_gerencia_%1$s" on public.%1$I
                      for all to authenticated
                      using (public.is_equipe()) with check (public.is_equipe())', t);
  end loop;
end $$;

-- O cliente lê as etapas e tarefas dos projetos dele, mas não as
-- observações internas — por isso a tela dele usa a view abaixo.
drop policy if exists "cliente_le_etapas" on public.projeto_etapas;
create policy "cliente_le_etapas" on public.projeto_etapas
  for select to authenticated using (public.meu_projeto(project_id));

drop policy if exists "cliente_le_tarefas" on public.projeto_tarefas;
create policy "cliente_le_tarefas" on public.projeto_tarefas
  for select to authenticated using (public.meu_projeto(project_id));

-- Só a atualização marcada como pública chega ao cliente.
drop policy if exists "cliente_le_atualizacoes" on public.projeto_atualizacoes;
create policy "cliente_le_atualizacoes" on public.projeto_atualizacoes
  for select to authenticated
  using (publica and public.meu_projeto(project_id));

-- Histórico é registro interno: fica com a equipe.
drop policy if exists "cliente_le_aprovacoes" on public.projeto_aprovacoes;
create policy "cliente_le_aprovacoes" on public.projeto_aprovacoes
  for select to authenticated using (public.meu_projeto(project_id));

-- Aprovar é do cliente; o resto da linha é da equipe, e o gatilho garante.
drop policy if exists "cliente_responde_aprovacao" on public.projeto_aprovacoes;
create policy "cliente_responde_aprovacao" on public.projeto_aprovacoes
  for update to authenticated
  using (public.meu_projeto(project_id) and situacao = 'PENDENTE')
  with check (public.meu_projeto(project_id));

-- A policy deixa o cliente escrever na linha, mas não diz QUAIS colunas:
-- sem este gatilho ele poderia reescrever o título e o prazo na mesma
-- chamada. Aqui tudo volta ao que a equipe gravou, menos a resposta.
create or replace function public.aprovacao_cliente_limita()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  resposta_cliente text;
  situacao_nova    text;
  nome             text;
begin
  if current_user in ('anon','authenticated')
     and not public.is_equipe()
     and public.meu_projeto(old.project_id) then

    if new.situacao not in ('APROVADA','AJUSTES') then
      raise exception 'Responda aprovando ou pedindo ajustes.';
    end if;
    if new.situacao = 'AJUSTES' and coalesce(btrim(new.resposta), '') = '' then
      raise exception 'Ao pedir ajustes, escreva o que precisa mudar.';
    end if;

    situacao_nova    := new.situacao;
    resposta_cliente := new.resposta;
    select coalesce(p.name, p.company) into nome
    from public.profiles p where p.id = auth.uid();

    new := old;
    new.situacao       := situacao_nova;
    new.resposta       := resposta_cliente;
    new.respondido_por := nome;
    new.respondido_em  := now();
  end if;
  return new;
end $$;

drop trigger if exists aprovacao_cliente_limita on public.projeto_aprovacoes;
create trigger aprovacao_cliente_limita
  before update on public.projeto_aprovacoes
  for each row execute function public.aprovacao_cliente_limita();

drop policy if exists "cliente_le_documentos" on public.projeto_documentos;
create policy "cliente_le_documentos" on public.projeto_documentos
  for select to authenticated
  using (publico and public.meu_projeto(project_id));

drop policy if exists "cliente_envia_documento" on public.projeto_documentos;
create policy "cliente_envia_documento" on public.projeto_documentos
  for insert to authenticated
  with check (public.meu_projeto(project_id) and enviado_tipo = 'CLIENTE' and publico);

drop policy if exists "cliente_le_mensagens_projeto" on public.projeto_mensagens;
create policy "cliente_le_mensagens_projeto" on public.projeto_mensagens
  for select to authenticated using (public.meu_projeto(project_id));

drop policy if exists "cliente_escreve_mensagem_projeto" on public.projeto_mensagens;
create policy "cliente_escreve_mensagem_projeto" on public.projeto_mensagens
  for insert to authenticated
  with check (public.meu_projeto(project_id) and autor_tipo = 'CLIENTE');
