"""Comprueba el esquema del servidor exacto usado para probar los Snaps."""


def verify_schema(store, expected_version):
    actual = store.hget("schema:state", "version")
    if actual != str(expected_version):
        raise RuntimeError(
            f"Esquema Redis incorrecto: esperado {expected_version}, recibido {actual!r}"
        )
    return expected_version
