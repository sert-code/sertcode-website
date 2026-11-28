-- ════════════════════════════════════════════════════════════════
-- Remove os registros de TESTE criados na validação do formulário
-- de Contato sobre Privacidade em 28/11/2026.
--
-- Rodar uma vez no SQL Editor e depois pode apagar este arquivo.
--
-- São 8 pedidos de teste, todos com o nome "TESTE TECNICO - apagar" e
-- e-mails no domínio .invalid, que por definição não existe (RFC 2606) —
-- nenhum deles é pedido de titular de verdade.
--
-- O histórico sai junto, por cascade. Os avisos da equipe não têm
-- chave estrangeira para o pedido, então saem na segunda instrução.
-- ════════════════════════════════════════════════════════════════

-- Confira antes de apagar: devem aparecer 8 linhas, todas de teste.
select protocol, name, email, type, created_at
  from public.privacy_requests
 where email like '%@exemplo.invalid'
 order by created_at;

-- Avisos da equipe que apontam para esses pedidos.
delete from public.notificacoes
 where tipo = 'PRIVACIDADE'
   and referencia in (
     select id from public.privacy_requests where email like '%@exemplo.invalid'
   );

-- Os pedidos e, por cascade, o histórico de cada um.
delete from public.privacy_requests
 where email like '%@exemplo.invalid';

-- Deve voltar zero.
select count(*) as sobraram
  from public.privacy_requests
 where email like '%@exemplo.invalid';
