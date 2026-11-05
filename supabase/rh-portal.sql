-- ════════════════════════════════════════════════════════════════
-- Meu RH — portal do colaborador
-- Rodar DEPOIS do rh-tudo.sql, no SQL Editor do Supabase.
-- Pode ser executado de novo sem efeito colateral.
--
-- A Gestão de Pessoas administra; o Meu RH consulta. Cada pessoa
-- enxerga apenas a própria linha, nunca a de outro colaborador, e
-- alteração de cargo, salário ou vínculo continua sendo da Gestão.
-- ════════════════════════════════════════════════════════════════

-- 1. Solicitações ────────────────────────────────────────────────
-- O pedido que o colaborador abre: mudança de endereço, férias,
-- inclusão de dependente, declaração, revisão de desconto.
create table if not exists public.rh_solicitacoes (
  id             uuid primary key default gen_random_uuid(),
  colaborador_id uuid not null references public.rh_colaboradores(id) on delete cascade,
  tipo           text not null,   -- CADASTRO | FERIAS | AFASTAMENTO | BENEFICIO | DEPENDENTE | DOCUMENTO | FINANCEIRO
  assunto        text not null,
  descricao      text,
  anexo          text,            -- objeto no bucket rh-documentos
  -- ABERTA | EM_ANALISE | AGUARDANDO_COLABORADOR | APROVADA | RECUSADA | CONCLUIDA
  status         text not null default 'ABERTA',
  responsavel    text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists rh_solicitacoes_colab_idx
  on public.rh_solicitacoes (colaborador_id, created_at desc);
create index if not exists rh_solicitacoes_status_idx
  on public.rh_solicitacoes (status);

-- Conversa da solicitação: o que a Gestão responde e o que o
-- colaborador complementa ficam na mesma linha do tempo.
create table if not exists public.rh_solicitacao_mensagens (
  id             uuid primary key default gen_random_uuid(),
  solicitacao_id uuid not null references public.rh_solicitacoes(id) on delete cascade,
  autor_nome     text,
  autor_tipo     text not null default 'GESTAO',   -- GESTAO | COLABORADOR
  mensagem       text not null,
  created_at     timestamptz not null default now()
);

create index if not exists rh_solicitacao_mensagens_idx
  on public.rh_solicitacao_mensagens (solicitacao_id, created_at);

-- 2. Quem é o colaborador logado ─────────────────────────────────
-- Usada pelas regras abaixo; evita repetir a subconsulta em cada uma.
create or replace function public.meu_colaborador_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.rh_colaboradores where profile_id = auth.uid() limit 1;
$$;

-- 3. Acesso às solicitações ──────────────────────────────────────
alter table public.rh_solicitacoes enable row level security;
alter table public.rh_solicitacao_mensagens enable row level security;

drop policy if exists "gestor_gerencia_solicitacoes" on public.rh_solicitacoes;
create policy "gestor_gerencia_solicitacoes" on public.rh_solicitacoes
  for all to authenticated
  using (public.is_gestor()) with check (public.is_gestor());

drop policy if exists "colaborador_le_proprias_solicitacoes" on public.rh_solicitacoes;
create policy "colaborador_le_proprias_solicitacoes" on public.rh_solicitacoes
  for select to authenticated
  using (colaborador_id = public.meu_colaborador_id());

-- Abrir é do colaborador; mudar status é da Gestão, por isso só INSERT.
drop policy if exists "colaborador_abre_solicitacao" on public.rh_solicitacoes;
create policy "colaborador_abre_solicitacao" on public.rh_solicitacoes
  for insert to authenticated
  with check (colaborador_id = public.meu_colaborador_id() and status = 'ABERTA');

drop policy if exists "gestor_gerencia_mensagens" on public.rh_solicitacao_mensagens;
create policy "gestor_gerencia_mensagens" on public.rh_solicitacao_mensagens
  for all to authenticated
  using (public.is_gestor()) with check (public.is_gestor());

drop policy if exists "colaborador_le_mensagens" on public.rh_solicitacao_mensagens;
create policy "colaborador_le_mensagens" on public.rh_solicitacao_mensagens
  for select to authenticated
  using (exists (
    select 1 from public.rh_solicitacoes s
    where s.id = rh_solicitacao_mensagens.solicitacao_id
      and s.colaborador_id = public.meu_colaborador_id()
  ));

drop policy if exists "colaborador_responde_solicitacao" on public.rh_solicitacao_mensagens;
create policy "colaborador_responde_solicitacao" on public.rh_solicitacao_mensagens
  for insert to authenticated
  with check (
    autor_tipo = 'COLABORADOR'
    and exists (
      select 1 from public.rh_solicitacoes s
      where s.id = rh_solicitacao_mensagens.solicitacao_id
        and s.colaborador_id = public.meu_colaborador_id()
    )
  );

-- 4. Os próprios dados, em leitura ───────────────────────────────
-- Documentos, dependentes, benefícios, afastamentos, histórico
-- salarial e registro de alterações: tudo apenas da própria pessoa.
drop policy if exists "colaborador_le_proprios_documentos" on public.rh_documentos;
create policy "colaborador_le_proprios_documentos" on public.rh_documentos
  for select to authenticated
  using (colaborador_id = public.meu_colaborador_id());

drop policy if exists "colaborador_le_proprios_dependentes" on public.rh_dependentes;
create policy "colaborador_le_proprios_dependentes" on public.rh_dependentes
  for select to authenticated
  using (colaborador_id = public.meu_colaborador_id());

drop policy if exists "colaborador_le_proprios_beneficios" on public.rh_colaborador_beneficios;
create policy "colaborador_le_proprios_beneficios" on public.rh_colaborador_beneficios
  for select to authenticated
  using (colaborador_id = public.meu_colaborador_id());

drop policy if exists "colaborador_le_catalogo_beneficios" on public.rh_beneficios;
create policy "colaborador_le_catalogo_beneficios" on public.rh_beneficios
  for select to authenticated
  using (public.is_equipe());

drop policy if exists "colaborador_le_proprios_afastamentos" on public.rh_afastamentos;
create policy "colaborador_le_proprios_afastamentos" on public.rh_afastamentos
  for select to authenticated
  using (colaborador_id = public.meu_colaborador_id());

drop policy if exists "colaborador_le_proprio_salario" on public.rh_salarios;
create policy "colaborador_le_proprio_salario" on public.rh_salarios
  for select to authenticated
  using (colaborador_id = public.meu_colaborador_id());

drop policy if exists "colaborador_le_proprio_historico" on public.rh_auditoria;
create policy "colaborador_le_proprio_historico" on public.rh_auditoria
  for select to authenticated
  using (colaborador_id = public.meu_colaborador_id());

-- 5. Anexo da solicitação ────────────────────────────────────────
-- Fica em rh-documentos, numa pasta por colaborador. O gestor já lê
-- o bucket inteiro; aqui o colaborador envia e lê só a própria pasta.
drop policy if exists "colaborador_envia_anexo_rh" on storage.objects;
create policy "colaborador_envia_anexo_rh" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'rh-documentos'
    and (storage.foldername(name))[1] = 'solicitacoes'
    and (storage.foldername(name))[2] = public.meu_colaborador_id()::text
  );

drop policy if exists "colaborador_le_proprios_arquivos_rh" on storage.objects;
create policy "colaborador_le_proprios_arquivos_rh" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'rh-documentos'
    and (
      (storage.foldername(name))[1] = public.meu_colaborador_id()::text
      or ((storage.foldername(name))[1] = 'solicitacoes'
          and (storage.foldername(name))[2] = public.meu_colaborador_id()::text)
    )
  );
