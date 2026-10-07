/** Local workbook authoring with the bundled @oai/artifact-tool runtime.
 * Usage: node export_web_report.mjs report.json output.xlsx [preview-directory]
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';

const [source, destination, previews] = process.argv.slice(2);
if (!source || !destination) throw new Error('report.json and output.xlsx required');
const report = JSON.parse(await fs.readFile(source, 'utf8'));
const workbook = Workbook.create();
const names = ['Summary', 'User', 'Admin'];
const sheets = Object.fromEntries(names.map(name => [name, workbook.worksheets.add(name)]));
const statuses = ['PASSED', 'FAILED', 'BLOCKED', 'REUSED'];
const columns = ['Test Case#', 'Test Title / Scenario', 'Test Summary', 'Test Steps', 'Test Data', 'Expected Result', 'Post-condition', 'Actual Result', 'Status', 'Notes'];
const evidenceNotes = item => [item.screenshot || 'Không có screenshot',
  item.first_passed_evidence && `First action PASS: ${item.first_passed_evidence.screenshot}`,
  item.script && `Script: ${item.script}:${item.script_line}`].filter(Boolean).join('\n');
for (const [application, name] of [['user', 'User'], ['admin', 'Admin']]) {
  const sheet = sheets[name];
  const cases = report.cases.filter(item => item.application === application);
  const rows = cases.map(item => [item.id, item.name, `${item.module} / ${item.actor}`, item.steps || 'Thực hiện assertion theo script và chụp bằng chứng', item.data || 'Synthetic E2E fixtures', item.expected || 'Assertion trong script phải thành công', 'Database E2E riêng; fixture chính được giữ cho lần chạy sau', item.actual || (item.status === 'reused' ? 'Fixture đã có được đọc lại và kiểm tra; không chạy lại thao tác tạo' : item.status === 'passed' ? 'Assertions hoàn tất' : 'Xem report.json và screenshot'), item.status.toUpperCase(), evidenceNotes(item)]);
  sheet.getRange('A1:J1').merge();
  sheet.getRange('A1').values = [[`HuTube • Web ${name} • ${report.run_id}`]];
  sheet.getRange('A2:J2').merge();
  sheet.getRange('A2').values = [['SMOKE chỉ kiểm tra route. REUSED kiểm tra fixture tồn tại. Các flow chưa có script vẫn chưa hoàn tất.']];
  sheet.getRange('A4:J4').values = [columns];
  if (rows.length) sheet.getRange(`A5:J${rows.length + 4}`).values = rows;
  sheet.getRange(`A1:J${rows.length + 4}`).format.font = {name:'Calibri', size:11, color:'#17243A'};
  sheet.getRange(`A4:J${rows.length + 4}`).format.wrapText = true;
  sheet.getRange(`A4:J${rows.length + 4}`).format.verticalAlignment = 'top';
  sheet.getRange(`A5:J${rows.length + 4}`).format.rowHeight = 120;
  [24,43,25,43,30,43,40,43,13,56].forEach((width,index) => { sheet.getRange(`${String.fromCharCode(65+index)}:${String.fromCharCode(65+index)}`).format.columnWidth = width; });
  sheet.getRange('A1:J1').format = {fill:'#12243A',font:{bold:true,size:17,color:'#FFFFFF'},rowHeight:32};
  sheet.getRange('A2:J2').format = {font:{italic:true,color:'#59677D'},rowHeight:25};
  sheet.getRange('A4:J4').format = {fill:'#1D5278',font:{bold:true,color:'#FFFFFF'},rowHeight:35,wrapText:true};
  sheet.freezePanes.freezeRows(4); sheet.freezePanes.freezeColumns(1); sheet.showGridLines=false;
  for (const [status, fill, color] of [['PASSED','#E2F1E9','#226342'],['FAILED','#FBE4E5','#A42D39'],['BLOCKED','#FFF0D5','#895D15'],['REUSED','#E5EEF8','#365E8C']]) {
    sheet.getRange(`I5:I${rows.length + 4}`).conditionalFormats.add('containsText',{text:status,format:{fill,font:{bold:true,color}}});
  }
  sheet.tables.add(`A4:J${rows.length + 4}`,true,`Web${name}Results`);
}
const summary = sheets.Summary;
summary.getRange('A1:F1').merge(); summary.getRange('A1').values = [['HuTube • Web E2E results']];
summary.getRange('A2:F2').merge(); summary.getRange('A2').values = [[`Run: ${report.run_id}`]];
summary.getRange('A4:F4').values = [['Application', ...statuses, 'TOTAL']];
summary.getRange('A5:A6').values = [['User'],['Admin']];
for (const [index,name] of ['User','Admin'].entries()) {
  const count=report.cases.filter(item => item.application===name.toLowerCase()).length;
  summary.getRange(`B${index+5}:E${index+5}`).formulas = [statuses.map(status => `=COUNTIF('${name}'!I5:I${count+4},"${status}")`)];
  summary.getRange(`F${index+5}`).formulas = [[`=SUM(B${index+5}:E${index+5})`]];
}
summary.getRange('A8:F8').merge(); summary.getRange('A8').values=[['Nguồn: report.json cùng run; tên/cột theo DevLearningHub_Testcase.xlsx (E2E).']];
summary.getRange('A10:F11').merge(); summary.getRange('A10').values=[['Đây là kết quả của các case đã triển khai. Chưa chứng minh hoàn tất mọi binding/flow trong WEB_TEST_SCENARIOS.md. PASS route SMOKE không thay thế test CRUD hoặc phân quyền.']];
summary.getRange('A13:F14').merge(); summary.getRange('A13').values=[['Mở User/Admin để lọc FAILED/BLOCKED. Notes chứa đường dẫn screenshot trong gói evidence. Fixture dùng database riêng; không sử dụng mật khẩu tài khoản cá nhân.']];
summary.getRange('A1:F14').format = {font:{name:'Calibri',size:12,color:'#17243A'},wrapText:true,columnWidth:21,rowHeight:25};
summary.getRange('A1:F1').format={fill:'#12243A',font:{bold:true,size:20,color:'#FFFFFF'},rowHeight:42};
summary.getRange('A4:F4').format={fill:'#1D5278',font:{bold:true,color:'#FFFFFF'},rowHeight:30};
summary.getRange('B5:F6').format.font={bold:true,size:16,color:'#17243A'};
summary.getRange('A10:F11').format.fill='#FFF0D5';
summary.showGridLines=false;
workbook.recalculate();
console.log((await workbook.inspect({kind:'table',range:'Summary!A4:F6',include:'values,formulas',tableMaxRows:3,tableMaxCols:6,maxChars:1800})).ndjson);
console.log((await workbook.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!|#SPILL!',options:{useRegex:true,maxResults:10},maxChars:800})).ndjson);
if (previews) {
  await fs.mkdir(previews,{recursive:true});
  for (const name of names) {
    const preview=await workbook.render({sheetName:name,range:name==='Summary'?'A1:F14':'A1:J7',scale:1});
    await fs.writeFile(path.join(previews,name+'.png'),new Uint8Array(await preview.arrayBuffer()));
  }
}
await fs.mkdir(path.dirname(destination),{recursive:true});
await (await SpreadsheetFile.exportXlsx(workbook)).save(destination);
console.log(destination);
