-- ════════════════════════════════════════════════════════════════
-- Suporte da SertCode — modelo do SertLink
-- Rodar no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
--
-- O chamado deixa de ser assunto + resposta única e passa a ter
-- número, tipo, prioridade, responsável, prazo e conversa — do lado
-- do cliente e do lado da equipe.
-- ════════════════════════════════════════════════════════════════

-- 1. Numeração ───────────────────────────────────────────────────
-- Número curto e sequencial (#SC-000020) porque é o que cliente e
-- equipe citam por telefone; o id interno é longo demais para isso.
create sequence if not exists public.ticket_numero_seq start 1;

alter table public.tickets
  add column if not exists numero         bigint,
  add column if not exists anexo          text,
  add column if not exists aguardando_equipe boolean not null default true,
  add column if not exists prioridade     text not null default 'MEDIA',   -- ALTA | MEDIA | BAIXA
  add column if not exists responsavel_id uuid,
  add column if not exists responsavel_nome text,
  add column if not exists prazo          date,
  add column if not exists primeira_resposta_em timestamptz,
  add column if not exists concluido_em   timestamptz,
  add column if not exists cancelado_em   timestamptz,
  add column if not exists atualizado_em  timestamptz default now();

alter table public.tickets
  alter column numero set default nextval('public.ticket_numero_seq');

-- Numera o que já existe, na ordem de abertura.
with ordenados as (
  select id, row_number() over (order by created_at) as n
  from public.tickets where numero is null
)
update public.tickets t set numero = o.n
from ordenados o where t.id = o.id;

select setval('public.ticket_numero_seq',
  greatest(coalesce((select max(numero) from public.tickets), 0), 1));

create unique index if not exists tickets_numero_idx on public.tickets (numero);

-- 2. Vocabulário novo ────────────────────────────────────────────
update public.tickets set type = case type
  when 'bug'     then 'ERRO'
  when 'urgent'  then 'ERRO'
  when 'feature' then 'FUNCIONALIDADE'
  when 'doubt'   then 'SUGESTAO'
  else type
end
where type in ('bug', 'urgent', 'feature', 'doubt');

update public.tickets set status = case status
  when 'open'     then 'ABERTO'
  when 'analysis' then 'EM_ATENDIMENTO'
  when 'done'     then 'CONCLUIDO'
  else status
end
where status in ('open', 'analysis', 'done');

update public.tickets set type = 'SUGESTAO'
where type is null or type not in ('ERRO','FINANCEIRO','SUGESTAO','ELOGIO','FUNCIONALIDADE');

update public.tickets set status = 'ABERTO'
where status is null or status not in ('ABERTO','EM_ATENDIMENTO','AGUARDANDO_RESPOSTA','CONCLUIDO','CANCELADO');

-- Chamado encerrado não espera ninguém.
update public.tickets set aguardando_equipe = false
where status in ('CONCLUIDO', 'CANCELADO');

alter table public.tickets drop constraint if exists tickets_type_check;
alter table public.tickets drop constraint if exists tickets_status_check;
alter table public.tickets
  add constraint tickets_type_check
  check (type in ('ERRO','FINANCEIRO','SUGESTAO','ELOGIO','FUNCIONALIDADE'));
alter table public.tickets
  add constraint tickets_status_check
  check (status in ('ABERTO','EM_ATENDIMENTO','AGUARDANDO_RESPOSTA','CONCLUIDO','CANCELADO'));

-- 3. Prazo de primeira resposta (SLA) ────────────────────────────
-- O prazo nasce do tipo do chamado, não da mão de quem atende: assim o
-- cliente sabe o que esperar antes de alguém olhar o chamado.
create or replace function public.dias_uteis(partida date, dias int)
returns date language plpgsql immutable as $$
declare
  d date := partida;
  faltam int := dias;
begin
  while faltam > 0 loop
    d := d + 1;
    -- Sábado e domingo não contam no prazo.
    if extract(isodow from d) < 6 then
      faltam := faltam - 1;
    end if;
  end loop;
  return d;
end $$;

create or replace function public.ticket_define_prazo()
returns trigger language plpgsql as $$
declare
  dias int := case new.type
    when 'ERRO'           then 1
    when 'FINANCEIRO'     then 1
    when 'SUGESTAO'       then 3
    when 'FUNCIONALIDADE' then 3
    else null                        -- Elogio não tem prazo
  end;
begin
  if new.prazo is null and dias is not null then
    new.prazo := public.dias_uteis(coalesce(new.created_at, now())::date, dias);
  end if;
  return new;
end $$;

drop trigger if exists ticket_define_prazo on public.tickets;
create trigger ticket_define_prazo
  before insert on public.tickets
  for each row execute function public.ticket_define_prazo();

-- Preenche o prazo dos chamados que já existiam.
update public.tickets t set prazo = public.dias_uteis(t.created_at::date,
  case t.type when 'ERRO' then 1 when 'FINANCEIRO' then 1 else 3 end)
where t.prazo is null and t.type <> 'ELOGIO';

-- 4. Conversa ────────────────────────────────────────────────────
-- A resposta única não bastava: cliente e equipe trocam mensagens, e
-- a equipe precisa de uma anotação que o cliente não vê.
create table if not exists public.ticket_mensagens (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid not null references public.tickets(id) on delete cascade,
  autor_id   uuid,
  autor_nome text,
  autor_tipo text not null default 'EQUIPE',     -- CLIENTE | EQUIPE
  tipo       text not null default 'RESPOSTA',   -- RESPOSTA | SOLICITACAO | NOTA_INTERNA
  mensagem   text not null,
  anexo      text,
  created_at timestamptz not null default now()
);

create index if not exists ticket_mensagens_idx
  on public.ticket_mensagens (ticket_id, created_at);

-- O cliente não pode escrever na tabela de chamados, mas responder
-- precisa reabrir o atendimento: o gatilho faz isso por ele, sem abrir
-- a tabela tickets para o portal.
create or replace function public.ticket_mensagem_marca()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.tipo = 'NOTA_INTERNA' then
    return new;                      -- conversa interna não move o chamado
  end if;

  update public.tickets set
    aguardando_equipe = (new.autor_tipo = 'CLIENTE'),
    -- A primeira resposta da equipe é o que o SLA mede.
    primeira_resposta_em = case
      when new.autor_tipo = 'EQUIPE' and primeira_resposta_em is null
        then now() else primeira_resposta_em end,
    status = case
      when new.autor_tipo = 'CLIENTE' and status in ('AGUARDANDO_RESPOSTA','CONCLUIDO')
        then 'EM_ATENDIMENTO'
      else status
    end,
    concluido_em  = case when new.autor_tipo = 'CLIENTE' and status = 'CONCLUIDO'
                         then null else concluido_em end,
    atualizado_em = now()
  where id = new.ticket_id;

  return new;
end $$;

drop trigger if exists ticket_mensagem_marca on public.ticket_mensagens;
create trigger ticket_mensagem_marca
  after insert on public.ticket_mensagens
  for each row execute function public.ticket_mensagem_marca();

-- 5. Histórico ───────────────────────────────────────────────────
-- Quem mudou situação, prioridade ou responsável, e quando.
create table if not exists public.ticket_eventos (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid not null references public.tickets(id) on delete cascade,
  descricao  text not null,
  autor_nome text,
  created_at timestamptz not null default now()
);

create index if not exists ticket_eventos_idx
  on public.ticket_eventos (ticket_id, created_at desc);

-- 6. Anexos ──────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('suporte-anexos', 'suporte-anexos', false)
on conflict (id) do nothing;

drop policy if exists "equipe_le_anexos_suporte"    on storage.objects;
drop policy if exists "equipe_envia_anexos_suporte" on storage.objects;
drop policy if exists "cliente_anexos_suporte"      on storage.objects;
drop policy if exists "cliente_le_anexos_suporte"   on storage.objects;

create policy "equipe_le_anexos_suporte" on storage.objects
  for select to authenticated
  using (bucket_id = 'suporte-anexos' and public.is_equipe());

create policy "equipe_envia_anexos_suporte" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'suporte-anexos' and public.is_equipe());

