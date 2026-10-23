"""Diagnostic-only timings for Redis, asyncio and the real TLS game listener."""
import asyncio
import ctypes
import json
import os
import socket
import ssl
import threading
import time


class TimedRedis:
    def __init__(self, client, rows):
        self.client, self.rows = client, rows

    def __getattr__(self, name):
        method = getattr(self.client, name)

        def measured(*args, **kwargs):
            started = time.monotonic()
            row = {"command": name, "started": started, "ok": False}
            try:
                result = method(*args, **kwargs)
                row["ok"] = True
                return result
            except Exception as error:
                row["error"] = type(error).__name__
                raise
            finally:
                row["seconds"] = time.monotonic() - started
                self.rows.append(row)
        return measured


def windows_memory():
    if os.name != "nt":
        return {}

    class Memory(ctypes.Structure):
        _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong)] + [
            (name, ctypes.c_ulonglong) for name in (
                "physical_total", "physical_available", "page_total", "page_available",
                "virtual_total", "virtual_available", "extended_available")]
    state = Memory()
    state.length = ctypes.sizeof(state)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(state)):
        return {"error": "GlobalMemoryStatusEx"}
    return {name: getattr(state, name) for name in (
        "load", "physical_total", "physical_available", "page_total", "page_available")}


class SnapshotObservation:
    def __init__(self, fixture):
        self.fixture = fixture
        self.stop = threading.Event()
        self.data = {"diagnostic_only": True, "commands": [], "tls_game_ping": [],
                     "async_redis_ping": [], "windows_memory": []}
        self.threads = []

    def sample(self, key, operation):
        started = time.monotonic()
        row = {"started": started, "ok": False}
        try:
            operation()
            row["ok"] = True
        except Exception as error:
            row["error"] = type(error).__name__
        row["seconds"] = time.monotonic() - started
        self.data[key].append(row)
        return row["ok"]

    def tls_ping(self):
        try:
            port, certificate = self.fixture.snapshot_endpoint
            context = ssl.create_default_context(cafile=str(certificate))
            context.minimum_version = ssl.TLSVersion.TLSv1_2

            def ping():
                # Reconnect for each public health ping: authentication expiry
                # must not end an idle observer before the RDB copy finishes.
                with socket.create_connection(("127.0.0.1", port), timeout=5) as raw:
                    with context.wrap_socket(raw, server_hostname="localhost") as wrapped:
                        wrapped.settimeout(5)
                        wrapped.sendall(b"\x77")
                        if wrapped.recv(1) != b"\x58":
                            raise RuntimeError("Unexpected PONG")

            while not self.stop.is_set():
                if not self.sample("tls_game_ping", ping):
                    break
                self.data["windows_memory"].append({"at": time.monotonic(), **windows_memory()})
                self.stop.wait(0.5)
        except Exception as error:
            self.data["tls_monitor_error"] = type(error).__name__

    async def async_ping(self):
        from redis.asyncio import Redis
        from redis.asyncio.retry import Retry
        from redis.backoff import NoBackoff

        client = Redis(host="127.0.0.1", port=self.fixture.port,
                       password=self.fixture.password_file.read_text(),
                       socket_timeout=5, socket_connect_timeout=5,
                       retry=Retry(NoBackoff(), 0), max_connections=1)
        try:
            while not self.stop.is_set():
                started = time.monotonic()
                row = {"started": started, "ok": False}
                try:
                    await client.ping()
                    row["ok"] = True
                except Exception as error:
                    row["error"] = type(error).__name__
                row["seconds"] = time.monotonic() - started
                self.data["async_redis_ping"].append(row)
                if not row["ok"]:
                    break
                await asyncio.sleep(0.1)
        finally:
            await client.aclose()

    def __enter__(self):
        for target in (self.tls_ping, lambda: asyncio.run(self.async_ping())):
            thread = threading.Thread(target=target, daemon=True)
            thread.start()
            self.threads.append(thread)
        return self

    def wrap(self, client):
        return TimedRedis(client, self.data["commands"])

    def __exit__(self, *_):
        self.stop.set()
        for thread in self.threads:
            thread.join(timeout=6)
        self.data["threads_finished"] = all(not thread.is_alive() for thread in self.threads)
        self.data["windows_memory_after"] = windows_memory()
        try:
            with self.fixture.client() as client:
                self.data["latency_events"] = client.latency_latest()
                self.data["redis_state"] = client.info("persistence") | client.info("memory") | client.info("stats")
                self.data["slowlog"] = [{"duration_us": row["duration"],
                                         "command": row["command"].split(b" ", 1)[0].decode()}
                                        for row in client.slowlog_get(12)]
        except Exception as error:
            self.data["diagnostic_collection_error"] = type(error).__name__
        path = self.fixture.evidence / "windows-snapshot-observation.json"
        path.write_text(json.dumps(self.data, indent=2) + "\n")
