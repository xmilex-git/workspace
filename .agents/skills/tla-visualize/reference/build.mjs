// usage: .git_ignored_dir/tla-visualize/tools/bin/node .agents/skills/tla-visualize/reference/build.mjs <page.json>
//
// Assembles index.html next to page.json from template.html, the page data, the pele renderer and the
// fonts subset to the page's glyphs (tools from `just tla-visualize-install`). Every Mermaid source,
// every counterexample step included, is rendered once in Node first: a syntax error or an unknown
// node, edge or actor stops the build with the field that holds it. Prints `BUILT <path> <bytes>`.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve, basename } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '../../../..');
const tools = join(repo, '.git_ignored_dir/tla-visualize/tools');
const fail = (msg) => { console.error('ERROR: ' + msg); process.exit(1); };

if (process.argv.length !== 3) fail('usage: build.mjs <page.json>');
const pagePath = resolve(process.argv[2]);
const outDir = dirname(pagePath);
if (!existsSync(join(tools, 'lib/pele/dist/pele.js'))) fail(`${tools} missing: run \`just tla-visualize-install\``);
const { render } = await import(join(tools, 'lib/pele/dist/pele.js'));
const page = JSON.parse(readFileSync(pagePath, 'utf8'));

// ---------- text helpers ----------
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
// inline markup in page text: `code`, **bold**, [label](url); everything else is escaped
const md = (s) => esc(s)
  .replace(/`([^`]+)`/g, '<code>$1</code>')
  .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
  .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1 ↗</a>');
const paras = (v) => (Array.isArray(v) ? v : v ? [v] : []).map((p) => `<p>${md(p)}</p>`).join('\n');
const need = (obj, keys, where) => keys.forEach((k) => { if (obj[k] === undefined || obj[k] === '') fail(`${where}.${k} is required`); });

const KIND = {
  current: { label: '현재 코드', cls: 'tv-k-current' },
  fix: { label: '후보 수정', cls: 'tv-k-fix' },
  alt: { label: '대안', cls: 'tv-k-alt' },
  adopted: { label: '채택안', cls: 'tv-k-adopted' },
};
const RESULT = { OK: 'tv-k-adopted', FAILED: 'tv-k-current', PARTIAL: 'tv-k-alt', '미완': 'tv-k-current' };
const resultBadge = (r) => `<span class="tv-badge ${RESULT[r] || ''}">${esc(r === 'OK' ? 'RESULT: OK' : r === '미완' ? '미완' : 'RESULT: ' + r)}</span>`;

// ---------- diagrams ----------
const diagrams = {};
function check(src, where) {
  try { render(src); } catch (e) { fail(`${where}: pele cannot render it: ${String(e.message).split('\n').slice(0, 3).join(' | ')}`); }
  return src;
}
let figN = 0;
function figure(src, where, caption, right = '') {
  const id = 'd' + (++figN);
  diagrams[id] = check(src, where);
  return `<figure class="tv-fig"><figcaption><span>${md(caption)}</span>${right ? `<span>${md(right)}</span>` : ''}</figcaption><div class="tv-pele" id="${id}" data-diagram="${id}"></div></figure>`;
}

// Flowchart edges in source order (Mermaid's linkStyle index): one edge per line, `A --> B`, `A -.->|x| B`, `A -- x --> B`.
const NODE = String.raw`([A-Za-z_][A-Za-z0-9_]*)(?:\s*(?:\[\[.*?\]\]|\[\(.*?\)\]|\(\(.*?\)\)|\(\[.*?\]\)|\[.*?\]|\(.*?\)|\{\{.*?\}\}|\{.*?\}|>.*?\]))?`;
const EDGE = new RegExp(String.raw`^\s*${NODE}\s*(?:--\s.*?\s-->|-\.\s.*?\s\.->|==\s.*?\s==>|-->|---|-\.->|-\.-|==>|===|--o|--x|<-->)\s*(?:\|[^|]*\|\s*)?${NODE}\s*(?::::\w+)?\s*;?\s*$`);
function edgesOf(src) {
  const out = [];
  for (const line of src.split('\n')) {
    const m = EDGE.exec(line);
    if (m) out.push(`${m[1]}->${m[2]}`);
  }
  return out;
}
function nodesOf(src) {
  const ids = new Set();
  for (const line of src.split('\n').slice(1)) {
    if (/^\s*(classDef|class|linkStyle|style|click|subgraph|end|direction|%%)\b/.test(line)) continue;
    for (const m of line.matchAll(/(?:^|[\s&>|-])([A-Za-z_][A-Za-z0-9_]*)(?=\s*(?:\[|\(|\{|>|-->|---|-\.|==|&|$|;|:::))/g)) ids.add(m[1]);
  }
  return ids;
}
const OVERLAY = [
  'classDef tvPath fill:#2b2230,stroke:#fec5fb,color:#fffce1,stroke-width:2px',
  'classDef tvCur fill:#fec5fb,stroke:#fec5fb,color:#0e100f,stroke-width:3px',
  'classDef tvBad fill:#ff8709,stroke:#ff8709,color:#0e100f,stroke-width:3px',
  'classDef tvGuard fill:#0d2614,stroke:#0ae448,color:#fffce1,stroke-width:3px',
];
function overlay(base, visited, cur, bad, edgeIdx, guard, guardEdges = []) {
  const lines = [base.trimEnd(), ...OVERLAY];
  const past = [...new Set(visited)].filter((n) => n !== cur && n !== bad && n !== guard);
  if (past.length) lines.push(`class ${past.join(',')} tvPath`);
  if (cur && cur !== bad) lines.push(`class ${cur} tvCur`);
  if (bad) lines.push(`class ${bad} tvBad`);
  if (guard) lines.push(`class ${guard} tvGuard`);
  const idx = [...new Set(edgeIdx)].sort((a, b) => a - b);
  if (idx.length) lines.push(`linkStyle ${idx.join(',')} stroke:#fec5fb,stroke-width:3px`);
  if (guardEdges.length) lines.push(`linkStyle ${guardEdges.join(',')} stroke:#0ae448,stroke-width:3px`);
  return lines.join('\n');
}
const seqText = (s) => String(s).replace(/[;\n]/g, ', ').replace(/#/g, '#35;');

// ---------- page ----------
need(page, ['issue', 'title', 'eyebrow', 'lead', 'specs', 'compare', 'models', 'verification', 'bounds'], 'page');
const models = Object.fromEntries(page.models.map((m) => [m.id, m]));
const sections = [];
const nav = [];
const sec = (id, label, h2, lead, body) => {
  nav.push(`<a href="#${id}">${esc(label)}</a>`);
  sections.push(`<section class="tv-sec" id="${id}"><h2>${md(h2)}</h2>${lead ? `<p class="tv-lead">${md(lead)}</p>` : ''}\n${body}</section>`);
};

// problem
if (page.problem) {
  const p = page.problem;
  need(p, ['heading', 'body'], 'problem');
  let body = paras(p.body);
  if (p.repro) {
    need(p.repro, ['sql', 'result', 'build'], 'problem.repro');
    body += `<figure class="tv-fig"><figcaption><span>런타임 재현</span><span>${md(p.repro.build)}</span></figcaption><pre style="margin:0;padding:18px 22px;overflow-x:auto;font:13px/1.75 var(--mono);color:var(--cream)">${esc(p.repro.sql)}</pre></figure><div class="tv-note tv-warn">${md(p.repro.result)}</div>`;
  }
  sec('problem', '문제', p.heading, p.lead, body);
}

// compare
{
  const rows = page.compare.map((r, i) => {
    need(r, ['variant', 'kind', 'spec', 'model', 'defect', 'effect', 'handling', 'evidence'], `compare[${i}]`);
    const k = KIND[r.kind] || fail(`compare[${i}].kind must be one of ${Object.keys(KIND).join(', ')}`);
    const repro = r.kind === 'adopted' || r.effect === '—' ? '' : r.reproduced
      ? `<span class="tv-repro"><span class="tv-badge tv-k-current">런타임 재현</span></span>`
      : r.reproduced === false ? `<span class="tv-repro"><span class="tv-badge tv-k-none">런타임 재현 없음</span></span>` : '';
    return `<tr class="${k.cls}"><td><span class="tv-chip">${k.label}</span><span class="tv-vname">${esc(r.variant)}</span><span class="tv-vwhat">${md(r.spec)}</span><span class="tv-vwhat" style="margin-top:8px;color:var(--text)">${md(r.model)}</span></td><td>${md(r.defect)}</td><td>${repro}${md(r.effect)}</td><td class="tv-hand"><b>${md(r.handling.split('\n')[0])}</b><span>${md(r.handling.split('\n').slice(1).join(' '))}</span></td><td>${md(r.evidence)}</td></tr>`;
  }).join('\n');
  const legend = `<div class="tv-legend">${Object.values(KIND).map((k) => `<span class="tv-chip ${k.cls}">${k.label}</span>`).join('')}<span class="tv-chip tv-k-path">반례 경로</span></div>`;
  sec('compare', '비교', page.compareHeading || '모델 변형 비교', page.compareLead,
    `${legend}<div class="tv-table-wrap"><table class="tv-compare"><thead><tr><th>모델 변형</th><th>발견된 결함</th><th>CUBRID에서 생길 수 있는 일</th><th>처리</th><th>근거</th></tr></thead><tbody>${rows}</tbody></table></div>`);
}

// timeline
if (page.timeline && page.timeline.length) {
  const tl = ['timeline', ...page.timeline.map((t, i) => {
    need(t, ['date', 'events'], `timeline[${i}]`);
    return `  ${t.date} : ${t.events.map((e) => String(e).replace(/:/g, '：').replace(/\n/g, ' ')).join(' : ')}`;
  })].join('\n');
  sec('timeline', '경위', page.timelineHeading || '경위', page.timelineLead, figure(tl, 'timeline', '날짜별 경위', page.timelineSource || ''));
}

// models
{
  const body = page.models.map((m, i) => {
    need(m, ['id', 'dir', 'module', 'result', 'what', 'claims', 'diagram'], `models[${i}]`);
    const claims = m.claims.map((c) => `<tr><td><code>${esc(c.id)}</code></td><td>${esc(c.kind)}</td><td>${md(c.text)}</td><td>${md(c.source)}</td></tr>`).join('');
    const map = (m.map || []).length ? `<h4>모델의 한 스텝과 코드</h4><div class="tv-table-wrap"><table><thead><tr><th>모델 스텝</th><th>코드</th><th>한 스텝으로 묶는 근거</th></tr></thead><tbody>${m.map.map((r) => `<tr><td><code>${esc(r.step)}</code></td><td>${md(r.code)}</td><td>${md(r.why)}</td></tr>`).join('')}</tbody></table></div>` : '';
    return `<div class="tv-model" id="model-${esc(m.id)}"><div class="tv-model-head"><h3>${md(m.title || m.module)}</h3>${resultBadge(m.result)}<code>${esc(m.dir)}/${esc(m.module)}.tla</code></div>
${paras(m.what)}
${figure(m.diagram, `models[${i}].diagram`, m.diagramCaption || '모델 구조', m.diagramRight || '')}
${(m.diagramNotes || []).length ? `<div class="tv-note">${m.diagramNotes.map(md).join('<br>')}</div>` : ''}
<h4>Claim</h4><div class="tv-table-wrap"><table><thead><tr><th>Claim</th><th>종류</th><th>내용</th><th>출처</th></tr></thead><tbody>${claims}</tbody></table></div>
${map}</div>`;
  }).join('\n');
  sec('models', '모델', page.modelsHeading || '모델은 무엇을 나타내나', page.modelsLead, body);
}

// counterexamples
const cxData = [];
if ((page.counterexamples || []).length) {
  const body = page.counterexamples.map((cx, ci) => {
    const where = `counterexamples[${ci}]`;
    need(cx, ['title', 'variant', 'kind', 'property', 'lead', 'model', 'actors', 'steps'], where);
    const model = models[cx.model] || fail(`${where}.model: no model with id ${cx.model}`);
    const base = cx.structure || model.diagram;
    if (!/^\s*(flowchart|graph)\b/.test(base)) fail(`${where}: the structure diagram must be a flowchart to carry the path overlay`);
    const nodes = nodesOf(base);
    const edges = edgesOf(base);
    const actors = Object.fromEntries(cx.actors.map((a) => [a.id, a.label]));
    const visited = [], edgeIdx = [];
    const structure = [], sequence = [];
    let prevNode = null, badNode = null;
    cx.steps.forEach((s, si) => {
      const w = `${where}.steps[${si}]`;
      need(s, ['actor', 'action', 'text'], w);
      if (!actors[s.actor]) fail(`${w}.actor ${s.actor} is not in ${where}.actors`);
      if (s.to && !actors[s.to]) fail(`${w}.to ${s.to} is not in ${where}.actors`);
      if (s.node && !nodes.has(s.node)) fail(`${w}.node ${s.node} is not a node of the structure diagram (${[...nodes].join(', ')})`);
      const edgeKey = s.edge || (prevNode && s.node ? `${prevNode}->${s.node}` : null);
      if (s.edge && !edges.includes(s.edge)) fail(`${w}.edge ${s.edge} is not an edge of the structure diagram`);
      if (edgeKey) edges.forEach((e, i) => { if (e === edgeKey) edgeIdx.push(i); });
      if (s.node) { visited.push(s.node); prevNode = s.node; }
      if (s.bad) badNode = s.node || badNode;
      structure.push(check(overlay(base, visited, s.node, s.bad ? s.node : null, edgeIdx), `${w} (structure overlay)`));
    });
    const seqHead = ['sequenceDiagram', ...cx.actors.map((a) => `  participant ${a.id} as ${seqText(a.label)}`)];
    const seqLine = (s, i) => {
      const t = `${i + 1}. ${seqText(s.action)}${s.bad ? ' ✕' : ''}`;
      return s.to ? `  ${s.actor}->>${s.to}: ${t}` : `  Note over ${s.actor}: ${t}`;
    };
    cx.steps.forEach((_, k) => {
      const lines = [...seqHead];
      cx.steps.forEach((s, i) => {
        if (i === k) lines.push(`  rect ${s.bad ? 'rgba(255,135,9,0.28)' : 'rgba(254,197,251,0.20)'}`, '  ' + seqLine(s, i), '  end');
        else lines.push(seqLine(s, i));
      });
      sequence.push(check(lines.join('\n'), `${where}.steps[${k}] (sequence)`));
    });
    const id = 'cx-' + (ci + 1);
    cxData.push({ id, steps: cx.steps.length, structure, sequence });
    const k = KIND[cx.kind] || fail(`${where}.kind must be one of ${Object.keys(KIND).join(', ')}`);
    const items = cx.steps.map((s, i) => `<li tabindex="0" class="${s.bad ? 'bad' : ''}"><div class="h"><span class="n">${i + 1}</span><span class="a">${md(s.action)}</span><span class="who">${esc(actors[s.actor])}${s.to ? ' → ' + esc(actors[s.to]) : ''}</span></div>${md(s.text)}${s.code ? `<span class="c">${esc(s.code)}</span>` : ''}</li>`).join('');
    const cols = cx.stateCols || [];
    const state = cols.length ? `<h4>스텝마다 바뀐 값</h4><div class="tv-table-wrap"><table class="tv-state"><thead><tr><th>스텝</th>${cols.map((c) => `<th>${esc(c)}</th>`).join('')}</tr></thead><tbody>${cx.steps.map((s, i) => {
      const prev = i ? cx.steps[i - 1].state || {} : {};
      return `<tr class="${s.bad ? 'bad' : ''}"><td>${i + 1}. ${esc(s.action)}</td>${cols.map((c) => { const v = (s.state || {})[c] ?? ''; return `<td class="${i && v !== (prev[c] ?? '') ? 'on' : ''}">${esc(v)}</td>`; }).join('')}</tr>`;
    }).join('')}</tbody></table></div>` : '';
    let fix = '';
    if (cx.fix) {
      need(cx.fix, ['variant', 'node', 'stopAt', 'text'], `${where}.fix`);
      if (!nodes.has(cx.fix.node)) fail(`${where}.fix.node ${cx.fix.node} is not a node of the structure diagram`);
      const upto = cx.steps.slice(0, cx.fix.stopAt - 1);
      const v2 = upto.map((s) => s.node).filter(Boolean);
      const e2 = []; let p2 = null;
      upto.forEach((s) => { const key = s.edge || (p2 && s.node ? `${p2}->${s.node}` : null); if (key) edges.forEach((e, i) => { if (e === key) e2.push(i); }); if (s.node) p2 = s.node; });
      const ge = p2 ? edges.flatMap((e, i) => (e === `${p2}->${cx.fix.node}` ? [i] : [])) : [];
      const after = overlay(base, v2, null, null, e2, cx.fix.node, ge);
      const before = structure[structure.length - 1];
      fix = `<h4>수정이 막는 자리</h4><div class="tv-pair"><div class="tv-k-current"><div class="tv-side-title">${esc(cx.variant)}<span>${esc(cx.steps.length)}스텝에서 ${esc(cx.property)} 위반</span></div>${figure(before, `${where} (before)`, '반례가 끝까지 감')}</div><div class="tv-k-adopted"><div class="tv-side-title">${esc(cx.fix.variant)}<span>${esc(cx.fix.stopAt)}번째 스텝에서 막힘</span></div>${figure(check(after, `${where}.fix`), `${where}.fix`, '채택안의 가드에서 멈춤')}</div></div><div class="tv-note">${md(cx.fix.text)}</div>`;
    }
    const logLine = cx.log ? `TLC 로그 <code>${esc(cx.log)}</code>` : 'TLC 로그 없음: MAP.md의 스텝을 옮겼습니다';
    return `<div class="tv-cx" id="${id}">
<div class="tv-cx-meta"><span class="tv-chip ${k.cls}">${k.label}</span><code>${esc(cx.variant)}</code><span class="tv-badge tv-k-current">${esc(cx.property)} 위반</span></div>
<h3>${md(cx.title)}</h3>
${paras(cx.lead)}
<div class="tv-stage">
  <div class="tv-stage-left"><figure class="tv-fig"><figcaption><span>모델 구조 위의 반례 경로</span><span>${esc(model.module)}</span></figcaption>
    <div class="tv-ctl"><button type="button" data-prev aria-label="이전 스텝">‹</button><input type="range" min="1" max="${cx.steps.length}" value="${cx.steps.length}" aria-label="스텝"><button type="button" data-next aria-label="다음 스텝">›</button><output></output></div>
    <div class="tv-pele" id="${id}-s" data-step-structure></div></figure></div>
  <ol class="tv-steps">${items}</ol>
</div>
<figure class="tv-fig"><figcaption><span>참여자 사이의 순서</span><span>${logLine}</span></figcaption><div class="tv-pele" id="${id}-q" data-step-sequence></div></figure>
${state}
${fix}
</div>`;
  }).join('\n');
  sec('counterexamples', '반례', page.cxHeading || '반례: 어떤 순서에서 깨지나', page.cxLead, body);
}

// verification
{
  const v = page.verification;
  need(v, ['mutants'], 'verification');
  const mut = v.mutants.map((m, i) => { need(m, ['name', 'removes'], `verification.mutants[${i}]`); return `<tr class="${m.caught ? '' : 'tv-k-current'}"><td><code>${esc(m.name)}</code></td><td>${md(m.removes)}</td><td>${m.caught ? `<span class="tv-chip tv-k-adopted">${md(m.caught)}</span>` : '<span class="tv-chip tv-k-current">살아남음</span>'}</td></tr>`; }).join('');
  const wit = (v.witnesses || []).map((w) => `<tr><td><code>${esc(w.name)}</code></td><td>${md(w.shows)}</td></tr>`).join('');
  sec('verification', '검증', v.heading || '수정과 검증', v.lead,
    `${paras(v.body)}<h3>Mutant: 일부러 뺀 보호를 속성이 잡는가</h3><div class="tv-table-wrap"><table><thead><tr><th>mutant</th><th>뺀 것</th><th>잡은 속성</th></tr></thead><tbody>${mut}</tbody></table></div>` +
    (wit ? `<h3>Witness: 이 결과에 실제로 도달하는가</h3><div class="tv-table-wrap"><table><thead><tr><th>witness</th><th>도달을 보인 결과</th></tr></thead><tbody>${wit}</tbody></table></div>` : '') +
    ((v.lines || []).length ? `<div class="tv-note">${v.lines.map(md).join('<br>')}</div>` : ''));
}

// bounds
{
  const b = page.bounds;
  need(b, ['checked', 'outside', 'indinv', 'proof'], 'bounds');
  const box = (k, h, t) => `<div class="${k}"><h4>${h}</h4>${paras(t)}</div>`;
  sec('bounds', '범위', b.heading || '검사한 범위', b.lead,
    `<div class="tv-bounds">${box('tv-k-adopted', '검사한 범위', b.checked)}${box('tv-k-current', '범위 밖', b.outside)}${box('tv-k-fix', '귀납 불변식', b.indinv)}${box('tv-k-alt', '증명', b.proof)}</div>`);
}

// hero stats, computed from the data so they cannot disagree with the table
const kinds = page.compare.reduce((a, r) => ((a[r.kind] = (a[r.kind] || 0) + 1), a), {});
const defects = page.compare.filter((r) => r.defect && !/^(없음|—|-)$/.test(r.defect.trim())).length;
const mutTotal = page.verification.mutants.length, mutCaught = page.verification.mutants.filter((m) => m.caught).length;
const results = page.specs.map((s) => s.result);
const overall = results.every((r) => r === 'OK') ? 'OK' : results.includes('FAILED') ? 'FAILED' : results.includes('미완') ? '미완' : 'PARTIAL';
const stats = [
  { k: '모델 변형', v: page.compare.length, u: '개', d: Object.entries(kinds).map(([k, n]) => `${KIND[k].label} ${n}`).join(', ') },
  { k: '발견된 결함', v: defects, u: '건', d: '비교표의 결함 열', cls: defects ? 'tv-k-current' : '' },
  { k: 'mutant 검출', v: `${mutCaught}`, u: `/ ${mutTotal}`, d: mutCaught === mutTotal ? '모든 mutant를 속성이 거부' : `${mutTotal - mutCaught}개가 살아남음`, cls: mutCaught === mutTotal ? '' : 'tv-k-current' },
  { k: '검증 결과', v: overall === 'OK' ? 'OK' : overall, u: '', d: `spec ${page.specs.length}개의 RESULT`, cls: RESULT[overall] },
];
const hero = `<header class="tv-wrap tv-hero" id="top">
<p class="tv-brace">{ ${esc(page.eyebrow)} }</p>
<h1>${esc(page.title).replace(/\n/g, '<br>')}</h1>
<div class="tv-hero-row"><p>${md(page.lead)}</p><div class="tv-pills">${(page.links || []).map((l, i) => `<a class="tv-pill${i === 0 ? ' tv-primary' : ''}" href="${esc(l.href)}" target="_blank" rel="noopener">${esc(l.label)} ↗</a>`).join('')}</div></div>
<div class="tv-stats">${stats.map((s) => `<div class="${s.cls || ''}"><p class="k">${s.k}</p><p class="v" style="color:var(--k,var(--cream))">${esc(s.v)}<span class="u">${esc(s.u)}</span></p><p class="d">${esc(s.d)}</p></div>`).join('')}</div>
<div class="tv-specs">${page.specs.map((s) => { need(s, ['dir', 'result'], 'specs[]'); return `<span>${resultBadge(s.result)} ${esc(s.dir)}${s.run ? ` <span style="color:var(--dim)">${esc(s.run)}</span>` : ''}</span>`; }).join('')}</div>
</header>`;

const body = `<div class="tv-nav"><a class="tv-brand" href="#top"><i></i>${esc(page.issue)}</a><nav>${nav.join('')}</nav></div>
${hero}
<main class="tv-wrap">${sections.join('\n')}</main>
<footer class="tv-foot">${md(page.footer || `이 페이지는 \`tla-visualize\`가 spec 디렉터리의 MAP.md, cfg, TLC 로그에서 만들었습니다. 생성 ${new Date().toISOString().slice(0, 10)}.`)}</footer>`;

// ---------- fonts: subset to the glyphs of the page ----------
const dataJson = JSON.stringify({ diagrams, counterexamples: cxData }).replace(/</g, '\\u003c');
const fontDir = join(tools, 'share/fonts');
const work = join(outDir, '.fonts');
mkdirSync(work, { recursive: true });
const textFile = join(work, 'text.txt');
writeFileSync(textFile, [...new Set(body + dataJson + '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ{}[]()<>.,:;!?-_/\'"`~@#$%^&*+=|\\ ‹›↗→✕·…—')].join(''));
const faces = [
  ['Inter Tight', 'InterTight-wght.ttf', '100 900'],
  ['JetBrains Mono', 'JetBrainsMono-wght.ttf', '100 800'],
  ['Pretendard', 'Pretendard-Regular.otf', '400'],
  ['Pretendard', 'Pretendard-Medium.otf', '500'],
  ['Pretendard', 'Pretendard-SemiBold.otf', '600'],
  ['Pretendard', 'Pretendard-Bold.otf', '700'],
];
const fontsCss = faces.map(([family, file, weight]) => {
  const out = join(work, basename(file).replace(/\.\w+$/, '.woff2'));
  execFileSync(join(tools, 'bin/pyftsubset'), [join(fontDir, file), `--text-file=${textFile}`, '--flavor=woff2', '--layout-features=*', `--output-file=${out}`], { stdio: ['ignore', 'ignore', 'inherit'] });
  return `@font-face{font-family:'${family}';font-weight:${weight};font-style:normal;font-display:block;src:url(data:font/woff2;base64,${readFileSync(out).toString('base64')}) format('woff2')}`;
}).join('\n');

// ---------- assemble ----------
const peleJs = readFileSync(join(tools, 'lib/pele/dist/pele.global.js'), 'utf8');
if (/<\/script/i.test(peleJs)) fail('pele.global.js contains </script; it cannot be inlined');
const template = readFileSync(join(here, 'template.html'), 'utf8');
const html = template
  .replace('{{TITLE}}', () => esc(`${page.issue} — ${page.title.replace(/\n/g, ' ')}`))
  .replace('{{FONTS_CSS}}', () => fontsCss)
  .replace('{{BODY}}', () => body)
  .replace('{{DATA_JSON}}', () => dataJson)
  .replace('{{PELE_JS}}', () => peleJs);
const outPath = join(outDir, 'index.html');
writeFileSync(outPath, html);
console.log(`BUILT ${outPath} ${Buffer.byteLength(html)} bytes, ${Object.keys(diagrams).length} diagrams, ${cxData.reduce((a, c) => a + 2 * c.steps, 0)} step diagrams`);
