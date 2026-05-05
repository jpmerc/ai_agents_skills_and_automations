#!/usr/bin/env python3
"""
Reconstruit les conversations LinkedIn depuis un backup messages.csv vers un fichier
markdown par interlocuteur, navigable manuellement.

Usage :
    python3 extract_linkedin_conversations.py [BACKUP_DIR] [OUTPUT_DIR]

Defaults :
    BACKUP_DIR : le plus recent dans /home/jp/Documents/NQB/LinkedIn/backups/
    OUTPUT_DIR : /home/jp/Documents/NQB/LinkedIn/conversations/

Filtres :
    - >= 1 message de l'interlocuteur externe ET >= 1 message de JP
    - Skip drafts (IS MESSAGE DRAFT = TRUE)
    - Skip conversations de groupe (>1 interlocuteur externe)
    - Skip "LinkedIn Member" (anonymous)

Sortie :
    Un fichier <prenom>_<nom>.md par interlocuteur.
    Si plusieurs conversation_ids existent pour la meme personne (rare), les
    conversations sont concatenees dans le meme fichier separees par un divider.
"""

import csv
import os
import re
import sys
import unicodedata
from collections import defaultdict
from datetime import datetime
from pathlib import Path

JP_NAME = "Jean-Philippe Mercier"
DEFAULT_BACKUPS_ROOT = Path("/home/jp/Documents/NQB/LinkedIn/backups")
DEFAULT_OUTPUT_DIR = Path("/home/jp/Documents/NQB/LinkedIn/conversations")


def slugify_name(name):
    """Convert 'Jean-Philippe Mercier' -> 'jean_philippe_mercier'."""
    if not name:
        return "unknown"
    # Strip emojis and certifications
    s = re.sub(r"[\U0001F300-\U0001FAFF☀-➿]", "", name)
    # Drop common suffixes
    s = re.sub(r",\s*(ing\.?|m\.?\s*sc\.?|mba|p\.?\s*eng\.?|ph\.?\s*d\.?|crha|cpa|pmp|cisa)[^,]*",
               "", s, flags=re.IGNORECASE)
    # Normalize accents
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    # Lowercase + replace non-alphanum with underscore
    s = s.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "_", s)
    s = re.sub(r"_+", "_", s).strip("_")
    return s or "unknown"


def find_latest_backup(root):
    if not root.exists():
        return None
    candidates = [d for d in root.iterdir() if d.is_dir()]
    if not candidates:
        return None
    return max(candidates, key=lambda d: d.stat().st_mtime)


