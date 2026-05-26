const express = require('express');
const multer = require('multer');
const archiver = require('archiver');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = Number(process.env.PORT) || 3333;

app.use(express.json({ limit: '50mb' }));
app.use(express.static(path.join(__dirname, 'public')));

const DATA_DIR    = path.join(__dirname, 'data');
const UPLOADS_DIR = path.join(__dirname, 'uploads');
const GAME_DATA_DIR = path.resolve(__dirname, '..', 'game_data');
const MANAGED_UPLOAD_TYPES = new Set(['characters', 'backgrounds', 'bgm', 'gallery', 'achievements']);

['data', 'uploads/characters', 'uploads/backgrounds', 'uploads/bgm', 'uploads/gallery', 'uploads/achievements'].forEach(d =>
  fs.mkdirSync(path.join(__dirname, d), { recursive: true })
);

function readData(file) {
  const fp = path.join(DATA_DIR, file);
  if (!fs.existsSync(fp)) return [];
  try { return JSON.parse(fs.readFileSync(fp, 'utf8')); } catch { return []; }
}
function writeData(file, data) {
  fs.writeFileSync(path.join(DATA_DIR, file), JSON.stringify(data, null, 2), 'utf8');
}

function getManagedUploadInfo(url) {
  if (!url || typeof url !== 'string') return null;
  const normalized = url.replace(/\\/g, '/');
  const match = normalized.match(/^\/uploads\/([^/]+)\/([^/]+)$/);
  if (!match || !MANAGED_UPLOAD_TYPES.has(match[1])) return null;

  const type = match[1];
  const filename = path.basename(match[2]);
  const typeDir = path.resolve(UPLOADS_DIR, type);
  const filePath = path.resolve(typeDir, filename);
  if (!filePath.startsWith(typeDir + path.sep)) return null;

  return { type, filename, filePath };
}

function deleteFileWithImport(filePath) {
  [filePath, `${filePath}.import`].forEach(target => {
    try {
      if (fs.existsSync(target)) fs.unlinkSync(target);
    } catch (err) {
      console.warn(`Failed to delete ${target}:`, err.message);
    }
  });
}

function collectReferencedAssetUrls() {
  const urls = new Set();

  const characters = readData('characters.json');
  if (Array.isArray(characters)) {
    characters.forEach(c => (c.arts || []).forEach(a => {
      if (a && a.url) urls.add(a.url);
    }));
  }

  const backgrounds = readData('backgrounds.json');
  if (Array.isArray(backgrounds)) {
    backgrounds.forEach(b => {
      if (b && b.url) urls.add(b.url);
    });
  }

  const story = readData('story.json');
  if (story && Array.isArray(story.nodes)) {
    story.nodes.forEach(n => {
      if (n.bgm_url) urls.add(n.bgm_url);
      if (n.cg_url) urls.add(n.cg_url);
      if (n.achievement_icon_url) urls.add(n.achievement_icon_url);
    });
  }

  return urls;
}

function deleteManagedAsset(url) {
  const info = getManagedUploadInfo(url);
  if (!info) return;

  deleteFileWithImport(info.filePath);

  const gameTypeDir = path.resolve(GAME_DATA_DIR, info.type);
  const gameFilePath = path.resolve(gameTypeDir, info.filename);
  if (gameFilePath.startsWith(gameTypeDir + path.sep)) deleteFileWithImport(gameFilePath);
}

function cleanupUnreferencedAssets(urls) {
  const referenced = collectReferencedAssetUrls();
  [...new Set(urls.filter(Boolean))].forEach(url => {
    if (!referenced.has(url)) deleteManagedAsset(url);
  });
}

function characterAssetUrls(character) {
  return ((character && character.arts) || []).map(a => a && a.url).filter(Boolean);
}

function backgroundAssetUrls(background) {
  return background && background.url ? [background.url] : [];
}

function getUploadPath(url) {
  const info = getManagedUploadInfo(url);
  return info ? info.filePath : null;
}

