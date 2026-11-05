-- ════════════════════════════════════════════════════════════════
-- Correção: situação dos projetos
-- Rodar no Supabase: SQL Editor → New query → colar → Run.
-- Pode ser executado de novo sem efeito colateral.
--
-- O banco já tinha uma regra chamada `projects_status_check`, do
-- vocabulário antigo (analysis, dev, testing, done). O arquivo
-- `projetos.sql` só criava a regra nova quando não existisse nenhuma
-- com esse nome — então a antiga permaneceu, e cadastrar projeto
-- falhava com "violates check constraint projects_status_check".
--
-- Aqui a regra é trocada de verdade, e os registros antigos são
-- convertidos para o vocabulário novo antes da troca.
-- ════════════════════════════════════════════════════════════════

alter table public.projects drop constraint if exists projects_status_check;

-- Converte o que ficou do vocabulário antigo.
update public.projects set status = case status
  when 'analysis' then 'cadastrado'
  when 'dev'      then 'andamento'
  when 'testing'  then 'andamento'
  when 'done'     then 'concluido'
  else status
end
where status in ('analysis', 'dev', 'testing', 'done');

-- Sem situação definida, o projeto nasce como cadastrado.
update public.projects set status = 'cadastrado'
where status is null or status not in ('cadastrado','andamento','pausado','cancelado','concluido');

alter table public.projects
  add constraint projects_status_check
  check (status in ('cadastrado','andamento','pausado','cancelado','concluido'));
