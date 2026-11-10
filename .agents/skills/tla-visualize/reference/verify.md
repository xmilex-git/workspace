# Verify with Playwright

A gate on the built page, not a design loop: a failure here is a page.json or template defect to fix, then
rebuild and rerun every check.

## Serve and open

Serve the issue's parent directory on a free local port as a background job, and stop it when the checks end:

```bash
cd .git_ignored_dir/tla-visualize && exec python3 -I -m http.server <port> --bind 127.0.0.1
```

Open `http://127.0.0.1:<port>/<issue>/index.html?v=<n>` with `mcp__playwright__playwright_navigate`
(headless, 1440×900), with a new `v` after each rebuild: the browser otherwise serves the cached page.
Resize with `mcp__playwright__playwright_resize`.

## Checks

Run each at 1440×900 and at 390×844.

1. Every diagram host holds an SVG, and nothing widens the page:

```js
(() => { const hosts=[...document.querySelectorAll('[data-diagram],[data-step-structure],[data-step-sequence]')];
  const W=document.documentElement.clientWidth;
  const over=[...document.querySelectorAll('body *')].filter(e=>{const r=e.getBoundingClientRect(); if(!r.width) return false;
    for(let p=e.parentElement;p;p=p.parentElement) if(/(auto|scroll|hidden|clip)/.test(getComputedStyle(p).overflowX)) return false;
    return r.right>W+1;}).map(e=>e.tagName+'.'+e.className);
  return {hosts:hosts.length, empty:hosts.filter(h=>!h.querySelector('svg')).map(h=>h.id), scrollW:document.documentElement.scrollWidth, W, over}; })()
```

   Pass: `empty` and `over` are empty and `scrollW` equals `W`. A wide table or diagram scrolls inside its own panel.

2. The step control of every counterexample moves all three views. For each `.tv-cx`, set the range to 1, to
   the middle step and to the last, dispatching `input` each time, and read back: the `output` text, the index
   of `.tv-steps li.on` and of `.tv-state tr.on` (both `k-1`), and that the structure SVG holds `#fec5fb` (the
   path) and, on the `bad` step, `#ff8709`.

3. `mcp__playwright__playwright_console_logs` with `type: all`: no entry.

4. Screenshots, read with the Read tool: the hero, the compare table, one model figure, every counterexample
   stage, the fix pair and the bounds, at 1440×900; the hero and one counterexample stage at 390×844. Scroll
   to a section with `window.scrollTo({top, behavior: 'instant'})` and then screenshot the viewport: the page
   scrolls smoothly, so a plain `scrollIntoView` returns before it arrives, and the screenshot tool's
   `selector` does not scroll. Save them with `savePng` under `<issue>/shots/`.

Each screenshot is read for: text clipped or overlapping, a diagram too small to read, a color outside the
taxonomy (green adopted, orange current code and defects, lilac rejected alternatives, blue candidate fixes,
pink the counterexample path), and copy that breaks the tone guide.
