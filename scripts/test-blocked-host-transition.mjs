/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 asami
 */

import { execFile } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const [tokenPath, outputPath] = process.argv.slice(2);

if (!tokenPath || !outputPath) {
	throw new Error('usage: node scripts/test-blocked-host-transition.mjs TOKENS_JSON OUTPUT_JSON');
}

const baselineUrl = process.env.BASELINE_URL ?? 'http://127.0.0.1:3101';
const candidateUrl = process.env.CANDIDATE_URL ?? 'http://127.0.0.1:3102';
const blockedHost = process.env.BLOCKED_HOST ?? 'blocked.example';
const queryPrefix = process.env.QUERY_PREFIX ?? 'codexperf ';
const baselineUnit = process.env.BASELINE_SERVICE ?? '';
const candidateUnit = process.env.CANDIDATE_SERVICE ?? '';

if ((baselineUnit === '') !== (candidateUnit === '')) {
	throw new Error('set both BASELINE_SERVICE and CANDIDATE_SERVICE, or neither');
}

const seed = JSON.parse(await readFile(tokenPath, 'utf8'));
const adminToken = seed?.accounts?.admin?.token;
if (typeof adminToken !== 'string' || adminToken.length === 0) {
	throw new Error('TOKENS_JSON does not contain accounts.admin.token');
}

const servers = {
	baseline: { baseUrl: baselineUrl, unit: baselineUnit },
	candidate: { baseUrl: candidateUrl, unit: candidateUnit },
};
const queries = [
	'case exact',
	'case subdomain',
	'case deepdomain',
	'reply-to-blocked-host',
	'renote-of-blocked-host',
];

async function api(baseUrl, endpoint, body) {
	const response = await fetch(`${baseUrl}/api/${endpoint}`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body),
	});
	const responseBody = response.status === 204 ? null : await response.json();
	if (!response.ok) {
		throw new Error(`${endpoint}: HTTP ${response.status}: ${JSON.stringify(responseBody)}`);
	}
	return responseBody;
}

async function counts(baseUrl) {
	const result = {};
	for (const query of queries) {
		const notes = await api(baseUrl, 'notes/search', { query: `${queryPrefix}${query}`, limit: 20 });
		result[query] = notes.length;
	}
	return result;
}

async function serviceState(unit) {
	if (unit === '') return null;
	const { stdout } = await execFileAsync('systemctl', [
		'show', unit, '--no-pager',
		'--property=ActiveState,SubState,NRestarts,ActiveEnterTimestampMonotonic',
	]);
	return Object.fromEntries(stdout.trim().split('\n').filter(Boolean).map(line => line.split('=', 2)));
}

function withoutBlockedHost(hosts) {
	const target = blockedHost.toLowerCase();
	return hosts.filter(host => host.toLowerCase() !== target);
}

function withBlockedHost(hosts) {
	return [...withoutBlockedHost(hosts), blockedHost];
}

function allVisible(state) {
	return queries.every(query => state[query] > 0);
}

function allHidden(state) {
	return queries.every(query => state[query] === 0);
}

const originals = {};
const result = {
	releaseTest: 'note blocked-host live transition',
	blockedHost,
	serviceBefore: {},
	serviceAfter: {},
	unblocked: {},
	blocked: {},
	unblockedAgain: {},
	blockedAgain: {},
	restored: false,
	serviceRestartCheck: baselineUnit === '' ? 'SKIP' : 'PENDING',
};

try {
	for (const [name, server] of Object.entries(servers)) {
		result.serviceBefore[name] = await serviceState(server.unit);
		const meta = await api(server.baseUrl, 'admin/meta', { i: adminToken });
		if (!Array.isArray(meta.blockedHosts)) throw new Error(`${name}: admin/meta blockedHosts is not an array`);
		originals[name] = meta.blockedHosts;

		const unblockedHosts = withoutBlockedHost(meta.blockedHosts);
		const blockedHosts = withBlockedHost(meta.blockedHosts);

		await api(server.baseUrl, 'admin/update-meta', { i: adminToken, blockedHosts: unblockedHosts });
		result.unblocked[name] = await counts(server.baseUrl);

		await api(server.baseUrl, 'admin/update-meta', { i: adminToken, blockedHosts });
		result.blocked[name] = await counts(server.baseUrl);

		await api(server.baseUrl, 'admin/update-meta', { i: adminToken, blockedHosts: unblockedHosts });
		result.unblockedAgain[name] = await counts(server.baseUrl);

		await api(server.baseUrl, 'admin/update-meta', { i: adminToken, blockedHosts });
		result.blockedAgain[name] = await counts(server.baseUrl);
	}
} finally {
	let restored = Object.keys(originals).length === Object.keys(servers).length;
	for (const [name, server] of Object.entries(servers)) {
		if (!originals[name]) continue;
		await api(server.baseUrl, 'admin/update-meta', { i: adminToken, blockedHosts: originals[name] });
		const meta = await api(server.baseUrl, 'admin/meta', { i: adminToken });
		restored &&= JSON.stringify(meta.blockedHosts) === JSON.stringify(originals[name]);
		result.serviceAfter[name] = await serviceState(server.unit);
	}
	result.restored = restored;
}

const statePairs = ['unblocked', 'blocked', 'unblockedAgain', 'blockedAgain'];
result.baselineCandidateEqual = statePairs.every(state =>
	JSON.stringify(result[state].baseline) === JSON.stringify(result[state].candidate));
result.expectedTransitions = Object.keys(servers).every(name =>
	allVisible(result.unblocked[name]) &&
	allHidden(result.blocked[name]) &&
	allVisible(result.unblockedAgain[name]) &&
	allHidden(result.blockedAgain[name]));

if (baselineUnit !== '') {
	result.serviceRestartCheck = Object.keys(servers).every(name => {
		const before = result.serviceBefore[name];
		const after = result.serviceAfter[name];
		return before?.ActiveState === 'active' && after?.ActiveState === 'active' &&
			before?.SubState === 'running' && after?.SubState === 'running' &&
			before?.NRestarts === after?.NRestarts &&
			before?.ActiveEnterTimestampMonotonic === after?.ActiveEnterTimestampMonotonic;
	}) ? 'PASS' : 'FAIL';
}

result.pass = result.baselineCandidateEqual && result.expectedTransitions && result.restored &&
	result.serviceRestartCheck !== 'FAIL';

await writeFile(outputPath, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600 });
console.log(JSON.stringify({
	pass: result.pass,
	baselineCandidateEqual: result.baselineCandidateEqual,
	expectedTransitions: result.expectedTransitions,
	restored: result.restored,
	serviceRestartCheck: result.serviceRestartCheck,
}));
if (!result.pass) process.exitCode = 1;
