const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createHmac } = require('node:crypto');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

const secret = 'feedback-test-secret-with-at-least-32-characters';
const formId = '1FAIpQLSef9jF_PK4qnoEZjPjS7kq1Lk4iQbEtoSXxS8XMkoWcVcoecg';
function harness() {
  const values = {
    HUTUBE_API_BASE_URL: 'https://api.example.test/api/v1', HUTUBE_WEBHOOK_SECRET: secret,
    HUTUBE_FORM_ID: 'private-editor-form-id', HUTUBE_TOKEN_ITEM_ID: '42',
  };
  const calls = [];
  const statuses = [];
  const context = vm.createContext({
    console: { log() {}, warn() {} },
    PropertiesService: { getScriptProperties: () => ({
      getProperty: key => values[key] ?? null,
      setProperty: (key, value) => { values[key] = value; },
      setProperties: data => Object.assign(values, data),
      deleteProperty: key => { delete values[key]; },
      getProperties: () => ({ ...values }),
    }) },
    Utilities: {
      Charset: { UTF_8: 'utf-8' },
      computeHmacSha256Signature: (value, key) => Array.from(createHmac('sha256', key).update(value).digest(), byte => byte > 127 ? byte - 256 : byte),
    },
    UrlFetchApp: { fetch(url, options) {
      calls.push({ url, options });
      return { getResponseCode: () => statuses.shift() ?? 204 };
    } },
  });
  vm.runInContext(readFileSync(__dirname + '/hutube-feedback.gs', 'utf8'), context);
  const event = token => ({
    source: { getId: () => values.HUTUBE_FORM_ID },
    response: {
      getId: () => 'response-one', getTimestamp: () => new Date('2026-10-16T02:00:00Z'),
      getItemResponses: () => [{ getItem: () => ({ getId: () => 42 }), getResponse: () => token }],
    },
  });
  return { context, values, calls, statuses, event };
}

test('submit signs the callback and keeps failed delivery for a later retry', () => {
  const h = harness();
  h.statuses.push(502, 204);
  const token = 'a'.repeat(32) + '.' + 'b'.repeat(64);
  h.context.onHuTubeFeedbackSubmit(h.event(token));
  assert.ok(h.values['hutube_pending_response-one']);
  assert.equal(h.calls.length, 1);
  const { url, options } = h.calls[0];
  assert.equal(url, 'https://api.example.test/api/v1/feedback-survey/google-form-submission');
  const body = JSON.parse(options.payload);
  assert.deepEqual(body, { formId, surveyToken: token, responseId: 'response-one', submittedAt: '2026-10-16T02:00:00.000Z' });
  assert.equal(options.headers['X-HuTube-Survey-Signature'], 'sha256=' + createHmac('sha256', secret)
    .update(options.headers['X-HuTube-Survey-Timestamp'] + '.' + options.payload).digest('hex'));
  h.context.retryHuTubeFeedback();
  assert.equal(h.calls.length, 2);
  assert.equal(h.values['hutube_pending_response-one'], undefined);
});

test('a direct form submission without a linked account sends no webhook', () => {
  const h = harness();
  h.context.onHuTubeFeedbackSubmit(h.event(''));
  assert.equal(h.calls.length, 0);
});

test('a manual run or an event from another form is rejected', () => {
  const h = harness();
  assert.throws(() => h.context.onHuTubeFeedbackSubmit());
  const event = h.event('a'.repeat(32) + '.' + 'b'.repeat(64));
  event.source.getId = () => 'another-form';
  assert.throws(() => h.context.onHuTubeFeedbackSubmit(event));
  assert.equal(h.calls.length, 0);
});

test('unlinked tokens are removed after a permanent callback error to avoid blocking retries', () => {
  const h = harness();
  h.statuses.push(400);
  h.context.onHuTubeFeedbackSubmit(h.event('a'.repeat(32) + '.' + 'b'.repeat(64)));
  assert.equal(h.values['hutube_pending_response-one'], undefined);
});

test('installation creates one optional token question and one pair of triggers across repeated runs', () => {
  const h = harness();
  const items = [];
  const triggers = [];
  const text = {
    getId: () => 42,
    setTitle() { return this; },
    setHelpText() { return this; },
    setRequired(value) { assert.equal(value, false); return this; },
    createResponse: value => ({ value }),
  };
  const form = {
    getId: () => 'private-editor-form-id',
    getPublishedUrl: () => 'https://docs.google.com/forms/d/e/' + formId + '/viewform',
    getItems: () => items,
    addTextItem() {
      items.push({ getId: text.getId, getTitle: () => 'Mã khảo sát HuTube', asTextItem: () => text });
      return text;
    },
    createResponse() { return { withItemResponse() { return this; }, toPrefilledUrl: () => form.getPublishedUrl() + '?usp=pp_url&entry.987=HUTUBE_SETUP' }; },
  };
  h.context.FormApp = { getActiveForm: () => form, ItemType: { TEXT: 'text' } };
  h.context.ScriptApp = {
    getProjectTriggers: () => triggers,
    newTrigger(handler) {
      let source = '';
      return {
        forForm(value) { source = value.getId(); return this; },
        onFormSubmit() { return this; },
        timeBased() { return this; },
        everyMinutes(value) { assert.equal(value, 5); return this; },
        create() { triggers.push({ getHandlerFunction: () => handler, getTriggerSourceId: () => source }); },
      };
    },
  };
  h.context.installHuTubeFeedback();
  h.context.installHuTubeFeedback();
  assert.equal(items.length, 1);
  assert.equal(triggers.length, 2);
  assert.equal(h.values.HUTUBE_TOKEN_ITEM_ID, '42');
});
