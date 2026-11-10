// Categorias, serviços e modelos de etapas dos projetos da SertCode.
//
// O fluxo principal (as sete fases) é o mesmo para todo projeto, porque é
// o que o cliente acompanha e o que a SertCode apresenta no site. O que
// muda por serviço são as ATIVIDADES dentro de cada fase: uma manutenção
// pontual não passa por prototipação, e uma landing page não tem
// modelagem de banco. Por isso cada etapa do modelo carrega a fase a que
// pertence — a equipe trabalha na atividade, o cliente lê a fase.

export const FASES = {
  DIAGNOSTICO:    { ordem: 1, nome: 'Diagnóstico',            descricao: 'Entendimento da empresa, levantamento das necessidades e definição dos objetivos.' },
  PLANEJAMENTO:   { ordem: 2, nome: 'Planejamento',           descricao: 'Definição de escopo, funcionalidades, tecnologias, cronograma e arquitetura.' },
  DESIGN:         { ordem: 3, nome: 'Design e prototipação',  descricao: 'Interfaces, estrutura visual, experiência do usuário e aprovação das telas.' },
  DESENVOLVIMENTO:{ ordem: 4, nome: 'Desenvolvimento',        descricao: 'Programação, implementação das funcionalidades, integrações e configurações.' },
  TESTES:         { ordem: 5, nome: 'Testes e homologação',   descricao: 'Testes funcionais, correções, validação e aprovação do cliente.' },
  ENTREGA:        { ordem: 6, nome: 'Entrega e implantação',  descricao: 'Publicação, configuração do ambiente, treinamento e disponibilização.' },
  SUPORTE:        { ordem: 7, nome: 'Suporte e acompanhamento', descricao: 'Acompanhamento pós-entrega, suporte contratado e evolução contínua.' },
};

// Categoria → serviços que ela oferece. O serviço é quem escolhe o modelo
// de etapas; a categoria só organiza a lista para quem cadastra.
export const CATEGORIAS = {
  WEB: {
    nome: 'Desenvolvimento Web',
    servicos: { LANDING: 'Landing page', SITE: 'Site institucional' },
  },
  SISTEMAS: {
    nome: 'Sistemas',
    servicos: { SISTEMA: 'Sistema web sob medida', CRM: 'CRM', ERP: 'ERP', PORTAL: 'Portal ou plataforma' },
  },
  DASHBOARDS: {
    nome: 'Dashboards',
    servicos: { DASHBOARD: 'Dashboard gerencial e indicadores' },
  },
  PAINEIS: {
    nome: 'Painéis administrativos',
    servicos: { PAINEL: 'Painel interno e administrativo' },
  },
  AUTOMACAO: {
    nome: 'Automação',
    servicos: { AUTOMACAO: 'Automação de processos e fluxos' },
  },
  INTEGRACOES: {
    nome: 'Integrações',
    servicos: { INTEGRACAO: 'Integração entre sistemas, APIs e plataformas' },
  },
  GESTAO: {
    nome: 'Controle e gestão',
    servicos: { GESTAO: 'Sistema de gestão empresarial' },
  },
  ATENDIMENTO: {
    nome: 'Atendimento e vendas',
    servicos: { CHATBOT: 'Chatbot e atendimento', COMERCIAL: 'Solução comercial' },
  },
  SAAS: {
    nome: 'SaaS',
    servicos: { SAAS: 'Implantação do SertCode One' },
  },
  MANUTENCAO: {
    nome: 'Manutenção',
    servicos: { MANUTENCAO: 'Correções, monitoramento e suporte' },
  },
  EVOLUCAO: {
    nome: 'Evolução e aprimoramento',
    servicos: { EVOLUCAO: 'Novas funcionalidades, melhorias e modernização' },
  },
  CONSULTORIA: {
    nome: 'Consultoria e diagnóstico',
    servicos: { CONSULTORIA: 'Análise de processos e planejamento tecnológico' },
  },
};

export const SERVICOS = Object.fromEntries(
  Object.entries(CATEGORIAS).flatMap(([cat, c]) =>
    Object.entries(c.servicos).map(([s, nome]) => [s, { nome, categoria: cat }])));

const e = (fase, nome, peso = 1) => ({ fase, nome, peso });

