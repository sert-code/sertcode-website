// Sino de notificações do painel e do portal.
//
// O aviso é criado por gatilho no banco (supabase/notificacoes.sql), não
// pela tela: um chamado aberto de madrugada continua lá quando alguém
// entrar, sem depender de quem estava com a página aberta.

const ICONES = {
  CHAMADO:    '<path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/>',
  FATURA:     '<path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/>',
  PROJETO:    '<path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z"/>',
  DEPOIMENTO: '<polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>',
  FEEDBACK:   '<path d="M21 11.5a8.38 8.38 0 01-.9 3.8 8.5 8.5 0 01-7.6 4.7 8.38 8.38 0 01-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 01-.9-3.8 8.5 8.5 0 014.7-7.6 8.38 8.38 0 013.8-.9h.5a8.48 8.48 0 018 8v.5z"/>',
  RH:         '<path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/>',
};

const escapar = t => String(t ?? '').replace(/[&<>"']/g,
  c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function quando(data) {
  const minutos = Math.floor((Date.now() - new Date(data)) / 60000);
  if (minutos < 1)    return 'agora';
  if (minutos < 60)   return `há ${minutos} min`;
  if (minutos < 1440) return `há ${Math.floor(minutos / 60)} h`;
  if (minutos < 2880) return 'ontem';
  return new Date(data).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' });
}

/**
 * Liga o sino do cabeçalho.
 * @param {object} supabase   cliente já autenticado
 * @param {string} profileId  id de quem está vendo
 * @param {string[]} destinos quais avisos esta tela mostra
 * @param {(aba:string, referencia:string)=>void} abrir  o que fazer ao clicar
 */
export async function ligarNotificacoes({ supabase, profileId, destinos, abrir }) {
  const botao = document.querySelector('.notif-btn');
  if (!botao) return { recarregar: () => {} };

  const painel = document.createElement('div');
  painel.className = 'notif-painel';
  painel.hidden = true;
  painel.innerHTML = `
    <div class="notif-topo">
      <strong>Notificações</strong>
      <button class="notif-limpar" type="button">Marcar todas como lidas</button>
    </div>
    <div class="notif-lista"></div>`;
  botao.appendChild(painel);

  const lista = painel.querySelector('.notif-lista');
  const ponto = botao.querySelector('.notif-dot');
  let avisos = [], lidas = new Set();

  async function carregar() {
    const [n, l] = await Promise.all([
      supabase.from('notificacoes').select('*')
        .in('destino', destinos).order('created_at', { ascending: false }).limit(50),
      supabase.from('notificacoes_lidas').select('notificacao_id').eq('profile_id', profileId),
    ]);
    avisos = n.data || [];
    lidas = new Set((l.data || []).map(x => x.notificacao_id));
    desenhar();
  }

  function desenhar() {
    const naoLidas = avisos.filter(a => !lidas.has(a.id)).length;
    if (ponto) ponto.style.display = naoLidas ? '' : 'none';
    botao.dataset.contagem = naoLidas > 9 ? '9+' : (naoLidas || '');
    botao.classList.toggle('tem-aviso', Boolean(naoLidas));

    lista.innerHTML = avisos.length ? avisos.map(a => `
      <button class="notif-item${lidas.has(a.id) ? '' : ' nao-lida'}" data-id="${a.id}" type="button">
        <span class="notif-icone">
          <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" viewBox="0 0 24 24">
            ${ICONES[a.tipo] || ICONES.CHAMADO}</svg>
        </span>
        <span class="notif-texto">
          <span class="notif-titulo">${escapar(a.titulo)}</span>
          ${a.descricao ? `<span class="notif-desc">${escapar(a.descricao)}</span>` : ''}
          <span class="notif-quando">${quando(a.created_at)}</span>
        </span>
      </button>`).join('')
      : '<div class="notif-vazio">Nada por aqui ainda.</div>';
  }

  async function marcarLidas(ids) {
    const novas = ids.filter(id => !lidas.has(id));
    if (!novas.length) return;
    novas.forEach(id => lidas.add(id));
    desenhar();
    await supabase.from('notificacoes_lidas')
      .upsert(novas.map(id => ({ notificacao_id: id, profile_id: profileId })),
              { onConflict: 'notificacao_id,profile_id' });
  }

  botao.addEventListener('click', e => {
    if (e.target.closest('.notif-painel')) return;
    painel.hidden = !painel.hidden;
    if (!painel.hidden) carregar();
  });

  painel.querySelector('.notif-limpar').addEventListener('click', () =>
    marcarLidas(avisos.map(a => a.id)));

  lista.addEventListener('click', async e => {
    const item = e.target.closest('.notif-item');
    if (!item) return;
    const aviso = avisos.find(a => a.id === item.dataset.id);
    await marcarLidas([item.dataset.id]);
    painel.hidden = true;
    if (aviso && abrir) abrir(aviso.aba, aviso.referencia);
  });

  // Clicar fora fecha, como qualquer menu suspenso.
  document.addEventListener('click', e => {
    if (!botao.contains(e.target)) painel.hidden = true;
  });

  await carregar();
  // Recarrega de minuto em minuto para quem deixa o painel aberto o dia todo.
  setInterval(carregar, 60000);
  return { recarregar: carregar };
}
