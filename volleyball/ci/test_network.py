"""Real UDP loss/jitter proxy, version refusal and a clean disconnect/rejoin.

Runs actual Godot processes; does not stand in for testing physical phones.
"""
from pathlib import Path
import heapq
import random
import socket
import subprocess
import sys
import threading
import time

root = Path(__file__).resolve().parents[1]
godot = sys.argv[1] if len(sys.argv) > 1 else 'godot'
logs = root / 'build' / 'logs'
logs.mkdir(parents=True, exist_ok=True)
children, handles = [], []
stop = threading.Event()
metrics = {'sent': 0, 'dropped': 0}


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def launch(role, port):
    log = logs / f'network-{role}.log'
    output = log.open('w', encoding='utf-8')
    handles.append(output)
    child = subprocess.Popen([godot, '--headless', '--path', str(root), '--script', 'tests/test_network_peer.gd', '--', role, str(port), '127.0.0.1'], stdout=output, stderr=subprocess.STDOUT)
    children.append(child)
    return child, log


def wait_for(log, marker):
    until = time.monotonic() + 10
    while time.monotonic() < until:
        if marker in log.read_text(encoding='utf-8', errors='replace'):
            return
        time.sleep(.05)
    raise AssertionError(log.read_text(encoding='utf-8', errors='replace'))


def relay(sock, host_port):
    rng = random.Random(15015)
    pending = []
    client = None
    sequence = 0
    sock.settimeout(.005)
    while not stop.is_set():
        try:
            data, source = sock.recvfrom(65535)
            from_host = source == ('127.0.0.1', host_port)
            if not from_host:
                client = source
            target = client if from_host else ('127.0.0.1', host_port)
            sequence += 1
            # Deterministic loss in both directions, plus packet reordering.
            if sequence % (17 if from_host else 13) == 0:
                metrics['dropped'] += 1
            elif target:
                heapq.heappush(pending, (time.monotonic() + rng.uniform(.015, .07), sequence, data, target))
        except (socket.timeout, ConnectionResetError):
            pass
        while pending and pending[0][0] <= time.monotonic():
            _, _, data, target = heapq.heappop(pending)
            sock.sendto(data, target)
            metrics['sent'] += 1


try:
    # Godot advertises on the adjacent port; check both before use.
    for _ in range(30):
        host_port = random.SystemRandom().randrange(30000, 35000)
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as a, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as b:
                a.bind(('0.0.0.0', host_port))
                b.bind(('0.0.0.0', host_port + 1))
            break
        except OSError:
            continue
    else:
        raise AssertionError('No free server/discovery port pair')
    host, host_log = launch('host', host_port)
    wait_for(host_log, 'NETWORK_HOST_READY')
    old, old_log = launch('old', host_port)
    assert old.wait(timeout=12) == 0, old_log.read_text(encoding='utf-8', errors='replace')
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as proxy:
        proxy.bind(('127.0.0.1', 0))
        worker = threading.Thread(target=relay, args=(proxy, host_port), daemon=True)
        worker.start()
        client, client_log = launch('client', proxy.getsockname()[1])
        try:
            assert client.wait(timeout=28) == 0, client_log.read_text(encoding='utf-8', errors='replace')
            # The impaired proxy can drop the final disconnect datagram.
            # Keep relaying until ENet detects the departed peer; ten seconds
            # can expire before transport cleanup. All state checks stay strict.
            assert host.wait(timeout=40) == 0, host_log.read_text(encoding='utf-8', errors='replace')
        finally:
            stop.set()
            worker.join(timeout=2)
    for log in (host_log, old_log, client_log):
        text = log.read_text(encoding='utf-8', errors='replace')
        print(text)
        assert 'SCRIPT ERROR' not in text and 'ERROR:' not in text
    assert metrics['dropped'] > 0 and metrics['sent'] > 100, metrics
    print(f'NETWORK INTEGRATION PASSED: loss/jitter, reliable action release, version refusal, reconnect; {metrics}')
finally:
    stop.set()
    for child in children:
        if child.poll() is None:
            child.terminate()
            child.wait(timeout=5)
    for handle in handles:
        handle.close()
