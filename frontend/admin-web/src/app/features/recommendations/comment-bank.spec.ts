import { mergeCommentTemplates, parseCommentCsv } from './comment-bank';

describe('Comment CSV', () => {
  it('reads UTF-8 BOM, CRLF, escaped quotes, commas and multiline comments', () => {
    const rows = parseCommentCsv('\uFEFFcomment\r\n"Nhạc hay, rất thư giãn"\r\n"Một câu ""trích dẫn"""\r\n"Dòng một\nDòng hai"\r\n');
    expect(rows).toEqual([['Nhạc hay, rất thư giãn'], ['Một câu "trích dẫn"'], ['Dòng một\nDòng hai']]);
  });

  it('appends valid templates and reports duplicates and invalid rows', () => {
    const result = mergeCommentTemplates(['Existing'], parseCommentCsv('comment\nExisting\nNew comment\nNew comment\nno\nbad,columns\n'));
    expect(result.templates).toEqual(['Existing', 'New comment']);
    expect(result).toEqual(jasmine.objectContaining({ added: 1, duplicates: 2, invalid: 2, overflow: 0 }));
  });

  it('keeps the existing bank and never silently exceeds 100 templates', () => {
    const bank = Array.from({ length: 99 }, (_, i) => `Existing ${i}`);
    const result = mergeCommentTemplates(bank, [['First'], ['Second'], ['x'.repeat(5001)]]);
    expect(result.templates).toEqual([...bank, 'First']);
    expect(result.overflow).toBe(1); expect(result.invalid).toBe(1);
    expect(bank.length).toBe(99);
  });

  for (const csv of ['', 'wrong\nValid comment', 'comment,other\nA,B', 'comment\n"Unclosed', 'comment\n"Closed"junk', 'comment\nBad"quote']) {
    it(`rejects malformed CSV ${JSON.stringify(csv)}`, () => {
      expect(() => parseCommentCsv(csv)).toThrowError('INVALID_COMMENT_CSV');
    });
  }
});
