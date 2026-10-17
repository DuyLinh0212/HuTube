"""Read-only PDF validation with bundled pypdf; no replacement document authored."""
import json,sys,unicodedata
from pathlib import Path
from pypdf import PdfReader
path=Path(sys.argv[1]);expected=json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
assert path.read_bytes().startswith(b'%PDF-'),'Downloaded file is not a PDF'
reader=PdfReader(path);assert reader.pages,'PDF has no pages'
text=' '.join((page.extract_text() or '') for page in reader.pages)
normalize=lambda value:''.join(unicodedata.normalize('NFC',value).split())
for label,value in expected.items():
    assert normalize(value) in normalize(text),'PDF omits actual published '+label
print(json.dumps({'pages':len(reader.pages),'published_fields_verified':sorted(expected),'text_characters':len(text)}))
