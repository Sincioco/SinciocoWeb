"""Isolated contract tests for the card-thumbnail validator.

All fixture images are synthetic RGB PNGs. Nothing is read from or written to the
canonical site, and all temporary fixtures stay beneath this tests directory.
"""
from __future__ import annotations

from functools import lru_cache
from hashlib import sha256
from html import escape
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import sys
import unittest
from uuid import uuid4
import zlib


TEST_ROOT = Path(__file__).resolve().parent
CHECKER = Path(os.environ.get("CARD_THUMBNAIL_CHECKER", TEST_ROOT / "check-card-thumbnails.py"))
if not CHECKER.is_file() and "CARD_THUMBNAIL_CHECKER" not in os.environ:
    CHECKER = TEST_ROOT.parent / "candidate/AgenticAI/tools/check-card-thumbnails.py"
SPEC = importlib.util.spec_from_file_location("card_thumbnail_validator", CHECKER)
VALIDATOR = importlib.util.module_from_spec(SPEC)
_previous_bytecode = sys.dont_write_bytecode
try:
    sys.dont_write_bytecode = True
    SPEC.loader.exec_module(VALIDATOR)
finally:
    sys.dont_write_bytecode = _previous_bytecode
WIDTHS = [320, 368, 480, 640, 736, 960]
ALTS = {"sinaiprompt": "Sin AI Prompt project preview", "pmt": "PMT project preview"}
SIZES = ("(max-width: 520px) calc(100vw - 42px), "
         "(max-width: 700px) calc(50vw - 34px), "
         "(max-width: 1000px) calc(50vw - 46px), "
         "(max-width: 1184px) calc((100vw - 118px) / 3), 355.333333px")
SOURCE_CONTRACTS = {
    "sinaiprompt": ("images/sinaiprompt/sin-ai-prompt-thumbnail.png",
                   "images/sinaiprompt/sin-ai-prompt-card-", 2400, 1440),
    "pmt": ("images/pmt/pmt-1-thumbnail-draft-1c.png",
            "images/pmt/pmt-1-draft-1c-card-", 1619, 971),
}
CI_ALLOWLIST = ".github/static-site/publish-files.json"
PRIVATE_ALLOWLIST = "Deployment/publish-files.json"
METADATA = "AgenticAI/content/card-thumbnails.json"


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))


@lru_cache(maxsize=None)
def rgb_png(width: int, height: int, shade: int = 31) -> bytes:
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    row = b"\x00" + bytes((shade, 83, 149)) * width
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(row * height, level=1))
            + chunk(b"IEND", b""))


