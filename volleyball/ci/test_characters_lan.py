"""Real ENet host and guest: fixed characters, teams, bots and physical quick set."""
from pathlib import Path
import random,socket,subprocess,sys,time
root=Path(__file__).resolve().parents[1]
logs=root/'build/logs';logs.mkdir(parents=True,exist_ok=True)
for port in random.SystemRandom().sample(range(30000,40000),30):
 try:
  with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:s.bind(('127.0.0.1',port))
  with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:s.bind(('127.0.0.1',port+1))
  break
 except OSError:continue
children=[];handles=[]
try:
 for index,role in enumerate(['host','guest']):
  path=logs/f'characters-{index}.log';handle=path.open('w',encoding='utf-8');handles.append(handle)
  child=subprocess.Popen([sys.argv[1],'--headless','--max-fps','60','--path',str(root),'--script','tests/characters_peer.gd','--',role,str(port),sys.argv[2] if len(sys.argv)>2 else 'normal'],stdout=handle,stderr=subprocess.STDOUT)
  children.append((child,path))
  if index==0:
   until=time.monotonic()+10
   while 'CHARACTER_HOST_READY' not in path.read_text(encoding='utf-8',errors='replace'):
    assert child.poll() is None and time.monotonic()<until
    time.sleep(.1)
 for child,path in children:
  code=child.wait(timeout=25);text=path.read_text(encoding='utf-8',errors='replace');print(text)
  assert code==0 and 'ERROR:' not in text and 'CHARACTER_PEER_PASSED' in text
 print('CHARACTERS LAN PASSED')
finally:
 for child,_ in children:
  if child.poll() is None:child.terminate()
 for handle in handles:handle.close()
