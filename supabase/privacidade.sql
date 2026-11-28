-- ════════════════════════════════════════════════════════════════
-- Solicitações de privacidade (LGPD)
-- Rodar no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
--
-- Três decisões que valem o registro:
--
-- 1. O formulário público NÃO escreve na tabela. Quem envia é um visitante
--    anônimo; dar a ele INSERT em privacy_requests abriria a porta para
--    inundar a tabela e para tentar ler de volta o que outros escreveram.
--    Toda a entrada passa por uma função SECURITY DEFINER que gera o
--    protocolo, aplica o limite de envios e devolve só o protocolo.
--
-- 2. O histórico fica em tabela própria (privacy_request_events). A LGPD
--    pede que a empresa consiga demonstrar o que fez e quando; sobrescrever
--    um campo "última ação" apagaria exatamente essa prova.
--
-- 3. O acesso é restrito por permissão, não por perfil solto. Por padrão só
--    administrador e gestor enxergam; um gestor pode abrir a área para
--    outra pessoa criando a exceção 'privacidade.ver' em equipe_permissoes.
-- ════════════════════════════════════════════════════════════════

-- 1. Tabelas ──────────────────────────────────────────────────────
create table if not exists public.privacy_requests (
  id          uuid primary key default gen_random_uuid(),
  protocol    text not null unique,
  name        text not null,
  email       text not null,
  related_to  text,                       -- empresa ou sistema relacionado
  account_ref text,                       -- identificação do cadastro, quando houver
  type        text not null,
  description text not null,
  status      text not null default 'RECEBIDA',
  assigned_to uuid references public.profiles(id) on delete set null,
  origem_hash text,                       -- hash do IP: serve só para limitar envios
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  closed_at   timestamptz
);

alter table public.privacy_requests drop constraint if exists privacy_requests_type_check;
alter table public.privacy_requests
  add constraint privacy_requests_type_check check (type in (
    'CONFIRMAR','ACESSO','CORRIGIR','EXCLUIR','REVOGAR','COMPARTILHAMENTO','OUTRA'));

alter table public.privacy_requests drop constraint if exists privacy_requests_status_check;
alter table public.privacy_requests
  add constraint privacy_requests_status_check check (status in (
    'RECEBIDA','EM_ANALISE','IDENTIDADE','RESPONDIDA','ENCERRADA'));

create index if not exists privacy_requests_idx
  on public.privacy_requests (status, created_at desc);
create index if not exists privacy_requests_email_idx
  on public.privacy_requests (email, created_at desc);

create table if not exists public.privacy_request_events (
  id         uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.privacy_requests(id) on delete cascade,
  kind       text not null,
  text       text not null,
  author_id  uuid references public.profiles(id) on delete set null,
  author     text,                        -- nome gravado na hora: sobrevive à saída da pessoa
  created_at timestamptz not null default now()
);

alter table public.privacy_request_events drop constraint if exists privacy_request_events_kind_check;
alter table public.privacy_request_events
  add constraint privacy_request_events_kind_check check (kind in (
    'ABERTURA','NOTA','STATUS','RESPOSTA','RESPONSAVEL'));

create index if not exists privacy_request_events_idx
  on public.privacy_request_events (request_id, created_at);


-- 2. Quem pode atender ────────────────────────────────────────────
-- Por padrão administrador e gestor. A exceção em equipe_permissoes manda
-- sobre o padrão, nos dois sentidos: libera para quem não teria e tira de
-- quem teria. O coalesce com p.role cobre as contas criadas antes de
-- equipe.sql, que ainda não têm `perfil` preenchido.
create or replace function public.pode_privacidade()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.profiles p
    left join public.equipe_permissoes ep
      on ep.profile_id = p.id and ep.chave = 'privacidade.ver'
    where p.id = auth.uid()
      and p.status = 'ativo'
      and coalesce(
            ep.permitido,
            p.perfil in ('ADMINISTRADOR','GESTOR') or p.role = 'gestor'
          )
  );
$$;

-- O painel chama esta função antes de mostrar o item no menu: um SELECT
-- barrado pela RLS volta vazio, não com erro, e sem perguntar não dá para
-- distinguir "não pode ver" de "ainda não chegou pedido nenhum".
revoke all on function public.pode_privacidade() from public, anon;
grant execute on function public.pode_privacidade() to authenticated;