function buildGameExport() {
  const story       = migrateStory(readData('story.json'));
  const characters  = readData('characters.json');
  const backgrounds = readData('backgrounds.json');
  const locales     = readData('locales.json') || [];
  const files       = [];

  const remappedChars = characters.map(c => ({
    ...c,
    arts: (c.arts || []).map(a => ({
      ...a,
      gameUrl: a.url ? 'game_data/characters/' + path.basename(a.url) : null
    }))
  }));

  const remappedBgs = backgrounds.map(b => ({
    ...b,
    gameUrl: b.url ? 'game_data/backgrounds/' + path.basename(b.url) : null
  }));

  const bgmFiles = new Set();
  const cgFiles  = new Set();
  const achievementFiles = new Set();
  const remappedNodes = (story.nodes || []).map(n => {
    const updated = { ...n };
    if (n.bgm_url && n.bgm_url !== '__stop__' && n.bgm_url.startsWith('/uploads/')) {
      const fname = path.basename(n.bgm_url);
      bgmFiles.add(fname);
      updated.bgm_game_url = 'game_data/bgm/' + fname;
    }
    if (n.type === 'gallery_cg') {
      const sourceBg = n.cg_background_id ? backgrounds.find(b => b.id === n.cg_background_id) : null;
      if (sourceBg && sourceBg.url && sourceBg.url.startsWith('/uploads/')) {
        updated.cg_game_url = 'game_data/backgrounds/' + path.basename(sourceBg.url);
      } else if (n.cg_url && n.cg_url.startsWith('/uploads/')) {
        const fname = path.basename(n.cg_url);
        cgFiles.add(fname);
        updated.cg_game_url = 'game_data/gallery/' + fname;
      }
    }
    if (n.type === 'achievement' && n.achievement_icon_url && n.achievement_icon_url.startsWith('/uploads/')) {
      const fname = path.basename(n.achievement_icon_url);
      achievementFiles.add(fname);
      updated.achievement_icon_game_url = 'game_data/achievements/' + fname;
    }
    return updated;
  });

  characters.forEach(c => (c.arts || []).forEach(a => {
    if (a.url) {
      const fp = getUploadPath(a.url);
      if (fp && fs.existsSync(fp)) {
        files.push({ from: fp, to: path.join(GAME_DATA_DIR, 'characters', path.basename(fp)) });
      }
    }
  }));

  backgrounds.forEach(b => {
    if (b.url) {
      const fp = getUploadPath(b.url);
      if (fp && fs.existsSync(fp)) {
        files.push({ from: fp, to: path.join(GAME_DATA_DIR, 'backgrounds', path.basename(fp)) });
      }
    }
  });

  bgmFiles.forEach(fname => {
    const fp = path.join(UPLOADS_DIR, 'bgm', fname);
    if (fs.existsSync(fp)) files.push({ from: fp, to: path.join(GAME_DATA_DIR, 'bgm', fname) });
  });

  cgFiles.forEach(fname => {
    const fp = path.join(UPLOADS_DIR, 'gallery', fname);
    if (fs.existsSync(fp)) files.push({ from: fp, to: path.join(GAME_DATA_DIR, 'gallery', fname) });
  });

  achievementFiles.forEach(fname => {
    const fp = path.join(UPLOADS_DIR, 'achievements', fname);
    if (fs.existsSync(fp)) files.push({ from: fp, to: path.join(GAME_DATA_DIR, 'achievements', fname) });
  });

  const gameData = JSON.stringify({
    story:       { ...story, nodes: remappedNodes },
    characters:  remappedChars,
    backgrounds: remappedBgs,
    locales,
  }, null, 2);

  return { gameData, files };
}

function syncGameDataToDisk() {
  const { gameData, files } = buildGameExport();
  fs.mkdirSync(GAME_DATA_DIR, { recursive: true });
  fs.writeFileSync(path.join(GAME_DATA_DIR, 'game_data.json'), gameData, 'utf8');

  files.forEach(({ from, to }) => {
    const target = path.resolve(to);
    if (!target.startsWith(GAME_DATA_DIR + path.sep)) return;
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(from, target);
  });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(UPLOADS_DIR, req.params.type);
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const ext  = path.extname(file.originalname).toLowerCase();
    const base = path.basename(file.originalname, ext).replace(/[\/\\:*?"<>|]/g, '_').slice(0, 60);
    cb(null, Date.now() + '_' + base + ext);
  }
});
const upload = multer({ storage, limits: { fileSize: 100 * 1024 * 1024 } });

app.use('/uploads', express.static(UPLOADS_DIR));

// ---- Characters ----
app.get('/api/characters', (req, res) => res.json(readData('characters.json')));

app.post('/api/characters', (req, res) => {
  const list = readData('characters.json');
  const item = { id: 'c_' + Date.now(), arts: [], ...req.body };
  list.push(item);
  writeData('characters.json', list);
  syncGameDataToDisk();
  res.json(item);
});

app.put('/api/characters/:id', (req, res) => {
  let list = readData('characters.json');
  const oldItem = list.find(c => c.id === req.params.id);
  if (!oldItem) return res.status(404).json({ error: 'character not found' });
  list = list.map(c => c.id === req.params.id ? { ...c, ...req.body, id: req.params.id } : c);
  writeData('characters.json', list);
  cleanupUnreferencedAssets(characterAssetUrls(oldItem));
  syncGameDataToDisk();
  res.json(list.find(c => c.id === req.params.id));
});

