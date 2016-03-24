
.PHONY: dist images

#HUGO := $(shell command -v hugo)
HUGO := $(HOME)/go/bin/hugo

all: dist

serve:
	$(HUGO) server --watch --buildDrafts

dist: thumbs images
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

thumbs: $(patsubst images/%,static/thumbs/%,$(wildcard images/*))
static/thumbs/%: images/% Makefile
	convert -define jpeg:size=500x180  $<  -auto-orient \
    	-thumbnail 250x90   -unsharp 0x.5  $@

images: $(patsubst images/%,static/images/%,$(wildcard images/*))
static/images/%: images/% Makefile
	convert -define jpeg $< -resize '800000@>' $@

deploy: dist commit dist-commit
