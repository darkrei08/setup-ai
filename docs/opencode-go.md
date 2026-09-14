# OpenCode Go inside pi

An OpenCode Go subscription is reusable in pi (no lock-in). After
`opencode auth login`, add a custom provider in pi:

```js
pi.registerProvider("opencode-go", {
  baseUrl: "https://opencode.ai/zen/v1",
  apiKey: "$OPENCODE_API_KEY",
  authHeader: true,
  api: "openai-completions",
  models: [ /* your Go plan model ids */ ],
});
```

or run `/provider add` in pi. Docs: <https://pi.dev/docs/latest/custom-provider>.

The `opencode` module installs the CLI and, on Windows, resolves the native
launcher behind the npm shim so the `opencode-pi` extension can spawn it (see
[modules](./modules.md#codex--antigravity--opencode)).

Back to the [README](../README.md).