app.delete('/api/characters/:id', (req, res) => {
  let list = readData('characters.json');
  const oldItem = list.find(c => c.id === req.params.id);
  list = list.filter(c => c.id !== req.params.id);
  writeData('characters.json', list);
  if (oldItem) cleanupUnreferencedAssets(characterAssetUrls(oldItem));
  syncGameDataToDisk();
  res.json({ ok: true });
});

// ---- Backgrounds ----
app.get('/api/backgrounds', (req, res) => res.json(readData('backgrounds.json')));

app.post('/api/backgrounds', (req, res) => {
  const list = readData('backgrounds.json');
  const item = { id: 'b_' + Date.now(), ...req.body };
  list.push(item);
  writeData('backgrounds.json', list);
  syncGameDataToDisk();
  res.json(item);
});

app.put('/api/backgrounds/:id', (req, res) => {
  let list = readData('backgrounds.json');
  const oldItem = list.find(b => b.id === req.params.id);
  if (!oldItem) return res.status(404).json({ error: 'background not found' });
  list = list.map(b => b.id === req.params.id ? { ...b, ...req.body, id: req.params.id } : b);
  writeData('backgrounds.json', list);
  cleanupUnreferencedAssets(backgroundAssetUrls(oldItem));
  syncGameDataToDisk();
  res.json(list.find(b => b.id === req.params.id));
});

app.delete('/api/backgrounds/:id', (req, res) => {
  let list = readData('backgrounds.json');
  const oldItem = list.find(b => b.id === req.params.id);
  list = list.filter(b => b.id !== req.params.id);
  writeData('backgrounds.json', list);
  if (oldItem) cleanupUnreferencedAssets(backgroundAssetUrls(oldItem));
  syncGameDataToDisk();
  res.json({ ok: true });
});

// ---- File upload ----
app.post('/api/upload/:type', (req, res, next) => {
  if (!MANAGED_UPLOAD_TYPES.has(req.params.type)) {
    return res.status(400).json({ error: 'unsupported upload type' });
  }
  next();
}, upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'no file' });
  res.json({
    url: `/uploads/${req.params.type}/${req.file.filename}`,
    filename: req.file.filename
  });
});

// ---- BGM list ----
app.get('/api/bgm', (req, res) => {
  const dir = path.join(UPLOADS_DIR, 'bgm');
  fs.mkdirSync(dir, { recursive: true });
  try {
    const files = fs.readdirSync(dir).filter(f => /\.(mp3|ogg|wav|flac)$/i.test(f));
    res.json(files.map(f => ({
      file: f,
      name: f.replace(/^\d+_/, ''),   // strip timestamp prefix, keep original name
      url: `/uploads/bgm/${f}`
    })));
  } catch { res.json([]); }
});

// ---- BGM delete ----
app.delete('/api/bgm/:file', (req, res) => {
  const fname = path.basename(req.params.file);
  deleteManagedAsset(`/uploads/bgm/${fname}`);
  syncGameDataToDisk();
  res.json({ ok: true });
});

// ---- Locale export (all translatable strings for one language) ----
const LOCALE_FIELDS = {
  dialog:      ['text'],
  choice:      ['question'],
  chapter:     ['title'],
  achievement: ['achievement_name', 'achievement_desc'],
  gallery_cg:  ['cg_name'],
  end:         ['ending_name'],
};

app.get('/api/export/locale/:lang', (req, res) => {
  const lang  = req.params.lang;
  const story = readData('story.json');
  const out   = [];

  for (const node of (story.nodes || [])) {
    const fields = LOCALE_FIELDS[node.type];
    if (!fields) continue;
    const existing = ((node.locales || {})[lang]) || {};
    const strings  = {};

    for (const field of fields) {
      const original = String(node[field] || '');
      if (!original) continue;
      strings[field] = { original, translation: existing[field] || '' };
    }
    if (node.type === 'choice') {
      const ct = existing.choices_text || [];
      (node.choices || []).forEach((ch, i) => {
        const original = String(ch.text || '');
        if (!original) return;
        strings[`choices_text[${i}]`] = { original, translation: ct[i] || '' };
      });
    }
    if (Object.keys(strings).length === 0) continue;
    out.push({ id: node.id, type: node.type, strings });
  }

  res.setHeader('Content-Disposition', `attachment; filename=locale_${lang}.json`);
  res.json({ lang, nodes: out });
});

