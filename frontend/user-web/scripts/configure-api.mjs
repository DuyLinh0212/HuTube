import { readFileSync, writeFileSync } from 'node:fs';
const config = JSON.parse(readFileSync(new URL('../public/config.json', import.meta.url), 'utf8'));
if (process.env.API_BASE_URL) config.API_BASE_URL = process.env.API_BASE_URL;
else if (process.argv.includes('--local')) config.API_BASE_URL = 'http://localhost:5080/api/v1';
else config.API_BASE_URL = 'https://api.dalitu.app/api/v1';
const url = new URL(config.API_BASE_URL);
if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error('Invalid API_BASE_URL');
config.API_BASE_URL = url.href.replace(/\/$/, '');
const recommendationUrl = new URL(process.env.RECOMMENDATION_BASE_URL
  || (process.argv.includes('--local') ? 'http://localhost:8000/api/v1' : 'https://recommendation.dalitu.app/api/v1'));
if (!['http:', 'https:'].includes(recommendationUrl.protocol) || recommendationUrl.username || recommendationUrl.password || recommendationUrl.search || recommendationUrl.hash) throw new Error('Invalid RECOMMENDATION_BASE_URL');
config.RECOMMENDATION_BASE_URL = recommendationUrl.href.replace(/\/$/, '');
writeFileSync(new URL('../public/config.json', import.meta.url), JSON.stringify(config, null, 2) + '\n');
