/**
 * Bound to the HuTube Google Form (Forms > Script editor).
 * Script Properties, configured by the form owner:
 * HUTUBE_API_BASE_URL = https://hutube.onrender.com/api/v1
 * HUTUBE_WEBHOOK_SECRET = same random secret as FeedbackSurvey__WebhookSecret
 * Run installHuTubeFeedback() once and authorize the Forms, triggers and URL Fetch scopes.
 * Never put this secret in a form question, frontend config or a public repository.
 */
const HUTUBE_PUBLIC_FORM_ID = '1FAIpQLSef9jF_PK4qnoEZjPjS7kq1Lk4iQbEtoSXxS8XMkoWcVcoecg';
const HUTUBE_TOKEN_TITLE = 'Mã khảo sát HuTube';
const HUTUBE_PENDING_PREFIX = 'hutube_pending_';

function installHuTubeFeedback() {
  console.log('[1/4] Bắt đầu cài đặt: đọc Thuộc tính tập lệnh (Script properties).');
  const config = hutubeConfig_();
  console.log('[2/4] Kiểm tra Google Form đang liên kết với dự án.');
  const form = FormApp.getActiveForm();
  if (!form || form.getPublishedUrl().indexOf('/' + HUTUBE_PUBLIC_FORM_ID + '/') === -1) {
    throw new Error('Hãy mở Apps Script từ đúng Google Form khảo sát HuTube.');
  }
  const props = PropertiesService.getScriptProperties();
  console.log('[3/4] Chuẩn bị câu hỏi mã khảo sát.');
  let item = null;
  const savedId = props.getProperty('HUTUBE_TOKEN_ITEM_ID');
  if (savedId) item = form.getItems(FormApp.ItemType.TEXT).find(function (entry) { return String(entry.getId()) === savedId; });
  if (!item) item = form.getItems(FormApp.ItemType.TEXT).find(function (entry) { return entry.getTitle() === HUTUBE_TOKEN_TITLE; });
  item = item ? item.asTextItem() : form.addTextItem().setTitle(HUTUBE_TOKEN_TITLE);
  item.setHelpText('Mã được điền tự động từ HuTube để ghi nhận bạn đã hoàn thành. Vui lòng giữ nguyên mã. Nếu lỡ xóa hoặc sửa, hãy mở lại khảo sát từ HuTube để nhận mã đúng.');
  item.setRequired(true);
  item.setValidation(FormApp.createTextValidation()
    .requireTextMatchesPattern('^[a-f0-9]{32}\\.[a-f0-9]{64}$')
    .setHelpText('Mã khảo sát không đúng định dạng. Hãy mở lại khảo sát từ HuTube và giữ nguyên mã được điền sẵn.')
    .build());
  props.setProperties({ HUTUBE_FORM_ID: form.getId(), HUTUBE_TOKEN_ITEM_ID: String(item.getId()) });
  const setupToken = '0'.repeat(32) + '.' + '0'.repeat(64);
  const prefilled = form.createResponse().withItemResponse(item.createResponse(setupToken)).toPrefilledUrl();
  const entry = /[?&]entry\.(\d+)=/.exec(prefilled);
  if (!entry) throw new Error('Không tìm được entry ID của mã khảo sát.');

  console.log('[4/4] Tạo trình kích hoạt gửi bài và thử lại.');
  const triggers = ScriptApp.getProjectTriggers();
  if (!triggers.some(function (trigger) { return trigger.getHandlerFunction() === 'onHuTubeFeedbackSubmit' && trigger.getTriggerSourceId() === form.getId(); })) {
    ScriptApp.newTrigger('onHuTubeFeedbackSubmit').forForm(form).onFormSubmit().create();
  }
  if (!triggers.some(function (trigger) { return trigger.getHandlerFunction() === 'retryHuTubeFeedback'; })) {
    ScriptApp.newTrigger('retryHuTubeFeedback').timeBased().everyMinutes(5).create();
  }
  console.log('Cài đặt xong. Đặt các biến sau trên backend rồi triển khai:');
  console.log('FeedbackSurvey__Enabled=true');
  console.log('FeedbackSurvey__TokenEntryId=' + entry[1]);
  console.log('FeedbackSurvey__WebhookSecret phải giống HUTUBE_WEBHOOK_SECRET trong Script Properties.');
  console.log('API nhận xác nhận: ' + config.api + '/feedback-survey/google-form-submission');
}