def parse_date(s):
    """Parse 'YYYY-MM-DD HH:MM:SS UTC' to datetime, return None on failure."""
    if not s:
        return None
    s = s.replace(" UTC", "").strip()
    try:
        return datetime.strptime(s, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


def load_conversations(messages_csv):
    """Group rows by CONVERSATION ID, filter drafts."""
    convs = defaultdict(list)
    with open(messages_csv, encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader)  # skip header
        for row in reader:
            if len(row) < 12:
                continue
            if row[11] == "TRUE":  # IS MESSAGE DRAFT
                continue
            convs[row[0]].append(row)
    return convs


def conv_external_party(msgs):
    """Return (name, profile_url) of the single external party, or (None, None)
    if conversation is a group chat or has no clear external interlocutor."""
    senders = set(m[2] for m in msgs)
    external_senders = {s for s in senders if s and s != JP_NAME and s != "LinkedIn Member"}

    if not external_senders:
        return (None, None)
    if len(external_senders) > 1:
        # Group conversation - skip for v1
        return (None, None)

    name = next(iter(external_senders))

    # Find their profile URL
    url = ""
    for m in msgs:
        if m[2] == name and m[3]:
            url = m[3]
            break
    if not url:
        # Fallback: use recipient URL when JP wrote
        for m in msgs:
            if m[2] == JP_NAME and m[5]:
                url = m[5].split(",")[0].strip()
                break
    return (name, url)


def format_conversation_md(name, url, msg_groups):
    """Build the markdown content for a person's conversations.

    msg_groups: list of (conv_id, sorted_msgs) tuples.
    """
    lines = []
    lines.append(f"# {name}")
    lines.append("")
    if url:
        lines.append(f"**LinkedIn**: {url}")
        lines.append("")

    total_msgs = sum(len(msgs) for _, msgs in msg_groups)
    nb_inbound = sum(1 for _, msgs in msg_groups for m in msgs if m[2] != JP_NAME)
    nb_outbound = total_msgs - nb_inbound

    all_dates = [parse_date(m[6]) for _, msgs in msg_groups for m in msgs]
    all_dates = [d for d in all_dates if d]
    if all_dates:
        first = min(all_dates).strftime("%Y-%m-%d")
        last = max(all_dates).strftime("%Y-%m-%d")
        lines.append(f"**Echanges** : {total_msgs} messages "
                     f"({nb_inbound} entrants, {nb_outbound} sortants) "
                     f"du {first} au {last}")
    else:
        lines.append(f"**Echanges** : {total_msgs} messages "
                     f"({nb_inbound} entrants, {nb_outbound} sortants)")
    lines.append("")
    lines.append(f"**Conversations** : {len(msg_groups)}")
    lines.append("")
    lines.append("---")
    lines.append("")

    for idx, (conv_id, msgs) in enumerate(msg_groups, 1):
        if len(msg_groups) > 1:
            lines.append(f"## Conversation {idx}/{len(msg_groups)} — `{conv_id[:20]}...`")
            lines.append("")
        for m in msgs:
            who = "**JP**" if m[2] == JP_NAME else f"**{m[2]}**"
            date = m[6][:16] if m[6] else "?"
            content = (m[8] or "").strip()
            # Clean Windows line endings, normalize whitespace
            content = content.replace("\r\n", "\n").replace("\r", "\n")
            lines.append(f"### {date} — {who}")
            lines.append("")
            if content:
                # Indent each content line as a markdown blockquote for readability
                for cline in content.split("\n"):
                    if cline.strip():
                        lines.append(f"> {cline}")
                    else:
                        lines.append(">")
                lines.append("")
            else:
                lines.append("*(message vide)*")
                lines.append("")
        if idx < len(msg_groups):
            lines.append("---")
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main():
    args = sys.argv[1:]
    backup_dir = Path(args[0]) if len(args) >= 1 else find_latest_backup(DEFAULT_BACKUPS_ROOT)
    output_dir = Path(args[1]) if len(args) >= 2 else DEFAULT_OUTPUT_DIR

    if not backup_dir or not backup_dir.exists():
        print(f"ERROR: backup directory introuvable. Cherche dans {DEFAULT_BACKUPS_ROOT}",
              file=sys.stderr)
        sys.exit(1)

    messages_csv = backup_dir / "messages.csv"
    if not messages_csv.exists():
        print(f"ERROR: messages.csv introuvable dans {backup_dir}", file=sys.stderr)
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Backup        : {backup_dir}")
    print(f"Output        : {output_dir}")
    print()

    # Load all conversations
    convs = load_conversations(messages_csv)

    # Filter and group by external party
    by_party = {}  # slug -> {"name": ..., "url": ..., "convs": [(conv_id, sorted_msgs)]}
    skipped = {"no_jp_msg": 0, "no_external_msg": 0,
               "group": 0, "anon": 0, "no_external": 0}

    for conv_id, msgs in convs.items():
        # Require at least 1 message from JP and at least 1 from the other party
        nb_jp = sum(1 for m in msgs if m[2] == JP_NAME)
        nb_ext = sum(1 for m in msgs if m[2] and m[2] != JP_NAME)
        if nb_jp < 1:
            skipped["no_jp_msg"] += 1
            continue
        if nb_ext < 1:
            skipped["no_external_msg"] += 1
            continue

        name, url = conv_external_party(msgs)
        if name is None:
            external_count = len(set(m[2] for m in msgs if m[2] and m[2] != JP_NAME))
            if external_count > 1:
                skipped["group"] += 1
            elif external_count == 0:
                skipped["no_external"] += 1
            else:
                skipped["anon"] += 1
            continue

        slug = slugify_name(name)
        sorted_msgs = sorted(msgs, key=lambda m: m[6] or "")

        if slug not in by_party:
            by_party[slug] = {"name": name, "url": url, "convs": []}
        elif not by_party[slug]["url"] and url:
            by_party[slug]["url"] = url
        by_party[slug]["convs"].append((conv_id, sorted_msgs))

    # Write files
    written = 0
    for slug, info in by_party.items():
        # Sort the person's conversations chronologically by their first msg
        info["convs"].sort(key=lambda x: x[1][0][6] or "")
        content = format_conversation_md(info["name"], info["url"], info["convs"])
        out_path = output_dir / f"{slug}.md"
        out_path.write_text(content, encoding="utf-8")
        written += 1

    print(f"Conversations totales       : {len(convs)}")
    print(f"Skip - aucun message JP     : {skipped['no_jp_msg']}")
    print(f"Skip - aucun message ext.   : {skipped['no_external_msg']}")
    print(f"Skip - groupe (>1 ext)      : {skipped['group']}")
    print(f"Skip - LinkedIn Member anon : {skipped['anon']}")
    print(f"Skip - pas d'interlocuteur  : {skipped['no_external']}")
    print()
    print(f"Fichiers ecrits             : {written}")


if __name__ == "__main__":
    main()
