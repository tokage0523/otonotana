(function (root) {
  'use strict';
  function timestamp(seconds) {
    if (!Number.isFinite(seconds) || seconds < 0) throw new Error('時刻には0以上の秒数を入力してください。');
    const ms = Math.round(seconds * 1000);
    return `${String(Math.floor(ms / 60000)).padStart(2, '0')}:${String(Math.floor(ms / 1000) % 60).padStart(2, '0')}.${String(ms % 1000).padStart(3, '0')}`;
  }
  function parse(source) {
    const offset = Number(source.match(/\[offset:([+-]?\d+)\]/i)?.[1] || 0) / 1000;
    const result = [];
    for (const raw of source.split(/\r?\n|\r/)) {
      const matches = [...raw.matchAll(/\[(\d+):([0-5]\d)(?:\.(\d{1,3}))?\]/g)];
      if (!matches.length) continue;
      const last = matches[matches.length - 1];
      const text = raw.slice(last.index + last[0].length).trim();
      for (const m of matches) {
        const seconds = Number(m[1]) * 60 + Number(m[2]) + Number(`0.${m[3] || '0'}`) + offset;
        if (Number.isFinite(seconds)) result.push({ seconds: Math.max(0, seconds), text });
      }
    }
    return result.sort((a, b) => a.seconds - b.seconds);
  }
  function serialize(rows, duration) {
    if (!rows.length) throw new Error('先に歌詞を追加してください。');
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      if (!Number.isFinite(row.seconds) || row.seconds < 0) throw new Error(`${i + 1}行目の時刻を設定してください。`);
      if (Number.isFinite(duration) && row.seconds >= duration) throw new Error(`${i + 1}行目の時刻が曲の長さを超えています。`);
      if (typeof row.text !== 'string' || /[\r\n]/.test(row.text)) throw new Error(`${i + 1}行目の歌詞を確認してください。`);
    }
    return rows.slice().sort((a, b) => a.seconds - b.seconds)
      .map(row => `[${timestamp(row.seconds)}]${row.text}`).join('\n') + '\n';
  }
  function shift(rows, delta, start = 0) {
    if (!Number.isFinite(delta) || !Number.isInteger(start) || start < 0) throw new Error('ずらす秒数を確認してください。');
    return rows.map((row, index) => {
      if (row.seconds === null || index < start) return { ...row };
      const value = Math.round(Math.max(0, row.seconds + delta) * 1000) / 1000;
      if (!Number.isFinite(value)) throw new Error('ずらす秒数が大きすぎます。');
      return { ...row, seconds: value };
    });
  }
  const api = { timestamp, parse, serialize, shift };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.LyricsCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
