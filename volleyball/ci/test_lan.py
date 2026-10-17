"""Real ENet integration: host + eleven separate clients, shared ball and disconnect."""
import os
from pathlib import Path
import socket
import random
import subprocess
import sys
import time

godot = sys.argv[1] if len(sys.argv) > 1 else "godot"
root = Path(__file__).resolve().parents[1]
address = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
logs = root / "build" / "logs"
logs.mkdir(parents=True, exist_ok=True)
# Reserve-check both adjacent UDP ports; a random OS ephemeral port alone
# may leave its discovery neighbour occupied on Windows.
port = None
for candidate in random.SystemRandom().sample(range(25000, 30000), 50):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as discovery_probe:
            probe.bind(("0.0.0.0", candidate))
            discovery_probe.bind(("0.0.0.0", candidate + 1))
            port = candidate
            break
    except OSError:
        continue
assert port is not None, "No free adjacent LAN/discovery port pair"
processes = []
handles = []


def launch(role, index):
    path = logs / f"lan-{role}-{index}.log"
    handle = path.open("w", encoding="utf-8")
    handles.append(handle)
    command = [godot, "--headless", "--max-fps", "60", "--path", str(root), "--script", "tests/test_lan_peer.gd", "--", role, str(index), str(port), address]
    child = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT)
    processes.append((child, path))
    return child, path


def wait_for(path, marker, seconds=8):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if path.exists() and marker in path.read_text(encoding="utf-8", errors="replace"):
            return
        time.sleep(0.1)
    raise AssertionError(f"Missing {marker}: {path.read_text(encoding='utf-8', errors='replace')}")


try:
    print(f"Testing actual ENet endpoint {address}", flush=True)
    host, log = launch("host", 0)
    wait_for(log, "LAN_HOST_READY")
    driver, driver_log = launch("client", 1)
    wait_for(driver_log, "LAN_CLIENT_JOINED 1")
    for index in range(2, 12):
        launch("client", index)
        time.sleep(0.08)
    wait_for(log, "LAN_FULL_12", 10)
    # Transport capacity is 11 remote clients; a thirteenth player cannot join.
    rejected, rejected_log = launch("client", 12)
    time.sleep(1)
    assert "LAN_CLIENT_JOINED" not in rejected_log.read_text(encoding="utf-8", errors="replace"), "13th player admitted"
    rejected.terminate()
    rejected.wait(timeout=5)
    failures = []
    for child, path in processes[:-1]:
        code = child.wait(timeout=25)
        text = path.read_text(encoding="utf-8", errors="replace")
        print(text)
        if code or "SCRIPT ERROR" in text or "ERROR:" in text:
            failures.append(path.name)
    assert not failures, f"LAN integration failures: {failures}"
    print("LAN INTEGRATION PASSED: 12 players, two teams, movement, jump, pickup, lower serve, snapshots, capacity, disconnect")
finally:
    for child, _ in processes:
        if child.poll() is None:
            child.terminate()
    for handle in handles:
        handle.close()
