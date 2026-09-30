---
layout: default
title: Changelog
description: What changed in each dinky release.
permalink: /changelog/
---

# Changelog

{% capture changelog %}{% include changelog.md %}{% endcapture %}
{{ changelog | markdownify }}