// ---- Locale import (fill translations from file) ----
app.post('/api/import/locale', (req, res) => {
  const { lang, nodes: imported } = req.body;
  if (!lang || !Array.isArray(imported)) return res.status(400).json({ error: 'expected lang + nodes' });

  const story   = readData('story.json');
  const nodeMap = {};
  (story.nodes || []).forEach(n => { nodeMap[n.id] = n; });

  let count = 0;
  for (const entry of imported) {
    const node = nodeMap[entry.id];
    if (!node) continue;
    if (!node.locales)       node.locales       = {};
    if (!node.locales[lang]) node.locales[lang] = {};

    const choicesText = [];
    let hasChoices = false;

    for (const [key, val] of Object.entries(entry.strings || {})) {
      const t = (val.translation || '').trim();
      if (!t) continue;
      const cm = key.match(/^choices_text\[(\d+)\]$/);
      if (cm) { choicesText[parseInt(cm[1])] = t; hasChoices = true; }
      else    { node.locales[lang][key] = t; count++; }
    }
    if (hasChoices) { node.locales[lang].choices_text = choicesText; count++; }
  }

  writeData('story.json', story);
  syncGameDataToDisk();
  res.json({ ok: true, count });
});

// ---- Locales ----
app.get('/api/locales', (req, res) => {
  const locs = readData('locales.json');
  res.json(Array.isArray(locs) ? locs : []);
});
app.post('/api/locales', (req, res) => {
  if (!Array.isArray(req.body)) return res.status(400).json({ error: 'expected array' });
  writeData('locales.json', req.body);
  syncGameDataToDisk();
  res.json({ ok: true });
});

// ---- Story ----
app.get('/api/story', (req, res) => {
  const raw = readData('story.json');
  if (Array.isArray(raw) && raw.length === 0) return res.json({ nodes: [], edges: [] });
  return res.json(raw);
});
app.post('/api/story', (req, res) => {
  writeData('story.json', req.body);
  syncGameDataToDisk();
  res.json({ ok: true });
});

// ---- Export JSON ----
app.get('/api/export/json', (req, res) => {
  const data = {
    story:       readData('story.json'),
    characters:  readData('characters.json'),
    backgrounds: readData('backgrounds.json'),
    locales:     readData('locales.json') || [],
    exportedAt:  new Date().toISOString()
  };
  res.setHeader('Content-Disposition', 'attachment; filename=visual_novel_export.json');
  res.json(data);
});

// ---- Import JSON ----
app.post('/api/import/json', (req, res) => {
  const { story, characters, backgrounds, locales } = req.body;
  if (story)       writeData('story.json',       story);
  if (characters)  writeData('characters.json',  characters);
  if (backgrounds) writeData('backgrounds.json', backgrounds);
  if (Array.isArray(locales)) writeData('locales.json', locales);
  syncGameDataToDisk();
  res.json({ ok: true });
});

// ---- Schema migration ----
function migrateNode(n) {
  if (!Array.isArray(n.stage)) n.stage = [];
  if (n.character_id) {
    const exists = n.stage.find(s => s.character_id === n.character_id);
    if (!exists) n.stage.push({ character_id: n.character_id, emotion: n.emotion || '', x: 50, scale: 80 });
    if (n.type === 'dialog' && !n.speaker_id) n.speaker_id = n.character_id;
    delete n.character_id;
    delete n.emotion;
  }
  n.stage.forEach(s => { if (!('scale' in s)) s.scale = 80; });
  if (n.type === 'dialog' && !('speaker_id' in n)) n.speaker_id = '';
  return n;
}
function migrateStory(story) {
  if (!story || typeof story !== 'object') return story;
  const stageTypes = ['dialog', 'choice', 'scene'];
  const nodes = Array.isArray(story.nodes)
    ? story.nodes.map(n => stageTypes.includes(n.type) ? migrateNode(n) : n)
    : [];
  return { ...story, nodes, edges: story.edges || [] };
}

// ---- Export for game (ZIP) ----
app.get('/api/export/game', (req, res) => {
  syncGameDataToDisk();
  const { gameData, files } = buildGameExport();

  res.setHeader('Content-Type', 'application/zip');
  res.setHeader('Content-Disposition', 'attachment; filename=game_data.zip');

  const archive = archiver('zip', { zlib: { level: 9 } });
  archive.on('error', err => console.error(err));
  archive.pipe(res);

  archive.append(gameData, { name: 'game_data/game_data.json' });

  files.forEach(({ from, to }) => {
    if (fs.existsSync(from)) {
      archive.file(from, { name: 'game_data/' + path.relative(GAME_DATA_DIR, to).replace(/\\/g, '/') });
    }
  });

  archive.finalize();
});

try {
  syncGameDataToDisk();
} catch (err) {
  console.warn('Initial game data sync failed:', err.message);
}

app.listen(PORT, () => console.log(`\n  VN Editor: http://localhost:${PORT}\n`));
