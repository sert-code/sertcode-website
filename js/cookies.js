/* ════════════════════════════════════════════════════════════════
   Aviso e preferências de cookies — SertCode (LGPD)

   Script comum, sem módulo, para poder entrar em qualquer página do
   site e dos painéis com uma linha só.

   Duas regras que a LGPD impõe e que estão no código, não só no texto:

   1. Recusar tem o mesmo peso de aceitar. Os três botões — Aceitar,
      Recusar e Personalizar — têm o mesmo tamanho e ficam lado a lado.
      Não existe "X" que feche o aviso sem decidir: fechar sem escolher
      seria consentimento presumido, que a lei não aceita.

   2. Nada opcional roda antes da escolha. Hoje o site só usa o que é
      necessário e o tema claro/escuro (funcionalidade). As categorias de
      análise e publicidade existem para a escolha já ficar registrada:
      se um dia entrar uma ferramenta dessas, ela só é carregada para
      quem consentiu, consultando SertCodeCookies.permite('analise').
   ════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var CHAVE = 'sertcode_cookie_consent';
  var EVENTO = 'sertcode:cookie-consent';
  /* Mudou o texto ou as categorias? Suba a versão e o aviso volta a
     aparecer: um consentimento dado para outra lista não vale para esta. */
  var VERSAO = 1;

  var CATEGORIAS = [
    {
      id: 'necessarios',
      titulo: 'Cookies necessários',
      descricao: 'Essenciais para o funcionamento e a segurança do site: mantêm sua sessão no Portal do Cliente e no painel da equipe. Não podem ser desativados.',
      emUso: true
    },
    {
      id: 'analise',
      titulo: 'Cookies de desempenho e análise',
      descricao: 'Ajudam a entender como os visitantes utilizam o site.',
      emUso: false
    },
    {
      id: 'funcionalidade',
      titulo: 'Cookies de funcionalidade',
      descricao: 'Permitem lembrar preferências e melhorar sua experiência, como o tema claro ou escuro.',
      emUso: true
    },
    {
      id: 'publicidade',
      titulo: 'Cookies de publicidade',
      descricao: 'Utilizados para oferecer anúncios personalizados, quando aplicável.',
      emUso: false
    }
  ];

  var OPCIONAIS = ['analise', 'funcionalidade', 'publicidade'];
  /* Chaves do navegador que pertencem à categoria de funcionalidade. */
  var CHAVES_DE_FUNCIONALIDADE = ['sertcode_theme'];

  /* A página pode estar numa subpasta (instagram/, por exemplo). */
  var RAIZ = (function () {
    var partes = window.location.pathname.split('/').filter(Boolean);
    var profundidade = Math.max(partes.length - 1, 0);
    return profundidade ? new Array(profundidade + 1).join('../') : '';
  })();

  function tudo(v) {
    return { analise: v, funcionalidade: v, publicidade: v };
  }

  function ler() {
    try {
      var bruto = window.localStorage.getItem(CHAVE);
      if (!bruto) return null;
      var p = JSON.parse(bruto);
      if (!p || p.v !== VERSAO) return null;
      return {
        v: VERSAO,
        necessarios: true,
        analise: p.analise === true,
        funcionalidade: p.funcionalidade === true,
        publicidade: p.publicidade === true,
        em: typeof p.em === 'string' ? p.em : new Date().toISOString()
      };
    } catch (e) {
      /* Navegador sem armazenamento: trata como "ainda não decidiu". */
      return null;
    }
  }

  /* Respeita a recusa: sem consentimento de funcionalidade, o que estava
     guardado é apagado e não passa para a próxima visita. */
  function aplicar(prefs) {
    if (!prefs || prefs.funcionalidade) return;
    try {
      for (var i = 0; i < CHAVES_DE_FUNCIONALIDADE.length; i++) {
        window.localStorage.removeItem(CHAVES_DE_FUNCIONALIDADE[i]);
      }
    } catch (e) { /* sem armazenamento, nada a apagar */ }
  }

  function salvar(escolha) {
    var prefs = {
      v: VERSAO,
      necessarios: true,
      analise: escolha.analise === true,
      funcionalidade: escolha.funcionalidade === true,
      publicidade: escolha.publicidade === true,
      em: new Date().toISOString()
    };
    try {
      window.localStorage.setItem(CHAVE, JSON.stringify(prefs));
    } catch (e) { /* a escolha vale só nesta visita */ }
    aplicar(prefs);
    window.dispatchEvent(new CustomEvent(EVENTO, { detail: prefs }));
    return prefs;
  }

  // ── interface ────────────────────────────────────────────────────
  var elBanner = null, elPainel = null, escolhaAtual = tudo(false), focoAnterior = null;

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function montarBanner() {
    var el = document.createElement('div');
    el.className = 'ck-banner';
    el.setAttribute('role', 'region');
    el.setAttribute('aria-label', 'Aviso de cookies');
    el.innerHTML =
      '<div class="ck-banner-texto">' +
        '<svg class="ck-icone" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true">' +
          '<path d="M12 2a10 10 0 1 0 10 10 4 4 0 0 1-5-5 4 4 0 0 1-5-5z"/>' +
          '<circle cx="9" cy="10" r="1" fill="currentColor" stroke="none"/>' +
          '<circle cx="14.5" cy="14.5" r="1" fill="currentColor" stroke="none"/>' +
          '<circle cx="8.5" cy="15.5" r="1" fill="currentColor" stroke="none"/>' +
        '</svg>' +
        '<div>' +
          '<p class="ck-titulo">Sua privacidade é importante para nós.</p>' +
          '<p class="ck-desc">Utilizamos cookies para garantir o funcionamento do site, melhorar sua experiência e, com sua autorização, analisar a navegação e personalizar conteúdos. Saiba mais na <a href="' + RAIZ + 'cookies.html">Política de Cookies</a>.</p>' +
        '</div>' +
      '</div>' +
      '<div class="ck-acoes">' +
        '<button type="button" class="ck-btn" data-ck="recusar">Recusar</button>' +
        '<button type="button" class="ck-btn" data-ck="personalizar">Personalizar</button>' +
        '<button type="button" class="ck-btn ck-btn-forte" data-ck="aceitar">Aceitar</button>' +
      '</div>';
    el.querySelector('[data-ck="recusar"]').addEventListener('click', function () { decidir(tudo(false)); });
    el.querySelector('[data-ck="aceitar"]').addEventListener('click', function () { decidir(tudo(true)); });
    el.querySelector('[data-ck="personalizar"]').addEventListener('click', function () { abrirPainel(); });
    return el;
  }

  function montarPainel() {
    var el = document.createElement('div');
    el.className = 'ck-overlay';
    el.innerHTML =
      '<div class="ck-painel" role="dialog" aria-modal="true" aria-labelledby="ck-painel-titulo">' +
        '<div class="ck-painel-topo">' +
          '<h2 id="ck-painel-titulo">Preferências de cookies</h2>' +
          '<button type="button" class="ck-fechar" data-ck="fechar" aria-label="Fechar">' +
            '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>' +
          '</button>' +
        '</div>' +
        '<p class="ck-painel-intro">Você pode escolher quais categorias de cookies deseja permitir. Os cookies necessários são utilizados para garantir o funcionamento e a segurança do site.</p>' +
        '<ul class="ck-lista">' +
          CATEGORIAS.map(function (c) {
            var fixo = c.id === 'necessarios';
            return '<li class="ck-item">' +
              '<div class="ck-item-texto">' +
                '<p class="ck-item-titulo">' + esc(c.titulo) + '</p>' +
                '<p class="ck-item-desc">' + esc(c.descricao) + '</p>' +
                (c.emUso ? '' : '<p class="ck-item-nota">A SertCode não usa cookies desta categoria hoje. Sua escolha fica registrada para o futuro.</p>') +
              '</div>' +
              (fixo
                ? '<span class="ck-sempre">Sempre ativos</span>'
                : '<label class="ck-switch"><input type="checkbox" data-ck-cat="' + c.id + '" aria-label="' + esc(c.titulo) + '"><span class="ck-switch-trilho"></span></label>') +
            '</li>';
          }).join('') +
        '</ul>' +
        '<p class="ck-painel-rodape">Você pode alterar suas preferências a qualquer momento em “Preferências de cookies”, no rodapé do site.</p>' +
        '<div class="ck-acoes ck-acoes-painel">' +
          '<button type="button" class="ck-btn" data-ck="recusar-opcionais">Recusar opcionais</button>' +
          '<button type="button" class="ck-btn" data-ck="salvar">Salvar escolhas</button>' +
          '<button type="button" class="ck-btn ck-btn-forte" data-ck="aceitar-todos">Aceitar todos</button>' +
        '</div>' +
      '</div>';

    el.addEventListener('click', function (ev) { if (ev.target === el) fecharPainel(); });
    el.querySelector('[data-ck="fechar"]').addEventListener('click', fecharPainel);
    el.querySelector('[data-ck="recusar-opcionais"]').addEventListener('click', function () { decidir(tudo(false)); });
    el.querySelector('[data-ck="aceitar-todos"]').addEventListener('click', function () { decidir(tudo(true)); });
    el.querySelector('[data-ck="salvar"]').addEventListener('click', function () { decidir(escolhaAtual); });
    el.querySelectorAll('[data-ck-cat]').forEach(function (input) {
      input.addEventListener('change', function () {
        escolhaAtual[input.dataset.ckCat] = input.checked;
      });
    });
    return el;
  }

  function abrirPainel() {
    var p = ler();
    escolhaAtual = p
      ? { analise: p.analise, funcionalidade: p.funcionalidade, publicidade: p.publicidade }
      : tudo(false);
    if (!elPainel) {
      elPainel = montarPainel();
      document.body.appendChild(elPainel);
    }
    elPainel.querySelectorAll('[data-ck-cat]').forEach(function (input) {
      input.checked = escolhaAtual[input.dataset.ckCat] === true;
    });
    focoAnterior = document.activeElement;
    elPainel.classList.add('ck-aberto');
    document.body.classList.add('ck-travado');
    if (elBanner) elBanner.classList.add('ck-oculto');
    var primeiro = elPainel.querySelector('[data-ck="fechar"]');
    if (primeiro) primeiro.focus();
    document.addEventListener('keydown', aoTeclar);
  }

  function fecharPainel() {
    if (!elPainel) return;
    elPainel.classList.remove('ck-aberto');
    document.body.classList.remove('ck-travado');
    document.removeEventListener('keydown', aoTeclar);
    /* Fechar sem decidir devolve o aviso: o site não pode seguir sem escolha. */
    if (elBanner && !ler()) elBanner.classList.remove('ck-oculto');
    if (focoAnterior && focoAnterior.focus) focoAnterior.focus();
  }

  function aoTeclar(ev) {
    if (ev.key === 'Escape') fecharPainel();
  }

  function decidir(escolha) {
    salvar(escolha);
    if (elBanner) { elBanner.remove(); elBanner = null; }
    if (elPainel) {
      elPainel.classList.remove('ck-aberto');
      document.body.classList.remove('ck-travado');
      document.removeEventListener('keydown', aoTeclar);
    }
  }

  function iniciar() {
    var atual = ler();
    aplicar(atual);
    if (!atual) {
      elBanner = montarBanner();
      document.body.appendChild(elBanner);
    }
    /* Qualquer botão com data-cookies="preferencias" abre o painel:
       é assim que o link do rodapé e o da Política de Cookies funcionam. */
    document.addEventListener('click', function (ev) {
      var alvo = ev.target.closest ? ev.target.closest('[data-cookies="preferencias"]') : null;
      if (!alvo) return;
      ev.preventDefault();
      abrirPainel();
    });
  }

  window.SertCodeCookies = {
    abrir: abrirPainel,
    ler: ler,
    /** Use antes de carregar qualquer script de análise ou publicidade. */
    permite: function (categoria) {
      var p = ler();
      return !!(p && p[categoria] === true);
    },
    EVENTO: EVENTO,
    CATEGORIAS: CATEGORIAS,
    OPCIONAIS: OPCIONAIS
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();
