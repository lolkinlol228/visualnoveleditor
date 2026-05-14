document.addEventListener('DOMContentLoaded', async () => {
  // Tabs
  document.querySelectorAll('.nav-btn[data-tab]').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(s => s.classList.remove('active'));
      btn.classList.add('active');
      document.getElementById('tab-' + btn.dataset.tab)?.classList.add('active');
    });
  });

  // Add buttons
  document.getElementById('btn-add-char').addEventListener('click', () => Characters.createChar());
  document.getElementById('btn-add-bg').addEventListener('click', () => Backgrounds.createBg());

  // BGM upload zone
  const bgmZone  = document.getElementById('bgm-upload-zone');
  const bgmInput = document.getElementById('bgm-upload-input');
  if (bgmZone && bgmInput) {
    bgmZone.addEventListener('click', () => bgmInput.click());
    bgmZone.addEventListener('dragover', e => { e.preventDefault(); bgmZone.classList.add('drag-over'); });
    bgmZone.addEventListener('dragleave', () => bgmZone.classList.remove('drag-over'));
    bgmZone.addEventListener('drop', async e => {
      e.preventDefault(); bgmZone.classList.remove('drag-over');
      await uploadBgmFiles(e.dataTransfer.files);
    });
    bgmInput.addEventListener('change', async e => {
      await uploadBgmFiles(e.target.files);
      bgmInput.value = '';
    });
  }

  // Init data modules
  await Promise.all([Locales.load(), BGM.load(), Characters.load(), Backgrounds.load()]);

  // Init node editor (needs chars/bgs loaded first)
  NodeEditor.init();
  await NodeEditor.loadStory();

  BGM.initPlayer();
  BGM.render();

  // ---- Locale management UI ----
  renderLocalesList();

  const localeInput = document.getElementById('locale-new-input');
  const btnAddLocale = document.getElementById('btn-add-locale');

  if (btnAddLocale) {
    btnAddLocale.addEventListener('click', async () => {
      const code = localeInput?.value.trim();
      if (!code) return;
      const added = await Locales.addLocale(code);
      if (added) {
        if (localeInput) localeInput.value = '';
        renderLocalesList();
        showToast('Язык добавлен: ' + code.toUpperCase(), 'success');
      } else {
        showToast('Такой язык уже есть или код некорректен', 'error');
      }
    });
    localeInput?.addEventListener('keydown', e => {
      if (e.key === 'Enter') btnAddLocale.click();
    });
  }
});

async function uploadBgmFiles(fileList) {
  let ok = 0;
  for (const file of fileList) {
    if (!/\.(mp3|ogg|wav|flac)$/i.test(file.name)) continue;
    try {
      await api.uploadFile(file, 'bgm');
      ok++;
    } catch (e) { showToast('Ошибка: ' + e.message, 'error'); }
  }
  if (ok > 0) {
    await BGM.load();
    BGM.render();
    showToast('Загружено: ' + ok + ' трек(ов)', 'success');
  }
}

function renderLocalesList() {
  const list = document.getElementById('locales-list');
  const tags = document.getElementById('locales-tags');
  const locs = Locales.getList();

  if (list) {
    if (locs.length === 0) {
      list.innerHTML = '<div class="empty-state">Нет языков</div>';
    } else {
      list.innerHTML = locs.map(l => `
        <div class="item-card locale-item" data-locale="${escH(l)}" style="display:flex;align-items:center;gap:6px">
          <div style="flex:1">
            <div class="item-card-name">${escH(l.toUpperCase())}</div>
            <div class="item-card-sub">${escH(l)}</div>
          </div>
          <button class="btn-secondary btn-sm locale-export-btn" data-locale="${escH(l)}" title="Скачать файл для перевода"><i class="ph ph-download-simple"></i></button>
          <button class="btn-secondary btn-sm locale-import-btn" data-locale="${escH(l)}" title="Загрузить перевод"><i class="ph ph-upload-simple"></i></button>
          <button class="btn-icon danger locale-del-btn" data-locale="${escH(l)}" title="Удалить язык"><i class="ph ph-trash"></i></button>
          <input type="file" class="locale-import-file" data-locale="${escH(l)}" accept=".json" style="display:none">
        </div>
      `).join('');

      // Export buttons
      list.querySelectorAll('.locale-export-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
          const lang = btn.dataset.locale;
          try {
            const data = await api.exportLocale(lang);
            const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
            const url  = URL.createObjectURL(blob);
            const a    = document.createElement('a');
            a.href = url; a.download = `locale_${lang}.json`; a.click();
            URL.revokeObjectURL(url);
            showToast(`Экспортировано ${data.nodes.length} нод для ${lang.toUpperCase()}`, 'success');
          } catch (e) { showToast('Ошибка: ' + e.message, 'error'); }
        });
      });

      // Import buttons
      list.querySelectorAll('.locale-import-btn').forEach(btn => {
        const lang  = btn.dataset.locale;
        const input = list.querySelector(`.locale-import-file[data-locale="${lang}"]`);
        btn.addEventListener('click', () => input?.click());
        input?.addEventListener('change', async e => {
          const file = e.target.files[0]; if (!file) return;
          try {
            const text = await file.text();
            const data = JSON.parse(text);
            const nodes = data.nodes || data; // accept both {lang,nodes} and bare array
            const res  = await api.importLocale(lang, nodes);
            showToast(`Импортировано переводов: ${res.count} для ${lang.toUpperCase()}`, 'success');
          } catch (e) { showToast('Ошибка импорта: ' + e.message, 'error'); }
          input.value = '';
        });
      });

      // Delete buttons
      list.querySelectorAll('.locale-del-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
          await Locales.removeLocale(btn.dataset.locale);
          renderLocalesList();
          showToast('Язык удалён', 'success');
        });
      });
    }
  }

  if (tags) {
    tags.innerHTML = locs.map(l => `
      <span class="locale-tag-pill">
        ${escH(l.toUpperCase())}
        <button class="locale-tag-del" data-locale="${escH(l)}" title="Удалить язык">
          <i class="ph ph-x"></i>
        </button>
      </span>
    `).join('');

    tags.querySelectorAll('.locale-tag-del').forEach(btn => {
      btn.addEventListener('click', async () => {
        await Locales.removeLocale(btn.dataset.locale);
        renderLocalesList();
        showToast('Язык удалён', 'success');
      });
    });
  }
}
