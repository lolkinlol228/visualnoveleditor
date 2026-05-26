const Backgrounds = (() => {
  let bgs = [];
  let selectedId = null;

  async function load() {
    bgs = await api.getBackgrounds();
    renderList();
    if (selectedId) {
      const b = bgs.find(x => x.id === selectedId);
      if (b) renderEditor(b); else { selectedId = null; clearEditor(); }
    }
  }

  function renderList() {
    const el = document.getElementById('bg-list');
    el.innerHTML = '';
    if (!bgs.length) { el.innerHTML = '<div class="empty-state">Нет фонов</div>'; return; }
    bgs.forEach(b => {
      const d = document.createElement('div');
      d.className = 'item-card' + (b.id === selectedId ? ' selected' : '');
      d.innerHTML = `<div class="item-card-name">${esc(b.name || 'Без имени')}</div>
        <div class="item-card-sub">${esc(b.description || '')}</div>`;
      d.addEventListener('click', () => { selectedId = b.id; renderList(); renderEditor(b); });
      el.appendChild(d);
    });
  }

  function clearEditor() {
    document.getElementById('bg-editor').innerHTML = '<div class="empty-state">Выберите фон или создайте новый</div>';
  }

  function renderEditor(b) {
    const el = document.getElementById('bg-editor');
    el.innerHTML = `
      ${b.url
        ? `<img class="bg-preview" src="${b.url}" alt="">`
        : `<div class="bg-placeholder" id="bg-upload-zone">Нажмите для загрузки изображения</div>`}
      ${b.url ? `<div class="bg-placeholder" id="bg-upload-zone" style="height:48px">Заменить изображение</div>` : ''}
      <div class="form-group">
        <label class="form-label">Название</label>
        <input class="form-input" id="bf-name" value="${esc(b.name||'')}">
      </div>
      <div class="form-group">
        <label class="form-label">Описание</label>
        <textarea class="form-textarea" id="bf-desc" rows="3">${esc(b.description||'')}</textarea>
      </div>
      <div class="row-btns">
        <button class="btn-primary" id="bf-save">Сохранить</button>
        <button class="btn-danger btn-sm" id="bf-delete">Удалить</button>
      </div>
    `;
    document.getElementById('bg-upload-zone')?.addEventListener('click', () => uploadBg(b));
    document.getElementById('bf-save').addEventListener('click', () => saveBg(b));
    document.getElementById('bf-delete').addEventListener('click', () => deleteBg(b));
  }

  async function uploadBg(b) {
    const input = document.createElement('input');
    input.type = 'file'; input.accept = 'image/*';
    input.onchange = async () => {
      const file = input.files[0]; if (!file) return;
      try {
        const res = await api.uploadFile(file, 'backgrounds');
        b.url = res.url;
        await api.updateBackground(b.id, b);
        bgs = bgs.map(x => x.id === b.id ? b : x);
        renderEditor(b);
        showToast('Загружено', 'success');
      } catch(e) { showToast('Ошибка: ' + e.message, 'error'); }
    };
    input.click();
  }

  async function saveBg(b) {
    b.name = document.getElementById('bf-name').value.trim();
    b.description = document.getElementById('bf-desc').value.trim();
    await api.updateBackground(b.id, b);
    bgs = bgs.map(x => x.id === b.id ? b : x);
    renderList();
    showToast('Сохранено', 'success');
  }

  async function deleteBg(b) {
    if (!confirm(`Удалить "${b.name}"?`)) return;
    await api.deleteBackground(b.id);
    selectedId = null;
    await load();
    clearEditor();
    showToast('Удалено');
  }

  async function createBg() {
    const b = await api.createBackground({ name: 'Новый фон', description: '' });
    bgs.push(b);
    selectedId = b.id;
    renderList();
    renderEditor(b);
  }

  function esc(s) {
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  return { load, createBg, getAll: () => bgs };
})();
