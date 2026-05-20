# examples/

Sample assets that work *with* `arche-diary` but are deliberately not
shipped as part of the package. The goal is to keep `arche-diary.el`
focused on writing and exporting the diary, while deployment and other
side concerns live here as small, easy-to-audit files you copy out and
adapt.

## `upload-diary` — push the HTML export over FTPS

A `lftp`-based mirror script meant to be triggered from
`arche-diary-after-export-hook` so each export auto-syncs the HTML
folder to a remote host. The script intentionally stays transport
logic only; no Emacs Lisp is involved in the upload itself.

Quick start:

```sh
# 1. Install lftp.
# 2. Store credentials in ~/.netrc (mode 600, no spaces around `=`):
cat > ~/.netrc <<'EOF'
machine ftp.example.com
  login    mydiary
  password supersecretlongrandomstring
EOF
chmod 600 ~/.netrc

# 3. Copy the script somewhere on your PATH.
install -m 0755 examples/upload-diary ~/bin/upload-diary

# 4. First run with --dry-run to preview what would change.
DIARY_FTP_HOST=ftp.example.com \
DIARY_FTP_REMOTE=/public_html/diary \
DIARY_MIRROR_FLAGS="--dry-run --verbose --reverse --delete" \
    ~/bin/upload-diary

# 5. Wire it into the export hook (in your init, not in arche-diary.el):
```

```elisp
(add-hook 'arche-diary-after-export-hook
          (lambda ()
            (let ((process-environment
                   (append '("DIARY_FTP_HOST=ftp.example.com"
                             "DIARY_FTP_REMOTE=/public_html/diary")
                           process-environment)))
              (start-process "diary-upload" "*diary-upload*"
                             (expand-file-name "~/bin/upload-diary")))))
```

`start-process` runs asynchronously, so `M-x arche-diary-export-html`
returns immediately; watch `*diary-upload*` for progress.

### Security notes (also at the top of the script)

- Plain FTP transmits credentials and data in cleartext. FTPS fixes that
  *only when TLS is actually verified.* The script keeps
  `ssl:verify-certificate` and `ssl:check-hostname` enabled; don't turn
  them off. For a self-signed host, pin the CA instead.
- `ftp:ssl-force true` refuses any silent fallback to plain FTP.
- `--delete` mirrors deletions: an empty/missing local `html/` will wipe
  the remote. Always dry-run first.
- Credentials live in `~/.netrc` (mode 600) — never inline in the script,
  on a command line, or in Emacs config.

### Adapting to other transports

The script's whole job is "turn a local directory into a remote
directory." Swap the body and the hook stays the same:

- **rsync over SSH** (recommended whenever the host supports it):
  `rsync -avz --delete "$LOCAL/" diary-site:/var/www/diary/`
- **GitHub Pages / Netlify / S3**: replace with the relevant CLI
  (`git push`, `netlify deploy`, `aws s3 sync`).

In all cases, `arche-diary.el` itself does not need to change.
