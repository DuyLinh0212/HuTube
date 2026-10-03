import { csvCell } from './csv';

describe('CSV spreadsheet text safety', () => {
  for (const input of ['=HYPERLINK("https://example.test")', '+1+1', '-1+1', '@SUM(A1)', ' \t=1+1', '\rcommand', '\ncommand']) {
    it(`neutralizes ${JSON.stringify(input)}`, () => expect(csvCell(input)).toBe('"\'' + input.replace(/"/g, '""') + '"'));
  }
  it('preserves plain text and quotes embedded delimiters', () => expect(csvCell('A,"B"')).toBe('"A,""B"""'));
});
