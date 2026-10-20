"""RTT placements and final peer visibility, independent of server imports."""


def run_matrix(world, store, x, y):
    world.base = {1: (2, x + 4, y), 2: (2, x + 4, y + 2)}
    world.reset(store)
    world.benchmark(store)
    world.benchmark(store, slow_readers=0, report_name="benchmark-no-slow.json")
    world.base = {1: (1, x + 4, y), 2: (2, x + 4, y + 2)}
    world.reset(store)
    world.benchmark(store, report_name="benchmark-distributed.json")
    # Peer chat is a same-map assertion, after the distributed measurement ends.
    world.base = {1: (2, x + 4, y), 2: (2, x + 4, y + 2)}
    world.reset(store)
