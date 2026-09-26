# Install the MapleHarness binaries on Windows from GitHub Releases.
#
#   irm https://raw.githubusercontent.com/kinncj/maple-harness-dist/main/install.ps1 | iex
#
#   .\install.ps1 -InstallLocation "C:\tools"
#
# Release-based install needs a published repository with releases; until
# there is one, build from source (`make build`, `make dist/app`; see
# docs/install.md). No credential is needed for a public release repository,
# which is the default. A private one, or one with no release yet, answers
# 404 to an anonymous request, and that looks like "no such release"; when a
# download fails and there is no credential, the error says so.
# The gh CLI is used automatically when present and logged in
# (it resolves release assets by name); GITHUB_TOKEN is honored as a
# fallback for scripting or a private fork. The token path uses
# Invoke-RestMethod, which deserializes the payload properly rather than
# by string matching — a release asset's nested "uploader" object carries
# URL templates with braces that a hand-rolled parser can choke on.
#
# Every release is signed. SHA256SUMS is checked against the project's
# Ed25519 release key (built into this script and the binaries) before any
# hash in it is trusted, and the install is refused when that cannot be done.
# Windows has no built-in Ed25519, so this uses openssl.exe (OpenSSL 3, e.g.
# the one that ships with Git for Windows) or an already-installed
# maple-harness.exe; with neither, it stops and says how to proceed. NOTE: this
# part of the script has not been run on Windows. See docs/supply-chain.md.
#
# Environment overrides (parameters win over all of them):
#   MAPLEHARNESS_VERSION   release tag to install (default: latest)
#   MAPLEHARNESS_BIN_DIR   install directory
#   MAPLEHARNESS_REPO      release owner/repo (default: kinncj/maple-harness-dist)
#   GITHUB_TOKEN            optional (or GH_TOKEN, or an authenticated `gh`): only for a private fork
#
# macOS and Linux: use scripts/install.sh.

