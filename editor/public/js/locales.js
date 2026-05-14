// Locales module — multi-language support for VN Editor
// Each node stores base text in its own fields (default language).
// Translations live in node.locales[langCode] = { text, question, choices_text, title, ... }
// This module tracks which language is currently being edited in the props panel.

const Locales = (() => {
  let list = [];      // e.g. ["en", "de", "ja"]
  let current = '';   // '' = default/base language; "en" = editing English translation

  async function load() {
    try {
      const data = await api.getLocales();
      list = Array.isArray(data) ? data : [];
    } catch { list = []; }
  }

  async function save() {
    await api.saveLocales(list);
  }

  async function addLocale(code) {
    code = code.trim().toLowerCase().replace(/[^a-z0-9_-]/g, '');
    if (!code || list.includes(code)) return false;
    list.push(code);
    await save();
    return true;
  }

  async function removeLocale(code) {
    list = list.filter(l => l !== code);
    if (current === code) current = '';
    await save();
  }

  function getList()          { return list; }
  function getCurrent()       { return current; }
  function setCurrent(code)   { current = code; }

  // Read a text field from a node, using current locale with fallback to base
  function getText(node, key) {
    if (!current) return node[key] || '';
    const lv = (node.locales || {})[current] || {};
    const v = lv[key];
    return (v !== undefined && v !== null) ? String(v) : (node[key] || '');
  }

  // Write a text field to node (base or current locale)
  function setText(node, key, value) {
    if (!current) { node[key] = value; return; }
    if (!node.locales) node.locales = {};
    if (!node.locales[current]) node.locales[current] = {};
    node.locales[current][key] = value;
  }

  // Get array of choice texts for current locale (falls back to base choices[i].text)
  function getChoicesText(node) {
    if (current) {
      const lv = (node.locales || {})[current] || {};
      if (Array.isArray(lv.choices_text) && lv.choices_text.length > 0)
        return lv.choices_text;
    }
    return (node.choices || []).map(c => c.text || '');
  }

  // Set one choice text in current locale
  function setChoiceText(node, index, value) {
    if (!current) {
      if (node.choices && node.choices[index]) node.choices[index].text = value;
      return;
    }
    if (!node.locales) node.locales = {};
    if (!node.locales[current]) node.locales[current] = {};
    const baseLen = (node.choices || []).length;
    if (!Array.isArray(node.locales[current].choices_text))
      node.locales[current].choices_text = Array(baseLen).fill('');
    while (node.locales[current].choices_text.length < baseLen)
      node.locales[current].choices_text.push('');
    node.locales[current].choices_text[index] = value;
  }

  // Build a locale selector bar HTML for the props panel
  function buildLocaleBar() {
    if (list.length === 0) return '';
    const chips = [
      `<span class="locale-chip${!current ? ' active' : ''}" data-locale="">По умолч.</span>`,
      ...list.map(l =>
        `<span class="locale-chip${current === l ? ' active' : ''}" data-locale="${escH(l)}">${escH(l.toUpperCase())}</span>`
      )
    ].join('');
    return `<div class="locale-bar"><i class="ph ph-translate locale-bar-icon"></i>${chips}</div>`;
  }

  return { load, save, addLocale, removeLocale, getList, getCurrent, setCurrent,
           getText, setText, getChoicesText, setChoiceText, buildLocaleBar };
})();
