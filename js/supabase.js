import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

export const SUPABASE_URL = 'https://ljylkqyksgzbwxfvrcaf.supabase.co'
export const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxqeWxrcXlrc2d6Ynd4ZnZyY2FmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2NTY1NTksImV4cCI6MjA5NTIzMjU1OX0.6Lr3FKKF1apqH3wguTPTfd7b024zqhQYAi4vn6NhoMw'

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

/**
 * Cliente isolado para criar contas sem trocar a sessão de quem está logado.
 * Sem `persistSession`, a sessão do cadastro fica só na memória e não
 * substitui a do gestor no navegador.
 */
export function createSignupClient() {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}
