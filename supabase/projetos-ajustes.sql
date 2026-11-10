-- ════════════════════════════════════════════════════════════════
-- Projetos: anexos por etapa
-- Rodar no Supabase DEPOIS de projetos-gestao.sql.
-- Pode ser executado de novo sem efeito colateral.
--
-- A especificação pede "Arquivos: anexos, documentos e imagens" dentro
-- da janela de edição da etapa. Em vez de criar outra tabela, o arquivo
-- continua em projeto_documentos e passa a saber a que etapa pertence:
-- assim ele aparece nos dois lugares sem duplicar nada.
-- ════════════════════════════════════════════════════════════════

alter table public.projeto_documentos
  add column if not exists etapa_id uuid references public.projeto_etapas(id) on delete set null;

create index if not exists projeto_documentos_etapa_idx
  on public.projeto_documentos (etapa_id);