def write(path: Path, content: str | bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(content, bytes):
        path.write_bytes(content)
    else:
        path.write_text(content, encoding="utf-8")


def write_json(path: Path, data) -> None:
    write(path, json.dumps(data, indent=2))


class Fixture:
    def __init__(self, base: Path):
        self.site = base / "site"
        self.payload = base / "payload"
        self.manifest = {"version": 1, "sizes": SIZES, "images": {}}
        for slug, (source, prefix, width, height) in SOURCE_CONTRACTS.items():
            crop_width = min(width, height * 16 / 9)
            crop_height = crop_width * 9 / 16
            self.manifest["images"][slug] = {
                "source": source, "sourceWidth": width, "sourceHeight": height,
                "cropBox": [(width-crop_width)/2, (height-crop_height)/2,
                            (width+crop_width)/2, (height+crop_height)/2],
                "variants": [{"path": prefix + str(w) + ".png", "width": w, "height": w * 9 // 16}
                             for w in WIDTHS],
            }
        self.entries = []
        for number, image in enumerate(self.manifest["images"].values()):
            source = rgb_png(image["sourceWidth"], image["sourceHeight"], 31 + number)
            image["sourceSha256"] = sha256(source).hexdigest()
            write(self.site / "AgenticAI" / image["source"], source)
            for variant in image["variants"]:
                data = rgb_png(variant["width"], variant["height"], 31 + number)
                variant["sha256"] = sha256(data).hexdigest()
                variant["bytes"] = len(data)
                relative = "AgenticAI/" + variant["path"]
                write(self.site / relative, data)
                write(self.payload / relative, data)
                self.entries.append({"source": "main", "path": relative, "deployed": relative})
        self.save_manifest()
        write_json(self.site / CI_ALLOWLIST, self.entries)
        write_json(self.site / PRIVATE_ALLOWLIST, self.entries)
        self.tags = {slug: self.image_tag(slug) for slug in ALTS}
        cards = [f'<article class="project-card">{self.tags[slug]}</article>' for slug in ALTS]
        cards.extend(f'<a class="project-card" href="other-{i}.html">'
                     f'<img src="other-{i}.png" alt="Other project {i}"></a>' for i in range(4))
        html = '<!doctype html><html><body><main>' + "\n".join(cards) + '</main></body></html>'
        write(self.site / "AgenticAI/Index.html", html)
        write(self.payload / "AgenticAI/index.html", html)

    def save_manifest(self):
        write_json(self.site / METADATA, self.manifest)

    def image_tag(self, slug):
        image = self.manifest["images"][slug]
        urls = {v["width"]: v["path"] + "?v=" + v["sha256"][:16] for v in image["variants"]}
        attrs = {
            "src": urls[368],
            "srcset": ", ".join(urls[width] + f" {width}w" for width in WIDTHS),
            "sizes": self.manifest["sizes"],
            "width": "368", "height": "207", "alt": ALTS[slug],
            "loading": "lazy", "decoding": "async",
        }
        return '<img ' + ' '.join(key + '="' + escape(value, quote=True) + '"'
                                 for key, value in attrs.items()) + '>'

    def variant(self):
        return self.manifest["images"]["sinaiprompt"]["variants"][0]

    def variant_path(self, payload=False):
        return (self.payload if payload else self.site) / "AgenticAI" / self.variant()["path"]


class ThumbnailValidatorTests(unittest.TestCase):
    def setUp(self):
        # Normal mkdir inherits the workspace ACL on Windows. Python 3.13's
        # mode-0700 TemporaryDirectory can exclude the restricted test runner.
        self.fixture_root = TEST_ROOT / ("thumbnail-fixture-" + uuid4().hex)
        self.fixture_root.mkdir()
        self.addCleanup(self.clean_fixture)
        self.fixture = Fixture(self.fixture_root)

    def clean_fixture(self):
        resolved = self.fixture_root.resolve()
        if (resolved.parent != TEST_ROOT.resolve()
                or not resolved.name.startswith("thumbnail-fixture-")
                or self.fixture_root.is_symlink()):
            raise ValueError("Refusing cleanup outside this test's fixture directory")
        shutil.rmtree(resolved)

    def validate(self, payload=False, require_private=True):
        return VALIDATOR.validate(self.fixture.site,
                                  self.fixture.payload if payload else None,
                                  require_private=require_private)

    def replace_html(self, old, new, payload=False):
        path = ((self.fixture.payload / "AgenticAI/index.html") if payload
                else (self.fixture.site / "AgenticAI/Index.html"))
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text, "Test mutation must change the fixture")
        write(path, text.replace(old, new, 1))

    def test_valid_assets_render_expected_markup(self):
        manifest, tags = VALIDATOR.load_assets(self.fixture.site)
        self.assertEqual(manifest, self.fixture.manifest)
        self.assertEqual(tags, self.fixture.tags)

    def test_valid_site_private_manifest_and_payload(self):
        result = self.validate(payload=True)
        self.assertTrue(result["passed"])
        self.assertEqual((result["cards"], result["variants"]), (2, 12))
        self.assertEqual(result["publication_manifests_checked"], 2)
        self.assertTrue(result["payload_checked"])
        self.assertEqual(result["bytes"], sum(v["bytes"] for i in self.fixture.manifest["images"].values()
                                              for v in i["variants"]))

    def test_success_does_not_cache_later_asset_mutation(self):
        self.assertTrue(self.validate()["passed"])
        path = self.fixture.variant_path()
        path.write_bytes(path.read_bytes() + b"changed after successful check")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            self.validate()

    def test_stale_markup_cache_key_is_rejected(self):
        variant = self.fixture.variant()
        self.replace_html(variant["path"] + "?v=" + variant["sha256"][:16],
                          variant["path"] + "?v=0000000000000000")
        with self.assertRaisesRegex(ValueError, "markup/cache key"):
            self.validate()

    def test_missing_variant_is_rejected(self):
        self.fixture.variant_path().unlink()
        with self.assertRaisesRegex(ValueError, "Missing thumbnail input"):
            self.validate()

    def test_mutated_same_length_variant_is_rejected(self):
        path = self.fixture.variant_path()
        data = bytearray(path.read_bytes())
        data[-5] ^= 1
        path.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            self.validate()

    def test_wrong_dimensions_fail_even_with_matching_hash_and_length(self):
        variant = self.fixture.variant()
        data = rgb_png(variant["width"] + 16, variant["height"])
        write(self.fixture.variant_path(), data)
        variant.update(sha256=sha256(data).hexdigest(), bytes=len(data))
        self.fixture.save_manifest()
        with self.assertRaisesRegex(ValueError, "RGB dimensions"):
            VALIDATOR.load_assets(self.fixture.site)

    def test_invalid_header_crc_fails_even_with_matching_hash(self):
        variant = self.fixture.variant()
        data = bytearray(self.fixture.variant_path().read_bytes())
        data[29] ^= 1
        write(self.fixture.variant_path(), bytes(data))
        variant["sha256"] = sha256(data).hexdigest()
        self.fixture.save_manifest()
        with self.assertRaisesRegex(ValueError, "header checksum"):
            VALIDATOR.load_assets(self.fixture.site)

    def test_traversal_variant_path_is_rejected(self):
        self.fixture.variant()["path"] = "../outside.png"
        self.fixture.save_manifest()
        with self.assertRaisesRegex(ValueError, "thumbnail path"):
            VALIDATOR.load_assets(self.fixture.site)

    def test_symlink_variant_is_rejected(self):
        original = self.fixture.variant_path()
        target = self.fixture_root / "outside-the-site.png"
        shutil.copyfile(original, target)
        original.unlink()
        try:
            original.symlink_to(target)
        except (OSError, NotImplementedError) as error:
            self.skipTest("Host does not permit symlink creation: " + str(error))
        with self.assertRaisesRegex(ValueError, "Linked paths"):
            VALIDATOR.load_assets(self.fixture.site)

    def test_missing_ci_publication_entry_is_rejected(self):
        write_json(self.fixture.site / CI_ALLOWLIST, self.fixture.entries[1:])
        with self.assertRaisesRegex(ValueError, "publication entry"):
            self.validate()

    def test_missing_private_publication_entry_is_rejected(self):
        write_json(self.fixture.site / PRIVATE_ALLOWLIST, self.fixture.entries[1:])
        with self.assertRaisesRegex(ValueError, "publication entry"):
            self.validate()

    def test_duplicate_publication_entry_is_rejected(self):
        write_json(self.fixture.site / CI_ALLOWLIST, self.fixture.entries + self.fixture.entries[:1])
        with self.assertRaisesRegex(ValueError, "publication entry"):
            self.validate()

    def test_authoring_metadata_publication_is_rejected(self):
        entry = {"source": "main", "path": METADATA, "deployed": METADATA}
        write_json(self.fixture.site / CI_ALLOWLIST, self.fixture.entries + [entry])
        with self.assertRaisesRegex(ValueError, "metadata must not be published"):
            self.validate()

    def test_private_manifest_requirement_is_enforced(self):
        (self.fixture.site / PRIVATE_ALLOWLIST).unlink()
        self.assertEqual(self.validate(require_private=False)["publication_manifests_checked"], 1)
        with self.assertRaisesRegex(ValueError, "Missing thumbnail input"):
            self.validate(require_private=True)

    def test_incorrect_srcset_width_is_rejected(self):
        self.replace_html(" 320w,", " 321w,")
        with self.assertRaisesRegex(ValueError, "markup/cache key"):
            self.validate()

    def test_duplicate_image_attribute_is_rejected(self):
        # HTML uses the first duplicate attribute; dict(attrs) keeps the last.
        # A valid trailing src must never conceal the wrong browser-facing src.
        self.replace_html('<img src="', '<img src="wrong-artwork.png" src="')
        with self.assertRaises(ValueError):
            self.validate()

    def test_responsive_markup_on_unapproved_card_is_rejected(self):
        self.replace_html('src="other-0.png"', 'src="other-0.png" srcset="other-0.png 320w"')
        with self.assertRaisesRegex(ValueError, "limited to the two approved cards"):
            self.validate()

    def test_missing_payload_variant_is_rejected(self):
        self.fixture.variant_path(payload=True).unlink()
        with self.assertRaisesRegex(ValueError, "Missing thumbnail input"):
            self.validate(payload=True)

    def test_mutated_payload_variant_is_rejected(self):
        path = self.fixture.variant_path(payload=True)
        path.write_bytes(path.read_bytes() + b"payload changed")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            self.validate(payload=True)

    def test_incorrect_payload_markup_is_rejected(self):
        self.replace_html(" 320w,", " 321w,", payload=True)
        with self.assertRaisesRegex(ValueError, "markup/cache key"):
            self.validate(payload=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
