#!/usr/bin/env python3
"""Writes dist/appcast.xml, the Sparkle feed, for the signed and zipped build/dinky.app."""
import datetime
import email.utils
from pathlib import Path
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

version = sys.argv[1]
archive = Path("dist/dinky.app.zip")
info = plistlib.loads(Path("build/dinky.app/Contents/Info.plist").read_bytes())
assert info["CFBundleShortVersionString"] == version
signature = Path("dist/signature.txt").read_text().strip()
assert re.fullmatch(r"[A-Za-z0-9+/]{86}==", signature), "Invalid Ed25519 signature"

ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", ns)
rss = ET.Element("rss", version="2.0")
channel = ET.SubElement(rss, "channel")
ET.SubElement(channel, "title").text = "dinky"
item = ET.SubElement(channel, "item")
ET.SubElement(item, "title").text = version
ET.SubElement(item, "pubDate").text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(item, f"{{{ns}}}minimumSystemVersion").text = info["LSMinimumSystemVersion"]
ET.SubElement(item, f"{{{ns}}}releaseNotesLink").text = f"https://github.com/mikker/Dinky/releases/tag/v{version}"
ET.SubElement(item, "enclosure", {
    "url": f"https://github.com/mikker/Dinky/releases/download/v{version}/dinky.app.zip",
    "length": str(archive.stat().st_size),
    "type": "application/octet-stream",
    f"{{{ns}}}version": info["CFBundleVersion"],
    f"{{{ns}}}shortVersionString": version,
    f"{{{ns}}}edSignature": signature,
})
ET.indent(rss)
ET.ElementTree(rss).write("dist/appcast.xml", encoding="utf-8", xml_declaration=True)