// Peso maior onde o trabalho é maior: o progresso geral do projeto é a
// média ponderada das etapas, então desenvolvimento não pode valer o
// mesmo que "registro do atendimento".
const MODELO_LANDING = [
  e('DIAGNOSTICO',     'Levantamento de informações e objetivos'),
  e('PLANEJAMENTO',    'Definição da estrutura da página'),
  e('DESIGN',          'Criação do layout e identidade visual', 2),
  e('DESENVOLVIMENTO', 'Desenvolvimento da página', 3),
  e('DESENVOLVIMENTO', 'Configuração de formulários e integrações'),
  e('DESENVOLVIMENTO', 'Responsividade e otimização'),
  e('TESTES',          'Testes e validação'),
  e('ENTREGA',         'Publicação e entrega'),
];

const MODELO_SITE = [
  e('DIAGNOSTICO',     'Diagnóstico e levantamento de requisitos'),
  e('PLANEJAMENTO',    'Planejamento das páginas e estrutura'),
  e('DESIGN',          'Design e prototipação', 2),
  e('DESENVOLVIMENTO', 'Desenvolvimento do site', 3),
  e('DESENVOLVIMENTO', 'Configuração de domínio e hospedagem'),
  e('DESENVOLVIMENTO', 'SEO e otimização'),
  e('TESTES',          'Testes de navegação e responsividade'),
  e('TESTES',          'Aprovação do cliente'),
  e('ENTREGA',         'Publicação e entrega'),
];

const MODELO_SISTEMA = [
  e('DIAGNOSTICO',     'Diagnóstico empresarial'),
  e('DIAGNOSTICO',     'Levantamento de requisitos', 2),
  e('PLANEJAMENTO',    'Definição dos módulos e funcionalidades', 2),
  e('PLANEJAMENTO',    'Arquitetura e modelagem do banco de dados', 2),
  e('DESIGN',          'Design e prototipação', 2),
  e('DESENVOLVIMENTO', 'Desenvolvimento do backend', 4),
  e('DESENVOLVIMENTO', 'Desenvolvimento do frontend', 4),
  e('DESENVOLVIMENTO', 'Integrações e permissões de acesso', 2),
  e('TESTES',          'Testes funcionais e de segurança', 2),
  e('TESTES',          'Homologação', 2),
  e('ENTREGA',         'Implantação e treinamento', 2),
  e('SUPORTE',         'Entrega e suporte'),
];

const MODELO_DASHBOARD = [
  e('DIAGNOSTICO',     'Levantamento das necessidades'),
  e('DIAGNOSTICO',     'Identificação das fontes de dados'),
  e('PLANEJAMENTO',    'Definição dos indicadores (KPIs)', 2),
  e('PLANEJAMENTO',    'Modelagem e organização dos dados', 2),
  e('DESIGN',          'Criação do layout'),
  e('DESENVOLVIMENTO', 'Desenvolvimento dos painéis', 3),
  e('DESENVOLVIMENTO', 'Configuração de filtros e gráficos'),
  e('TESTES',          'Testes e validação dos dados', 2),
  e('ENTREGA',         'Entrega e treinamento'),
];

const MODELO_AUTOMACAO = [
  e('DIAGNOSTICO',     'Identificação dos processos manuais'),
  e('DIAGNOSTICO',     'Mapeamento do fluxo atual', 2),
  e('PLANEJAMENTO',    'Planejamento da automação', 2),
  e('PLANEJAMENTO',    'Definição das ferramentas e integrações'),
  e('DESENVOLVIMENTO', 'Desenvolvimento dos fluxos automatizados', 3),
  e('DESENVOLVIMENTO', 'Configuração de notificações e regras'),
  e('TESTES',          'Testes de execução', 2),
  e('ENTREGA',         'Implantação'),
  e('SUPORTE',         'Monitoramento inicial'),
];

const MODELO_INTEGRACAO = [
  e('DIAGNOSTICO',     'Identificação das plataformas envolvidas'),
  e('DIAGNOSTICO',     'Análise de APIs e documentação', 2),
  e('PLANEJAMENTO',    'Planejamento da integração', 2),
  e('PLANEJAMENTO',    'Configuração de autenticação e permissões'),
  e('DESENVOLVIMENTO', 'Desenvolvimento da comunicação', 3),
  e('DESENVOLVIMENTO', 'Sincronização e tratamento de dados', 2),
  e('TESTES',          'Testes de integração', 2),
  e('TESTES',          'Validação'),
  e('ENTREGA',         'Implantação e monitoramento'),
];

