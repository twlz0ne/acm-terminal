# acm-terminal

Patch for LSP bridge acm on Terminal.

<img src="./screenshot.png">

## Requirements

- [lsp-bridge](https://github.com/manateelazycat/lsp-bridge) 81cc2fc(2023-01-08) or newer
- [popon](https://codeberg.org/akib/emacs-popon)

## Installation

### Manual

Clone or download repositories, then put the following in .emacs:

```emacs-lisp
(unless (package-installed-p 'yasnippet)
  (package-install 'yasnippet))

(add-to-list 'load-path "<path-to-lsp-bridge>")

(unless (display-graphic-p)
  (add-to-list 'load-path "<path-to-popon>")
  (add-to-list 'load-path "<path-to-acm-terminal>"))
```

### Quelpa

```emacs-lisp
(unless (package-installed-p 'yasnippet)
  (package-install 'yasnippet))

(quelpa '(lsp-bridge :fetcher github
                     :repo "manateelazycat/lsp-bridge"
                     :files ("*.el" "*.py" "acm" "core" "langserver"
                             "multiserver" "resources")))

(unless (display-graphic-p)
  (quelpa '(popon :fetcher git :url "https://codeberg.org/akib/emacs-popon.git"))
  (quelpa '(acm-terminal :fetcher github :repo "twlz0ne/acm-terminal")))
```

### Straight

```emacs-lisp
(unless (package-installed-p 'yasnippet)
  (package-install 'yasnippet))

(straight-use-package
 '(lsp-bridge :host github
              :repo "manateelazycat/lsp-bridge"
              :files ("*.el" "*.py" "acm" "core" "langserver"
                      "multiserver" "resources")))

(unless (display-graphic-p)
  (straight-use-package
   '(popon :host nil :repo "https://codeberg.org/akib/emacs-popon.git"))
  (straight-use-package
   '(acm-terminal :host github :repo "twlz0ne/acm-terminal")))
```

### Doom Emacs

```emacs-lisp
(package! yasnippet)

(package! lsp-bridge
  :recipe (:host github
           :repo "manateelazycat/lsp-bridge"
           :files ("*.el" "*.py" "acm" "core" "langserver"
                   "multiserver" "resources")))

(unless (display-graphic-p)
  (package! popon
    :recipe (:host nil :repo "https://codeberg.org/akib/emacs-popon.git"))
  (package! acm-terminal
    :recipe (:host github :repo "twlz0ne/acm-terminal")))
```

## Configuration

```emacs-lisp
(add-hook 'emacs-startup-hook
          (lambda ()
            (require 'yasnippet)
            (yas-global-mode 1)

            (require 'lsp-bridge)
            (global-lsp-bridge-mode)

            (unless (display-graphic-p)
              (with-eval-after-load 'acm
                (require 'acm-terminal)))))
```

