"""The Store smoke must accept a completed account without the retired party packet."""

import ast
import asyncio
from enum import IntEnum
from pathlib import Path
import struct
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, Mock


SOURCE = Path(__file__).resolve().parents[1] / "snap-pair-login.py"
METHOD = next(
    node for node in ast.parse(SOURCE.read_text()).body
    if isinstance(node, ast.AsyncFunctionDef) and node.name == "create_account"
)


class CurrentPackets(IntEnum):
    LOGGED = 0
    DICE_ROLL = 67
    PONG = 88


class SnapPairAccountTests(unittest.IsolatedAsyncioTestCase):
    async def exercise(self, *, accept=True):
        peers = []

        class Peer:
            def __init__(self, reader, writer):
                self.frames = []
                self.sent = []
                self.closed = False
                self.error = None
                self.task = asyncio.get_running_loop().create_future()
                peers.append(self)

            async def send(self, packet):
                self.sent.append(packet[0])
                if packet[0] == 1:
                    self.frames.append(bytes([CurrentPackets.DICE_ROLL]))
                elif packet[0] == 2 and accept:
                    self.frames.append(bytes([CurrentPackets.LOGGED, 1]))
                elif packet[0] == 0x77:
                    self.frames.append(bytes([CurrentPackets.PONG]))
                elif packet[0] == 0x47:
                    self.task.set_result(None)

            async def wait(self, predicate):
                if not predicate(self.frames):
                    raise RuntimeError("EOF before account was accepted")

            async def close(self):
                self.closed = True
                if not self.task.done():
                    self.task.set_result(None)

        connection = AsyncMock(return_value=(object(), object()))
        context = object()
        ssl_factory = Mock(return_value=context)
        namespace = {
            "asyncio": SimpleNamespace(open_connection=connection, timeout=asyncio.timeout),
            "ssl": SimpleNamespace(create_default_context=ssl_factory),
            "struct": struct,
            "ServerPacketID": CurrentPackets,
            "ProtocolPeer": Peer,
        }
        exec(compile(ast.Module(body=[METHOD], type_ignores=[]), str(SOURCE), "exec"), namespace)
        try:
            await asyncio.wait_for(
                namespace["create_account"](7666, "fixture.crt", "Fixture", "fixture-only"),
                timeout=1,
            )
        finally:
            ssl_factory.assert_called_once_with(cafile="fixture.crt")
            self.assertEqual(connection.await_args.kwargs, {"ssl": context, "server_hostname": "localhost"})
            self.assertTrue(peers[0].closed)
            self.last_peer = peers[0]
        return peers[0]

    async def test_current_account_handshake_does_not_need_show_party_form(self):
        peer = await self.exercise()
        self.assertEqual(peer.sent, [1, 2, 0x77, 0x47])
        self.assertEqual([frame[0] for frame in peer.frames], [67, 0, 88])

    async def test_rejected_account_does_not_advance_to_ping_or_quit(self):
        with self.assertRaisesRegex(RuntimeError, "before account was accepted"):
            await self.exercise(accept=False)
        self.assertEqual(self.last_peer.sent, [1, 2])


if __name__ == "__main__":
    unittest.main()