const MODELO_GESTAO = [
  e('DIAGNOSTICO',     'Diagnóstico operacional'),
  e('DIAGNOSTICO',     'Levantamento dos processos', 2),
  e('PLANEJAMENTO',    'Definição dos módulos', 2),
  e('PLANEJAMENTO',    'Planejamento das funcionalidades', 2),
  e('DESIGN',          'Design e prototipação', 2),
  e('DESENVOLVIMENTO', 'Desenvolvimento', 4),
  e('DESENVOLVIMENTO', 'Configuração dos usuários e permissões'),
  e('TESTES',          'Testes', 2),
  e('TESTES',          'Homologação', 2),
  e('ENTREGA',         'Implantação e treinamento', 2),
];

const MODELO_SAAS = [
  e('DIAGNOSTICO',     'Cadastro e identificação do cliente'),
  e('PLANEJAMENTO',    'Seleção do produto SaaS'),
  e('PLANEJAMENTO',    'Definição do plano contratado'),
  e('DESENVOLVIMENTO', 'Configuração da empresa', 2),
  e('DESENVOLVIMENTO', 'Configuração de usuários e permissões'),
  e('DESENVOLVIMENTO', 'Personalizações contratadas', 2),
  e('DESENVOLVIMENTO', 'Importação de dados, quando aplicável', 2),
  e('TESTES',          'Testes e validação', 2),
  e('ENTREGA',         'Treinamento e orientação', 2),
  e('ENTREGA',         'Liberação do acesso'),
  e('SUPORTE',         'Acompanhamento inicial'),
];

const MODELO_MANUTENCAO = [
  e('DIAGNOSTICO',     'Recebimento da solicitação'),
  e('DIAGNOSTICO',     'Análise e diagnóstico do problema', 2),
  e('DIAGNOSTICO',     'Classificação da demanda'),
  e('PLANEJAMENTO',    'Planejamento da correção'),
  e('DESENVOLVIMENTO', 'Execução do serviço', 3),
  e('TESTES',          'Testes e validação', 2),
  e('TESTES',          'Aprovação e conclusão'),
  e('ENTREGA',         'Registro do atendimento'),
];

const MODELO_EVOLUCAO = [
  e('DIAGNOSTICO',     'Levantamento das melhorias solicitadas'),
  e('DIAGNOSTICO',     'Análise de viabilidade', 2),
  e('PLANEJAMENTO',    'Definição do escopo', 2),
  e('PLANEJAMENTO',    'Planejamento da implementação'),
  e('DESENVOLVIMENTO', 'Desenvolvimento das melhorias', 4),
  e('TESTES',          'Testes', 2),
  e('TESTES',          'Homologação', 2),
  e('ENTREGA',         'Atualização do sistema'),
  e('ENTREGA',         'Registro da versão e entrega'),
];

const MODELO_CONSULTORIA = [
  e('DIAGNOSTICO',     'Entendimento do negócio'),
  e('DIAGNOSTICO',     'Mapeamento dos processos atuais', 2),
  e('DIAGNOSTICO',     'Identificação dos gargalos', 2),
  e('PLANEJAMENTO',    'Análise de ferramentas e alternativas', 2),
  e('PLANEJAMENTO',    'Planejamento tecnológico', 2),
  e('ENTREGA',         'Apresentação do diagnóstico e das recomendações', 2),
];

export const MODELOS = {
  LANDING:    MODELO_LANDING,
  SITE:       MODELO_SITE,
  SISTEMA:    MODELO_SISTEMA,
  CRM:        MODELO_SISTEMA,
  ERP:        MODELO_SISTEMA,
  PORTAL:     MODELO_SISTEMA,
  DASHBOARD:  MODELO_DASHBOARD,
  PAINEL:     MODELO_DASHBOARD,
  AUTOMACAO:  MODELO_AUTOMACAO,
  INTEGRACAO: MODELO_INTEGRACAO,
  GESTAO:     MODELO_GESTAO,
  CHATBOT:    MODELO_GESTAO,
  COMERCIAL:  MODELO_GESTAO,
  SAAS:       MODELO_SAAS,
  MANUTENCAO: MODELO_MANUTENCAO,
  EVOLUCAO:   MODELO_EVOLUCAO,
  CONSULTORIA:MODELO_CONSULTORIA,
};

