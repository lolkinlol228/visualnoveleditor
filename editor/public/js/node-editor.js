const NodeEditor = (() => {
  const NODE_W = 240;
  let nodes = [];
  let edges = [];
  let selectedNodeId = null;
  let camera = { x: 80, y: 80, zoom: 1 };
  let dragging = null;
  let panning = false;
  let panStart = null;
  let spaceDown = false;
  let connectStart = null;
  let dragMousePos = { x: 0, y: 0 };

  let canvasWrapper, canvasWorld, svgOverlay, svgConnections, svgDragLine, dragPath;

  function init() {
    canvasWrapper  = document.getElementById('canvas-wrapper');
    canvasWorld    = document.getElementById('canvas-world');
    svgOverlay     = document.getElementById('svg-overlay');
    svgConnections = document.getElementById('svg-connections');
    svgDragLine    = document.getElementById('svg-drag-line');
    dragPath       = document.getElementById('drag-path');
    applyCamera();
    bindEvents();
  }

  // ---- Camera ----
  function applyCamera() {
    canvasWorld.style.transform = `translate(${camera.x}px,${camera.y}px) scale(${camera.zoom})`;
    canvasWorld.style.transformOrigin = '0 0';
    svgOverlay.style.transform = `translate(${camera.x + 5000}px,${camera.y + 5000}px) scale(${camera.zoom})`;
    svgOverlay.style.transformOrigin = '0 0';
  }

  function screenToWorld(sx, sy) {
    const rect = canvasWrapper.getBoundingClientRect();
    return {
      x: (sx - rect.left - camera.x) / camera.zoom,
      y: (sy - rect.top  - camera.y) / camera.zoom
    };
  }

  // ---- Port world positions ----
  function getPortPos(nodeId, portType, choiceIndex) {
    const node = nodes.find(n => n.id === nodeId);
    if (!node) return null;
    const el = document.getElementById('node-' + nodeId);
    if (!el) return null;
    const body = el.querySelector('.node-body');
    const bodyTop = body ? body.offsetTop : 0;
    const bodyH   = body ? body.offsetHeight : el.offsetHeight;
    const portY   = node.y + bodyTop + bodyH / 2;

    if (portType === 'in')  return { x: node.x,          y: portY };
    if (portType === 'out') return { x: node.x + NODE_W, y: portY };
    if (portType === 'choice') {
      const portEls = el.querySelectorAll('.port-choice');
      const pe = portEls[choiceIndex];
      if (!pe) return { x: node.x + NODE_W, y: portY };
      let cx = pe.offsetWidth / 2, cy = pe.offsetHeight / 2;
      let e = pe;
      while (e && e !== canvasWorld) { cx += e.offsetLeft; cy += e.offsetTop; e = e.offsetParent; }
      return { x: cx, y: cy };
    }
    return null;
  }

  // ---- Render ----
  function render() { renderNodes(); renderEdges(); renderProps(); }

  function renderNodes() {
    [...canvasWorld.children].forEach(el => {
      if (!nodes.find(n => 'node-' + n.id === el.id)) el.remove();
    });
    nodes.forEach(n => {
      let el = document.getElementById('node-' + n.id);
      if (!el) {
        el = buildNodeEl(n);
        canvasWorld.appendChild(el);
      } else {
        el.style.left = n.x + 'px';
        el.style.top  = n.y + 'px';
        el.classList.toggle('selected', n.id === selectedNodeId);
        updateNodeContent(el, n);
      }
    });
  }

  function buildNodeEl(n) {
    const el = document.createElement('div');
    el.id = 'node-' + n.id;
    el.className = `vn-node node-${n.type}` + (n.id === selectedNodeId ? ' selected' : '');
    el.style.left = n.x + 'px';
    el.style.top  = n.y + 'px';
    el.style.width = NODE_W + 'px';
    buildNodeContent(el, n);
    bindNodeEvents(el, n);
    return el;
  }

  function typeLabel(t) {
    const icons = {
      start:       '<i class="ph ph-play"></i> Старт',
      dialog:      '<i class="ph ph-chat-text"></i> Диалог',
      choice:      '<i class="ph ph-git-fork"></i> Выбор',
      scene:       '<i class="ph ph-film-strip"></i> Сцена',
      end:         '<i class="ph ph-stop-circle"></i> Конец',
      chapter:     '<i class="ph ph-book-open-text"></i> Глава',
      set_flag:    '<i class="ph ph-flag"></i> Флаг',
      branch_flag: '<i class="ph ph-shuffle"></i> Ветвление',
      achievement: '<i class="ph ph-trophy"></i> Ачивка',
      gallery_cg:  '<i class="ph ph-image"></i> CG',
    };
    return icons[t] || t;
  }

  // ---- Schema migration ----
  function migrateNode(n) {
    if (!Array.isArray(n.stage)) n.stage = [];
    if (n.character_id) {
      const exists = n.stage.find(s => s.character_id === n.character_id);
      if (!exists) n.stage.push({ character_id: n.character_id, emotion: n.emotion || '', x: 50, scale: 80 });
      if (n.type === 'dialog' && !n.speaker_id) n.speaker_id = n.character_id;
      delete n.character_id; delete n.emotion;
    }
    n.stage.forEach(s => { if (!('scale' in s)) s.scale = 80; });
    if (['dialog', 'choice', 'scene'].includes(n.type) && !('speaker_id' in n)) n.speaker_id = '';
    return n;
  }

  function renderStagePreview(n) {
    if (!n.stage || n.stage.length === 0) return '';
    const chars = Characters.getAll();
    const chips = n.stage.map(s => {
      const c = chars.find(x => x.id === s.character_id);
      const name = c ? c.name : '?';
      const emo = s.emotion ? ':' + s.emotion : '';
      const isSpeaker = n.type === 'dialog' && s.character_id && s.character_id === n.speaker_id;
      return `<span class="stage-chip${isSpeaker ? ' speaker' : ''}">${escH(name)}${escH(emo)}</span>`;
    }).join('');
    return `<div class="node-stage-chips">${chips}</div>`;
  }

  function renderStageVisual(n) {
    const chars = Characters.getAll();
    const bgs   = Backgrounds.getAll();
    const bg    = bgs.find(b => b.id === n.background_id);
    const bgStyle = bg && bg.url ? `background-image:url('${bg.url}')` : '';

    const items = (n.stage || []).map((s, i) => {
      const c = chars.find(x => x.id === s.character_id);
      let imgUrl = null;
      if (c && Array.isArray(c.arts) && c.arts.length) {
        const art = c.arts.find(a => a.emotion === s.emotion) || c.arts[0];
        if (art && art.url) imgUrl = art.url;
      }
      const isSpeaker = n.type === 'dialog' && s.character_id && s.character_id === n.speaker_id;
      const label = c ? c.name : '?';
      const xPct  = Math.max(0, Math.min(100, Number(s.x) || 0));
      const scPct = Math.max(20, Math.min(150, Number(s.scale) || 80));
      const inner = imgUrl ? `<img src="${imgUrl}" draggable="false" alt="">` : `<div class="stage-vis-placeholder">?</div>`;
      return `<div class="stage-vis-char${isSpeaker ? ' speaker' : ''}" data-si="${i}" style="left:${xPct}%;height:${scPct}%" title="Тащи влево/вправо">
        ${inner}<div class="stage-vis-label">${escH(label)}${s.emotion ? ' · ' + escH(s.emotion) : ''}</div>
      </div>`;
    }).join('');

    const empty = (!n.stage || n.stage.length === 0) ? '<div class="stage-vis-empty">— сцена пуста —</div>' : '';
    return `<div class="stage-visual" style="${bgStyle}">${empty}${items}
      <div class="stage-vis-floor"></div>
      <div class="stage-vis-ruler">
        <span style="left:0%">0</span><span style="left:25%">25</span>
        <span style="left:50%">50</span><span style="left:75%">75</span><span style="left:100%">100</span>
      </div></div>`;
  }

  function buildNodeContent(el, n)  { el.innerHTML = buildNodeHTML(n); bindPortEvents(el, n); }
  function updateNodeContent(el, n) {
    el.innerHTML = buildNodeHTML(n);
    el.className = `vn-node node-${n.type}` + (n.id === selectedNodeId ? ' selected' : '');
    bindPortEvents(el, n);
    bindNodeEvents(el, n);
  }

  function buildNodeHTML(n) {
    const chars = Characters.getAll();
    let body = '';
    const locText = (key) => Locales.getText(n, key);

    if (n.type === 'start') {
      body = `<div class="node-preview">Начало истории</div>`;
    } else if (n.type === 'end') {
      const eName = Locales.getText(n, 'ending_name');
      body = `<div class="node-preview">${escH(eName || n.ending_id || 'Конец истории')}</div>`;
    } else if (n.type === 'dialog') {
      const speaker = chars.find(c => c.id === n.speaker_id);
      const displayText = locText('text');
      body = `${renderStagePreview(n)}
        <div class="node-char-name">${speaker ? escH(speaker.name) : '<span style="color:var(--text2)">— говорящий не выбран —</span>'}</div>
        <div class="node-preview">${escH(displayText || '...')}</div>`;
    } else if (n.type === 'choice') {
      const choicesText = Locales.getChoicesText(n);
      const items = (n.choices || []).map((c, i) => `
        <li><span class="choice-label">${escH(choicesText[i] || c.text || '...')}</span>
        <span class="port port-out port-choice" data-node="${n.id}" data-port="choice" data-ci="${i}"></span></li>`).join('');
      body = `${renderStagePreview(n)}
        <div class="node-preview" style="margin-bottom:6px">${escH(locText('question') || n.question || 'Вопрос...')}</div>
        <ul class="node-choice-list">${items}</ul>`;
    } else if (n.type === 'scene') {
      body = `${renderStagePreview(n)}<div class="node-preview" style="color:var(--text2)">Обновление сцены (auto-skip)</div>`;
    } else if (n.type === 'chapter') {
      body = `<div class="node-preview" style="font-weight:600;color:var(--text)">${escH(locText('title') || n.title || '— Заголовок главы —')}</div>`;
    } else if (n.type === 'set_flag') {
      body = `<div class="node-preview" style="font-family:monospace">${escH(n.flag_name || '?')} = <strong>${escH(n.flag_value || '')}</strong></div>`;
    } else if (n.type === 'branch_flag') {
      const fn = escH(n.flag_name || '?'), fv = escH(n.flag_value || 'true');
      body = `<ul class="node-choice-list node-branch-list">
        <li><span class="choice-label">${fn} == ${fv}</span><span class="port port-out port-choice port-branch" data-node="${n.id}" data-port="choice" data-ci="0"></span></li>
        <li><span class="choice-label">Иначе</span><span class="port port-out port-choice port-branch" data-node="${n.id}" data-port="choice" data-ci="1"></span></li>
      </ul>`;
    } else if (n.type === 'achievement') {
      body = `<div class="node-preview">${escH(locText('achievement_name') || n.achievement_id || '— без названия —')}</div>`;
    } else if (n.type === 'gallery_cg') {
      body = `<div class="node-preview">${escH(locText('cg_name') || n.cg_id || '— CG изображение —')}</div>`;
    }

    const hasIn  = n.type !== 'start';
    const hasOut = !['end', 'choice', 'branch_flag'].includes(n.type);

    return `<div class="node-header">${typeLabel(n.type)}<span class="node-id">#${n.id.slice(-4)}</span></div>
      <div class="node-body" style="position:relative">
        ${hasIn  ? `<span class="port port-in"  data-node="${n.id}" data-port="in"></span>` : ''}
        ${hasOut ? `<span class="port port-out" data-node="${n.id}" data-port="out"></span>` : ''}
        ${body}
      </div>`;
  }

  function bindNodeEvents(el, n) {
    const header = el.querySelector('.node-header');
    if (!header) return;
    header.addEventListener('mousedown', e => {
      if (e.button !== 0) return;
      e.stopPropagation();
      selectNode(n.id);
      dragging = { nodeId: n.id, startNodeX: n.x, startNodeY: n.y, startMouseX: e.clientX, startMouseY: e.clientY };
    });
    el.addEventListener('mousedown', e => {
      if (e.target.classList.contains('port')) return;
      if (e.button === 0) selectNode(n.id);
    });
  }

  function bindPortEvents(el, n) {
    el.querySelectorAll('.port').forEach(port => {
      port.addEventListener('mousedown', e => {
        e.stopPropagation();
        const nodeId   = port.dataset.node;
        const portType = port.dataset.port;
        const ci = port.dataset.ci !== undefined ? parseInt(port.dataset.ci) : undefined;
        if (connectStart) {
          finishConnect(nodeId, portType, ci);
        } else {
          connectStart = { nodeId, portType, choiceIndex: ci };
          canvasWrapper.classList.add('connecting');
        }
      });
    });
  }

  function finishConnect(toNodeId, toPortType, toChoiceIndex) {
    const from = connectStart;
    connectStart = null;
    canvasWrapper.classList.remove('connecting');
    svgDragLine.style.display = 'none';

    let fromNodeId, fromPortType, fromChoiceIndex, toNId;

    if (from.portType === 'in') {
      if (toPortType === 'in') return;
      fromNodeId = toNodeId; fromPortType = toPortType; fromChoiceIndex = toChoiceIndex;
      toNId = from.nodeId;
    } else {
      if (toPortType !== 'in') return;
      fromNodeId = from.nodeId; fromPortType = from.portType; fromChoiceIndex = from.choiceIndex;
      toNId = toNodeId;
    }

    if (fromNodeId === toNId) return;

    edges = edges.filter(e => !(e.fromNode === fromNodeId && e.fromPort === fromPortType && e.choiceIndex === fromChoiceIndex));
    edges = edges.filter(e => e.toNode !== toNId);
    edges.push({ fromNode: fromNodeId, fromPort: fromPortType, choiceIndex: fromChoiceIndex, toNode: toNId });

    // Auto-inherit stage+bg: only for visual node types, only when dest is empty
    const stageTypes = ['dialog', 'choice', 'scene'];
    const srcNode  = nodes.find(n => n.id === fromNodeId);
    const destNode = nodes.find(n => n.id === toNId);
    if (srcNode && destNode && stageTypes.includes(srcNode.type) && stageTypes.includes(destNode.type)) {
      const destEmpty = (!destNode.stage || destNode.stage.length === 0) && !destNode.background_id;
      if (destEmpty) {
        destNode.stage = JSON.parse(JSON.stringify(srcNode.stage || []));
        destNode.background_id = srcNode.background_id || '';
        destNode.bgm_url = srcNode.bgm_url || '';
        const destEl = document.getElementById('node-' + destNode.id);
        if (destEl) updateNodeContent(destEl, destNode);
        if (selectedNodeId === destNode.id) renderProps();
      }
    }

    renderEdges();
    autoSave();
  }

  // ---- Edges ----
  function renderEdges() {
    svgConnections.innerHTML = '';
    edges.forEach(e => {
      const from = getPortPos(e.fromNode, e.fromPort, e.choiceIndex);
      const to   = getPortPos(e.toNode, 'in');
      if (!from || !to) return;
      const el = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      el.setAttribute('d', makePath(from.x, from.y, to.x, to.y));
      el.setAttribute('stroke', '#7c6af7');
      el.setAttribute('stroke-width', '2');
      el.setAttribute('fill', 'none');
      el.setAttribute('marker-end', 'url(#arrowhead)');
      el.style.pointerEvents = 'stroke';
      el.style.cursor = 'pointer';
      el.addEventListener('click', () => { edges = edges.filter(x => x !== e); renderEdges(); autoSave(); });
      svgConnections.appendChild(el);
    });
  }

  function makePath(x1, y1, x2, y2) {
    const dx = Math.max(Math.abs(x2 - x1) * 0.5, 80);
    return `M ${x1} ${y1} C ${x1 + dx} ${y1}, ${x2 - dx} ${y2}, ${x2} ${y2}`;
  }

  // ---- Selection & Props ----
  function selectNode(id) {
    selectedNodeId = id;
    nodes.forEach(n => document.getElementById('node-' + n.id)?.classList.toggle('selected', n.id === id));
    renderProps();
  }

  function renderProps() {
    const panel = document.getElementById('props-panel');
    if (!selectedNodeId) { panel.innerHTML = '<div class="empty-state">Выберите узел</div>'; return; }
    const n = nodes.find(x => x.id === selectedNodeId);
    if (!n) { panel.innerHTML = '<div class="empty-state">Выберите узел</div>'; return; }

    const chars  = Characters.getAll();
    const bgs    = Backgrounds.getAll();
    const bgOpts = bgs.map(b => `<option value="${b.id}" ${b.id === n.background_id ? 'selected' : ''}>${escH(b.name)}</option>`).join('');
    const isLocale = !!Locales.getCurrent();
    const locText  = (key) => Locales.getText(n, key);

    let html = `<div class="props-title">${typeLabel(n.type)}</div>`;
    html += Locales.buildLocaleBar();

    // BGM selector for nodes that have it
    const bgmField = (types) => {
      if (!types.includes(n.type)) return '';
      const curUrl = n.bgm_url || '';
      return `<div class="form-group">
        <label class="form-label"><i class="ph ph-music-note"></i> Музыка</label>
        <div style="display:flex;gap:4px">
          <select class="form-select" id="pf-bgm" style="flex:1">${BGM.buildSelect(curUrl)}</select>
          <button class="btn-secondary btn-sm btn-icon neutral" id="pf-bgm-upload" title="Загрузить mp3/ogg/wav"><i class="ph ph-upload-simple"></i></button>
        </div>
      </div>
      <input type="file" id="pf-bgm-file" accept=".mp3,.ogg,.wav,.flac" style="display:none">`;
    };

    // Notify global player about this node's BGM
    BGM.setNodeBgm(n.bgm_url || '');

    // Background selector helper
    const bgField = () => `<div class="form-group">
      <label class="form-label">Фон</label>
      <select class="form-select" id="pf-bg"><option value="">— нет —</option>${bgOpts}</select>
    </div>`;

    if (n.type === 'start') {
      html += `<div style="color:var(--text2);font-size:12px">Начальный узел. Соедините с первым диалогом.</div>`;

    } else if (n.type === 'end') {
      html += `<div class="props-section-title">Концовка</div>
        <div class="form-group">
          <label class="form-label">ID концовки (для счётчика)</label>
          <input class="form-input" id="pf-ending-id" value="${escH(n.ending_id || '')}" placeholder="ending_good" ${isLocale ? 'disabled' : ''}>
        </div>
        <div class="form-group">
          <label class="form-label">${isLocale ? `Название [${Locales.getCurrent().toUpperCase()}]` : 'Название концовки'}</label>
          <input class="form-input" id="pf-ending-name" value="${escH(locText('ending_name'))}" placeholder="Хорошая концовка">
        </div>`;

    } else if (['dialog', 'choice', 'scene'].includes(n.type)) {
      if (!isLocale) {
        html += bgField();
        html += bgmField(['dialog', 'choice', 'scene']);
      }

      // Stage section (not shown in locale-only mode)
      if (!isLocale) {
        const stageRows = (n.stage || []).map((s, i) => {
          const selChar = chars.find(c => c.id === s.character_id);
          const charOpts = chars.map(c => `<option value="${c.id}" ${c.id === s.character_id ? 'selected' : ''}>${escH(c.name)}</option>`).join('');
          const emoOpts  = selChar ? (selChar.arts || []).map(a => `<option value="${a.emotion}" ${a.emotion === s.emotion ? 'selected' : ''}>${escH(a.emotion)}</option>`).join('') : '';
          const scalVal  = Number(s.scale) || 80;
          const xVal     = Number(s.x) || 0;
          return `<div class="stage-row" data-si="${i}">
            <div class="stage-row-head">
              <select class="form-select stage-char" data-si="${i}"><option value="">— персонаж —</option>${charOpts}</select>
              <select class="form-select stage-emo" data-si="${i}"><option value="">— эмоция —</option>${emoOpts}</select>
              <button class="btn-icon stage-del" data-si="${i}" title="Убрать"><i class="ph ph-trash"></i></button>
            </div>
            <div class="stage-row-sliders">
              <div class="slider-row">
                <span class="slider-lbl">X</span>
                <input type="range" min="0" max="100" step="1" class="stage-x-range" data-si="${i}" value="${xVal}">
                <input type="number" min="0" max="100" step="1" class="stage-num stage-x-num" data-si="${i}" value="${xVal}">
                <span class="slider-unit">%</span>
              </div>
              <div class="slider-row">
                <span class="slider-lbl">Размер</span>
                <input type="range" min="20" max="150" step="5" class="stage-sc-range" data-si="${i}" value="${scalVal}">
                <input type="number" min="20" max="150" step="5" class="stage-num stage-sc-num" data-si="${i}" value="${scalVal}">
                <span class="slider-unit">%</span>
              </div>
            </div>
          </div>`;
        }).join('');

        html += `<div class="props-section-title">Сцена</div>
          ${renderStageVisual(n)}
          <div id="stage-list">${stageRows || '<div style="color:var(--text2);font-size:12px">— пусто —</div>'}</div>
          <button class="btn-secondary btn-sm" id="pf-stage-add" style="width:100%;margin-top:4px"><i class="ph ph-plus"></i> Добавить персонажа</button>
          <button class="btn-primary btn-sm" id="pf-preview" style="width:100%;margin-top:6px"><i class="ph ph-eye"></i> Предпросмотр</button>`;
      }

      if (n.type === 'dialog') {
        if (!isLocale) {
          const speakerOpts = (n.stage || []).filter(s => s.character_id).map(s => {
            const c = chars.find(x => x.id === s.character_id);
            return `<option value="${s.character_id}" ${s.character_id === n.speaker_id ? 'selected' : ''}>${escH(c ? c.name : s.character_id)}</option>`;
          }).join('');
          html += `<div class="form-group" style="margin-top:10px">
            <label class="form-label">Говорящий</label>
            <select class="form-select" id="pf-speaker"><option value="">— нет (рассказчик) —</option>${speakerOpts}</select>
          </div>`;
        }
        html += `<div class="form-group">
          <label class="form-label">${isLocale ? `Текст [${Locales.getCurrent().toUpperCase()}]` : 'Текст реплики'}</label>
          <textarea class="form-textarea" id="pf-text" rows="4">${escH(locText('text'))}</textarea>
        </div>`;
        if (!isLocale) {
          html += `<div class="form-group">
            <label class="checkbox-label"><input type="checkbox" id="pf-nvl" ${n.nvl ? 'checked' : ''}> NVL-режим</label>
            <div class="form-hint">Текст накапливается на экране; очищается при смене фона.</div>
          </div>`;
        }
      } else if (n.type === 'choice') {
        const choicesText = Locales.getChoicesText(n);
        const choicesHtml = (n.choices || []).map((c, i) => `
          <div class="choice-edit-row">
            <input class="form-input choice-text-inp" data-ci="${i}" placeholder="Вариант ответа" value="${escH(choicesText[i] || c.text || '')}">
            ${!isLocale ? `<button class="btn-danger btn-sm" data-del-ci="${i}">✕</button>` : ''}
          </div>`).join('');
        html += `<div class="form-group" style="margin-top:10px">
          <label class="form-label">${isLocale ? `Вопрос [${Locales.getCurrent().toUpperCase()}]` : 'Текст вопроса'}</label>
          <textarea class="form-textarea" id="pf-question" rows="2">${escH(locText('question') || n.question || '')}</textarea>
        </div>
        <div class="props-section-title">Варианты</div>
        <div id="choices-list">${choicesHtml}</div>
        ${!isLocale ? `<button class="btn-secondary btn-sm" id="pf-add-choice" style="width:100%;margin-top:4px">+ Добавить вариант</button>` : ''}`;
      } else if (n.type === 'scene') {
        html += `<div style="color:var(--text2);font-size:12px;margin-top:8px">Обновляет сцену без текста. Автоматически переходит к следующему узлу.</div>`;
      }

    } else if (n.type === 'chapter') {
      html += `<div class="form-group">
        <label class="form-label">${isLocale ? `Заголовок [${Locales.getCurrent().toUpperCase()}]` : 'Заголовок главы'}</label>
        <input class="form-input" id="pf-chapter-title" value="${escH(locText('title'))}">
      </div>`;
      if (!isLocale) {
        html += bgField();
        html += bgmField(['chapter']);
      }

    } else if (n.type === 'set_flag') {
      html += `<div class="form-group">
        <label class="form-label">Имя флага</label>
        <input class="form-input" id="pf-flag-name" value="${escH(n.flag_name || '')}" placeholder="has_key">
      </div>
      <div class="form-group">
        <label class="form-label">Значение</label>
        <input class="form-input" id="pf-flag-value" value="${escH(n.flag_value || 'true')}" placeholder="true">
        <div class="form-hint">Строка или true/false. Флаги сохраняются между сеансами игры.</div>
      </div>`;

    } else if (n.type === 'branch_flag') {
      html += `<div class="form-group">
        <label class="form-label">Имя флага</label>
        <input class="form-input" id="pf-flag-name" value="${escH(n.flag_name || '')}" placeholder="has_key">
      </div>
      <div class="form-group">
        <label class="form-label">Сравнить с</label>
        <input class="form-input" id="pf-flag-value" value="${escH(n.flag_value || 'true')}" placeholder="true">
        <div class="form-hint">Если флаг == значение → порт <strong>Совпадает</strong> (верхний), иначе → <strong>Иначе</strong> (нижний).</div>
      </div>`;

    } else if (n.type === 'achievement') {
      html += `<div class="form-group">
        <label class="form-label">ID достижения</label>
        <input class="form-input" id="pf-ach-id" value="${escH(n.achievement_id || '')}" placeholder="found_key" ${isLocale ? 'disabled' : ''}>
      </div>
      <div class="form-group">
        <label class="form-label">${isLocale ? `Название [${Locales.getCurrent().toUpperCase()}]` : 'Название'}</label>
        <input class="form-input" id="pf-ach-name" value="${escH(locText('achievement_name'))}" placeholder="Нашёл ключ">
      </div>
      <div class="form-group">
        <label class="form-label">${isLocale ? `Описание [${Locales.getCurrent().toUpperCase()}]` : 'Описание'}</label>
        <textarea class="form-textarea" id="pf-ach-desc" rows="2">${escH(locText('achievement_desc'))}</textarea>
      </div>`;

    } else if (n.type === 'gallery_cg') {
      const cgPreview = n.cg_url ? `<img src="${n.cg_url}" style="width:100%;border-radius:6px;margin-bottom:8px;max-height:140px;object-fit:cover">` : '';
      html += `<div class="form-group">
        <label class="form-label">ID изображения</label>
        <input class="form-input" id="pf-cg-id" value="${escH(n.cg_id || '')}" placeholder="cg_001" ${isLocale ? 'disabled' : ''}>
      </div>
      <div class="form-group">
        <label class="form-label">${isLocale ? `Название [${Locales.getCurrent().toUpperCase()}]` : 'Название'}</label>
        <input class="form-input" id="pf-cg-name" value="${escH(locText('cg_name'))}">
      </div>
      ${!isLocale ? `${cgPreview}<div class="upload-zone" id="pf-cg-upload"><i class="ph ph-image"></i> ${n.cg_url ? 'Заменить изображение' : 'Загрузить изображение'}</div>
      <input type="file" id="pf-cg-file" accept="image/*" style="display:none">` : ''}`;
    }

    html += `<div class="props-delete-zone">
      <button class="btn-danger delete-node-btn" id="pf-delete"><i class="ph ph-trash"></i> Удалить узел</button>
    </div>`;

    panel.innerHTML = html;
    bindPropsEvents(n);
  }

  function bindPropsEvents(n) {
    const panel = document.getElementById('props-panel');
    const isLocale = !!Locales.getCurrent();

    const rebuildVisual = () => {
      const wrap = panel.querySelector('.stage-visual');
      if (!wrap) return;
      wrap.outerHTML = renderStageVisual(n);
      bindStageVisualDrag(n);
    };
    const refresh = () => {
      updateNodeContent(document.getElementById('node-' + n.id), n);
      renderEdges();
      autoSave();
    };

    // Locale chip clicks
    panel.querySelectorAll('.locale-chip').forEach(chip => {
      chip.addEventListener('click', () => { Locales.setCurrent(chip.dataset.locale); renderProps(); });
    });

    // Delete node
    document.getElementById('pf-delete')?.addEventListener('click', () => deleteNode(n.id));

    // BGM
    const bgmSel = document.getElementById('pf-bgm');
    if (bgmSel) bgmSel.addEventListener('change', () => {
      n.bgm_url = bgmSel.value;
      autoSave();
      BGM.setNodeBgm(n.bgm_url);
    });
    const bgmUpBtn = document.getElementById('pf-bgm-upload');
    const bgmFile  = document.getElementById('pf-bgm-file');
    if (bgmUpBtn && bgmFile) {
      bgmUpBtn.addEventListener('click', () => bgmFile.click());
      bgmFile.addEventListener('change', async e => {
        const file = e.target.files[0]; if (!file) return;
        try {
          const result = await api.uploadFile(file, 'bgm');
          await BGM.load();
          n.bgm_url = result.url;
          autoSave(); renderProps(); showToast('Музыка загружена', 'success');
        } catch (err) { showToast('Ошибка: ' + err.message, 'error'); }
        e.target.value = '';
      });
    }

    // Background
    const bgEl = document.getElementById('pf-bg');
    if (bgEl) bgEl.addEventListener('change', e => { n.background_id = e.target.value; rebuildVisual(); autoSave(); });

    bindStageVisualDrag(n);

    // Stage rows
    panel.querySelectorAll('.stage-char').forEach(sel => {
      const i = parseInt(sel.dataset.si);
      sel.addEventListener('change', () => {
        n.stage[i].character_id = sel.value; n.stage[i].emotion = '';
        if (n.type === 'dialog' && n.speaker_id && !n.stage.find(s => s.character_id === n.speaker_id)) n.speaker_id = '';
        refresh(); renderProps();
      });
    });
    panel.querySelectorAll('.stage-emo').forEach(sel => {
      const i = parseInt(sel.dataset.si);
      sel.addEventListener('change', () => { n.stage[i].emotion = sel.value; rebuildVisual(); refresh(); });
    });
    const syncX = (i, val) => {
      const v = Math.max(0, Math.min(100, parseInt(val) || 0)); n.stage[i].x = v;
      const range = panel.querySelector(`.stage-x-range[data-si="${i}"]`);
      const num   = panel.querySelector(`.stage-x-num[data-si="${i}"]`);
      if (range && range.value != v) range.value = v;
      if (num   && num.value   != v) num.value   = v;
      const vc = panel.querySelector(`.stage-vis-char[data-si="${i}"]`);
      if (vc) vc.style.left = v + '%';
      refresh();
    };
    const syncScale = (i, val) => {
      const v = Math.max(20, Math.min(150, parseInt(val) || 80)); n.stage[i].scale = v;
      const range = panel.querySelector(`.stage-sc-range[data-si="${i}"]`);
      const num   = panel.querySelector(`.stage-sc-num[data-si="${i}"]`);
      if (range && range.value != v) range.value = v;
      if (num   && num.value   != v) num.value   = v;
      const vc = panel.querySelector(`.stage-vis-char[data-si="${i}"]`);
      if (vc) vc.style.height = v + '%';
      refresh();
    };
    panel.querySelectorAll('.stage-x-range').forEach(el => { const i = parseInt(el.dataset.si); el.addEventListener('input', () => syncX(i, el.value)); });
    panel.querySelectorAll('.stage-x-num').forEach(el   => { const i = parseInt(el.dataset.si); el.addEventListener('input', () => syncX(i, el.value)); });
    panel.querySelectorAll('.stage-sc-range').forEach(el => { const i = parseInt(el.dataset.si); el.addEventListener('input', () => syncScale(i, el.value)); });
    panel.querySelectorAll('.stage-sc-num').forEach(el   => { const i = parseInt(el.dataset.si); el.addEventListener('input', () => syncScale(i, el.value)); });
    panel.querySelectorAll('.stage-del').forEach(btn => {
      const i = parseInt(btn.dataset.si);
      btn.addEventListener('click', () => {
        const rid = n.stage[i].character_id; n.stage.splice(i, 1);
        if (n.type === 'dialog' && n.speaker_id === rid) n.speaker_id = '';
        refresh(); renderProps();
      });
    });
    document.getElementById('pf-stage-add')?.addEventListener('click', () => {
      if (!Array.isArray(n.stage)) n.stage = [];
      n.stage.push({ character_id: '', emotion: '', x: 50, scale: 80 });
      refresh(); renderProps();
    });
    document.getElementById('pf-preview')?.addEventListener('click', () => openNodePreview(n));

    // Dialog fields
    const speakerEl = document.getElementById('pf-speaker');
    if (speakerEl) speakerEl.addEventListener('change', () => { n.speaker_id = speakerEl.value; rebuildVisual(); refresh(); });
    const textEl = document.getElementById('pf-text');
    if (textEl) textEl.addEventListener('input', () => { Locales.setText(n, 'text', textEl.value); refresh(); });
    const nvlEl = document.getElementById('pf-nvl');
    if (nvlEl) nvlEl.addEventListener('change', () => { n.nvl = nvlEl.checked; autoSave(); });

    // Choice fields
    const qEl = document.getElementById('pf-question');
    if (qEl) qEl.addEventListener('input', () => { Locales.setText(n, 'question', qEl.value); refresh(); });
    panel.querySelectorAll('.choice-text-inp').forEach(inp => {
      const i = parseInt(inp.dataset.ci);
      inp.addEventListener('input', e => { Locales.setChoiceText(n, i, e.target.value); refresh(); });
    });
    panel.querySelectorAll('[data-del-ci]').forEach(btn => {
      const i = parseInt(btn.dataset.delCi);
      btn.addEventListener('click', () => {
        n.choices.splice(i, 1);
        edges = edges.filter(e => !(e.fromNode === n.id && e.fromPort === 'choice' && e.choiceIndex >= i));
        refresh(); renderProps();
      });
    });
    document.getElementById('pf-add-choice')?.addEventListener('click', () => {
      if (!n.choices) n.choices = [];
      n.choices.push({ id: 'ch_' + Date.now(), text: '' });
      refresh(); renderProps();
    });

    // End node fields
    const endingIdEl = document.getElementById('pf-ending-id');
    if (endingIdEl) endingIdEl.addEventListener('input', () => { n.ending_id = endingIdEl.value; refresh(); });
    const endingNameEl = document.getElementById('pf-ending-name');
    if (endingNameEl) endingNameEl.addEventListener('input', () => { Locales.setText(n, 'ending_name', endingNameEl.value); refresh(); });

    // Chapter fields
    const chapterTitleEl = document.getElementById('pf-chapter-title');
    if (chapterTitleEl) chapterTitleEl.addEventListener('input', () => { Locales.setText(n, 'title', chapterTitleEl.value); refresh(); });

    // Flag fields (shared by set_flag + branch_flag)
    const flagNameEl = document.getElementById('pf-flag-name');
    if (flagNameEl) flagNameEl.addEventListener('input', () => { n.flag_name = flagNameEl.value; refresh(); });
    const flagValEl = document.getElementById('pf-flag-value');
    if (flagValEl) flagValEl.addEventListener('input', () => { n.flag_value = flagValEl.value; refresh(); });

    // Achievement fields
    const achIdEl = document.getElementById('pf-ach-id');
    if (achIdEl) achIdEl.addEventListener('input', () => { n.achievement_id = achIdEl.value; refresh(); });
    const achNameEl = document.getElementById('pf-ach-name');
    if (achNameEl) achNameEl.addEventListener('input', () => { Locales.setText(n, 'achievement_name', achNameEl.value); refresh(); });
    const achDescEl = document.getElementById('pf-ach-desc');
    if (achDescEl) achDescEl.addEventListener('input', () => { Locales.setText(n, 'achievement_desc', achDescEl.value); autoSave(); });

    // Gallery CG fields
    const cgIdEl = document.getElementById('pf-cg-id');
    if (cgIdEl) cgIdEl.addEventListener('input', () => { n.cg_id = cgIdEl.value; refresh(); });
    const cgNameEl = document.getElementById('pf-cg-name');
    if (cgNameEl) cgNameEl.addEventListener('input', () => { Locales.setText(n, 'cg_name', cgNameEl.value); refresh(); });
    const cgUploadZone = document.getElementById('pf-cg-upload');
    const cgFileInput  = document.getElementById('pf-cg-file');
    if (cgUploadZone && cgFileInput) {
      cgUploadZone.addEventListener('click', () => cgFileInput.click());
      cgFileInput.addEventListener('change', async e => {
        const file = e.target.files[0]; if (!file) return;
        try {
          const result = await api.uploadFile(file, 'gallery');
          n.cg_url = result.url;
          refresh(); renderProps(); showToast('CG загружено', 'success');
        } catch (err) { showToast('Ошибка: ' + err.message, 'error'); }
        e.target.value = '';
      });
    }
  }

  function openNodePreview(n) {
    const chars = Characters.getAll();
    const bgs   = Backgrounds.getAll();
    const bg    = bgs.find(b => b.id === n.background_id);
    const bgCss = bg && bg.url ? `background-image:url('${bg.url}')` : 'background:#0e0a1c';
    const locText = (key) => Locales.getText(n, key);

    const charsHtml = (n.stage || []).map(s => {
      const c = chars.find(x => x.id === s.character_id); if (!c) return '';
      const art = (c.arts || []).find(a => a.emotion === s.emotion) || (c.arts || [])[0];
      if (!art || !art.url) return '';
      const xPct = Math.max(0, Math.min(100, Number(s.x) || 0));
      const scPct = Math.max(20, Math.min(150, Number(s.scale) || 80));
      const isSpeaker = n.type === 'dialog' && s.character_id === n.speaker_id;
      return `<img src="${art.url}" class="gp-char${isSpeaker ? ' speaking' : ''}" style="left:${xPct}%;height:${scPct}%" alt="${escH(c.name)}">`;
    }).join('');

    let bottomHtml = '';
    if (n.type === 'dialog') {
      const speaker = chars.find(c => c.id === n.speaker_id);
      if (n.nvl) {
        bottomHtml = `<div class="gp-nvl-panel">
          <div class="gp-nvl-line">${speaker ? `<span class="gp-nvl-speaker">${escH(speaker.name)}:</span> ` : ''}<span>${escH(locText('text') || '...')}</span></div>
          <div class="gp-next">Далее ▶</div>
        </div>`;
      } else {
        bottomHtml = `<div class="gp-dialog">
          ${speaker ? `<div class="gp-speaker">${escH(speaker.name)}</div>` : ''}
          <div class="gp-text">${escH(locText('text') || '...')}</div>
          <div class="gp-next">Далее ▶</div>
        </div>`;
      }
    } else if (n.type === 'choice') {
      const choicesText = Locales.getChoicesText(n);
      bottomHtml = `<div class="gp-dialog"><div class="gp-text">${escH(locText('question') || n.question || '...')}</div></div>
        <div class="gp-choices">${(n.choices || []).map((c, i) => `<div class="gp-choice-btn">${escH(choicesText[i] || c.text || '...')}</div>`).join('')}</div>`;
    } else if (n.type === 'scene') {
      bottomHtml = `<div class="gp-scene-label">Обновление сцены — auto-skip</div>`;
    } else if (n.type === 'chapter') {
      bottomHtml = `<div class="gp-chapter-label">${escH(locText('title') || n.title || 'Глава')}</div>`;
    } else if (n.type === 'set_flag') {
      bottomHtml = `<div class="gp-flag-label">${escH(n.flag_name || '?')} = ${escH(n.flag_value || '')}</div>`;
    } else if (n.type === 'achievement') {
      bottomHtml = `<div class="gp-chapter-label" style="color:#34d399">Достижение: ${escH(locText('achievement_name') || n.achievement_id || '?')}</div>`;
    }

    openModal('Предпросмотр', `<div class="game-preview" style="${bgCss}"><div class="gp-stage">${charsHtml}</div>${bottomHtml}</div>`, '', { wide: true });
  }

  function bindStageVisualDrag(n) {
    const panel  = document.getElementById('props-panel');
    const visual = panel.querySelector('.stage-visual');
    if (!visual) return;
    visual.querySelectorAll('.stage-vis-char').forEach(charEl => {
      const i = parseInt(charEl.dataset.si);
      charEl.addEventListener('mousedown', startEv => {
        startEv.preventDefault(); startEv.stopPropagation();
        charEl.classList.add('dragging');
        const rect = visual.getBoundingClientRect();
        const move = e => {
          const x = Math.max(0, Math.min(100, Math.round(((e.clientX - rect.left) / rect.width) * 100)));
          n.stage[i].x = x; charEl.style.left = x + '%';
          const range = panel.querySelector(`.stage-x-range[data-si="${i}"]`);
          const num   = panel.querySelector(`.stage-x-num[data-si="${i}"]`);
          if (range) range.value = x; if (num) num.value = x;
          updateNodeContent(document.getElementById('node-' + n.id), n);
        };
        const up = () => {
          charEl.classList.remove('dragging');
          document.removeEventListener('mousemove', move); document.removeEventListener('mouseup', up);
          autoSave(); renderEdges();
        };
        document.addEventListener('mousemove', move); document.addEventListener('mouseup', up);
      });
    });
  }

  function deleteNode(id) {
    nodes = nodes.filter(n => n.id !== id);
    edges = edges.filter(e => e.fromNode !== id && e.toNode !== id);
    document.getElementById('node-' + id)?.remove();
    if (selectedNodeId === id) { selectedNodeId = null; renderProps(); }
    renderEdges(); autoSave();
  }

  // ---- Add node ----
  function addNode(type) {
    const center = screenToWorld(
      canvasWrapper.getBoundingClientRect().left + canvasWrapper.offsetWidth  / 2,
      canvasWrapper.getBoundingClientRect().top  + canvasWrapper.offsetHeight / 2
    );
    const base = {
      id:   'n_' + Date.now(),
      type,
      x:    Math.round(center.x - NODE_W / 2 + (Math.random() * 60 - 30)),
      y:    Math.round(center.y - 60         + (Math.random() * 60 - 30)),
      locales: {}
    };

    const defaults = {
      start:       {},
      dialog:      { background_id: '', stage: [], speaker_id: '', text: '', bgm_url: '', nvl: false },
      choice:      { background_id: '', stage: [], speaker_id: '', question: '', bgm_url: '',
                     choices: [{ id: 'ch_' + Date.now(), text: '' }, { id: 'ch_' + (Date.now()+1), text: '' }] },
      scene:       { background_id: '', stage: [], bgm_url: '' },
      end:         { ending_id: '', ending_name: '' },
      chapter:     { title: '', background_id: '', bgm_url: '' },
      set_flag:    { flag_name: '', flag_value: 'true' },
      branch_flag: { flag_name: '', flag_value: 'true' },
      achievement: { achievement_id: '', achievement_name: '', achievement_desc: '' },
      gallery_cg:  { cg_id: '', cg_name: '', cg_url: '' },
    };

    const n = { ...base, ...(defaults[type] || {}) };
    nodes.push(n);
    canvasWorld.appendChild(buildNodeEl(n));
    renderEdges();
    selectNode(n.id);
    autoSave();
  }

  // ---- Save/Load ----
  let saveTimer = null;
  function autoSave() { clearTimeout(saveTimer); saveTimer = setTimeout(saveStory, 800); }

  async function saveStory() {
    try { await api.saveStory({ nodes, edges }); } catch(e) { console.warn('autosave failed', e); }
  }

  async function loadStory() {
    try {
      const data = await api.getStory();
      const stageTypes = ['dialog', 'choice', 'scene'];
      nodes = (data.nodes || []).map(n => stageTypes.includes(n.type) ? migrateNode(n) : n);
      edges = data.edges || [];
      render(); autoSave();
    } catch(e) { console.warn('load failed', e); }
  }

  // ---- Events ----
  function bindEvents() {
    document.querySelectorAll('[data-type]').forEach(btn => {
      btn.addEventListener('click', () => addNode(btn.dataset.type));
    });

    document.getElementById('btn-save-story').addEventListener('click', async () => {
      await saveStory(); showToast('Сохранено', 'success');
    });
    document.getElementById('btn-export-json').addEventListener('click', () => { window.location.href = '/api/export/json'; });
    document.getElementById('btn-import-json').addEventListener('click', () => { document.getElementById('import-file-input').click(); });
    document.getElementById('import-file-input').addEventListener('change', async e => {
      const file = e.target.files[0]; if (!file) return;
      const text = await file.text();
      try {
        const data = JSON.parse(text);
        await api.importJson(data);
        await Characters.load(); await Backgrounds.load();
        if (Array.isArray(data.locales)) { await Locales.load(); }
        if (data.story) {
          const stageTypes = ['dialog', 'choice', 'scene'];
          nodes = (data.story.nodes || []).map(n => stageTypes.includes(n.type) ? migrateNode(n) : n);
          edges = data.story.edges || [];
        }
        canvasWorld.innerHTML = ''; render(); autoSave();
        showToast('Импортировано', 'success');
      } catch(err) { showToast('Ошибка импорта: ' + err.message, 'error'); }
      e.target.value = '';
    });
    document.getElementById('btn-export-game').addEventListener('click', () => {
      saveStory().then(() => { window.location.href = '/api/export/game'; });
    });

    canvasWrapper.addEventListener('mousedown', e => {
      if (connectStart && !e.target.classList.contains('port')) {
        connectStart = null; canvasWrapper.classList.remove('connecting'); svgDragLine.style.display = 'none';
      }
      if (e.target === canvasWrapper || e.target === canvasWorld || e.target === svgOverlay) {
        selectedNodeId = null;
        nodes.forEach(n => document.getElementById('node-' + n.id)?.classList.remove('selected'));
        renderProps();
      }
      if (e.button === 2 || (e.button === 0 && spaceDown)) {
        e.preventDefault(); panning = true;
        panStart = { mx: e.clientX, my: e.clientY, cx: camera.x, cy: camera.y };
        canvasWrapper.classList.add('panning');
      }
    });
    canvasWrapper.addEventListener('contextmenu', e => e.preventDefault());

    window.addEventListener('mousemove', e => {
      dragMousePos = { x: e.clientX, y: e.clientY };
      if (dragging) {
        const dx = (e.clientX - dragging.startMouseX) / camera.zoom;
        const dy = (e.clientY - dragging.startMouseY) / camera.zoom;
        const node = nodes.find(n => n.id === dragging.nodeId);
        if (node) {
          node.x = Math.round(dragging.startNodeX + dx); node.y = Math.round(dragging.startNodeY + dy);
          const el = document.getElementById('node-' + node.id);
          if (el) { el.style.left = node.x + 'px'; el.style.top = node.y + 'px'; }
          renderEdges();
        }
      }
      if (panning) {
        camera.x = panStart.cx + (e.clientX - panStart.mx);
        camera.y = panStart.cy + (e.clientY - panStart.my);
        applyCamera();
      }
      if (connectStart) {
        const from = getPortPos(connectStart.nodeId, connectStart.portType, connectStart.choiceIndex);
        if (from) {
          const to = screenToWorld(e.clientX, e.clientY);
          dragPath.setAttribute('d', makePath(from.x, from.y, to.x, to.y));
          svgDragLine.style.display = '';
        }
      }
    });

    window.addEventListener('mouseup', e => {
      if (dragging) { autoSave(); dragging = null; }
      if (panning)  { panning = false; canvasWrapper.classList.remove('panning'); }
    });

    canvasWrapper.addEventListener('wheel', e => {
      e.preventDefault();
      const rect = canvasWrapper.getBoundingClientRect();
      const mx = e.clientX - rect.left, my = e.clientY - rect.top;
      const factor = e.deltaY < 0 ? 1.1 : 0.9;
      const newZoom = Math.min(3, Math.max(0.2, camera.zoom * factor));
      camera.x = mx - (mx - camera.x) * (newZoom / camera.zoom);
      camera.y = my - (my - camera.y) * (newZoom / camera.zoom);
      camera.zoom = newZoom; applyCamera();
    }, { passive: false });

    window.addEventListener('keydown', e => {
      if (e.code === 'Space' && !['INPUT','TEXTAREA','SELECT'].includes(document.activeElement.tagName)) {
        spaceDown = true; e.preventDefault();
      }
      if ((e.key === 'Delete' || e.key === 'Backspace') && !['INPUT','TEXTAREA','SELECT'].includes(document.activeElement.tagName)) {
        if (selectedNodeId) deleteNode(selectedNodeId);
      }
      if (e.key === 'Escape' && connectStart) {
        connectStart = null; canvasWrapper.classList.remove('connecting'); svgDragLine.style.display = 'none';
      }
    });
    window.addEventListener('keyup', e => { if (e.code === 'Space') spaceDown = false; });
  }

  return { init, loadStory };
})();
