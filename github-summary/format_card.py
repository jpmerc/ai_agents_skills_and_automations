#!/usr/bin/env python3
"""Convertit un resume GitHub en texte en Google Chat Card JSON."""
import json
import re
import sys


def parse_summary(text):
    """Parse le resume markdown-like en sections."""
    sections = []
    current_repo = None
    current_content = []
    overview = ""
    title = ""

    for line in text.split("\n"):
        # Titre principal
        if line.startswith("# "):
            title = line.lstrip("# ").strip()
        # Nouveau repo
        elif line.startswith("## "):
            if current_repo:
                sections.append({"repo": current_repo, "content": "\n".join(current_content).strip()})
            current_repo = line.lstrip("# ").strip()
            current_content = []
        # Vue d'ensemble
        elif "vue d'ensemble" in line.lower() or "vue d'ensemble" in line.lower():
            if current_repo:
                sections.append({"repo": current_repo, "content": "\n".join(current_content).strip()})
                current_repo = None
                current_content = []
        elif current_repo is None and line.startswith("**Vue"):
            overview = line.replace("**Vue d'ensemble:**", "").replace("**Vue d'ensemble :**", "").strip()
        elif current_repo is None and not line.startswith("#") and not line.startswith("---") and line.strip() and not title:
            overview += " " + line.strip()
        elif current_repo:
            current_content.append(line)

    if current_repo:
        sections.append({"repo": current_repo, "content": "\n".join(current_content).strip()})

    # Chercher la vue d'ensemble dans le texte brut
    if not overview:
        match = re.search(r"\*\*Vue d'ensemble[^*]*\*\*[:\s]*(.*?)(?:\n\n|\Z)", text, re.DOTALL | re.IGNORECASE)
        if match:
            overview = match.group(1).strip()

    return title, sections, overview


def md_to_html(text):
    """Convertit le markdown basique en HTML pour Google Chat cards."""
    # Bold: **text** -> <b>text</b>
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    # Italic: *text* -> <i>text</i> (mais pas les listes)
    # Bullet lists: - text -> bullet
    lines = []
    in_list = False
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped.startswith("- "):
            if not in_list:
                lines.append("<ul>")
                in_list = True
            lines.append(f"<li>{stripped[2:]}</li>")
        else:
            if in_list:
                lines.append("</ul>")
                in_list = False
            if stripped:
                lines.append(stripped + "<br>")
    if in_list:
        lines.append("</ul>")
    return "\n".join(lines)


def build_card(title, sections, overview):
    """Construit le payload Google Chat card."""
    card_sections = []

    for section in sections:
        html_content = md_to_html(section["content"])
        card_sections.append({
            "header": section["repo"],
            "widgets": [
                {"textParagraph": {"text": html_content}}
            ]
        })

    if overview:
        card_sections.append({
            "header": "Vue d'ensemble",
            "widgets": [
                {"textParagraph": {"text": f"<i>{overview}</i>"}}
            ]
        })

    payload = {
        "cards": [
            {
                "header": {
                    "title": title or "Resume GitHub",
                    "subtitle": "NQB AI"
                },
                "sections": card_sections
            }
        ]
    }

    return payload


if __name__ == "__main__":
    input_file = sys.argv[1]
    with open(input_file) as f:
        text = f.read()

    title, sections, overview = parse_summary(text)

    if not sections:
        print("AUCUNE_SECTION", file=sys.stderr)
        sys.exit(1)

    payload = build_card(title, sections, overview)
    print(json.dumps(payload))
