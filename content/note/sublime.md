+++
date = "2015-08-27T14:14:44-07:00"
title = "Sublime Text Configuration & Notes"
image = "/images/background-64258_1280.jpg"
+++

## General

- Browse Command lift: `⌘ shift P`
- Column Mode - `option` + click
- Multiselect `⌘D`

Edit `~/Library/Application Support/Sublime Text 2/Packages/Makefile/Make.sublime-build` to support additional make targets:

```json
{
	"cmd": ["make"],
	"file_regex": "^(..[^:]*):([0-9]+):?([0-9]+)?:? (.*)$",
	"working_dir": "${project_path:${folder:${file_path}}}",
	"selector": "source.makefile",

	"variants":
	[
		{
			"name": "Clean",
			"cmd": ["make", "clean"]
		},
		{
			"name": "Deploy",
			"cmd": ["make", "deploy"]
		},
		{
			"name": "Check",
			"cmd": ["make", "check"]
		}
	]
}
```

## Plugins

 - GitGutter (experminting)
 - MarkdownEditing 

## Golang

Useful instructions for setting up GoSublime are here: http://www.wolfe.id.au/2015/03/05/using-sublime-text-for-go-development/

My GoSublime.sublime-settings looks like:

	{
		"env": {
			"GOPATH": "$HOME/go",
			"PATH": "/usr/local/go/bin:$GOPATH/bin:$PATH"
		},
		"fmt_cmd": ["goimports"],
		"comp_lint_enabled": true,
		"comp_lint_commands": [
			{"cmd": ["golint *.go"], "shell": true},
			{"cmd": ["go", "vet"]},
			{"cmd": ["go", "install"]},
		],
		"on_save": [
			{"cmd": "gs_comp_lint"}
		]
	}

Helpful keybindings:

	- `⌘+.` `⌘.H` - Documentation hints
	- `⌘+.` `⌘.D` - Jump to definition
	- `⌘+.` `shift-space` - Function hints

## References

- https://blog.generalassemb.ly/sublime-text-3-tips-tricks-shortcuts/


