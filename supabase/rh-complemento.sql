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
