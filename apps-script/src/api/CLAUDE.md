# API Module — CLAUDE.md

## Purpose
HTTP entry points. doGet() and doPost() route requests by `action` parameter via switch statement.

## Pattern
Every action: validate → log start → handle → log completion → return JSON response.
All responses use ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(JSON).

## Existing Actions (from enterprise)
- GET: getLogs, health, ping
- POST: writeLog

## Actions Added by This Project
- POST: reportChange — validates payload, calls ChangeTracker.notify(), returns result

## Recent Changes
@changelog.md
