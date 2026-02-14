# /push-gas — Push to Google Apps Script

Push the current apps-script/ code to GAS and verify.

## Steps
1. Run `cd apps-script && clasp push`
2. Verify the output shows "Pushed N files" with no errors
3. Report the file count and any warnings
4. If errors occur, read the error message and suggest fixes

## Post-push
- Test via `/dev` URL (always runs HEAD code, not frozen deployment)
- If testing against `/exec` URL, a new `clasp deploy` is needed first
