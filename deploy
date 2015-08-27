#!/bin/bash
set -ex
hugo -d dist
(
  cd dist
  git add -A
  git commit -m "rebuilding site $(date)"
  git push origin master
)

