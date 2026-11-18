import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const frontend = resolve(process.argv[2], 'packages/frontend/src');
const utility = pathToFileURL(resolve(frontend, 'utility/group-avatar-decorations.ts'));
const { groupAvatarDecorations, sortedAvatarDecorationCategoryKeys } = await import(utility);
const items = [
	{ id: 'a', category: '10. フレーム' },
	{ id: 'b', category: '' },
	{ id: 'c', category: '02. 衣装' },
	{ id: 'd', category: '99. その他' },
	{ id: 'e', category: '09. 色' },
	{ id: 'f', category: '01. フレーム' },
	{ id: 'g', category: '02. 衣装' },
	{ id: 'h', category: 'かめ' },
	{ id: 'i', category: 'あさ' },
	{ id: 'j', category: null },
	{ id: 'k', category: '__proto__' },
	{ id: 'l', category: '2' },
	{ id: 'm', category: '11' },
];
const grouped = groupAvatarDecorations(items);
const originalKeys = Object.keys(grouped);
const sorted = sortedAvatarDecorationCategoryKeys(grouped);
assert.equal(sorted.at(-1), '');
assert.deepEqual(sorted.filter(k => /^\d+\./.test(k)), ['01. フレーム', '02. 衣装', '09. 色', '10. フレーム', '99. その他']);
assert.deepEqual(sorted.filter(k => /^[\u3040-\u309f]/.test(k)), ['あさ', 'かめ']);
assert(sorted.indexOf('2') < sorted.indexOf('11'));
assert.deepEqual(grouped['02. 衣装'], [items[2], items[6]]);
assert.deepEqual(grouped[''], [items[1], items[9]]);
assert.deepEqual(grouped['__proto__'], [items[10]]);
assert.deepEqual(Object.keys(grouped), originalKeys);

for (const page of ['pages/avatar-decorations.vue', 'pages/settings/avatar-decoration.vue']) {
	const source = await readFile(resolve(frontend, page), 'utf8');
	assert.match(source, /v-for="category in sortedCategoryKeys"/);
	assert.match(source, /v-for="avatarDecoration in groupedDecorations\[category\]"/);
	assert.match(source, /computed\(\(\) => sortedAvatarDecorationCategoryKeys\(groupedDecorations.value\)\)/);
}
console.log('040: numeric and Japanese sorting, uncategorized last, stable groups and both Vue pages PASS');