-- O caminho começa com o id do cliente, como o portal grava ao enviar.
create policy "cliente_anexos_suporte" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'suporte-anexos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "cliente_le_anexos_suporte" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'suporte-anexos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- 7. Acesso ──────────────────────────────────────────────────────
alter table public.ticket_mensagens enable row level security;
alter table public.ticket_eventos   enable row level security;

drop policy if exists "equipe_gerencia_mensagens_ticket" on public.ticket_mensagens;
create policy "equipe_gerencia_mensagens_ticket" on public.ticket_mensagens
  for all to authenticated
  using (public.is_equipe()) with check (public.is_equipe());

-- Nota interna é conversa da equipe sobre o chamado: fica fora do que
-- o cliente lê, senão deixa de servir ao propósito.
drop policy if exists "cliente_le_mensagens_ticket" on public.ticket_mensagens;
create policy "cliente_le_mensagens_ticket" on public.ticket_mensagens
  for select to authenticated
  using (
    tipo <> 'NOTA_INTERNA'
    and exists (
      select 1 from public.tickets t
      where t.id = ticket_mensagens.ticket_id and t.client_id = auth.uid()
    )
  );

-- Cancelar é decisão do cliente: ele desiste do pedido. A equipe conclui,
-- não cancela. A policy abaixo é a única escrita do cliente em tickets, e
-- o gatilho garante que nada além da situação muda.
drop policy if exists "cliente_cancela_ticket" on public.tickets;
create policy "cliente_cancela_ticket" on public.tickets
  for update to authenticated
  using (client_id = auth.uid() and status <> 'CANCELADO')
  with check (client_id = auth.uid() and status = 'CANCELADO');

