"""Build-time only: stream the pinned public weights, verifying SHA-256."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request


def fetch_verified(item, destination):
    destination = Path(destination)
    temporary = destination.with_suffix(destination.suffix + ".download")
    maximum = item.get("bytes", 1024 * 1024)
    digest, count = hashlib.sha256(), 0
    try:
        request = urllib.request.Request(item["url"], headers={"User-Agent": "Kantura-Generation-Build/1"})
        with urllib.request.urlopen(request, timeout=180) as response, temporary.open("xb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                count += len(chunk)
                if count > maximum:
                    raise ValueError("Pinned download exceeds expected size: " + item["name"])
                digest.update(chunk)
                output.write(chunk)
        if digest.hexdigest() != item["sha256"] or ("bytes" in item and count != item["bytes"]):
            raise ValueError("Pinned download integrity check failed: " + item["name"])
        temporary.replace(destination)
        print(json.dumps({"verified": item["name"], "bytes": count, "sha256": digest.hexdigest()}), flush=True)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.output.is_absolute():
        parser.error("--output must be absolute")
    args.output.mkdir(parents=True, exist_ok=True)
    pins = json.loads(Path(__file__).with_name("pins.json").read_text())
    for item in pins["downloads"]:
        fetch_verified(item, args.output / item["name"])
    (args.output / "pins.json").write_text(json.dumps(pins, indent=2) + "\n")


if __name__ == "__main__":
    main()
