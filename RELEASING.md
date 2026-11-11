# Releasing a new version

Building and publishing is done by GitHub Actions (BigWigsMods/packager, file `.github/workflows/release.yml`).
It builds a zip without the tests and internal files (the list is in `.pkgmeta`) and uploads it
to **CurseForge**, **Wago Addons** and **GitHub Releases** as a file for WoW Forever 1.60.1
(Interface 16001 in `Bulwark.toc` is detected automatically).

## Once: connect the sites

1. **CurseForge**: create a project at https://authors.curseforge.com, get its **Project ID**
   (on the right of the project page) and an API token at https://legacy.curseforge.com/account/api-tokens.
2. **Wago**: create a project at https://addons.wago.io/developers, get its **ID** from the project URL
   and an API key at https://addons.wago.io/account/apikeys.
3. Put the IDs into `Bulwark.toc`:
   ```
   ## X-Curse-Project-ID: 123456
   ## X-Wago-ID: abcd1234
   ```
4. On GitHub: **Settings → Secrets and variables → Actions → New repository secret**:
   `CF_API_KEY` = the CurseForge token, `WAGO_API_TOKEN` = the Wago key.

A site without an ID or a key is simply skipped; the GitHub release is created either way.

## Every release

1. Bump `## Version:` in `Bulwark.toc` (and the version in the code, if it's written there too).
2. Commit and push to `main`.
3. Create a tag and push it:
   ```
   git tag v1.2.3
   git push origin v1.2.3
   ```
4. In a couple of minutes the version shows up on all sites. You can follow the build in the **Actions** tab on GitHub.

The changelog is built from the commit messages since the previous tag.
