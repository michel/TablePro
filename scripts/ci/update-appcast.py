#!/usr/bin/env python3
"""
Prepend new Sparkle appcast items to an existing feed, preserving history.

Sparkle shows cumulative release notes when a user skips versions, so the
appcast must contain items for all published releases — not just the latest.
"""

import argparse
import re
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)

INDENT = "    "
# Sentinel prefix used to mark description content for CDATA wrapping.
# ElementTree cannot produce CDATA natively, so we mark it and fix in post.
CDATA_SENTINEL = "__APPCAST_CDATA__"


def sparkle(tag: str) -> str:
    return f"{{{SPARKLE_NS}}}{tag}"


def make_item(
    version: str,
    build: str,
    min_os: str,
    pub_date: str,
    description: str,
    url: str,
    length: str,
    sig: str,
    hw_req: str | None = None,
) -> ET.Element:
    item = ET.Element("item")

    ET.SubElement(item, "title").text = version
    ET.SubElement(item, "pubDate").text = pub_date
    ET.SubElement(item, sparkle("version")).text = build
    ET.SubElement(item, sparkle("shortVersionString")).text = version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = min_os

    if hw_req:
        ET.SubElement(item, sparkle("hardwareRequirements")).text = hw_req

    # Mark description for CDATA wrapping in post-processing
    desc = ET.SubElement(item, "description")
    desc.text = CDATA_SENTINEL + description

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", url)
    enclosure.set("length", length)
    enclosure.set("type", "application/octet-stream")
    enclosure.set(f"{sparkle('edSignature')}", sig)

    return item


def mark_existing_descriptions(root: ET.Element) -> None:
    """Mark existing <description> elements for CDATA wrapping.

    When ElementTree parses <![CDATA[html]]>, it strips the CDATA wrapper
    and stores the raw HTML as text. We re-mark them so the post-processor
    can restore the CDATA wrapper on output.
    """
    for desc in root.iter("description"):
        if desc.text and not desc.text.startswith(CDATA_SENTINEL):
            desc.text = CDATA_SENTINEL + desc.text


def indent_tree(elem: ET.Element, level: int = 0) -> None:
    """Add consistent indentation to the XML tree."""
    prefix = "\n" + INDENT * level
    child_prefix = "\n" + INDENT * (level + 1)

    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = child_prefix
        for i, child in enumerate(elem):
            indent_tree(child, level + 1)
            child.tail = child_prefix if i < len(elem) - 1 else prefix
    if not elem.tail or not elem.tail.strip():
        elem.tail = prefix


def restore_cdata(xml_str: str) -> str:
    """Replace sentinel-marked descriptions with proper CDATA sections.

    After ET serializes, sentineled text looks like:
        <description>__APPCAST_CDATA__&lt;body ...&gt;...&lt;/body&gt;</description>
    We unescape the HTML entities and wrap in CDATA.
    """
    import html

    def replace_match(m: re.Match) -> str:
        raw = m.group(1)
        # Unescape XML/HTML entities that ET introduced
        content = html.unescape(raw)
        return f"<description><![CDATA[{content}]]></description>"

    return re.sub(
        rf"<description>{re.escape(CDATA_SENTINEL)}(.*?)</description>",
        replace_match,
        xml_str,
        flags=re.DOTALL,
    )


def build_fresh_feed() -> ET.Element:
    rss = ET.Element("rss")
    rss.set("xmlns:sparkle", SPARKLE_NS)
    rss.set("version", "2.0")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "TablePro"
    return rss


def main() -> None:
    parser = argparse.ArgumentParser(description="Update Sparkle appcast.xml")
    parser.add_argument("--output", required=True)
    parser.add_argument("--existing", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--min-os", required=True)
    parser.add_argument("--pub-date", required=True)
    parser.add_argument("--description", required=True)
    parser.add_argument("--arm64-url", required=True)
    parser.add_argument("--arm64-length", required=True)
    parser.add_argument("--arm64-sig", required=True)
    parser.add_argument("--x86-url", required=True)
    parser.add_argument("--x86-length", required=True)
    parser.add_argument("--x86-sig", required=True)
    args = parser.parse_args()

    common = dict(
        version=args.version,
        build=args.build,
        min_os=args.min_os,
        pub_date=args.pub_date,
        description=args.description,
    )
    arm64_item = make_item(
        **common,
        url=args.arm64_url,
        length=args.arm64_length,
        sig=args.arm64_sig,
        hw_req="arm64",
    )
    x86_item = make_item(
        **common,
        url=args.x86_url,
        length=args.x86_length,
        sig=args.x86_sig,
    )

    # Load existing feed or create fresh
    existing = Path(args.existing)
    if existing.is_file() and existing.stat().st_size > 0:
        tree = ET.parse(existing)
        rss = tree.getroot()
        mark_existing_descriptions(rss)
    else:
        rss = build_fresh_feed()

    channel = rss.find("channel")
    if channel is None:
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = "TablePro"

    # Insert new items after <title>, before existing <item>s
    items = list(channel.iter("item"))
    insert_idx = list(channel).index(items[0]) if items else len(list(channel))

    channel.insert(insert_idx, arm64_item)
    channel.insert(insert_idx + 1, x86_item)

    indent_tree(rss)
    raw = ET.tostring(rss, encoding="unicode", xml_declaration=False)
    raw = restore_cdata(raw)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with open(output, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" standalone="yes"?>\n')
        f.write(raw)
        f.write("\n")


if __name__ == "__main__":
    main()
