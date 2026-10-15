(function (root) {
  'use strict';
  const clone = value => JSON.parse(JSON.stringify(value));
  function validateDraft(data) {
    if (!data || data.version !== 1 || !Array.isArray(data.rows) || typeof data.name !== 'string') throw new Error('下書きの形式が違います。');
    if (!data.rows.every(r => r && typeof r.text === 'string' && !/[\r\n]/.test(r.text) && (r.seconds === null || (Number.isFinite(r.seconds) && r.seconds >= 0)))) throw new Error('下書きの歌詞・時刻を読み込めません。');
    return clone(data);
  }
  function readBook(data, makeID) {
    if (data?.version === 1) return { version: 2, activeID: 'migrated', drafts: [{ id: 'migrated', ...validateDraft(data) }] };
    if (data?.version !== 2 || !Array.isArray(data.drafts) || !data.drafts.length) throw new Error('下書き一覧の形式が違います。');
    const seen = new Set();
    const drafts = data.drafts.map(item => {
      const draft = validateDraft(item);
      const id = typeof item.id === 'string' && !seen.has(item.id) ? item.id : makeID();
      seen.add(id); return { ...draft, id };
    });
    return { version: 2, activeID: drafts.some(d => d.id === data.activeID) ? data.activeID : drafts[0].id, drafts };
  }
  class History {
    constructor(limit = 100) { this.limit = limit; this.past = []; this.future = []; }
    push(state) {
      const copy = clone(state);
      if (JSON.stringify(this.past.at(-1)) !== JSON.stringify(copy)) this.past.push(copy);
      if (this.past.length > this.limit) this.past.shift();
      this.future = [];
    }
    undo(current) { if (!this.past.length) return null; this.future.push(clone(current)); return this.past.pop(); }
    redo(current) { if (!this.future.length) return null; this.past.push(clone(current)); return this.future.pop(); }
  }
  const api = { History, readBook, validateDraft };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.EditorState = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
