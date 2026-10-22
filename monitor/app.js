// 같은 오리진의 POST /coupons/issue 를 반복 호출하고, 응답 버전 비율과 5xx 비율을 그린다.
// 쿼리: ?path=/coupons/issue&concurrency=4&interval=100
(() => {
  const params = new URLSearchParams(location.search);
  const path = params.get('path') || '/coupons/issue';
  const WINDOW_SEC = 120;
  const PALETTE = ['#3b82f6', '#10b981', '#f59e0b', '#a855f7', '#ec4899', '#14b8a6'];

  const $ = (id) => document.getElementById(id);
  const concurrencyInput = $('concurrency');
  const intervalInput = $('interval');
  if (params.get('concurrency')) concurrencyInput.value = params.get('concurrency');
  if (params.get('interval')) intervalInput.value = params.get('interval');

  const buckets = new Map(); // sec -> { total, e5xx, versions: Map }
  const colors = new Map();
  const totals = { requests: 0, e5xx: 0, fail: 0, versions: new Map() };
  const recent = [];
  let running = false;

  const colorOf = (v) => {
    if (!colors.has(v)) colors.set(v, PALETTE[colors.size % PALETTE.length]);
    return colors.get(v);
  };

  function record(status, version, latency) {
    const sec = Math.floor(Date.now() / 1000);
    let b = buckets.get(sec);
    if (!b) { b = { total: 0, e5xx: 0, versions: new Map() }; buckets.set(sec, b); }
    b.total++;
    totals.requests++;
    if (status >= 500 || status === 0) { b.e5xx++; totals.e5xx++; }
    if (status === 0) totals.fail++;
    const v = version || '(none)';
    b.versions.set(v, (b.versions.get(v) || 0) + 1);
    totals.versions.set(v, (totals.versions.get(v) || 0) + 1);
    colorOf(v);
    recent.unshift({ at: new Date(), status, version: v, latency });
    if (recent.length > 20) recent.pop();
  }

  async function worker() {
    while (running) {
      const started = performance.now();
      try {
        const res = await fetch(path, {
          method: 'POST',
          cache: 'no-store',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ userId: 'monitor', orderAmount: 25000 }),
        });
        record(res.status, res.headers.get('X-App-Version'), performance.now() - started);
      } catch {
        record(0, '', performance.now() - started);
      }
      const wait = Number(intervalInput.value) || 0;
      if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    }
  }

  function toggle() {
    running = !running;
    $('toggle').textContent = running ? '정지' : '시작';
    $('toggle').classList.toggle('running', running);
    if (running) {
      const n = Math.max(1, Math.min(32, Number(concurrencyInput.value) || 1));
      for (let i = 0; i < n; i++) worker();
    }
  }

  function renderStats() {
    const rate = totals.requests ? (totals.e5xx / totals.requests) * 100 : 0;
    const items = [
      ['총 요청', totals.requests.toLocaleString(), false],
      ['5xx / 실패', `${totals.e5xx} (${rate.toFixed(2)}%)`, totals.e5xx > 0],
      ['연결 실패', String(totals.fail), totals.fail > 0],
      ...[...totals.versions.entries()].map(([v, n]) => [
        `버전 ${v}`, `${((n / totals.requests) * 100).toFixed(1)}%`, false,
      ]),
    ];
    $('stats').innerHTML = items.map(([label, value, bad]) =>
      `<div class="stat"><div class="label">${label}</div><div class="value${bad ? ' bad' : ''}">${value}</div></div>`).join('');
    $('legend').innerHTML = [...colors.entries()].map(([v, c]) =>
      `<span><i style="background:${c}"></i>${v}</span>`).join('') +
      '<span><i style="background:var(--error);height:2px"></i>5xx 비율</span>';
    $('log').innerHTML = recent.map((r) =>
      `<tr><td>${r.at.toLocaleTimeString()}</td><td class="${r.status >= 500 || r.status === 0 ? 'err' : ''}">${r.status || 'ERR'}</td>` +
      `<td>${r.version}</td><td>${Math.round(r.latency)}ms</td></tr>`).join('');
  }

  function renderChart() {
    const canvas = $('chart');
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    const ctx = canvas.getContext('2d');
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, w, h);

    const css = getComputedStyle(document.documentElement);
    const pad = { l: 36, r: 8, t: 8, b: 20 };
    const cw = w - pad.l - pad.r;
    const ch = h - pad.t - pad.b;
    const now = Math.floor(Date.now() / 1000);
    const x = (i) => pad.l + (i / (WINDOW_SEC - 1)) * cw;
    const y = (ratio) => pad.t + (1 - ratio) * ch;

    ctx.strokeStyle = css.getPropertyValue('--grid');
    ctx.fillStyle = css.getPropertyValue('--muted');
    ctx.font = '11px sans-serif';
    for (const r of [0, 0.25, 0.5, 0.75, 1]) {
      ctx.beginPath(); ctx.moveTo(pad.l, y(r)); ctx.lineTo(w - pad.r, y(r)); ctx.stroke();
      ctx.fillText(`${r * 100}%`, 2, y(r) + 4);
    }
    ctx.fillText(`-${WINDOW_SEC}s`, pad.l, h - 4);
    ctx.fillText('now', w - pad.r - 22, h - 4);

    const series = [];
    for (let i = 0; i < WINDOW_SEC; i++) series.push(buckets.get(now - WINDOW_SEC + 1 + i));

    // 버전별 누적 영역
    const versions = [...colors.keys()];
    const base = new Array(WINDOW_SEC).fill(0);
    for (const v of versions) {
      const top = series.map((b, i) => base[i] + (b && b.total ? (b.versions.get(v) || 0) / b.total : 0));
      ctx.beginPath();
      for (let i = 0; i < WINDOW_SEC; i++) ctx.lineTo(x(i), y(top[i]));
      for (let i = WINDOW_SEC - 1; i >= 0; i--) ctx.lineTo(x(i), y(base[i]));
      ctx.closePath();
      ctx.fillStyle = colors.get(v) + 'cc';
      ctx.fill();
      for (let i = 0; i < WINDOW_SEC; i++) base[i] = top[i];
    }

    // 5xx 비율 선
    ctx.beginPath();
    ctx.strokeStyle = css.getPropertyValue('--error');
    ctx.lineWidth = 2;
    let started = false;
    series.forEach((b, i) => {
      if (!b || !b.total) { started = false; return; }
      const py = y(b.e5xx / b.total);
      if (started) ctx.lineTo(x(i), py); else { ctx.moveTo(x(i), py); started = true; }
    });
    ctx.stroke();
    ctx.lineWidth = 1;

    for (const sec of buckets.keys()) if (sec < now - WINDOW_SEC) buckets.delete(sec);
  }

  $('toggle').addEventListener('click', toggle);
  setInterval(() => { renderStats(); renderChart(); }, 500);
  renderStats();
  renderChart();
})();
