// Run from repository root: node mobile/user-app/scripts/sync_policy_reference.cjs
// Copies the user-web reference and translations; published API policies override it.
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('frontend/user-web/src/app/features/policy/public-policy-page.ts', 'utf8');
const data = {};
for (const group of ['guidelines', 'privacy', 'terms', 'enforcement']) {
  const match = source.match(new RegExp('readonly ' + group + 'List: PolicyRuleItem\\[\\] = (\\[[\\s\\S]*?\\n  \\]);'));
  if (!match) throw Error('Missing policy group ' + group);
  data[group] = vm.runInNewContext('(' + match[1] + ')', {}, {timeout:1000});
}
const translations = {vi:{}, en:{}};
const i18n = fs.readFileSync('frontend/user-web/src/app/core/i18n.service.ts', 'utf8');
const strings = /'((?:policies\.|policy\.)[^']+)'\s*:\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")/g;
for (const m of i18n.matchAll(strings)) {
  const lang = Object.hasOwn(translations.vi, m[1]) ? 'en' : 'vi';
  translations[lang][m[1]] = vm.runInNewContext(m[2], {}, {timeout:1000});
}
const extras = fs.readFileSync('frontend/user-web/src/app/features/policy/policy-translations.ts', 'utf8');
const extraData = vm.runInNewContext('(' + extras.slice(extras.indexOf('=') + 1).trim().replace(/;$/, '') + ')', {}, {timeout:1000});
for (const lang of ['vi','en']) Object.assign(translations[lang],extraData[lang]);
const out = '// GENERATED from user-web. Run scripts/sync_policy_reference.cjs from repo root.\n'
 + 'const Map<String, dynamic> policyReference = ' + JSON.stringify(data,null,2) + ';\n'
 + 'const Map<String, dynamic> policyTranslations = ' + JSON.stringify(translations,null,2) + ';\n';
fs.writeFileSync('mobile/user-app/lib/features/policies/policy_reference.dart',out);
console.log(Object.fromEntries(Object.entries(data).map(([k,v])=>[k,v.length])));
