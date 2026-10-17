"""Compare QR URL contracts with only fixed synthetic account/reference data."""
import hashlib,io,json,re
from pathlib import Path
from urllib.request import urlopen
from urllib.parse import urlencode,urlsplit,parse_qs
from PIL import Image
import zxingcpp

def main():
    account='0000000000';reference='QCLOCAL-DIAG0001';amount='12345';bank='970423'
    out=Path(__file__).resolve().parents[3]/'outputs/20261016-all-remaining/qr-diagnostic';out.mkdir(parents=True,exist_ok=True)
    urls={
        'legacy':'https://vietqr.app/img?'+urlencode({'acc':account,'bank':bank,'amount':amount,'des':reference}),
        'official':'https://img.vietqr.io/image/'+bank+'-'+account+'-compact.png?'+urlencode({'amount':amount,'addInfo':reference})}
    results=[]
    for name,url in urls.items():
        uri=urlsplit(url);query=parse_qs(uri.query)
        assert uri.scheme=='https' and uri.hostname in ('vietqr.app','img.vietqr.io')
        assert query.get('amount')==[amount]
        assert (query.get('acc')==[account] and query.get('des')==[reference]) if name=='legacy' else (account in uri.path and query.get('addInfo')==[reference])
        result={'endpoint_kind':name,'input_kind':'Fixed synthetic account0000000000, referenceQCLOCAL-DIAG0001, amount12345. No real transfer/payment or credentials.'}
        try:
            with urlopen(url,timeout=25) as response:payload=response.read();result['http_status']=response.status
            image=Image.open(io.BytesIO(payload));qr=zxingcpp.read_barcode(image);assert qr and qr.text
            (out/(name+'.png')).write_bytes(payload);text=qr.text;fields={};offset=0
            while offset<len(text):
                tag=text[offset:offset+2];length=int(text[offset+2:offset+4]);fields[tag]=text[offset+4:offset+4+length];offset+=4+length
            normalize=lambda s:re.sub('[^A-Za-z0-9]','',s)
            result.update(amount=fields.get('54'),exact_reference=reference in text,
                normalized_reference=normalize(reference) in normalize(text),account_matches=account in text,
                additional_data_length=len(fields.get('62','')),sha256=hashlib.sha256(payload).hexdigest())
        except Exception as error:result.update(error_type=type(error).__name__,http_status=getattr(error,'code',result.get('http_status')))
        results.append(result)
    (out/'diagnostic.json').write_text(json.dumps(results,indent=2),encoding='utf-8');print(json.dumps(results))

if __name__=='__main__':main()
