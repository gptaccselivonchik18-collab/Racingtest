"""Pack Emscripten's two WASM binaries around their common NNUE network."""
import hashlib, struct
from pathlib import Path
def uleb(buf,i):
    value=0; shift=0
    while True:
        x=buf[i]; i+=1; value|=(x&127)<<shift
        if x<128:return value,i
        shift+=7
def data_ranges(buf):
    i=8
    while i<len(buf):
        typ=buf[i];size,pos=uleb(buf,i+1);i=pos+size
        if typ!=11:continue
        count,pos=uleb(buf,pos)
        for _ in range(count):
            flag,pos=uleb(buf,pos)
            if flag==2:_,pos=uleb(buf,pos)
            if flag!=1:
                assert buf[pos]==65
                _,pos=uleb(buf,pos+1);assert buf[pos]==11;pos+=1
            n,pos=uleb(buf,pos)
            yield pos,pos+n
            pos+=n
def make_recipe(wasm,net):
    header=net[:64];start=wasm.index(header);net_pos=0;ops=[];literal_from=0;rebuilt=bytearray()
    for begin,end in data_ranges(wasm):
        if end<=start or net_pos>=len(net):continue
        begin=max(begin,start)
        prefix=wasm[begin:min(end,begin+64)]
        at=net.find(prefix,net_pos,min(len(net),net_pos+32768+len(prefix)))
        if at<0:continue
        amount=min(end-begin,len(net)-at)
        if wasm[begin:begin+amount]!=net[at:at+amount]:continue
        literal=wasm[literal_from:begin];ops.append((literal,at,amount))
        rebuilt.extend(literal);rebuilt.extend(net[at:at+amount])
        literal_from=begin+amount;net_pos=at+amount
    tail=wasm[literal_from:];ops.append((tail,0,0));rebuilt.extend(tail)
    assert rebuilt==wasm
    return struct.pack('<II',len(wasm),len(ops))+b''.join(struct.pack('<III',len(lit),at,n)+lit for lit,at,n in ops)
def build_engine_assets(target,net,variants):
    target.mkdir(exist_ok=True,parents=True)
    def part(buf):
        digest=hashlib.sha256(buf).hexdigest()
        (target/(digest+'.bin')).write_bytes(buf)
        return dict(id=digest,size=len(buf))
    netparts=[part(net[i:i+4194304]) for i in range(0,len(net),4194304)]
    output={}
    for key,(glue,wasm_path) in variants.items():
        wasm=wasm_path.read_bytes();(target/(key+'.js')).write_bytes(glue.read_bytes())
        parts=[part(make_recipe(wasm,net)),*netparts] if key!='lite' else [part(wasm)]
        output[key]=dict(parts=parts,size=sum(p['size'] for p in parts),sha256=hashlib.sha256(wasm).hexdigest())
        print(key,'download',output[key]['size'],'first part',parts[0]['size'])
    return output
