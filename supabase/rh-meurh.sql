-- ════════════════════════════════════════════════════════════════
-- Meu RH — o colaborador vê os próprios dados
-- Rodar DEPOIS do rh.sql e do rh-complemento.sql.
-- Pode ser executado de novo sem efeito colateral.
--
-- Até aqui o RH era fechado ao gestor. Estas regras abrem uma fresta
-- para cada pessoa: a própria ficha e os próprios demonstrativos, e
-- nada além disso.
-- ════════════════════════════════════════════════════════════════

-- 1. A própria ficha ─────────────────────────────────────────────
drop policy if exists "colaborador_le_propria_ficha" on public.rh_colaboradores;
create policy "colaborador_le_propria_ficha" on public.rh_colaboradores
  for select to authenticated
  using (profile_id = auth.uid());

-- 2. Os próprios demonstrativos ──────────────────────────────────
-- Só de folha aprovada ou paga: rascunho ainda muda, e holerite que
-- muda depois de visto gera mais dúvida do que informação.
drop policy if exists "colaborador_le_proprio_holerite" on public.rh_folha_itens;
create policy "colaborador_le_proprio_holerite" on public.rh_folha_itens
  for select to authenticated
  using (exists (
    select 1
    from public.rh_colaboradores c
    join public.rh_folhas f on f.id = rh_folha_itens.folha_id
    where c.id = rh_folha_itens.colaborador_id
      and c.profile_id = auth.uid()
      and f.status in ('APROVADA', 'PAGA')
  ));

-- 3. A competência da folha, para nomear o demonstrativo ─────────
drop policy if exists "colaborador_le_folha_do_holerite" on public.rh_folhas;
create policy "colaborador_le_folha_do_holerite" on public.rh_folhas
  for select to authenticated
  using (
    status in ('APROVADA', 'PAGA')
    and exists (
      select 1
      from public.rh_folha_itens i
      join public.rh_colaboradores c on c.id = i.colaborador_id
      where i.folha_id = rh_folhas.id and c.profile_id = auth.uid()
    )
  );

-- 4. O cargo que aparece na ficha ────────────────────────────────
drop policy if exists "equipe_le_cargos" on public.rh_cargos;
create policy "equipe_le_cargos" on public.rh_cargos
  for select to authenticated
  using (public.is_equipe());
