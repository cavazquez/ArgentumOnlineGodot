"""Conserva el contrato firmado de Ubuntu y cambia sólo sus URI en una copia de CI."""
import re
from pathlib import Path
import sys


def official_sources(source, architecture):
    if architecture not in {"amd64", "arm64"}:
        raise ValueError("Arquitectura CI de Ubuntu no admitida")
    sections = []
    for section in source.strip().split("\n\n"):
        if not re.search(r"(?m)^URIs:", section):
            sections.append(section)
            continue
        if not re.search(r"(?m)^Signed-By:\s*/usr/share/keyrings/ubuntu-archive-keyring\.gpg\s*$", section):
            raise ValueError("La fuente requiere la clave oficial de Ubuntu")
        if re.search(r"(?im)^Trusted:\s*yes\b", section):
            raise ValueError("La fuente no puede omitir autenticación")
        suites = re.search(r"(?m)^Suites:\s*(.+)$", section)
        if not suites:
            raise ValueError("La fuente no declara suites")
        if architecture == "arm64":
            uri = "https://ports.ubuntu.com/ubuntu-ports/"
        elif any(value.endswith("-security") for value in suites[1].split()):
            uri = "https://security.ubuntu.com/ubuntu/"
        else:
            uri = "https://archive.ubuntu.com/ubuntu/"
        sections.append(re.sub(r"(?m)^URIs:.*$", "URIs: " + uri, section))
    if not sections or not any(re.search(r"(?m)^URIs:", section) for section in sections):
        raise ValueError("No hay fuentes Ubuntu")
    return "\n\n".join(sections) + "\n"


if __name__ == "__main__":
    original, output, architecture = sys.argv[1:]
    Path(output).write_text(official_sources(Path(original).read_text(), architecture))
