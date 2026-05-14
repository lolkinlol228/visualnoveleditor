async function apiFetch(url, opts = {}) {
  const res = await fetch(url, {
    headers: { 'Content-Type': 'application/json', ...opts.headers },
    ...opts
  });
  if (!res.ok) throw new Error(await res.text());
  const ct = res.headers.get('content-type') || '';
  if (ct.includes('application/json')) return res.json();
  return res;
}

// Global escape helper (used by all modules)
function escH(s) {
  return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

const api = {
  getCharacters:   () => apiFetch('/api/characters'),
  createCharacter: (d) => apiFetch('/api/characters', { method: 'POST', body: JSON.stringify(d) }),
  updateCharacter: (id, d) => apiFetch(`/api/characters/${id}`, { method: 'PUT', body: JSON.stringify(d) }),
  deleteCharacter: (id) => apiFetch(`/api/characters/${id}`, { method: 'DELETE' }),

  getBackgrounds:   () => apiFetch('/api/backgrounds'),
  createBackground: (d) => apiFetch('/api/backgrounds', { method: 'POST', body: JSON.stringify(d) }),
  updateBackground: (id, d) => apiFetch(`/api/backgrounds/${id}`, { method: 'PUT', body: JSON.stringify(d) }),
  deleteBackground: (id) => apiFetch(`/api/backgrounds/${id}`, { method: 'DELETE' }),

  uploadFile: async (file, type) => {
    const fd = new FormData();
    fd.append('file', file);
    const res = await fetch(`/api/upload/${type}`, { method: 'POST', body: fd });
    if (!res.ok) throw new Error('Upload failed');
    return res.json();
  },

  getStory:   () => apiFetch('/api/story'),
  saveStory:  (d) => apiFetch('/api/story', { method: 'POST', body: JSON.stringify(d) }),
  importJson: (d) => apiFetch('/api/import/json', { method: 'POST', body: JSON.stringify(d) }),

  getLocales:   () => apiFetch('/api/locales'),
  saveLocales:  (d) => apiFetch('/api/locales', { method: 'POST', body: JSON.stringify(d) }),

  getBgmList:  () => apiFetch('/api/bgm'),
  deleteBgm:   (file) => apiFetch('/api/bgm/' + encodeURIComponent(file), { method: 'DELETE' }),

  exportLocale: (lang) => fetch('/api/export/locale/' + encodeURIComponent(lang)).then(r => r.json()),
  importLocale: (lang, nodes) => apiFetch('/api/import/locale', { method: 'POST', body: JSON.stringify({ lang, nodes }) }),
};

function showToast(msg, type = '') {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast show ' + type;
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.className = 'toast', 2500);
}

function openModal(title, bodyHtml, footerHtml = '', opts = {}) {
  document.getElementById('modal-title').textContent = title;
  document.getElementById('modal-body').innerHTML = bodyHtml;
  document.getElementById('modal-footer').innerHTML = footerHtml;
  document.getElementById('modal').classList.toggle('modal-wide', !!opts.wide);
  document.getElementById('modal-overlay').style.display = 'flex';
}
function closeModal() { document.getElementById('modal-overlay').style.display = 'none'; }
document.getElementById('modal-close').addEventListener('click', closeModal);
document.getElementById('modal-overlay').addEventListener('click', e => {
  if (e.target === document.getElementById('modal-overlay')) closeModal();
});
