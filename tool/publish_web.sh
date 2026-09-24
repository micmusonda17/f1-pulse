#!/bin/bash
# Pitbeat: put the project on GitHub and switch on the web version.
# Run it from the project folder:  bash tool/publish_web.sh
#
# After the first time, `git push` is enough: GitHub rebuilds the website
# on its own (.github/workflows/deploy-web.yml). Run this script again only
# when tool/deploy-web.yml changes. You can give it a commit message:
#   bash tool/publish_web.sh "Keep the news connected on the web"

set -o pipefail
cd "$(dirname "$0")/.." || exit 1
REPO=pitbeat
OLD_REPO=f1-pulse # The name before the app was renamed

echo
echo "== 1. The GitHub command line tool =="
if ! command -v gh >/dev/null 2>&1; then
  echo "Installing gh with Homebrew..."
  brew install gh || exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "Sign in to GitHub. Copy the code it shows, then press Enter to open the browser."
  gh auth login --hostname github.com --git-protocol https --web --scopes workflow || exit 1
fi
# Uploading a workflow file needs GitHub's 'workflow' permission.
if ! gh auth status 2>&1 | grep -q "'workflow'"; then
  echo "GitHub needs one more permission ('workflow'). Follow the browser steps."
  gh auth refresh --hostname github.com --scopes workflow || exit 1
fi
gh auth setup-git # Lets git push use this same GitHub login
OWNER=$(gh api user --jq .login) || exit 1
echo "Signed in as $OWNER."

echo
echo "== 2. The website build instructions for GitHub =="
# GitHub runs any workflow file it finds in .github/workflows. This one
# builds the website on every push and every 30 minutes.
if ! cmp -s tool/deploy-web.yml .github/workflows/deploy-web.yml; then
  mkdir -p .github/workflows
  cp tool/deploy-web.yml .github/workflows/deploy-web.yml
  echo "Copied the latest tool/deploy-web.yml into .github/workflows/"
else
  echo "Up to date."
fi

echo
echo "== 3. Git =="
if [ ! -d .git ]; then
  git init -b main
fi
# Commits need a name and an email. If git has none yet, use your GitHub
# name and GitHub's private no-reply address, so your real email stays private.
if [ -z "$(git config user.name)" ]; then
  git config user.name "$(gh api user --jq '.name // .login')"
fi
if [ -z "$(git config user.email)" ]; then
  git config user.email "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
fi
git add -A
git commit -m "${1:-Update Pitbeat}" >/dev/null 2>&1 && echo "Saved a commit." || echo "Nothing new to commit."

echo
echo "== 4. The repository on GitHub =="
# A repository still under its old name is renamed, not created again.
if ! gh repo view "$OWNER/$REPO" >/dev/null 2>&1 \
  && gh repo view "$OWNER/$OLD_REPO" >/dev/null 2>&1; then
  gh repo rename "$REPO" --repo "$OWNER/$OLD_REPO" --yes || exit 1
  echo "Renamed $OLD_REPO to $REPO."
fi
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "https://github.com/$OWNER/$REPO.git"
  echo "Connected to https://github.com/$OWNER/$REPO"
else
  gh repo create "$REPO" --public --source . --remote origin \
    --description "A Formula 1 companion app for iPhone and the web, built with Flutter" \
    || exit 1
fi

# The description and website link shown at the top of the repository page.
gh repo edit "$OWNER/$REPO" \
  --description "A Formula 1 companion app for iPhone and the web, built with Flutter" \
  --homepage "https://$OWNER.github.io/$REPO/" >/dev/null 2>&1

echo
echo "== 5. Switch on GitHub Pages =="
if gh api "repos/$OWNER/$REPO/pages" >/dev/null 2>&1; then
  echo "Already on."
elif gh api -X POST "repos/$OWNER/$REPO/pages" -f build_type=workflow >/dev/null 2>&1; then
  echo "Switched on."
else
  echo "Could not switch it on from here. On github.com, open $OWNER/$REPO,"
  echo "then Settings, Pages, and set Source to 'GitHub Actions'. Then run this again."
  exit 1
fi

echo
echo "== 6. Upload =="
git push -u origin main || exit 1

echo
echo "== 7. GitHub is building the website (about 3 minutes) =="
sleep 10 # Give GitHub a moment to start the build
RUN_ID=$(gh run list --repo "$OWNER/$REPO" --workflow deploy-web.yml --limit 1 \
  --json databaseId --jq '.[0].databaseId')
if [ -n "$RUN_ID" ]; then
  gh run watch "$RUN_ID" --repo "$OWNER/$REPO" --exit-status \
    || { echo "The build failed. See the output above, or the Actions tab on GitHub."; exit 1; }
fi

echo
echo "Done. Your website:  https://$OWNER.github.io/$REPO/"
echo "On your iPhone: open it in Safari, tap Share, then 'Add to Home Screen'."
