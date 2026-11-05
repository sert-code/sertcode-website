/**
 * Cálculo da folha de pagamento da SertCode.
 *
 * Funções puras, sem banco e sem tela: recebem o colaborador, os lançamentos
 * do mês e os parâmetros de INSS/IRRF, e devolvem os valores. Separado do
 * painel porque é a parte que precisa ser conferida com a contabilidade — e
 * conferir conta é mais fácil quando ela não está misturada com botão.
 */

const r2 = v => Math.round((Number(v) || 0) * 100) / 100;

/** INSS progressivo: cada faixa incide só sobre a parte que cai nela. */
export function calcularInss(base, faixas) {
  let total = 0, anterior = 0;
  for (const f of faixas) {
    if (base <= anterior) break;
    const topo = Math.min(base, f.ate ?? Infinity);
    total += (topo - anterior) * (f.aliquota / 100);
    anterior = f.ate ?? Infinity;
  }
  return r2(total);
}

/**
 * IRRF mensal. A base é o bruto menos a maior entre duas opções: as deduções
 * legais (INSS + dependentes) ou o desconto simplificado — a lei garante a
 * mais vantajosa para quem recebe.
 */
export function calcularIrrf({ bruto, inss, dependentes, config }) {
  const deducoes = Math.max(inss + dependentes * config.deducaoDependente, config.descontoSimplificado);
  const base = Math.max(0, bruto - deducoes);

  const faixa = config.irrf.find(f => f.ate === null || base <= f.ate) ?? config.irrf[config.irrf.length - 1];
  let imposto = r2(base * (faixa.aliquota / 100) - faixa.deducao);
  if (imposto < 0) imposto = 0;

  // Redução de 2026: isento até o piso e desconto decrescente até o teto.
  if (bruto <= config.isencaoAte) return 0;
  if (bruto <= config.reducaoAte) {
    const proporcao = (config.reducaoAte - bruto) / (config.reducaoAte - config.isencaoAte);
    imposto = r2(imposto * (1 - proporcao));
  }
  return Math.max(0, imposto);
}

/**
 * Valores de um colaborador na competência.
 *
 * `lancamentos` são os proventos e descontos digitados no ajuste.
 * `beneficios` traz o custo da empresa e o desconto do colaborador.
 */
export function calcularItem({ colaborador, lancamentos = [], beneficios = [], config }) {
  const pj = ['PJ', 'AUTONOMO'].includes(colaborador.vinculo);
  const clt = ['CLT', 'TEMPORARIO'].includes(colaborador.vinculo);

  const salarioBase = Number(colaborador.salario_base) || 0;
  const proventos = r2(lancamentos.filter(l => l.tipo === 'provento').reduce((t, l) => t + Number(l.valor || 0), 0));
  const outrosDescontos = r2(lancamentos.filter(l => l.tipo === 'desconto').reduce((t, l) => t + Number(l.valor || 0), 0));
  const bruto = r2(salarioBase + proventos);

  // Autônomo recolhe INSS próprio (alíquota única, limitada ao teto); PJ não
  // tem retenção; CLT segue a tabela progressiva.
  const tetoInss = config.inss[config.inss.length - 1]?.ate ?? Infinity;
  let inss = 0;
  if (clt) inss = calcularInss(bruto, config.inss);
  else if (colaborador.vinculo === 'AUTONOMO') inss = r2(Math.min(bruto, tetoInss) * (config.inssAutonomo / 100));

  const irrf = pj && colaborador.vinculo === 'PJ'
    ? 0
    : calcularIrrf({ bruto, inss, dependentes: Number(colaborador.dependentes) || 0, config });

  const descontoBeneficios = r2(beneficios.reduce((t, b) => t + Number(b.desconto || 0), 0));
  const custoBeneficios    = r2(beneficios.reduce((t, b) => t + Number(b.valor || 0), 0));

  const liquido = r2(bruto - inss - irrf - descontoBeneficios - outrosDescontos);

  const fgts = clt ? r2(bruto * (config.fgts / 100)) : 0;
  const patronal = clt
    ? r2(bruto * (config.patronal / 100))
    : colaborador.vinculo === 'AUTONOMO' ? r2(bruto * (config.patronalAutonomo / 100)) : 0;
  const encargos = r2(fgts + patronal);

  // 13º e férias + 1/3 são despesa do mês mesmo sem saída de dinheiro: 1/12 do
  // bruto para cada, mais 1/3 sobre as férias.
  const provisoes = config.provisoes && clt ? r2(bruto / 12 + (bruto / 12) * (4 / 3)) : 0;

  return {
    salario_base: salarioBase, proventos, salario_bruto: bruto,
    inss, irrf, desconto_beneficios: descontoBeneficios, outros_descontos: outrosDescontos,
    salario_liquido: liquido, fgts, encargos, custo_beneficios: custoBeneficios, provisoes,
    custo_total: r2(bruto + encargos + custoBeneficios + provisoes),
  };
}

/** Soma dos itens, para os cartões do topo da folha. */
export function somarFolha(itens) {
  const soma = campo => r2(itens.reduce((t, i) => t + Number(i[campo] || 0), 0));
  return {
    bruto: soma('salario_bruto'), liquido: soma('salario_liquido'),
    inss: soma('inss'), irrf: soma('irrf'), encargos: soma('encargos'),
    beneficios: soma('custo_beneficios'), provisoes: soma('provisoes'),
    custo: soma('custo_total'),
  };
}

const UNIDADES = ['', 'um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove', 'dez',
  'onze', 'doze', 'treze', 'quatorze', 'quinze', 'dezesseis', 'dezessete', 'dezoito', 'dezenove'];
const DEZENAS = ['', '', 'vinte', 'trinta', 'quarenta', 'cinquenta', 'sessenta', 'setenta', 'oitenta', 'noventa'];
const CENTENAS = ['', 'cento', 'duzentos', 'trezentos', 'quatrocentos', 'quinhentos',
  'seiscentos', 'setecentos', 'oitocentos', 'novecentos'];

function trecho(n) {
  if (n === 100) return 'cem';
  const c = Math.floor(n / 100), d = n % 100;
  const partes = [];
  if (c) partes.push(CENTENAS[c]);
  if (d < 20) { if (d) partes.push(UNIDADES[d]); }
  else {
    const dez = Math.floor(d / 10), un = d % 10;
    partes.push(un ? `${DEZENAS[dez]} e ${UNIDADES[un]}` : DEZENAS[dez]);
  }
  return partes.join(' e ');
}

/** Valor por extenso, exigido no recibo do demonstrativo. */
export function porExtenso(valor) {
  const inteiro = Math.floor(valor);
  const centavos = Math.round((valor - inteiro) * 100);
  if (inteiro === 0 && centavos === 0) return 'zero reais';

  const partes = [];
  const milhoes = Math.floor(inteiro / 1000000);
  const milhares = Math.floor((inteiro % 1000000) / 1000);
  const resto = inteiro % 1000;

  if (milhoes) partes.push(`${trecho(milhoes)} ${milhoes === 1 ? 'milhão' : 'milhões'}`);
  if (milhares) partes.push(milhares === 1 ? 'mil' : `${trecho(milhares)} mil`);
  if (resto) partes.push(trecho(resto));

  let texto = partes.join(' e ') + (inteiro === 1 ? ' real' : ' reais');
  if (centavos) texto += ` e ${trecho(centavos)} ${centavos === 1 ? 'centavo' : 'centavos'}`;
  return texto;
}
