# Upload to GitHub

The source archive includes the application, build scripts, tests, documentation and `.github` configuration. It excludes releases, diagnostics, test fixture data, runtime state, build caches and personal paths.

## Upload through the website

1. Create a repository in your GitHub account. Choose public/private as appropriate. Do not automatically add another README or license.
2. Extract `FileLock-0.4.2-Source.zip`.
3. Upload the extracted files and folders. Include hidden files such as `.gitignore` and `.github`.
4. Open the Actions tab to review the Windows build after the upload.
5. Create a release named `0.4.2` and attach the Setup EXE, Windows ZIP and checksums from `release`.

No repository has been published by this preparation step.

## Push using Git

This workspace has an independent Git repository on `codex/github-ready`. Use only this project directory, not the parent user-profile repository.

```powershell
git status
git add .
git commit -m "Prepare FileLock Windows application"
git remote add origin <your-GitHub-repository-URL>
git push -u origin codex/github-ready
```

Replace the URL placeholder before running the commands. Configure your own Git author identity if Git requests it. The workflow runs on any branch and pull request.

## What to commit

Commit maintained source and configuration. `.gitignore` excludes `dist`, `release`, `artifacts`, all `bin/obj` directories, `tests/.work`, logs, encrypted runtime state and executable archives. Do not upload recovery keys, screenshots of private folders, machine diagnostics or local state files.

No license is included, as requested. Choose a license separately if you later want to define reuse terms.
