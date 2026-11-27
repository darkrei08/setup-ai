# Releasing

Releases are published automatically when an annotated `vX.Y.Z` tag is pushed from a
clean, protected `main` checkout. GitHub Actions creates the GitHub Release with generated
notes, then publishes the exact tag to npm using trusted publishing (OIDC). Manual workflow
dispatch remains available for reruns and recovery.

## One-time npm trust setup

Run this once on the maintainer machine:

```bash
npm login
npm trust github @darkrei08/setup-ai --file publish.yml --repo darkrei08/setup-ai --allow-publish -y
npm trust list @darkrei08/setup-ai
```

`npm login` is only for this one-time trust configuration. Do not run `npm publish`
locally; publication belongs to the workflow.

## Release checklist

1. Ensure the working tree is clean, the intended version is on `main`, and the package
   version is the version being released.
2. Validate locally:

   ```bash
   bash -n setup-ai.sh
   node --check bin/setup-ai.mjs
   npm pack --dry-run
   ```

3. After the release commit is merged into remote `main`, create and push the annotated
   version tag. The tag push starts publication automatically:

   ```bash
   git tag -a v4.0.6 -m "Release v4.0.6"
   git push origin v4.0.6
   ```

4. Watch the automatically started workflow:

   ```bash
   run_id="$(gh run list --repo darkrei08/setup-ai --workflow publish.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
   gh run watch "$run_id" --repo darkrei08/setup-ai --exit-status
   ```

   For a recovery or rerun, dispatch the same workflow manually:

   ```bash
   gh workflow run publish.yml --repo darkrei08/setup-ai --ref main -f tag=v4.0.6
   ```

5. Confirm npm has the released version:

   ```bash
   npm view @darkrei08/setup-ai@4.0.6 version
   ```

The workflow verifies that the tag points to a commit contained in `main` and that its
version matches `package.json`. Existing GitHub Releases are reused on reruns, so an npm
publication failure can be retried without recreating the release.
