-- ════════════════════════════════════════════════════════════════
-- Notificações do painel e do portal
-- Rodar no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
--
-- O aviso nasce no banco, por gatilho, e não na tela: assim um chamado
-- aberto às duas da manhã continua aparecendo quando alguém entrar, e
-- não depende de quem estava com a página aberta na hora.
-- ════════════════════════════════════════════════════════════════

create table if not exists public.notificacoes (
  id         uuid primary key default gen_random_uuid(),
  destino    text not null,              -- EQUIPE | CLIENTE | COLABORADOR
  profile_id uuid references public.profiles(id) on delete cascade,
  tipo       text not null,              -- CHAMADO | FATURA | PROJETO | DEPOIMENTO | FEEDBACK | RH
  titulo     text not null,
  descricao  text,
  aba        text,                       -- aba a abrir ao clicar
  referencia uuid,
  created_at timestamptz not null default now()
);

alter table public.notificacoes drop constraint if exists notificacoes_destino_check;
alter table public.notificacoes
  add constraint notificacoes_destino_check
  check (destino in ('EQUIPE','CLIENTE','COLABORADOR'));

create index if not exists notificacoes_idx
  on public.notificacoes (destino, created_at desc);

-- Quem já leu fica em tabela separada porque um aviso para a EQUIPE é lido
-- por várias pessoas: marcar "lida" na própria linha faria o primeiro a
-- abrir apagar o aviso de todo mundo.
create table if not exists public.notificacoes_lidas (
  notificacao_id uuid not null references public.notificacoes(id) on delete cascade,
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  lida_em        timestamptz not null default now(),
  primary key (notificacao_id, profile_id)
);

-- ── Como cada aviso nasce ────────────────────────────────────────
create or replace function public.notificar(
  p_destino text, p_profile uuid, p_tipo text,
  p_titulo text, p_descricao text, p_aba text, p_ref uuid)
returns void language sql security definer set search_path = public as $$
  insert into public.notificacoes (destino, profile_id, tipo, titulo, descricao, aba, referencia)
  values (p_destino, p_profile, p_tipo, p_titulo, p_descricao, p_aba, p_ref);
$$;

-- Chamado aberto → avisa a equipe.
create or replace function public.notifica_ticket_novo()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.notificar('EQUIPE', null, 'CHAMADO',
    'Novo chamado #SC-' || lpad(coalesce(new.numero, 0)::text, 6, '0'),
    new.subject, 'chamados', new.id);
  return new;
end $$;

drop trigger if exists notifica_ticket_novo on public.tickets;
create trigger notifica_ticket_novo
  after insert on public.tickets
  for each row execute function public.notifica_ticket_novo();

-- Situação mudou → avisa o cliente dono do chamado.
create or replace function public.notifica_ticket_situacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  rotulo text := case new.status
    when 'ABERTO' then 'Aberto'
    when 'EM_ATENDIMENTO' then 'Em atendimento'
    when 'AGUARDANDO_RESPOSTA' then 'Aguardando sua resposta'
    when 'CONCLUIDO' then 'Concluído'
    when 'CANCELADO' then 'Cancelado'
    else new.status end;
begin
  if new.status is distinct from old.status then
    perform public.notificar('CLIENTE', new.client_id, 'CHAMADO',
      'Chamado #SC-' || lpad(coalesce(new.numero, 0)::text, 6, '0') || ': ' || rotulo,
      new.subject, 'suporte', new.id);
  end if;
  return new;
end $$;

drop trigger if exists notifica_ticket_situacao on public.tickets;
create trigger notifica_ticket_situacao
  after update on public.tickets
  for each row execute function public.notifica_ticket_situacao();

-- Mensagem na conversa → avisa o outro lado. Nota interna não avisa ninguém.
create or replace function public.notifica_ticket_mensagem()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  t public.tickets;
  marca text;
begin
  if new.tipo = 'NOTA_INTERNA' then return new; end if;
  select * into t from public.tickets where id = new.ticket_id;
  marca := '#SC-' || lpad(coalesce(t.numero, 0)::text, 6, '0');

  if new.autor_tipo = 'CLIENTE' then
    perform public.notificar('EQUIPE', null, 'CHAMADO',
      'Resposta do cliente em ' || marca, t.subject, 'chamados', t.id);
  else
    perform public.notificar('CLIENTE', t.client_id, 'CHAMADO',
      case when new.tipo = 'SOLICITACAO'
        then 'A SertCode pediu uma informação em ' || marca
        else 'A SertCode respondeu ' || marca end,
      t.subject, 'suporte', t.id);
  end if;
  return new;
end $$;

