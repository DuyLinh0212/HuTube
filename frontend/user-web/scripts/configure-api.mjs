import { readFileSync, writeFileSync } from 'node:fs';
const config = JSON.parse(readFileSync(new URL('../public/config.json', import.meta.url), 'utf8'));
if (process.env.API_BASE_URL) config.API_BASE_URL = process.env.API_BASE_URL;
const url = new URL(config.API_BASE_URL);
if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error('Invalid API_BASE_URL');
config.API_BASE_URL = url.href.replace(/\/$/, '');
writeFileSync(new URL('../public/config.json', import.meta.url), JSON.stringify(config, null, 2) + '\n');