function onHuTubeFeedbackSubmit(event) {
  const props = PropertiesService.getScriptProperties();
  if (!event || !event.response || !event.source || event.source.getId() !== props.getProperty('HUTUBE_FORM_ID')) {
    throw new Error('Hàm này phải được chạy bằng trigger On form submit của Google Forms.');
  }
  const tokenItemId = props.getProperty('HUTUBE_TOKEN_ITEM_ID');
  const answer = event.response.getItemResponses().find(function (response) { return String(response.getItem().getId()) === tokenItemId; });
  const token = answer ? String(answer.getResponse()).trim() : '';
  if (!/^[a-f0-9]{32}\.[a-f0-9]{64}$/.test(token)) {
    console.log('Bài khảo sát không có mã liên kết HuTube; câu trả lời vẫn được Google Forms lưu.');
    return;
  }
  const responseId = event.response.getId();
  const body = JSON.stringify({
    formId: HUTUBE_PUBLIC_FORM_ID,
    surveyToken: token,
    responseId: responseId,
    submittedAt: event.response.getTimestamp().toISOString(),
  });
  const key = HUTUBE_PENDING_PREFIX + responseId;
  // Save before the HTTP call so a cold start, timeout or failed execution is retryable.
  props.setProperty(key, body);
  hutubeDeliver_(key, body);
}

function retryHuTubeFeedback() {
  const pending = PropertiesService.getScriptProperties().getProperties();
  const keys = Object.keys(pending).filter(function (key) { return key.indexOf(HUTUBE_PENDING_PREFIX) === 0; });
  const started = Date.now();
  for (let index = 0; index < Math.min(keys.length, 20) && Date.now() - started < 240000; index++) {
    hutubeDeliver_(keys[index], pending[keys[index]]);
  }
}

function hutubeDeliver_(key, body) {
  try {
    const config = hutubeConfig_();
    const timestamp = String(Math.floor(Date.now() / 1000));
    const bytes = Utilities.computeHmacSha256Signature(timestamp + '.' + body, config.secret, Utilities.Charset.UTF_8);
    const signature = 'sha256=' + bytes.map(function (value) { return ('0' + ((value + 256) % 256).toString(16)).slice(-2); }).join('');
    const response = UrlFetchApp.fetch(config.api + '/feedback-survey/google-form-submission', {
      method: 'post',
      contentType: 'application/json',
      payload: body,
      headers: { 'X-HuTube-Survey-Timestamp': timestamp, 'X-HuTube-Survey-Signature': signature },
      muteHttpExceptions: true,
      followRedirects: false,
    });
    const status = response.getResponseCode();
    if ((status >= 200 && status < 300) || status === 400 || status === 404 || status === 413) {
      PropertiesService.getScriptProperties().deleteProperty(key);
      if (status >= 400) console.warn('Bài gửi không thể liên kết với tài khoản HuTube (HTTP ' + status + ').');
    }
    else console.warn('Chưa đồng bộ được khảo sát (HTTP ' + status + '). Bài gửi được giữ lại để thử lại.');
  } catch (error) {
    // Avoid logging payloads, survey tokens, answers or secrets.
    console.warn('Chưa kết nối được API HuTube. Bài gửi được giữ lại để thử lại.');
  }
}

function hutubeConfig_() {
  const props = PropertiesService.getScriptProperties();
  const api = (props.getProperty('HUTUBE_API_BASE_URL') || '').replace(/\/+$/, '');
  const secret = props.getProperty('HUTUBE_WEBHOOK_SECRET') || '';
  if (!/^https:\/\/[^\s?#]+\/api\/v1$/.test(api))
    throw new Error('Mở ⚙ Cài đặt dự án → Thuộc tính tập lệnh → Thêm thuộc tính: HUTUBE_API_BASE_URL = https://hutube.onrender.com/api/v1, rồi Lưu.');
  if (secret.length < 32)
    throw new Error('Mở ⚙ Cài đặt dự án → Thuộc tính tập lệnh → Thêm HUTUBE_WEBHOOK_SECRET: chuỗi bí mật ít nhất 32 ký tự, giống FeedbackSurvey__WebhookSecret trên backend Render, rồi Lưu.');
  return { api: api, secret: secret };
}
