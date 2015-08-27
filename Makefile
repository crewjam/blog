
.PHONY: dist

#HUGO := $(shell command -v hugo)
HUGO := $(HOME)/go/bin/hugo

all: dist

serve:
	$(HUGO) server --watch --buildDrafts

dist:
	$(HUGO) -d dist

commit: 
	git add -A
	git commit -m "..."
	git push origin master

dist-commit:
	(set -ex; \
	cd dist; \
	git add -A; \
  	git commit -m "rebuilding site $(date)"; \
  	git push origin master; \
  	)

deploy: dist commit dist-commit