-- 3. Protocolo ────────────────────────────────────────────────────
-- Formato PRV-AAAAMMDD-XXXX com o dia de Brasília. O alfabeto não tem
-- I, O, 0 nem 1: o protocolo é lido por telefone e ditado por e-mail.
create or replace function public.novo_protocolo_privacidade()
returns text language plpgsql volatile set search_path = public as $$
declare
  alfabeto constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  dia text := to_char(timezone('America/Sao_Paulo', now()), 'YYYYMMDD');
  sufixo text;
  tentativa int := 0;
  candidato text;
begin
  loop
    sufixo := '';
    for i in 1..4 loop
      sufixo := sufixo || substr(alfabeto, 1 + floor(random() * length(alfabeto))::int, 1);
    end loop;
    candidato := 'PRV-' || dia || '-' || sufixo;
    exit when not exists (select 1 from public.privacy_requests where protocol = candidato);
    tentativa := tentativa + 1;
    if tentativa >= 20 then
      raise exception 'Não foi possível gerar o protocolo.';
    end if;
  end loop;
  return candidato;
end $$;


-- 4. Entrada pelo formulário público ──────────────────────────────
-- Limites: 3 pedidos por e-mail em 24 h e 8 por origem em 1 h. Quem
-- precisa mesmo abrir vários pedidos escreve no e-mail de privacidade;
-- o limite existe para o robô, não para o titular.
create or replace function public.abrir_solicitacao_privacidade(
  p_name text, p_email text, p_type text, p_description text,
  p_related_to text default null, p_account_ref text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_nome  text := btrim(coalesce(p_name, ''));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_desc  text := btrim(coalesce(p_description, ''));
  v_rel   text := nullif(btrim(coalesce(p_related_to, '')), '');
  v_conta text := nullif(btrim(coalesce(p_account_ref, '')), '');
  v_ip    text;
  v_hash  text;
  v_protocolo text;
  v_id    uuid;
begin
  if length(v_nome) < 3 or length(v_nome) > 120 then
    raise exception 'Informe seu nome completo.' using errcode = 'check_violation';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 160 then
    raise exception 'Informe um e-mail válido para a resposta.' using errcode = 'check_violation';
  end if;
  if p_type is null or p_type not in
     ('CONFIRMAR','ACESSO','CORRIGIR','EXCLUIR','REVOGAR','COMPARTILHAMENTO','OUTRA') then
    raise exception 'Escolha o assunto da solicitação.' using errcode = 'check_violation';
  end if;
  if length(v_desc) < 10 then
    raise exception 'Descreva a solicitação com pelo menos 10 caracteres.' using errcode = 'check_violation';
  end if;
  if length(v_desc) > 4000 then
    raise exception 'Descrição muito longa: use até 4.000 caracteres.' using errcode = 'check_violation';
  end if;
  if length(coalesce(v_rel, '')) > 120 or length(coalesce(v_conta, '')) > 160 then
    raise exception 'Campo muito longo.' using errcode = 'check_violation';
  end if;

  -- O IP vem do cabeçalho que o PostgREST repassa; guardamos só o hash,
  -- porque o IP em claro seria mais um dado pessoal para proteger.
  begin
    v_ip := split_part(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ',', 1);
  exception when others then
    v_ip := null;
  end;
  -- sha256() é função do próprio Postgres (15): não depende do pgcrypto
  -- estar instalado neste ou naquele schema.
  v_hash := case when nullif(btrim(coalesce(v_ip, '')), '') is null then null
                 else encode(sha256(convert_to('privacidade:' || v_ip, 'UTF8')), 'hex') end;

  if (select count(*) from public.privacy_requests
      where email = v_email and created_at > now() - interval '24 hours') >= 3 then
    raise exception 'Já recebemos pedidos deste e-mail hoje. Responda o e-mail de confirmação para complementar.'
      using errcode = 'check_violation';
  end if;
  if v_hash is not null and (select count(*) from public.privacy_requests
      where origem_hash = v_hash and created_at > now() - interval '1 hour') >= 8 then
    raise exception 'Muitos envios seguidos. Tente novamente em alguns minutos.'
      using errcode = 'check_violation';
  end if;

  v_protocolo := public.novo_protocolo_privacidade();

  insert into public.privacy_requests (protocol, name, email, related_to, account_ref, type, description, origem_hash)
  values (v_protocolo, v_nome, v_email, v_rel, v_conta, p_type, v_desc, v_hash)
  returning id into v_id;

  insert into public.privacy_request_events (request_id, kind, text, author)
  values (v_id, 'ABERTURA', 'Solicitação recebida pelo formulário Contato sobre Privacidade.', 'Site');

  perform public.notificar('EQUIPE', null, 'PRIVACIDADE',
    'Nova solicitação de privacidade ' || v_protocolo,
    v_nome || ' — ' || public.rotulo_tipo_privacidade(p_type),
    'privacidade', v_id);

  return v_protocolo;
end $$;

-- Rótulo legível do tipo, usado no aviso e nos relatórios.
create or replace function public.rotulo_tipo_privacidade(p_tipo text)
returns text language sql immutable as $$
  select case p_tipo
    when 'CONFIRMAR'        then 'Confirmar se tratamos seus dados'
    when 'ACESSO'           then 'Acesso aos dados'
    when 'CORRIGIR'         then 'Correção de dados pessoais'
    when 'EXCLUIR'          then 'Exclusão de dados'
    when 'REVOGAR'          then 'Revogação de consentimento'
    when 'COMPARTILHAMENTO' then 'Com quem os dados são compartilhados'
    else 'Outra solicitação sobre privacidade'
  end;
$$;

revoke all on function public.abrir_solicitacao_privacidade(text, text, text, text, text, text) from public;
grant execute on function public.abrir_solicitacao_privacidade(text, text, text, text, text, text)
  to anon, authenticated;


-- 5. Mudança de situação e histórico ──────────────────────────────
-- Trocar a situação é uma ação, não só um UPDATE: ela precisa aparecer no
-- histórico com autor e data. Por isso a tela chama esta função em vez de
-- escrever direto na linha.
create or replace function public.privacidade_muda_situacao(
  p_id uuid, p_status text, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_antes text;
  v_nome  text;
begin
  if not public.pode_privacidade() then
    raise exception 'Sem permissão para atender solicitações de privacidade.';
  end if;
  if p_status not in ('RECEBIDA','EM_ANALISE','IDENTIDADE','RESPONDIDA','ENCERRADA') then
    raise exception 'Situação inválida.';
  end if;

  select status into v_antes from public.privacy_requests where id = p_id;
  if v_antes is null then
    raise exception 'Solicitação não encontrada.';
  end if;

  select coalesce(nickname, name, 'Equipe') into v_nome from public.profiles where id = auth.uid();

  update public.privacy_requests
     set status = p_status,
         updated_at = now(),
         closed_at = case when p_status = 'ENCERRADA' then now() else null end
   where id = p_id;

  insert into public.privacy_request_events (request_id, kind, text, author_id, author)
  values (p_id, 'STATUS',
          'Situação alterada de ' || public.rotulo_situacao_privacidade(v_antes) ||
          ' para ' || public.rotulo_situacao_privacidade(p_status) ||
          coalesce('. ' || nullif(btrim(p_nota), ''), ''),
          auth.uid(), v_nome);
end $$;

create or replace function public.rotulo_situacao_privacidade(p_status text)
returns text language sql immutable as $$
  select case p_status
    when 'RECEBIDA'   then 'Recebida'
    when 'EM_ANALISE' then 'Em análise'
    when 'IDENTIDADE' then 'Identidade a confirmar'
    when 'RESPONDIDA' then 'Respondida'
    when 'ENCERRADA'  then 'Encerrada'
    else p_status
  end;
$$;

revoke all on function public.privacidade_muda_situacao(uuid, text, text) from public, anon;
grant execute on function public.privacidade_muda_situacao(uuid, text, text) to authenticated;


-- 6. Acesso ───────────────────────────────────────────────────────
alter table public.privacy_requests       enable row level security;
alter table public.privacy_request_events enable row level security;

-- Nenhuma política para anon: o visitante só entra pela função do item 4.
drop policy if exists "privacidade_equipe_le" on public.privacy_requests;
create policy "privacidade_equipe_le" on public.privacy_requests
  for select to authenticated
  using (public.pode_privacidade());

-- A tela pode ajustar responsável e campos de atendimento; a situação
-- passa pela função, que escreve o histórico junto.
drop policy if exists "privacidade_equipe_atualiza" on public.privacy_requests;
create policy "privacidade_equipe_atualiza" on public.privacy_requests
  for update to authenticated
  using (public.pode_privacidade()) with check (public.pode_privacidade());

drop policy if exists "privacidade_eventos_le" on public.privacy_request_events;
create policy "privacidade_eventos_le" on public.privacy_request_events
  for select to authenticated
  using (public.pode_privacidade());

drop policy if exists "privacidade_eventos_escreve" on public.privacy_request_events;
create policy "privacidade_eventos_escreve" on public.privacy_request_events
  for insert to authenticated
  with check (public.pode_privacidade() and author_id = auth.uid());

-- Ninguém apaga pedido nem histórico pela aplicação: o registro do
-- atendimento é justamente o que demonstra o cumprimento da lei.
