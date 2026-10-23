<#
.SYNOPSIS
    Waits for the browser's native "Open" file dialog and types a path into it.

.DESCRIPTION
    Maestro cannot upload a file. It has no upload command, its runScript engine
    has no DOM, and injecting a File into the page's input element via JavaScript
    sets input.files but the Bulk Stock Upload component never registers it.

    The only path left is the one a human uses: click "Browse in my files" and
    answer the operating system's file dialog. Maestro cannot see that dialog -
    it is a native window, not part of the page - so this script drives it from
    outside, running in parallel with the flow.

    The path is pasted from the clipboard rather than typed with SendKeys,
    because SendKeys treats + ^ % ~ ( ) { } [ ] as control characters and a
    Windows path or a Chrome-deduplicated filename like "template (2).xlsx"
    would be mangled.

.NOTES
    Takes over the keyboard for a moment. Do not type or click while it runs.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $FilePath,

    # Generous by default: the flow has to log in and walk to the dialog first.
    [int] $TimeoutSeconds = 240
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $FilePath)) {
    throw "File to upload not found: $FilePath"
}
$FilePath = (Resolve-Path -LiteralPath $FilePath).Path

Add-Type -AssemblyName System.Windows.Forms

# Chrome's picker is titled "Open" on an English Windows. Matching on the start
# of the title rather than equality covers "Open File" and localised suffixes.
function Find-DialogProcess {
    Get-Process |
        Where-Object { $_.MainWindowTitle -and $_.MainWindowTitle -match '^Open' } |
        Select-Object -First 1
}

$shell = New-Object -ComObject WScript.Shell
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$dialog = $null

while ((Get-Date) -lt $deadline) {
    $dialog = Find-DialogProcess
    if ($dialog) { break }
    Start-Sleep -Milliseconds 250
}

if (-not $dialog) {
    throw "The file dialog never appeared within $TimeoutSeconds seconds."
}

Write-Host "Found file dialog: '$($dialog.MainWindowTitle)' (pid $($dialog.Id))"

if (-not $shell.AppActivate($dialog.Id)) {
    # A second attempt: the window can still be settling right after it opens.
    Start-Sleep -Milliseconds 500
    if (-not $shell.AppActivate($dialog.Id)) {
        throw 'Could not focus the file dialog.'
    }
}

# Let the dialog take focus and put the caret in its filename box.
Start-Sleep -Milliseconds 800

Set-Clipboard -Value $FilePath
[System.Windows.Forms.SendKeys]::SendWait('^v')
Start-Sleep -Milliseconds 600
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')

Write-Host "Submitted path to the dialog: $FilePath"
