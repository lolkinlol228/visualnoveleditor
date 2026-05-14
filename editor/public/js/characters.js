const Characters = (() => {
  let chars = [];
  let selectedId = null;

  async function load() {
    chars = await api.getCharacters();
    renderList();
    if (selectedId) {
      const c = chars.find(x => x.id === selectedId);
      if (c) renderEditor(c); else { selectedId = null; clearEditor(); }
    }
  }

  function renderList() {
    const el = document.getElementById('char-list');
    el.innerHTML = '';
    if (!chars.length) {
      el.innerHTML = '<div class="empty-state">Нет персонажей</div>';
      return;
    }
    chars.forEach(c => {
      const d = document.createElement('div');
      d.className = 'item-card' + (c.id === selectedId ? ' selected' : '');
      d.innerHTML = `<div class="item-card-name">${esc(c.name || 'Без имени')}</div>
        <div class="item-card-sub">${(c.arts || []).length} арт(ов)</div>`;
      d.addEventListener('click', () => { selectedId = c.id; load(); renderEditor(c); });
      el.appendChild(d);
    });
  }

  function clearEditor() {
    document.getElementById('char-editor').innerHTML = '<div class="empty-state">Выберите персонажа или создайте нового</div>';
  }

  function renderEditor(c) {
    const el = document.getElementById('char-editor');
    el.innerHTML = `
      <div class="form-group">
        <label class="form-label">Полное имя / ФИО</label>
        <input class="form-input" id="cf-name" value="${esc(c.name||'')}">
      </div>
      <div class="form-group">
        <label class="form-label">Описание персонажа</label>
        <textarea class="form-textarea" id="cf-desc" rows="3">${esc(c.description||'')}</textarea>
      </div>
      <div class="form-group">
        <label class="form-label">Прочие данные (возраст, роль и т.д.)</label>
        <input class="form-input" id="cf-meta" value="${esc(c.meta||'')}">
      </div>
      <div class="char-section-title">Арты / Эмоции</div>
      <div class="arts-grid" id="arts-grid"></div>
      <div class="upload-zone" id="art-upload-zone">
        <div>+ Добавить арт</div>
        <div style="font-size:11px;margin-top:4px;color:var(--text2)">PNG, JPG, WebP</div>
      </div>
      <div class="row-btns" style="margin-top:16px">
        <button class="btn-primary" id="cf-save">Сохранить</button>
        <button class="btn-danger btn-sm" id="cf-delete">Удалить персонажа</button>
      </div>
    `;
    renderArts(c);

    document.getElementById('art-upload-zone').addEventListener('click', () => promptArtUpload(c));
    document.getElementById('cf-save').addEventListener('click', () => saveChar(c));
    document.getElementById('cf-delete').addEventListener('click', () => deleteChar(c));
  }

  function renderArts(c) {
    const grid = document.getElementById('arts-grid');
    if (!grid) return;
    grid.innerHTML = '';
    (c.arts || []).forEach((art, i) => {
      const d = document.createElement('div');
      d.className = 'art-card';
      d.innerHTML = `
        ${art.url ? `<img src="${art.url}" alt="${esc(art.emotion||'')}">` : '<div style="height:90px;background:var(--bg3)"></div>'}
        <div class="art-body" style="padding:6px">
          <div class="art-card-emotion">${esc(art.emotion || 'Без названия')}</div>
          <div class="art-card-desc">${esc(art.desc || '')}</div>
        </div>
        <button class="art-delete" data-i="${i}">✕</button>
      `;
      d.querySelector('.art-delete').addEventListener('click', () => deleteArt(c, i));
      grid.appendChild(d);
    });
  }

  async function promptArtUpload(c) {
    openModal('Добавить арт', `
      <div class="form-group">
        <label class="form-label">Название эмоции (радость, злость, грусть...)</label>
        <input class="form-input" id="art-emotion" placeholder="нейтральный">
      </div>
      <div class="form-group">
        <label class="form-label">Описание (необязательно)</label>
        <input class="form-input" id="art-desc" placeholder="">
      </div>
      <div class="form-group">
        <label class="form-label">Файл изображения</label>
        <input type="file" id="art-file" accept="image/*" style="color:var(--text);font-size:12px">
      </div>
    `, `<button class="btn-primary" id="art-upload-btn">Загрузить</button>
        <button class="btn-secondary" onclick="closeModal()">Отмена</button>`);

    document.getElementById('art-upload-btn').addEventListener('click', async () => {
      const emotion = document.getElementById('art-emotion').value.trim() || 'нейтральный';
      const desc = document.getElementById('art-desc').value.trim();
      const file = document.getElementById('art-file').files[0];
      let url = null;
      if (file) {
        try {
          const res = await api.uploadFile(file, 'characters');
          url = res.url;
        } catch(e) { showToast('Ошибка загрузки: ' + e.message, 'error'); return; }
      }
      if (!c.arts) c.arts = [];
      c.arts.push({ emotion, desc, url });
      await api.updateCharacter(c.id, c);
      chars = chars.map(x => x.id === c.id ? c : x);
      renderArts(c);
      closeModal();
      showToast('Арт добавлен', 'success');
    });
  }

  async function deleteArt(c, i) {
    c.arts.splice(i, 1);
    await api.updateCharacter(c.id, c);
    chars = chars.map(x => x.id === c.id ? c : x);
    renderArts(c);
  }

  async function saveChar(c) {
    c.name = document.getElementById('cf-name').value.trim();
    c.description = document.getElementById('cf-desc').value.trim();
    c.meta = document.getElementById('cf-meta').value.trim();
    await api.updateCharacter(c.id, c);
    chars = chars.map(x => x.id === c.id ? c : x);
    renderList();
    showToast('Сохранено', 'success');
  }

  async function deleteChar(c) {
    if (!confirm(`Удалить "${c.name}"?`)) return;
    await api.deleteCharacter(c.id);
    selectedId = null;
    await load();
    clearEditor();
    showToast('Удалено');
  }

  async function createChar() {
    const c = await api.createCharacter({ name: 'Новый персонаж', description: '', meta: '', arts: [] });
    chars.push(c);
    selectedId = c.id;
    renderList();
    renderEditor(c);
  }

  function esc(s) {
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  return { load, createChar, getAll: () => chars };
})();
