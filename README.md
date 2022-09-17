# acm-terminal.el

Patch for LSP bridge acm on Terminal.

<img src="./screenshot.png">

## Requirements

- [lsp-bridge](https://github.com/manateelazycat/lsp-bridge) ddf03f3(2022-08-22) or newer
- [popon](https://codeberg.org/akib/emacs-popon)

## Installation

```emacs-lisp
(quelpa '(acm-terminal :repo "twlz0ne/acm-terminal"
                       :fetcher github
                       :files ("acm-terminal.el")))
```

## Configuration

```emacs-lisp
(require 'yasnippet)
(yas-global-mode 1)

(require 'lsp-bridge)
(global-lsp-bridge-mode)

(unless (display-graphic-p)
  (with-eval-after-load 'acm
    (require 'acm-terminal)))
```
