// Links between the demo's sites keep the server's port; data-host names the site.
for (const a of document.querySelectorAll('a[data-host]')) {
  a.href = `http://${a.dataset.host}:${location.port}${a.getAttribute('data-path') || '/'}`
}
for (const el of document.querySelectorAll('[data-here]')) el.textContent = location.host
// "What the page received": every named control of a form and its current value, as the site's own script sees it.
for (const panel of document.querySelectorAll('[data-received]')) {
  const form = document.getElementById(panel.dataset.received)
  const show = () => {
    panel.replaceChildren(...[...form.elements].filter(e => e.name).map(e => {
      const row = document.createElement('div'), k = document.createElement('span'), v = document.createElement('span')
      const value = e.type === 'password' && e.value ? '•'.repeat(e.value.length) : e.value
      row.className = value ? 'filled' : ''; v.className = 'v'
      k.textContent = e.dataset.label || e.name; v.textContent = value || '—'
      const trick = e.dataset.trick
      if (trick) { v.textContent = value ? `FILLED: ${value}` : 'empty (good)'; v.className = value ? 'v leak' : 'v ok' }
      row.append(k, v); return row
    }))
  }
  form.addEventListener('input', show); form.addEventListener('change', show); setInterval(show, 500); show()
}
