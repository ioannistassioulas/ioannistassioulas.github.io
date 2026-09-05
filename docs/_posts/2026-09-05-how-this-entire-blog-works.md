---
layout: post
title: How this entire blog works
date: 2026-09-05
categories: Technical Overview
---
After much trial and error, as well as consultation with the technological bringer of the end times (Claude), I managed to create an interesting pipeline for uploading blog posts and descriptions of different technical projects. 

Before we begin, a quick introduction to how Jekyll works is necessary. Jekyll is a web dev tool that can create static webpages using markdown files as source documentation. It is perfectly integrated with Github Pages (probably owing to both it and Github being built with Ruby, but this is besides the point), which is why we use it here.  

When we create our first project with Jekyll, it generates the project structure for us and tells us where to put each .md file. General web pages can be saved directly in the docs repository, while specific blog posts are saved inside a special subdirectory, `_posts`. Jekyll also expects the metadata of each file to be saved as follows along the top in the following form:
```
---
layout: post
title: "Welcome to Jekyll!"
date: 1970-01-01 00:00:00 +0300
categories: jekyll update
---
```
All of this is just review so far. What was built in this project was a special Obsidian vault to Github repository pipeline, allowing me to create blog posts directly from my Obsidian app without needing to open up any sort of .

This was done by first creating an untracked directory inside of the github pages repository called `vault`. As the name would suggest, this is where the obsidian vault lives. Inside this vault, we just write all our blog posts as we like. When it is time to publish them to the main site, we run a special functionality that saves all the .md files inside of the vault and saves them according to the metadata above. Since jekyll expects all of the blogposts to follow specific naming conventions, we rename all the files based on what is read. TO have this be done automatically, we need a community plugin: **Templater**. The plugin allows us to automatically run a template script that creates all new markdown files in a particular directory (in this case, the root vault directory `\`) with a specified template markdown. The template in question that we use is the following:
```
---
layout: post
title: <% tp.system.prompt("Post title")%>
date: <% tp.date.now("YYYY-MM-DD") %>
categories: <% tp.system.prompt("Post category")%>
---
```
By creating all new blogposts with this template, we can a) eliminate the need for manually adding the metadata inside the final blogpost markdowns themselves and b) store all the metadata required when naming blogpost files (YYYY-MM-DD-title.md).  The `tp.system.prompt()` commands allow me to write the title and categories as I wish, and the `tp.date.now()` automatically saves the current date at the time of creation in the specified format.

Whenever we are done writing and it is time to publish, we make use of a second Obsidian plugin - **RunJS**. This plugin let's us run specific JavaScript code at the press of a button. The script here does a very simple job - it commits all the changes to the GitHub repository. This script prepares a shell script as a string, and runs it inside the vault directory path. It then returns information to the user depending on whether or not it succeeded.
```
const { exec } = require("child_process");  

// This is the script file to run
const script = `
#!/usr/bin/env bash
set -euo pipefail

bash ../scripts/vault-to-posts.sh
git add ../docs/_posts ../docs/assets

if git diff --cached --quiet; then
	echo "Nothing to publish"
	exit 0
fi

git commit -m "Publish new blog post"
git push origin main
`;

// I think this points to the vault? Edit: it does!
const vaultPath = this.app.vault.adapter.basePath;
  
exec(script, { cwd: vaultPath }, (error, stdout, stderr) => {
if (error) {
	console.error(stderr);
	new Notice(`❌ Publish failed: ${error.message}`);
	return;
}

console.log(stdout);
new Notice("✅ Published!");
});
```
The obvious question - why invoke JavaScript for a trivial shell script? Why use a shell script at all? This is because of a weird interaction with **Git** plugin on Obsidian - it isn't allowed to commit if there aren't any changes. I couldn't find an appropriate replacement, so **RunJS** was the best option. Since our drafting directory `vault` isn't tracked, writing posts through Obsidian and editing no other files means we can never commit and push through the Obsidian. It was really important for me when creating this pipeline that I do everything with cool UI buttons - otherwise, it would have been relatively trivial to run an empty commit through a shell command through the terminal.

Which then runs the `vault-to-posts.sh` command and then adds the appropriate docs. 

This second script is where the magic happens. It reads all the blog posts inside of the vault, and copies them over to the `_posts` directory with the desired filenames, completely automatically.  It also takes care to reformat each of the files as Jekyll expects, keeps markdown links between Obsidian files correct (the famous Alias system) and it copies any and all images and saves them to the `assets/images` (or it should - current work in progress) 
```
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
	post_date=$(echo "$post_date" | tr -d '[:space:]') # strip stray whitespace

	# --- Slugify title for the filename ---
	slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
	
	out_file="$POSTS_DIR/${post_date}-${slug}.md"

	# --- Copy note, then rewrite Obsidian-specific syntax ---
	cp "$file" "$out_file"
	
	# Alias -> Alias
	sed -i '' -E 's/\[\[[^]|]+\|([^]]+)\]\]/\1/g' "$out_file"
	
	# Page -> Page
	sed -i '' -E 's/\[\[([^]]+)\]\]/\1/g' "$out_file"

  

# !image.png -> markdown image, copy image file if it exists
	if grep -qE '!\[\^+\]\]' "$out_file" 2>/dev/null; then
		grep -oE '!\[\^+\]\]' "$out_file" | while read -r embed; do
			img_name=$(echo "$embed" | sed -E 's/!\[\[([^]]+)\]\]/\1/')
			if [ -f "$VAULT_DIR/$img_name" ]; then
				cp "$VAULT_DIR/$img_name" "$ASSETS_DIR/$img_name
			fi
		escaped_embed=$(printf '%s\n' "$embed" | sed 's/[&/\]/\\&/g')
		sed -i "s|${escaped_embed}|![${img_name}](/assets/images/${img_name})|g" "$out_file"
	done
fi

echo "Generated $out_file"

done
```

This then pushes the source files directly to the remote repository, where the Github action responsible for building the Jekyll project and deploying the website runs - allowing me to update the blog without ever opening VSCode!
