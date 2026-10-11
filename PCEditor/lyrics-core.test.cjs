const assert = require('node:assert/strict');
const { parse, timestamp, serialize } = require('./lyrics-core.js');
assert.equal(timestamp(59.9996), '01:00.000');
assert.equal(timestamp(75.123), '01:15.123');
assert.deepEqual(parse('[ar:artist]\n[offset:-500]\n[00:01.25][01:02.003]日本語\n[00:00.1]'), [
  { seconds: 0, text: '' }, { seconds: 0.75, text: '日本語' }, { seconds: 61.503, text: '日本語' }
]);
assert.equal(parse('[00:60.00]invalid\ntext only').length, 0);
assert.throws(() => serialize([{ seconds: null, text: '未設定' }]));
assert.throws(() => serialize([{ seconds: 30, text: '曲の終了位置' }], 30));
assert.throws(() => serialize([{ seconds: -1, text: '負数' }]));
assert.throws(() => serialize([{ seconds: 1, text: 'a\nb' }]));
const rows = [{ seconds: 75.123, text: 'サビ' }, { seconds: 0, text: '' }, { seconds: 10.5, text: '歌い出し' }];
const original = JSON.stringify(rows);
assert.deepEqual(parse(serialize(rows)), [...rows].sort((a, b) => a.seconds - b.seconds));
assert.equal(JSON.stringify(rows), original);
console.log('LRC tests passed: precision, offset, repeated timestamps, validation, UTF-8 round trip.');
