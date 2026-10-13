from pathlib import Path
import hashlib, subprocess, urllib.request, json, re
root = Path(__file__).resolve().parents[1]
model = root / 'build/qwen-test.gguf'
sha = '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e'
if not model.exists():
    urllib.request.urlretrieve('https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/91cad51170dc346986eccefdc2dd33a9da36ead9/qwen2.5-1.5b-instruct-q4_k_m.gguf', model)
with model.open('rb') as f:
    assert hashlib.file_digest(f, 'sha256').hexdigest() == sha
framework = next(p.parent for p in (root / 'Vendor/llama.xcframework').rglob('llama.framework') if 'macos' in str(p))
binary = root / 'build/llama-smoke'
subprocess.run(['clang++', '-std=c++17', str(root/'Native/CoachLlama.cpp'), str(root/'scripts/llama_smoke.cpp'), '-F'+str(framework), '-Wl,-rpath,'+str(framework), '-framework', 'llama', '-framework', 'Foundation', '-framework', 'Metal', '-framework', 'Accelerate', '-o', str(binary)], check=True)
result = subprocess.run([str(binary), str(model)], check=True, timeout=180, capture_output=True, text=True, encoding='utf-8')
print(result.stdout)
russian = re.search(r'BEGIN_RUSSIAN\n(.*?)\nEND_RUSSIAN', result.stdout, re.S).group(1)
assert any('а' <= c.lower() <= 'я' for c in russian), 'Actual model did not produce Cyrillic Russian'
decision = re.search(r'BEGIN_DECISION\n(.*?)\nEND_DECISION', result.stdout, re.S).group(1)
first, last = decision.index('{'), decision.rindex('}')
plan = json.loads(decision[first:last+1])
assert plan['selected'] in ['gatherInformation', 'recover']
assert 0 <= plan['confidence'] <= 100
assert len(plan['alternatives']) == 2
assert {a['action'] for a in plan['alternatives']} == {'gatherInformation', 'recover'}
for a in plan['alternatives']:
    assert a['reason'] in ['insufficientEvidence', 'healthLimited']
    assert 0 <= a['utility'] <= 100 and 0 <= a['risk'] <= 100
print('LOCAL_MODEL_CHECK Russian_output=true structured_alternatives=true actual_weights=true')