create or replace function public.ticket_cliente_so_cancela()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_user in ('anon', 'authenticated')
     and not public.is_equipe()
     and old.client_id = auth.uid() then
    -- Devolve tudo ao que era, menos a situação e as marcas de cancelamento.
    new := old;
    new.status := 'CANCELADO';
    new.cancelado_em := now();
    new.aguardando_equipe := false;
    new.atualizado_em := now();
  end if;
  return new;
end $$;

drop trigger if exists ticket_cliente_so_cancela on public.tickets;
create trigger ticket_cliente_so_cancela
  before update on public.tickets
  for each row execute function public.ticket_cliente_so_cancela();

-- Chamado cancelado não recebe mais mensagem de ninguém.
drop policy if exists "cliente_responde_ticket" on public.ticket_mensagens;
create policy "cliente_responde_ticket" on public.ticket_mensagens
  for insert to authenticated
  with check (
    autor_tipo = 'CLIENTE' and tipo = 'RESPOSTA'
    and exists (
      select 1 from public.tickets t
      where t.id = ticket_mensagens.ticket_id
        and t.client_id = auth.uid()
        and t.status <> 'CANCELADO'
    )
  );

drop policy if exists "equipe_gerencia_eventos_ticket" on public.ticket_eventos;
create policy "equipe_gerencia_eventos_ticket" on public.ticket_eventos
  for all to authenticated
  using (public.is_equipe()) with check (public.is_equipe());

drop policy if exists "cliente_le_eventos_ticket" on public.ticket_eventos;
create policy "cliente_le_eventos_ticket" on public.ticket_eventos
  for select to authenticated
  using (exists (
    select 1 from public.tickets t
    where t.id = ticket_eventos.ticket_id and t.client_id = auth.uid()
  ));
