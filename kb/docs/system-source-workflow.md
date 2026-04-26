# System Source Workflow

The systems layer is patch-sensitive and should be refreshed through a source map instead of ad hoc edits.

Workflow:

1. Update [system-source-map.json](/Users/GUEST1/OneDrive/Desktop/warframe%20data/warframe-kb/core/mappings/system-source-map.json) with verified references and review metadata.
2. Run `powershell -ExecutionPolicy Bypass -File .\scripts\apply-system-source-map.ps1`.
3. Rebuild manifests, registry, and AI views.

Rules:

- Prefer source URLs that describe mechanics directly.
- Keep patch-sensitive records marked with `verification.patchSensitive = true`.
- Preserve canonical summaries and mechanic fields unless the source update explicitly changes them.
- Use `notesAppend` in the source map for review guidance instead of overwriting authored context.
