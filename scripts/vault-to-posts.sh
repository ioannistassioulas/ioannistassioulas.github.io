#!/usr/bin/env bash
set -euo pipefail

VAULT_DIR="vault"
POSTS_DIR="docs/_posts"
ASSETS_DIR="docs/assets/images"

mkdir -p "$POSTS_DIR" "$ASSETS_DIR"

shopt -s nullglob
for file in "$VAULT_DIR"/*.md; do
  filename=$(basename "$file" .md)

  # --- Extract frontmatter fields ---
  # Handles: title: "My Post" OR title: My Post
  title=$(awk -F': ' '/^title:/ {sub(/^title: /, ""); print; exit}' "$file")
  title=${title:-$filename}
  title=$(echo "$title" | sed -e 's/^"//' -e 's/"$//')

  post_date=$(awk -F': ' '/^date:/ {sub(/^date: /, ""); print; exit}' "$file")
  post_date=${post_date:-$(date +%Y-%m-%d)}
  post_date=$(echo "$post_date" | tr -d '[:space:]')  # strip stray whitespace

  # --- Slugify title for the filename ---
  slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')

  out_file="$POSTS_DIR/${post_date}-${slug}.md"

  # --- Copy note, then rewrite Obsidian-specific syntax ---
  cp "$file" "$out_file"

  # [[Page|Alias]] -> Alias
  sed -i '' -E 's/\[\[[^]|]+\|([^]]+)\]\]/\1/g' "$out_file"
  # [[Page]] -> Page
  sed -i '' -E 's/\[\[([^]]+)\]\]/\1/g' "$out_file"

  # ![[image.png]] -> markdown image, copy image file if it exists
  if grep -qE '!\[\[[^]]+\]\]' "$out_file" 2>/dev/null; then
    grep -oE '!\[\[[^]]+\]\]' "$out_file" | while read -r embed; do
      img_name=$(echo "$embed" | sed -E 's/!\[\[([^]]+)\]\]/\1/')
      if [ -f "$VAULT_DIR/$img_name" ]; then
        cp "$VAULT_DIR/$img_name" "$ASSETS_DIR/$img_name"
      fi
      escaped_embed=$(printf '%s\n' "$embed" | sed 's/[&/\]/\\&/g')
      sed -i "s|${escaped_embed}|![${img_name}](/assets/images/${img_name})|g" "$out_file"
    done
  fi
  echo "Generated $out_file"
done