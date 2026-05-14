// BGM module — manages list of uploaded background music files
const BGM = (() => {
  let files = []; // [{ file, name, url }]

  async function load() {
    try { files = await api.getBgmList(); if (!Array.isArray(files)) files = []; }
    catch { files = []; }
  }

  function getAll() { return files; }

  // Build <option> elements for a BGM selector
  // selectedUrl: current node.bgm_url value
  function buildSelect(selectedUrl) {
    const opts = [`<option value="">— музыка без изменений —</option>`,
                  `<option value="__stop__"${selectedUrl === '__stop__' ? ' selected' : ''}>⏹ Остановить музыку</option>`];
    files.forEach(f => {
      opts.push(`<option value="${escH(f.url)}"${f.url === selectedUrl ? ' selected' : ''}>${escH(f.name || f.file)}</option>`);
    });
    return opts.join('');
  }

  let previewAudio = null;

  function render() {
    const el = document.getElementById('bgm-list');
    if (!el) return;
    if (files.length === 0) {
      el.innerHTML = '<div class="empty-state">Нет треков — загрузите mp3 / ogg / wav</div>';
      return;
    }
    el.innerHTML = files.map(f => `
      <div class="item-card bgm-track-card" data-url="${escH(f.url)}" data-file="${escH(f.file)}">
        <button class="btn-icon neutral bgm-prev-btn" title="Воспроизвести/Пауза"><i class="ph ph-play"></i></button>
        <div style="flex:1;min-width:0">
          <div class="item-card-name" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${escH(f.name || f.file)}</div>
          <div class="item-card-sub">${escH(f.file)}</div>
        </div>
        <button class="btn-icon danger bgm-del-btn" data-file="${escH(f.file)}" title="Удалить"><i class="ph ph-trash"></i></button>
      </div>
    `).join('');

    el.querySelectorAll('.bgm-prev-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const card = btn.closest('.bgm-track-card');
        const url  = card.dataset.url;
        const icon = btn.querySelector('i');
        if (previewAudio && previewAudio._url === url) {
          if (previewAudio.paused) { previewAudio.play(); icon.className = 'ph ph-pause'; }
          else { previewAudio.pause(); icon.className = 'ph ph-play'; }
        } else {
          if (previewAudio) previewAudio.pause();
          el.querySelectorAll('.bgm-prev-btn i').forEach(i => i.className = 'ph ph-play');
          previewAudio = new Audio(url);
          previewAudio._url = url;
          previewAudio.play().catch(() => {});
          icon.className = 'ph ph-pause';
          previewAudio.onended = () => { icon.className = 'ph ph-play'; };
        }
      });
    });

    el.querySelectorAll('.bgm-del-btn').forEach(btn => {
      btn.addEventListener('click', async () => {
        if (!confirm('Удалить трек?')) return;
        try {
          if (previewAudio) { previewAudio.pause(); previewAudio = null; }
          await api.deleteBgm(btn.dataset.file);
          await load();
          render();
          showToast('Трек удалён', 'success');
        } catch (e) { showToast('Ошибка: ' + e.message, 'error'); }
      });
    });
  }

  return { load, getAll, buildSelect, render };
})();
