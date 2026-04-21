# SimpleText Release

Perform a full release: strip the local dev digit, bump to the target semver, build, zip, commit, tag, push, and create a GitHub release.

## Steps

### 1. Read current version
- Read `build.sh` — find the `VERSION=` line. It will look like `1.0.0.4` (with dev digit) or `1.0.0` (clean).
- Strip the fourth digit to get the base semver: `1.0.0.4` → `1.0.0`.

### 2. Ask the user which version to release
Present the base version and ask: "Current base is X.Y.Z. Which component do you want to bump for this release?"
- patch → X.Y.(Z+1)  e.g. 1.0.0 → 1.0.1
- minor → X.(Y+1).0  e.g. 1.0.0 → 1.1.0
- major → (X+1).0.0  e.g. 1.0.0 → 2.0.0
- none  → keep X.Y.Z (re-release same version)

Wait for the user's answer before proceeding.

### 3. Set the release version
- Write the chosen version (e.g. `1.0.1`) into `build.sh` as `VERSION="1.0.1"` — replace the entire old value including any dev digit.
- Update `CLAUDE.md`: replace the `- Current version: …` line with `- Current version: 1.0.1`.
- **Do NOT call `./build.sh` yet** — step 4 will build, and `build.sh` will immediately increment the dev digit if we don't set it first and then prevent the counter. Instead, set VERSION in build.sh AND temporarily rename the counter script so the next build is a clean release build:
  - Use `sed -i '' "s/VERSION=\"[^\"]*\"/VERSION=\"<new_version>\"/" build.sh`
  - Temporarily disable the counter by renaming: `mv .claude/local-build-counter.sh .claude/local-build-counter.sh.bak`

### 4. Build the release binary
```bash
./build.sh
```
Confirm it reports the correct version with no dev digit.

### 5. Restore the counter
```bash
mv .claude/local-build-counter.sh.bak .claude/local-build-counter.sh
```

### 6. Zip the app
```bash
cd build && zip -r SimpleText.app.zip SimpleText.app && cd ..
```

### 7. Commit and tag
```bash
git add build.sh CLAUDE.md
git commit -m "Release v<version>

Generated with AI

Co-Authored-By: Claude Code <ai@netwrix.com>"
git tag v<version>
```

### 8. Push
```bash
git push origin main
git push origin v<version>
```

### 9. Draft release notes
- Find the previous release tag: `gh release list --limit 10` — pick the tag just before the one being released.
- Get the commit log since that tag: `git log <prev-tag>..v<version> --oneline`
- Write user-facing release notes from those commits. Group into sections that apply (omit empty sections):
  - **New** — user-visible features
  - **Fixed** — bug fixes
  - **Improved** — enhancements to existing behaviour
  - **Chores** — version bumps, docs, CI, tooling (keep brief or omit if uninteresting)
- Keep each bullet short (one line). Skip purely internal/tooling commits that users won't care about.
- Show the draft to the user and wait for approval or edits before proceeding.

### 10. Create GitHub release
Once the user approves the release notes:
```bash
gh release create v<version> build/SimpleText.app.zip \
  --title "SimpleText v<version>" \
  --notes "<approved release notes>"
```

### 11. Report
Output the release URL so the user can verify it.