[CmdletBinding()]
param(
    [string]$InstallLocation,
    [string]$Version,
    [string]$Repo,
    [switch]$Quiet,
    [switch]$SkipVerify,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$LASTEXITCODE = 0

$BinaryNames = @('maple-proxy', 'maple-harness')
$DefaultRepo = 'kinncj/maple-harness-dist'

# The keys releases are signed with, "name=base64 Ed25519 public key". Must
# match common/pkg/selfupdate/keys.go and scripts/install.sh. The placeholder
# is a real key whose private half does not exist, so until the project's key
# replaces it nothing verifies and this script refuses to install.
$DefaultReleaseKeys = 'PLACEHOLDER-not-a-release-key=kdIYytfg0VNDBAGp4Lco4AjgX+p/7m/mdJsFcSjO5K0='

function Write-Banner {
    if ($Quiet) { return }
    $logo = @'
███╗   ███╗ █████╗ ██████╗ ██╗     ███████╗
████╗ ████║██╔══██╗██╔══██╗██║     ██╔════╝
██╔████╔██║███████║██████╔╝██║     █████╗  
██║╚██╔╝██║██╔══██║██╔═══╝ ██║     ██╔══╝  
██║ ╚═╝ ██║██║  ██║██║     ███████╗███████╗
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝
            H A R N E S S
'@
    Write-Host ""
    Write-Host $logo -ForegroundColor DarkYellow
    Write-Host ""
}

function Write-Step { param([string]$Message) Write-Host "-> $Message" }
function Write-Info { param([string]$Message) Write-Host "   $Message" }

function Fail {
    param([string]$Message)
    Write-Host ''
    [Console]::Error.WriteLine("error: $Message")
    exit 1
}

function Show-Usage {
    Write-Host @"
Install the MapleHarness binaries.

  -InstallLocation DIR   where to put the binaries
                         (default: %LOCALAPPDATA%\Programs\MapleHarness)
  -Version TAG           release tag to install (default: latest)
  -Repo OWNER/NAME       source repository (default: $DefaultRepo)
  -Quiet                 suppress the logo
  -SkipVerify            install even if the release signature cannot be checked
                         (checksums are still enforced). Not recommended.
  -Help                  this message

Environment:
  MAPLEHARNESS_VERSION   release tag
  MAPLEHARNESS_BIN_DIR   install directory
  MAPLEHARNESS_REPO      owner/repo to install from
  MAPLEHARNESS_RELEASE_KEYS  trusted release keys (name=base64, comma separated)
  GITHUB_TOKEN            required (or GH_TOKEN, or an authenticated gh)
"@
}

if ($Help) { Show-Usage; exit 0 }

Write-Banner

function Resolve-Setting {
    param([string]$Value, [string]$EnvName, [string]$Default)
    if (-not [string]::IsNullOrWhiteSpace($Value)) { return $Value }
    $fromEnv = [Environment]::GetEnvironmentVariable($EnvName)
    if (-not [string]::IsNullOrWhiteSpace($fromEnv)) { return $fromEnv }
    return $Default
}

$Repo = Resolve-Setting $Repo 'MAPLEHARNESS_REPO' $DefaultRepo
$Version = Resolve-Setting $Version 'MAPLEHARNESS_VERSION' 'latest'
$InstallLocation = Resolve-Setting $InstallLocation 'MAPLEHARNESS_BIN_DIR' `
    (Join-Path $env:LOCALAPPDATA 'Programs\MapleHarness')

$Token = [Environment]::GetEnvironmentVariable('GITHUB_TOKEN')
if (-not $Token) { $Token = [Environment]::GetEnvironmentVariable('GH_TOKEN') }

# Windows PowerShell 5.1 negotiates whatever SecurityProtocol the machine
# policy left behind, which on older images predates TLS 1.2;
# api.github.com has required it since 2018. PowerShell 7 needs no help.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

# Test-only override, so this script's tests can drive the token path
# against a local stub without touching the network.
$ApiBase = Resolve-Setting '' 'MAPLEHARNESS_API' 'https://api.github.com'

# ---------------------------------------------------------------------------
# Platform
# ---------------------------------------------------------------------------
# The release publishes windows/amd64 only. Windows on ARM runs x64
# binaries through emulation, so this is a note, not a refusal.
$Arch = 'amd64'
$hostArch = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE')
if ($hostArch -and $hostArch -notmatch '^(AMD64|x86)$') {
    Write-Info "note: $hostArch host; installing the amd64 build, which Windows will emulate."
}

# ---------------------------------------------------------------------------
# Auth — optional
# ---------------------------------------------------------------------------
# An authenticated gh, or a token, is used when present and never demanded:
# the default repository is public. GitHub answers 404 for a private
# repository and for a release that does not exist alike, so what a missing
# credential means is explained at the failed download, not before it.
$UseGh = $false
if (Get-Command gh -ErrorAction SilentlyContinue) {
    & gh auth status *> $null
    $UseGh = ($LASTEXITCODE -eq 0)
}

function Get-NoCredentialHint {
    if ($UseGh -or $Token) { return '' }
    return @"


  GitHub answers 404 both for a release that does not exist and for a
  private repository you cannot see. If $Repo is private, sign in with
  'gh auth login' or set `$env:GITHUB_TOKEN and run this again. If no release
  has been published yet, build from source instead: make build (or make dist/app).
"@
}

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('maple-install-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null

# Get-Asset downloads one release asset by name, or throws if the release
# does not carry it. Prefers gh, then an unauthenticated download (works
# for this public repo's releases), then falls back to GITHUB_TOKEN
# against the API asset endpoint for a private fork.
function Get-Asset {
    param([string]$Name, [string]$Destination)

    if ($UseGh) {
        if ($Version -eq 'latest') {
            & gh release download --repo $Repo --pattern $Name --output $Destination --clobber 2>$null
        } else {
            & gh release download $Version --repo $Repo --pattern $Name --output $Destination --clobber 2>$null
        }
        if ($LASTEXITCODE -eq 0) { return }
    }

    $publicUrl = if ($Version -eq 'latest') {
        "https://github.com/$Repo/releases/latest/download/$Name"
    } else {
        "https://github.com/$Repo/releases/download/$Version/$Name"
    }
    try {
        Invoke-WebRequest -Uri $publicUrl -OutFile $Destination -UseBasicParsing
        return
    } catch {
        if ([string]::IsNullOrWhiteSpace($Token)) { throw }
    }

    $releaseUrl = if ($Version -eq 'latest') {
        "$ApiBase/repos/$Repo/releases/latest"
    } else {
        "$ApiBase/repos/$Repo/releases/tags/$Version"
    }
    $headers = @{
        Authorization          = "Bearer $Token"
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -UseBasicParsing
    $asset = $release.assets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $asset) { throw "no asset named $Name" }

    $download = @{ Authorization = "Bearer $Token"; Accept = 'application/octet-stream' }
    Invoke-WebRequest -Uri "$ApiBase/repos/$Repo/releases/assets/$($asset.id)" `
        -Headers $download -OutFile $Destination -UseBasicParsing
}

# GitHub's "latest release" never includes pre-releases, so until there is a stable release it
# answers 404. In that case install the newest release of any kind, and say so.
if ($Version -eq 'latest') {
    try {
        Invoke-WebRequest -Uri "https://github.com/$Repo/releases/latest" -Method Head -UseBasicParsing | Out-Null
    } catch {
        try {
            $newest = Invoke-RestMethod -Uri "$ApiBase/repos/$Repo/releases?per_page=1" -UseBasicParsing
            $first = @($newest)[0]
            if ($first -and $first.tag_name) {
                $Version = $first.tag_name
                Write-Info "there is no stable release yet, so this installs the newest pre-release, $Version"
            }
        } catch { }
    }
}

try {
    Write-Host ''
    Write-Host 'MapleHarness'
    Write-Host "$Repo $Version (windows/$Arch)"
    Write-Host ''

    # -----------------------------------------------------------------------
    # Download
    # -----------------------------------------------------------------------
    $downloaded = @{}
    foreach ($bin in $BinaryNames) {
        $asset = "${bin}_windows_${Arch}.exe"
        Write-Step "Downloading $asset"
        $path = Join-Path $Tmp $asset
        try {
            Get-Asset -Name $asset -Destination $path
        } catch {
            Fail @"
no asset named $asset in release $Version of $Repo.

  Either the release predates this installer's binary names, or the release is
  still publishing. List what it does have:

    gh release view $Version --repo $Repo$(Get-NoCredentialHint)
"@
        }
        $downloaded[$bin] = $path
    }

    # -----------------------------------------------------------------------
    # Verify the signature on SHA256SUMS, then the checksums. A release with
    # no SHA256SUMS is indistinguishable from one whose manifest an attacker
    # removed, so both are refusals. The signed message is
    # "maple-harness-release-v1\n" + tag + "\n" + the exact bytes of SHA256SUMS.
    # -----------------------------------------------------------------------
    $sumsPath = Join-Path $Tmp 'SHA256SUMS'
    try {
        Get-Asset -Name 'SHA256SUMS' -Destination $sumsPath
    } catch {
        Fail 'this release publishes no SHA256SUMS; refusing to install unverified binaries.'
    }

    Write-Step 'Verifying the release signature'
    $sigPath = Join-Path $Tmp 'SHA256SUMS.sig'
    $haveSig = $true
    try { Get-Asset -Name 'SHA256SUMS.sig' -Destination $sigPath } catch { $haveSig = $false }

    function Get-KeyId {
        param([byte[]]$Raw)
        $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($Raw)
        return (($hash[0..7] | ForEach-Object { $_.ToString('x2') }) -join '')
    }

    # Find an openssl.exe that can verify raw Ed25519, by proving it can.
    function Find-Ed25519OpenSsl {
        $cands = @()
        $onPath = Get-Command openssl -ErrorAction SilentlyContinue
        if ($onPath) { $cands += $onPath.Source }
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if ($root) { $cands += (Join-Path $root 'Git\usr\bin\openssl.exe') }
        }
        foreach ($c in $cands) {
            if (-not (Test-Path -LiteralPath $c)) { continue }
            $d = Join-Path $Tmp ('probe-' + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $d | Out-Null
            try {
                & $c genpkey -algorithm ed25519 -out (Join-Path $d 'k.pem') *> $null
                if ($LASTEXITCODE -ne 0) { continue }
                [IO.File]::WriteAllBytes((Join-Path $d 'm'), [byte[]](120))
                & $c pkeyutl -sign -inkey (Join-Path $d 'k.pem') -rawin -in (Join-Path $d 'm') -out (Join-Path $d 's') *> $null
                if ($LASTEXITCODE -ne 0) { continue }
                & $c pkeyutl -verify -inkey (Join-Path $d 'k.pem') -rawin -in (Join-Path $d 'm') -sigfile (Join-Path $d 's') *> $null
                if ($LASTEXITCODE -eq 0) { return $c }
            } finally { Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue }
        }
        return $null
    }

    $signed = $false
    if ($haveSig) {
        $sigLines = @(Get-Content -Path $sigPath)
        if ($sigLines.Count -lt 1 -or $sigLines[0].Trim() -ne 'maple-harness-release-signature v1') {
            Fail 'SHA256SUMS.sig is not a release signature (unexpected header). Nothing has been installed.'
        }
        $f = @{}
        foreach ($l in $sigLines | Select-Object -Skip 1) {
            $k, $v = $l -split ':', 2
            if ($v) { $f[$k.Trim()] = $v.Trim() }
        }
        if (-not ($f['key'] -and $f['tag'] -and $f['sig'])) { Fail 'SHA256SUMS.sig is incomplete. Nothing has been installed.' }
        if ($Version -ne 'latest' -and $f['tag'] -ne $Version) {
            Fail "the signature is for release $($f['tag']), not $Version: it was moved from another release. Nothing has been installed."
        }

        $ring = Resolve-Setting '' 'MAPLEHARNESS_RELEASE_KEYS' $DefaultReleaseKeys
        $pubB64 = $null; $keyName = $null
        foreach ($entry in ($ring -split '[,\r\n]')) {
            $entry = $entry.Trim(); if (-not $entry) { continue }
            if ($entry.Contains('=')) { $name, $b64 = $entry -split '=', 2 } else { $name = 'key'; $b64 = $entry }
            try { $raw = [Convert]::FromBase64String($b64) } catch { continue }
            if ((Get-KeyId $raw) -eq $f['key']) { $pubB64 = $b64; $keyName = $name; break }
        }
        if (-not $pubB64) {
            if ($ring -like '*PLACEHOLDER-not-a-release-key*') {
                Fail @"
this installer has no release key yet (it carries a placeholder), so it cannot verify anything.

  Get the installer from the release you are installing, or see
  docs/supply-chain.md. Nothing has been installed.
"@
            }
            Fail "this release is signed by key $($f['key']), which this installer does not trust.`n`n  If the project rotated its key, get a newer installer. If you did not expect this, do not install. Nothing has been installed."
        }

        $msg = Join-Path $Tmp 'msg'
        $prefix = [Text.Encoding]::ASCII.GetBytes("maple-harness-release-v1`n$($f['tag'])`n")
        [IO.File]::WriteAllBytes($msg, $prefix + [IO.File]::ReadAllBytes($sumsPath))
        $sigBin = Join-Path $Tmp 'sig'
        [IO.File]::WriteAllBytes($sigBin, [Convert]::FromBase64String($f['sig']))

        $ossl = Find-Ed25519OpenSsl
        if ($ossl) {
            # An Ed25519 public key in DER is a fixed 12-byte prefix and the 32 raw bytes.
            $der = [byte[]](0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00) + [Convert]::FromBase64String($pubB64)
            $pem = "-----BEGIN PUBLIC KEY-----`n" + [Convert]::ToBase64String($der) + "`n-----END PUBLIC KEY-----`n"
            $pemPath = Join-Path $Tmp 'pub.pem'
            [IO.File]::WriteAllText($pemPath, $pem)
            & $ossl pkeyutl -verify -pubin -inkey $pemPath -rawin -in $msg -sigfile $sigBin *> $null
            if ($LASTEXITCODE -ne 0) {
                Fail "the signature on SHA256SUMS does NOT match. The release was altered after it was signed, or is not genuine.`n`n  Nothing has been installed. Do not use these files."
            }
            $signed = $true
        } else {
            # Only an already-installed maple-harness may vouch: the one just
            # downloaded cannot vouch for itself.
            $existing = Join-Path $InstallLocation 'maple-harness.exe'
            if (Test-Path -LiteralPath $existing) {
                & $existing update --verify-release $sumsPath --sig $sigPath --version $f['tag'] *> $null
                if ($LASTEXITCODE -ne 0) { Fail 'the installed maple-harness rejected the signature on SHA256SUMS. Nothing has been installed.' }
                $keyName = "$keyName (via the installed maple-harness)"
                $signed = $true
            }
        }
        if ($signed) { Write-Info "signed by $keyName for $($f['tag'])" }
    }

    if (-not $signed) {
        if ($SkipVerify) {
            Write-Host '! the release signature was not checked; continuing because of -SkipVerify. The checksums still apply, but nothing proves they came from the project.'
        } elseif (-not $haveSig -and -not $env:MAPLEHARNESS_RELEASE_KEYS -and $DefaultReleaseKeys -like '*PLACEHOLDER-not-a-release-key*') {
            # No release key is embedded: this project does not sign, so the
            # checksums are what is verified.
            Write-Info 'this release is not signed; verifying its checksums only'
        } elseif (-not $haveSig) {
            Fail @"
this release is not signed (no SHA256SUMS.sig), so its authenticity cannot be checked.

  Nothing has been installed. If you are sure about where you got it,
  -SkipVerify installs anyway (checksums are still enforced).
"@
        } else {
            Fail @"
cannot check the release signature: no OpenSSL 3 (openssl.exe) was found, and no maple-harness is installed yet to do it.

  Either:
    - install Git for Windows (it ships OpenSSL 3) or another OpenSSL 3 and run this again, or
    - verify by hand as docs/supply-chain.md describes, then re-run with -SkipVerify.

  Nothing has been installed.
"@
        }
    }

    $sums = @{}
    foreach ($line in (Get-Content -Path $sumsPath)) {
        $fields = $line.Trim() -split '\s+'
        if ($fields.Count -lt 2) { continue }
        $sums[$fields[1].TrimStart('*')] = $fields[0].ToLowerInvariant()
    }

    foreach ($bin in $BinaryNames) {
        $asset = "${bin}_windows_${Arch}.exe"
        if (-not $sums.ContainsKey($asset)) {
            Fail "SHA256SUMS has no entry for $asset; refusing to install an unverified binary."
        }
        $want = $sums[$asset]
        $got = (Get-FileHash -Path $downloaded[$bin] -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($want -ne $got) {
            Fail @"
checksum mismatch for $asset.

    expected: $want
    actual:   $got

  The download was corrupted or tampered with. Nothing has been installed.
"@
        }
        Write-Info "verified $asset"
    }

    # -----------------------------------------------------------------------
    # Install — %LOCALAPPDATA% is per-user and needs no elevation.
    # -----------------------------------------------------------------------
    New-Item -ItemType Directory -Path $InstallLocation -Force | Out-Null
    $InstallLocation = (Resolve-Path -LiteralPath $InstallLocation).Path

    Write-Step "Installing to $InstallLocation"
    foreach ($bin in $BinaryNames) {
        $dest = Join-Path $InstallLocation "$bin.exe"
        Move-Item -LiteralPath $downloaded[$bin] -Destination $dest -Force
        Write-Info "installed $dest"
    }

    # -----------------------------------------------------------------------
    # Licence and third-party notices, covered by the same signed checksums.
    # (They are also inside the binary: maple-harness licenses.)
    # -----------------------------------------------------------------------
    $shareDir = Join-Path $InstallLocation 'licenses'
    foreach ($n in @('LICENSE', 'THIRD_PARTY_NOTICES.md')) {
        $np = Join-Path $Tmp $n
        try { Get-Asset -Name $n -Destination $np } catch { continue }
        if ($sums.ContainsKey($n) -and $sums[$n] -eq (Get-FileHash -Path $np -Algorithm SHA256).Hash.ToLowerInvariant()) {
            New-Item -ItemType Directory -Path $shareDir -Force | Out-Null
            Copy-Item -LiteralPath $np -Destination (Join-Path $shareDir $n) -Force
        } else {
            Write-Info "skipping ${n}: it is not covered by the signed checksums."
        }
    }
    if (Test-Path -LiteralPath $shareDir) { Write-Info "licences: $shareDir" }

    # -----------------------------------------------------------------------
    # Report
    # -----------------------------------------------------------------------
    Write-Host ''
    Write-Host 'Installed'
    foreach ($bin in $BinaryNames) {
        $dest = Join-Path $InstallLocation "$bin.exe"
        $reported = 'installed'
        try {
            $out = & $dest version 2>$null
            if ($out) { $reported = ($out | Select-Object -First 1) }
        } catch {
            # A binary that will not run is still installed; `version` is a
            # courtesy, not a gate.
        }
        Write-Host ('  {0,-26} {1}' -f $bin, $reported)
    }

    # -----------------------------------------------------------------------
    # PATH — the user PATH is edited, never the machine PATH.
    # -----------------------------------------------------------------------
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    $entries = $userPath -split ';' | Where-Object { $_ -ne '' }
    $onPath = $entries | Where-Object { $_.TrimEnd('\') -ieq $InstallLocation.TrimEnd('\') }

    if ($onPath) {
        Write-Host ''
        Write-Info "$InstallLocation is already on your user PATH"
    } else {
        Write-Host ''
        Write-Host "$InstallLocation is not on your PATH."
        $answer = 'n'
        if ([Environment]::UserInteractive) {
            $answer = Read-Host 'Add it to your user PATH now? [Y/n]'
            if ([string]::IsNullOrWhiteSpace($answer)) { $answer = 'y' }
        }
        if ($answer -match '^[Yy]') {
            $updated = if ($userPath) { "$userPath;$InstallLocation" } else { $InstallLocation }
            [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
            $env:Path = "$env:Path;$InstallLocation"
            Write-Info 'added to your user PATH (open a new terminal for it to take effect)'
        } else {
            Write-Host ''
            Write-Host '  Add it yourself with:'
            Write-Host ''
            Write-Host ("    [Environment]::SetEnvironmentVariable('Path', " +
                "[Environment]::GetEnvironmentVariable('Path','User') + ';$InstallLocation', 'User')")
            Write-Host ''
            Write-Host '  or through Settings > System > About > Advanced system settings >'
            Write-Host '  Environment Variables > Path.'
        }
    }

    Write-Host ''
    Write-Host 'Run maple-harness to get started.'
    Write-Host 'Update later with:  maple-harness update'
    Write-Host ''
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
