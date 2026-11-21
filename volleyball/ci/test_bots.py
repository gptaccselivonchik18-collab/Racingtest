"""Real host + two guests: twelve game bots, coach, removal, mixed teams and serving."""
from pathlib import Path
import random
import socket
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
godot = sys.argv[1]
address = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
logs = root / "build" / "logs"
logs.mkdir(parents=True, exist_ok=True)
for port in random.SystemRandom().sample(range(30000, 40000), 50):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as first, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as second:
            first.bind(("0.0.0.0", port))
            second.bind(("0.0.0.0", port + 1))
            break
    except OSError:
        continue
else:
    raise AssertionError("No free UDP pair")
children = []
handles = []
try:
    for index, role in enumerate(["host", "client", "client"]):
        path = logs / f"bots-{index}.log"
        handle = path.open("w", encoding="utf-8")
        handles.append(handle)
        child = subprocess.Popen([godot, "--headless", "--max-fps", "60", "--path", str(root), "--script", "tests/test_bots_peer.gd", "--", role, str(port), address], stdout=handle, stderr=subprocess.STDOUT)
        children.append((child, path))
        if index == 0:
            deadline = time.monotonic() + 10
            while "BOTS_HOST_READY" not in path.read_text(encoding="utf-8", errors="replace"):
                assert child.poll() is None and time.monotonic() < deadline, path.read_text(encoding="utf-8", errors="replace")
                time.sleep(0.1)
    failures = []
    for child, path in children:
        code = child.wait(timeout=45)
        text = path.read_text(encoding="utf-8", errors="replace")
        print(text)
        if code or "ERROR:" in text or "SCRIPT ERROR" in text or "_PASSED" not in text:
            failures.append(path.name)
    assert not failures, failures
    print("BOTS INTEGRATION PASSED: twelve host-authoritative bots, training coexistence, shared removal, consent, mixed teams, real serve")
finally:
    for child, _ in children:
        if child.poll() is None:
            child.terminate()
    for handle in handles:
        handle.close()
