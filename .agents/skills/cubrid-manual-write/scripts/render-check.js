// render-check.js — paste into the Playwright MCP `playwright_evaluate` after navigating to any page of the
// local server (VERIFY.md §5). Edit PAGES and PROBES first. For each touched page in ko and en it reports:
//   leaks   text outside code that still holds RST markup (**, :ref:, ``, a backslash escape, ".. note")
//   sysmsg  docutils system messages / problematic nodes rendered into the page
//   probes  where each new string landed: pre (code/output block), text (prose), MISSING
//   refs    probe "#anchor" checks that a link to that anchor exists on the page
// Leaks in lines the change did not touch are pre-existing: note them, do not fix them in this PR.
(async () => {
  const PAGES = ['sql/query/prepare'];                       // touched pages, without .html
  const PROBES = { 'sql/query/prepare': ['?:0 of type character', '#execute-statement'] };
  const out = [];
  for (const lang of ['ko', 'en']) for (const p of PAGES) {
    const html = await (await fetch('/' + lang + '-html/' + p + '.html')).text();
    const d = new DOMParser().parseFromString(html, 'text/html');
    const body = d.querySelector('[role=main]') || d.body;
    const w = d.createTreeWalker(body, NodeFilter.SHOW_TEXT);
    const leaks = [];
    let n;
    while ((n = w.nextNode())) {
      if (n.parentElement.closest('pre,code,script,style')) continue;
      if (/\*\*|:ref:|``|\\ |:c:func:|\.\. (note|code-block)/.test(n.textContent)) leaks.push(n.textContent.trim().slice(0, 60));
    }
    const sys = body.querySelectorAll('.system-message,.problematic').length;
    const probes = (PROBES[p] || []).map((s) => {
      if (s.startsWith('#')) return s + ':' + [...body.querySelectorAll('a')].some((a) => (a.getAttribute('href') || '').endsWith(s));
      const inPre = [...body.querySelectorAll('pre')].some((e) => e.textContent.includes(s));
      return s.slice(0, 20) + ':' + (inPre ? 'pre' : body.textContent.includes(s) ? 'text' : 'MISSING');
    });
    out.push(`${lang}/${p} leaks=${leaks.length}${leaks.length ? JSON.stringify(leaks.slice(0, 3)) : ''} sysmsg=${sys} ${probes.join(' ')}`);
  }
  return out.join('\n');
})()
