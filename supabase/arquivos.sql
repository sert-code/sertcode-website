-- ════════════════════════════════════════════════════════════════
-- Arquivos dos projetos
-- Rodar no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
--
-- O painel e o Portal do Cliente já enviavam e baixavam arquivos de
-- `project-files`, mas o bucket nunca existiu: o envio falhava com
-- "Bucket not found". Este arquivo cria o bucket e as permissões.
-- ════════════════════════════════════════════════════════════════

-- Privado: contrato, proposta e arquivo de projeto não podem ficar
-- abertos por link direto. O painel gera um link temporário para baixar.
insert into storage.buckets (id, name, public)
values ('project-files', 'project-files', false)
on conflict (id) do nothing;

-- A equipe cuida dos arquivos de todos os clientes ───────────────
drop policy if exists "equipe_le_arquivos_projeto"    on storage.objects;
drop policy if exists "equipe_envia_arquivos_projeto" on storage.objects;
drop policy if exists "equipe_apaga_arquivos_projeto" on storage.objects;

create policy "equipe_le_arquivos_projeto" on storage.objects
  for select to authenticated
  using (bucket_id = 'project-files' and public.is_equipe());

create policy "equipe_envia_arquivos_projeto" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'project-files' and public.is_equipe());

create policy "equipe_apaga_arquivos_projeto" on storage.objects
  for delete to authenticated
  using (bucket_id = 'project-files' and public.is_equipe());

-- O cliente baixa apenas os próprios arquivos ────────────────────
-- O caminho começa com o id do cliente, como o painel grava ao enviar.
drop policy if exists "cliente_le_proprios_arquivos" on storage.objects;
create policy "cliente_le_proprios_arquivos" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'project-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
