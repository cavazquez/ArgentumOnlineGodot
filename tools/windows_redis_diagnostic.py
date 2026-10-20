"""Compara Redis real en Windows con ambos loops, sin Godot ni cuentas de juego."""
import argparse
import asyncio
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import tempfile
import time

from redis.asyncio import Redis

spec = importlib.util.spec_from_file_location("integration_world", Path(__file__).with_name("integration-world.py"))
world = importlib.util.module_from_spec(spec)
spec.loader.exec_module(world)


async def probe(fixture):
    client = Redis(host="127.0.0.1", port=fixture.port, password=fixture.password_file.read_text(), decode_responses=True, socket_timeout=5, socket_connect_timeout=5, max_connections=20)
    samples, errors, jitter = [], [], []
    active = True

    async def heartbeat():
        while active:
            start = time.monotonic()
            await asyncio.sleep(0.01)
            jitter.append(max(0, time.monotonic() - start - 0.01))

    async def commands(index):
        for _ in range(50):
            start = time.monotonic()
            try:
                await client.hset(f"diagnostic:{index}", mapping={"value": "1"})
                assert await client.hgetall(f"diagnostic:{index}") == {"value": "1"}
            except Exception as error:
                errors.append(type(error).__name__)
            samples.append(time.monotonic() - start)

    task = asyncio.create_task(heartbeat())
    start, cpu = time.monotonic(), time.process_time()
    try:
        await asyncio.gather(*(commands(i) for i in range(8)))
    finally:
        active = False
        await task
        await client.aclose()
    return {"elapsed_seconds": time.monotonic() - start, "cpu_seconds": time.process_time() - cpu, "commands": len(samples) * 2, "pair_p50_ms": statistics.median(samples) * 1000, "pair_max_ms": max(samples) * 1000, "loop_jitter_max_ms": max(jitter) * 1000, "errors": errors}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--redis-runtime", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result = {"platform": platform.platform(), "python": platform.python_version(), "cpus": os.cpu_count(), "loops": {}}
    with tempfile.TemporaryDirectory(prefix="pyao-redis-diagnostic-") as temporary:
        fixture = world.NativeRedis(args.redis_runtime, Path(temporary))
        try:
            with fixture:
                for name, factory in (("proactor", asyncio.ProactorEventLoop), ("selector", asyncio.SelectorEventLoop)):
                    result["loops"][name] = asyncio.run(probe(fixture), loop_factory=factory)
                    args.output.write_text(json.dumps(result, indent=2) + "\n")
                    print(name, json.dumps(result["loops"][name]), flush=True)
        finally:
            if (fixture.root / "redis.log").exists():
                shutil.copy2(fixture.root / "redis.log", args.output.with_suffix(".redis.log"))


if __name__ == "__main__":
    main()
