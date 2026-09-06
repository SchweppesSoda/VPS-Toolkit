$ErrorActionPreference = 'Stop'
# Includes unchanged-entry refresh, independent intervals, migration and removal.
& (Join-Path $PSScriptRoot 'test-client-channel-schedules.ps1')
