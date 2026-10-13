from pathlib import Path
import hashlib, subprocess, urllib.request
root = Path(__file__).resolve().parents[1]
model = root / 'build/qwen-test.gguf'
sha = '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db'
if not model.exists():
    urllib.request.urlretrieve('https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/9217f5db79a29953eb74d5343926648285ec7e67/qwen2.5-0.5b-instruct-q4_k_m.gguf', model)
with model.open('rb') as f:
    assert hashlib.file_digest(f, 'sha256').hexdigest() == sha
framework = next(p.parent for p in (root / 'Vendor/llama.xcframework').rglob('llama.framework') if 'macos' in str(p))
binary = root / 'build/llama-smoke'
subprocess.run(['clang++', '-std=c++17', str(root/'Native/CoachLlama.cpp'), str(root/'scripts/llama_smoke.cpp'), '-F'+str(framework), '-framework', 'llama', '-framework', 'Foundation', '-framework', 'Metal', '-framework', 'Accelerate', '-o', str(binary)], check=True)
subprocess.run([str(binary), str(model)], check=True, timeout=120)