export const PRIORIDADES = { BAIXA: 'Baixa', NORMAL: 'Normal', ALTA: 'Alta', URGENTE: 'Urgente' };

export const CONTRATACAO = {
  FECHADO:    'Projeto fechado',
  MODULOS:    'Desenvolvimento por módulos',
  HORAS:      'Banco de horas',
  MENSALIDADE:'Mensalidade de manutenção',
  ASSINATURA: 'Assinatura SaaS',
  PONTUAL:    'Serviço pontual',
};

// Situação do PROJETO. Separada da situação das etapas de propósito: um
// projeto pode estar em andamento com etapas concluídas e outras nem
// iniciadas, e misturar as duas escondia exatamente essa informação.
export const PROJETO_STATUS = {
  SOLICITACAO:          { label: 'Solicitação recebida',  cls: 'status-pending',  quando: 'O cliente solicitou o serviço.' },
  DIAGNOSTICO:          { label: 'Em diagnóstico',        cls: 'status-analysis', quando: 'Análise inicial.' },
  AGUARDANDO_APROVACAO: { label: 'Aguardando aprovação',  cls: 'status-analysis', quando: 'Proposta enviada, aguardando aceite.' },
  AGUARDANDO_INICIO:    { label: 'Aguardando início',     cls: 'status-pending',  quando: 'Contratado, mas ainda não iniciado.' },
  ANDAMENTO:            { label: 'Em andamento',          cls: 'status-dev',      quando: 'Projeto em execução.' },
  AGUARDANDO_CLIENTE:   { label: 'Aguardando cliente',    cls: 'status-expirado', quando: 'Depende do cliente para seguir.' },
  PAUSADO:              { label: 'Pausado',               cls: 'status-pending',  quando: 'Projeto suspenso.' },
  HOMOLOGACAO:          { label: 'Em homologação',        cls: 'status-analysis', quando: 'Em validação final.' },
  CONCLUIDO:            { label: 'Concluído',             cls: 'status-done',     quando: 'Entregue e finalizado.' },
  CANCELADO:            { label: 'Cancelado',             cls: 'status-cancelado',quando: 'Encerrado sem conclusão.' },
};

export const ETAPA_STATUS = {
  NAO_INICIADO:       { label: 'Não iniciado',      cls: '',                significado: 'Aguardando execução.' },
  ANDAMENTO:          { label: 'Em andamento',      cls: 'status-dev',      significado: 'Trabalho em execução.' },
  REVISAO:            { label: 'Em revisão',        cls: 'status-analysis', significado: 'Aguardando análise interna.' },
  AGUARDANDO_CLIENTE: { label: 'Aguardando cliente',cls: 'status-expirado', significado: 'Depende de informações ou aprovação.' },
  PAUSADO:            { label: 'Pausado',           cls: 'status-pending',  significado: 'Execução temporariamente interrompida.' },
  CONCLUIDO:          { label: 'Concluído',         cls: 'status-done',     significado: 'Etapa finalizada.' },
  CANCELADO:          { label: 'Cancelado',         cls: 'status-cancelado',significado: 'Etapa não será executada.' },
};

// Cancelada sai da conta: cobrar progresso de uma etapa que não será
// executada faria o projeto nunca chegar a 100%.
export function progressoGeral(etapas) {
  const valem = etapas.filter(et => et.status !== 'CANCELADO');
  const peso = valem.reduce((s, et) => s + (Number(et.peso) || 1), 0);
  if (!peso) return 0;
  const feito = valem.reduce((s, et) => s + (Number(et.peso) || 1) * (Number(et.progresso) || 0), 0);
  return Math.round(feito / peso);
}

export const TIPOS_APROVACAO = {
  ESCOPO:        'Escopo',
  DESIGN:        'Design',
  CONTEUDO:      'Conteúdo',
  DESENVOLVIMENTO:'Desenvolvimento',
  HOMOLOGACAO:   'Homologação',
  ENTREGA:       'Entrega final',
};

export const PASTAS_DOC = {
  CONTRATOS:     'Contratos',
  PROPOSTAS:     'Propostas',
  BRIEFING:      'Briefing',
  IDENTIDADE:    'Identidade visual',
  DESENVOLVIMENTO:'Desenvolvimento',
  APROVACOES:    'Aprovações',
  ENTREGAS:      'Entregas',
};
