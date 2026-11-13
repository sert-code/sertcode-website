-- ════════════════════════════════════════════════════════════════
-- Clientes: ficha completa, busca, encerramento e senha temporária
-- Rodar no Supabase DEPOIS de financeiro-gestao.sql.
-- Pode ser executado de novo sem efeito colateral.
-- ════════════════════════════════════════════════════════════════

-- 1. Campos da ficha ─────────────────────────────────────────────
alter table public.profiles
  add column if not exists cliente_desde date,
  add column if not exists descricao     text,
  add column if not exists encerrada_em  timestamptz,
  add column if not exists encerrada_por text,
  add column if not exists encerrada_motivo text;

update public.profiles
set cliente_desde = coalesce(cliente_desde, created_at::date)
where role = 'client' and cliente_desde is null;

-- Conta encerrada é situação à parte de inativo: inativo volta, encerrada
-- é o fim do relacionamento.
alter table public.profiles drop constraint if exists profiles_status_check;
alter table public.profiles
  add constraint profiles_status_check
  check (status in ('pendente', 'ativo', 'recusado', 'inativo', 'encerrada'));

-- 2. Senha temporária ────────────────────────────────────────────
-- O painel é uma página estática: não existe servidor onde guardar a
-- chave de serviço do Supabase, e colocá-la no JavaScript entregaria o
-- banco inteiro a quem abrisse o site. A troca acontece aqui dentro,
-- numa função que só roda para quem o banco reconhece como gestor.
create extension if not exists pgcrypto with schema extensions;

create or replace function public.gestor_redefine_senha(p_user uuid, p_senha text)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  alvo record;
begin
  if not public.is_gestor() then
    raise exception 'Somente um gestor pode redefinir senhas.';
  end if;
  if p_senha is null or length(p_senha) < 8 then
    raise exception 'A senha precisa ter pelo menos 8 caracteres.';
  end if;

  select id, role into alvo from public.profiles where id = p_user;
  if not found then
    raise exception 'Conta não encontrada.';
  end if;
  -- Trocar a senha do próprio gestor por aqui o deixaria de fora na hora
  -- seguinte, sem ter recebido a senha nova por nenhum canal.
  if p_user = auth.uid() then
    raise exception 'Para trocar a sua própria senha, use "Esqueci minha senha" na tela de acesso.';
  end if;

  update auth.users
  set encrypted_password = extensions.crypt(p_senha, extensions.gen_salt('bf')),
      updated_at = now()
  where id = p_user;

  -- Senha trocada com sessão aberta deixaria a antiga valendo até o
  -- refresh token expirar; derrubar as sessões fecha essa brecha.
  delete from auth.sessions where user_id = p_user;

  update public.profiles
  set senha_provisoria = true
  where id = p_user;
end $$;

revoke all on function public.gestor_redefine_senha(uuid, text) from public, anon;
grant execute on function public.gestor_redefine_senha(uuid, text) to authenticated;

-- 3. Encerrar a conta do cliente ─────────────────────────────────
-- Encerrar não apaga: desliga o acesso e marca a data. Os projetos, as
-- cobranças e os chamados continuam, porque são o histórico da SertCode
-- e podem ser necessários depois.
create or replace function public.gestor_encerra_cliente(p_user uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_gestor() then
    raise exception 'Somente um gestor pode encerrar uma conta.';
  end if;

  update public.profiles set
    status = 'encerrada',
    encerrada_em = now(),
    encerrada_por = (select coalesce(nickname, name) from public.profiles where id = auth.uid()),
    encerrada_motivo = p_motivo
  where id = p_user and role = 'client';

  delete from auth.sessions where user_id = p_user;
end $$;

revoke all on function public.gestor_encerra_cliente(uuid, text) from public, anon;
grant execute on function public.gestor_encerra_cliente(uuid, text) to authenticated;

create or replace function public.gestor_reabre_cliente(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_gestor() then
    raise exception 'Somente um gestor pode reabrir uma conta.';
  end if;
  update public.profiles
  set status = 'ativo', encerrada_em = null, encerrada_por = null, encerrada_motivo = null
  where id = p_user and role = 'client';
end $$;

revoke all on function public.gestor_reabre_cliente(uuid) from public, anon;
grant execute on function public.gestor_reabre_cliente(uuid) to authenticated;

-- 4. O portal barra conta encerrada ──────────────────────────────
-- Sem isto a pessoa continuaria entrando até a sessão expirar.
drop policy if exists "perfil_proprio_ou_equipe_le" on public.profiles;
create policy "perfil_proprio_ou_equipe_le" on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_equipe());
