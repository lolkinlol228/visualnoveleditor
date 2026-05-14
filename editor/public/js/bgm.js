// BGM module — track library + global editor player
const BGM = (() => {
  let files = [];

  // ---- Library ----

  async function load() {
    try { files = await api.getBgmList(); if (!Array.isArray(files)) files = []; }
    catch { files = []; }
  }

  function getAll() { return files; }

  function buildSelect(selectedUrl) {
    const opts = [
      `<option value="">— музыка без изменений —</option>`,
      `<option value="__stop__"${selectedUrl === '__stop__' ? ' selected' : ''}>⏹ Остановить музыку</option>`
    ];
    files.forEach(f => {
      opts.push(`<option value="${escH(f.url)}"${f.url === selectedUrl ? ' selected' : ''}>${escH(f.name || f.file)}</option>`);
    });
    return opts.join('');
  }

  // ---- Global player (topnav) ----

  let audio       = null;   // HTMLAudioElement
  let currentUrl  = '';     // url currently loaded / playing
  let isPlaying   = false;
  let volume      = 0.8;

  function _trackName(url) {
    if (!url || url === '__stop__') return '— нет трека —';
    const f = files.find(f => f.url === url);
    return f ? (f.name || f.file) : url.split('/').pop();
  }

  function _updateUI() {
    const btn  = document.getElementById('bgm-global-play');
    const name = document.getElementById('bgm-global-name');
    const wrap = document.getElementById('bgm-player-global');
    if (name) name.textContent = _trackName(currentUrl);
    if (btn)  btn.querySelector('i').className = isPlaying ? 'ph ph-pause' : 'ph ph-play';
    if (wrap) wrap.classList.toggle('is-playing', isPlaying);
  }

  // Called when user selects a node — mirrors game BGM logic
  function setNodeBgm(url) {
    if (!url) return;                 // empty = inherit, keep playing
    if (url === '__stop__') {
      if (audio) { audio.pause(); audio = null; }
      currentUrl = '';
      isPlaying  = false;
      _updateUI();
      return;
    }
    if (url === currentUrl) return;   // same track — don't restart
    currentUrl = url;
    if (isPlaying) {
      if (audio) audio.pause();
      audio = new Audio(url);
      audio.volume = volume;
      audio.loop   = true;
      audio.play().catch(() => {});
    }
    _updateUI();
  }

  function play() {
    if (!currentUrl) return;
    if (!audio) {
      audio = new Audio(currentUrl);
      audio.volume = volume;
      audio.loop   = true;
    }
    audio.play().catch(() => {});
    isPlaying = true;
    _updateUI();
  }

  function pause() {
    if (audio) audio.pause();
    isPlaying = false;
    _updateUI();
  }

  function setVolume(v) {
    volume = v;
    if (audio) audio.volume = v;
  }

  function initPlayer() {
    const playBtn = document.getElementById('bgm-global-play');
    const volEl   = document.getElementById('bgm-global-volume');
    if (playBtn) {
      playBtn.addEventListener('click', () => {
        if (isPlaying) pause(); else play();
      });
    }
    if (volEl) {
      volEl.value = volume;
      volEl.addEventListener('input', () => setVolume(parseFloat(volEl.value)));
    }
    _updateUI();
  }

  // ---- BGM tab list render ----

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
          else                     { previewAudio.pause(); icon.className = 'ph ph-play'; }
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

  return { load, getAll, buildSelect, setNodeBgm, initPlayer, render };
})();
