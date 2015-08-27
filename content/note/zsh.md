+++
date = "2015-08-27T15:25:20-07:00"
slug = "zsh"
title = "zsh Configuration & Notes"
image = "/images/background-64258_1280.jpg"
+++

Of modern shells, I prefer **zsh** over **fish** because it supports POSIX standards which make it possible to do stuff like copy & paste `export VARNME=value`. In virtually every other way, *fish* is awesome. 

* Use oh-my-zsh

* To get history that behaves like the bash default, in `~/.oh-my-zsh/lib/history.zsh` 
  remove `setopt share_history # share command history data`

* To get iTerm keybinding to work right, add to `.zshrc`:
    
  ```     
  bindkey -e
  bindkey '^[[1;9C' forward-word
  bindkey '^[[1;9D' backward-word
  ```

  Set up the keybindings to emit the correct escape sequence:

  ![](/images/iterm_zsh_arrow_keys.png)