drop trigger if exists notifica_ticket_mensagem on public.ticket_mensagens;
create trigger notifica_ticket_mensagem
  after insert on public.ticket_mensagens
  for each row execute function public.notifica_ticket_mensagem();

-- Cobrança emitida → avisa o cliente. Cobrança paga → avisa a equipe.
create or replace function public.notifica_fatura()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public.notificar('CLIENTE', new.client_id, 'FATURA',
      'Nova cobrança de R$ ' || to_char(new.amount - coalesce(new.desconto, 0), 'FM999G999D00'),
      coalesce(new.description, '') || ' · vence em ' || to_char(new.due_date, 'DD/MM/YYYY'),
      'financeiro', new.id);
  elsif new.status = 'pago' and old.status is distinct from 'pago' then
    perform public.notificar('EQUIPE', null, 'FATURA',
      'Fatura #' || lpad(coalesce(new.numero, 0)::text, 5, '0') || ' paga',
      coalesce(new.description, ''), 'financeiro', new.id);
  end if;
  return new;
end $$;

drop trigger if exists notifica_fatura on public.invoices;
create trigger notifica_fatura
  after insert or update on public.invoices
  for each row execute function public.notifica_fatura();

-- Projeto andou → avisa o cliente.
create or replace function public.notifica_projeto()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    perform public.notificar('CLIENTE', new.client_id, 'PROJETO',
      'Projeto ' || new.name || ': ' || new.status, null, 'projeto', new.id);
  elsif coalesce(new.progress, 0) is distinct from coalesce(old.progress, 0) then
    perform public.notificar('CLIENTE', new.client_id, 'PROJETO',
      'Projeto ' || new.name || ' em ' || new.progress || '%',
      coalesce(new.current_phase, ''), 'projeto', new.id);
  end if;
  return new;
end $$;

drop trigger if exists notifica_projeto on public.projects;
create trigger notifica_projeto
  after update on public.projects
  for each row execute function public.notifica_projeto();

-- Depoimento e feedback → avisam a equipe.
create or replace function public.notifica_depoimento()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.notificar('EQUIPE', null, 'DEPOIMENTO',
    'Novo depoimento de ' || coalesce(new.client_name, 'cliente'),
    new.content, 'depoimentos', new.id);
  return new;
end $$;

drop trigger if exists notifica_depoimento on public.testimonials;
create trigger notifica_depoimento
  after insert on public.testimonials
  for each row execute function public.notifica_depoimento();

create or replace function public.notifica_feedback()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.notificar('EQUIPE', null, 'FEEDBACK',
    'Novo feedback de ' || coalesce(new.client_name, 'cliente')
      || ' (' || coalesce(new.rating, 0) || ' estrelas)',
    new.message, 'feedbacks', new.id);
  return new;
end $$;

drop trigger if exists notifica_feedback on public.feedbacks;
create trigger notifica_feedback
  after insert on public.feedbacks
  for each row execute function public.notifica_feedback();

-- Solicitação do Meu RH → avisa a Gestão; a resposta avisa o colaborador.
create or replace function public.notifica_solicitacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  quem uuid;
begin
  select profile_id into quem from public.rh_colaboradores where id = new.colaborador_id;

  if tg_op = 'INSERT' then
    perform public.notificar('EQUIPE', null, 'RH',
      'Nova solicitação: ' || new.assunto, new.descricao, 'pessoas', new.id);
  elsif new.status is distinct from old.status and quem is not null then
    perform public.notificar('COLABORADOR', quem, 'RH',
      'Sua solicitação está ' || new.status, new.assunto, 'meu-rh', new.id);
  end if;
  return new;
end $$;

drop trigger if exists notifica_solicitacao on public.rh_solicitacoes;
create trigger notifica_solicitacao
  after insert or update on public.rh_solicitacoes
  for each row execute function public.notifica_solicitacao();

-- ── Acesso ───────────────────────────────────────────────────────
alter table public.notificacoes       enable row level security;
alter table public.notificacoes_lidas enable row level security;

-- A equipe lê os avisos dela e os que apontam para a própria pessoa.
drop policy if exists "le_minhas_notificacoes" on public.notificacoes;
create policy "le_minhas_notificacoes" on public.notificacoes
  for select to authenticated
  using (
    (destino = 'EQUIPE' and public.is_equipe())
    or profile_id = auth.uid()
  );

drop policy if exists "gestor_apaga_notificacoes" on public.notificacoes;
create policy "gestor_apaga_notificacoes" on public.notificacoes
  for delete to authenticated
  using (public.is_gestor());

-- Cada pessoa marca como lida só para si.
drop policy if exists "marca_lida_para_mim" on public.notificacoes_lidas;
create policy "marca_lida_para_mim" on public.notificacoes_lidas
  for all to authenticated
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());
