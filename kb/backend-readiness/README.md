# Backend Readiness

This folder stores generated checkpoint reports for the backend knowledge layer.

Files:

- `latest.backend-readiness.json`: machine-readable status summary for implemented backend layers, endpoint contracts, validations, generated views, and known gaps.

Regenerate with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-backend-readiness-report.ps1 -Root .
```
