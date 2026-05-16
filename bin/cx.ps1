param(
    [string]$Cmd = "menu",
    [string]$Arg1,
    [string]$Arg2,
    [int]$Limit = 25,
    [switch]$DryRun,
    [Alias("D")]
    [switch]$Divide,
    [switch]$Split
)

$ErrorActionPreference = "Stop"
$Codex = Join-Path $HOME ".codex"
$Sessions = Join-Path $Codex "sessions"
$History = Join-Path $Codex "history.jsonl"
$StateFile = Join-Path $Codex "memories\cx-state.json"
$OldStateFile = Join-Path $Codex "memories\session-workbench.json"
$LastFile = Join-Path $Codex "memories\cx-last.json"
$LaunchDir = Join-Path $Codex "memories\cx-launchers"

function Short($s, $n = 90) {
    if (-not $s) { return "" }
    $s = (($s -replace "\s+", " ").Trim())
    if ($s.Length -le $n) { return $s }
    $s.Substring(0, $n - 3) + "..."
}

function Sid($path) {
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    if ($name -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$") { $Matches[1] }
}

function ToHash($x) {
    if ($null -eq $x) { return $null }
    if ($x -is [hashtable]) { return $x }
    if ($x -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $x.Keys) { $h[$k] = ToHash $x[$k] }
        return $h
    }
    if ($x -is [System.Array]) {
        return @($x | ForEach-Object { ToHash $_ })
    }
    if ($x -is [pscustomobject]) {
        $h = @{}
        foreach ($p in $x.PSObject.Properties) { $h[$p.Name] = ToHash $p.Value }
        return $h
    }
    $x
}

function JsonReady($x) {
    if ($null -eq $x) { return $null }
    if ($x -is [System.Collections.IDictionary]) {
        $o = [ordered]@{}
        foreach ($k in $x.Keys) { $o[[string]$k] = JsonReady $x[$k] }
        return [pscustomobject]$o
    }
    if ($x -is [System.Array]) {
        return @($x | ForEach-Object { JsonReady $_ })
    }
    $x
}

function State {
    if (Test-Path $StateFile) {
        $json = Get-Content $StateFile -Raw | ConvertFrom-Json
        return (ToHash $json)
    }
    if (Test-Path $OldStateFile) {
        $json = Get-Content $OldStateFile -Raw | ConvertFrom-Json
        return (ToHash $json)
    }
    return @{ active = @{}; closed = @{}; notes = @{}; opened = @{} }
}

function Save($st) {
    foreach ($key in @("active", "closed", "notes", "opened")) {
        if (-not (Has $st $key)) {
            $st[$key] = @{}
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $StateFile) | Out-Null
    $json = JsonReady $st | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($StateFile, $json, (New-Object System.Text.UTF8Encoding $false))
}

function Has($map, $key) {
    if ($null -eq $map) { return $false }
    if ($map -is [hashtable]) { return $map.ContainsKey($key) }
    if ($map.PSObject.Properties[$key]) { return $true }
    if ($map -is [pscustomobject]) { return $false }
    $map.Contains($key)
}

function MapValue($map, $key) {
    if ($null -eq $map) { return $null }
    if ($map -is [hashtable]) {
        if ($map.ContainsKey($key)) { return $map[$key] }
        return $null
    }
    if ($map.PSObject.Properties[$key]) { return $map.PSObject.Properties[$key].Value }
    return $null
}

function Hist {
    $h = @{}
    if (-not (Test-Path $History)) { return $h }
    foreach ($line in Get-Content $History) {
        try { $x = $line | ConvertFrom-Json } catch { continue }
        if (-not $x.session_id) { continue }
        $id = [string]$x.session_id
        if (-not $h.ContainsKey($id)) {
            $h[$id] = @{ first = ""; last = ""; count = 0; ts = $null }
        }
        $txt = Short $x.text 170
        if ($txt) {
            if (-not $h[$id].first) { $h[$id].first = $txt }
            $h[$id].last = $txt
            $h[$id].count++
        }
        if ($x.ts) { $h[$id].ts = [DateTimeOffset]::FromUnixTimeSeconds([int64]$x.ts).LocalDateTime }
    }
    $h
}

function Meta($file) {
    $out = @{ cwd = ""; branch = ""; model = "" }
    if ($file.Length -eq 0) { return $out }
    foreach ($line in Get-Content $file.FullName -TotalCount 30) {
        if ($line -notmatch '"session_meta"') { continue }
        try {
            $p = ($line | ConvertFrom-Json).payload
            $out.cwd = [string]$p.cwd
            $out.model = [string]$p.model
            if ($p.git) { $out.branch = [string]$p.git.branch }
        } catch {}
        break
    }
    $out
}

function Rows($search = "", $mode = $Cmd) {
    $st = State
    $hist = Hist
    $rows = foreach ($f in Get-ChildItem $Sessions -Recurse -File -Filter "rollout-*.jsonl") {
        $id = Sid $f.FullName
        if (-not $id) { continue }
        $m = Meta $f
        $hh = if ($hist.ContainsKey($id)) { $hist[$id] } else { @{ first = ""; last = ""; count = 0; ts = $null } }
        $last = if ($hh.ts -and $hh.ts -gt $f.LastWriteTime) { $hh.ts } else { $f.LastWriteTime }
        $project = if ($m.cwd) { Split-Path $m.cwd -Leaf } else { "sin-cwd" }
        $note = if (Has $st.notes $id) { [string]$st.notes[$id] } else { "" }
        $openedInfo = MapValue $st.opened $id
        $openedAtRaw = if ($openedInfo -and (MapValue $openedInfo "at")) { [string](MapValue $openedInfo "at") } else { "" }
        if ($openedAtRaw) {
            try {
                $openedAt = [DateTime]::Parse($openedAtRaw)
                if ($openedAt -gt $last) { $last = $openedAt }
            } catch {}
        }
        $activeInfo = MapValue $st.active $id
        $activeAt = if ($activeInfo -and (MapValue $activeInfo "at")) { [string](MapValue $activeInfo "at") } else { "" }
        $title = if ($note) { $note } elseif ($hh.first) { "${project}: $(Short $hh.first 70)" } else { "${project}: $($id.Substring(0,8))" }
        $status = if (Has $st.active $id) { "active" } elseif (Has $st.closed $id) { "closed" } else { "recent" }
        [pscustomobject]@{ id = $id; status = $status; last = $last; activeAt = $activeAt; project = $project; branch = $m.branch; title = $title; cwd = $m.cwd; first = $hh.first; lastPrompt = $hh.last }
    }
    if ($mode -eq "active") {
        $rows = $rows | Where-Object status -eq "active" | Sort-Object activeAt, last
    } elseif ($mode -ne "all") {
        $rows = $rows | Where-Object status -ne "closed" | Sort-Object last -Descending
    } else {
        $rows = $rows | Sort-Object last -Descending
    }
    if ($search) {
        $q = [Regex]::Escape($search)
        $rows = $rows | Where-Object { $_.title -match $q -or $_.cwd -match $q -or $_.id -match $q -or $_.lastPrompt -match $q }
    }
    @($rows | Select-Object -First $Limit)
}

function Show($rows) {
    $i = 1
    $view = foreach ($r in $rows) {
        [pscustomobject]@{ N = $i++; State = $r.status; Last = $r.last.ToString("MM-dd HH:mm"); Project = Short $r.project 20; Branch = Short $r.branch 14; Title = Short $r.title 82; Id = $r.id.Substring(0, 8) }
    }
    $view | Format-Table -AutoSize
    Write-Host "Total: $(@($rows).Count)"
    New-Item -ItemType Directory -Force -Path (Split-Path $LastFile) | Out-Null
    $lastRows = @($rows | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title } })
    $json = ConvertTo-Json -InputObject $lastRows -Depth 3
    [IO.File]::WriteAllText($LastFile, $json, (New-Object System.Text.UTF8Encoding $false))
}

function Pick($x) {
    if (-not $x) { throw "Falta numero o id." }
    if ($x -match "^\d+$" -and (Test-Path $LastFile)) {
        $parsed = ConvertFrom-Json -InputObject (Get-Content $LastFile -Raw)
        $last = if ($parsed -is [array]) { $parsed } else { @($parsed) }
        $idx = [int]$x - 1
        if ($idx -ge 0 -and $idx -lt $last.Count) { return $last[$idx].id }
        throw "No existe el numero $x en la ultima lista. Corre 'cx list' y proba de nuevo."
    }
    if ($x -match "^\d+$") {
        throw "Primero corre 'cx list' para poder usar numeros."
    }
    $x
}

function Pin($id) { $st = State; $st.active[$id] = @{ at = (Get-Date).ToString("o") }; if (Has $st.closed $id) { $st.closed.Remove($id) }; Save $st }
function Close($id) { $st = State; if (Has $st.active $id) { $st.active.Remove($id) }; $st.closed[$id] = @{ at = (Get-Date).ToString("o") }; Save $st }
function Note($id, $txt) { $st = State; $st.notes[$id] = $txt; Save $st }
function MarkOpened($ids) {
    $st = State
    $now = (Get-Date).ToString("o")
    foreach ($id in @($ids)) {
        if (-not $id) { continue }
        $st.opened[$id] = @{ at = $now }
    }
    Save $st
}

function NormPath($path) {
    if (-not $path) { return "" }
    try {
        $resolved = Resolve-Path -LiteralPath $path -ErrorAction Stop
        return ([IO.Path]::GetFullPath($resolved.Path).TrimEnd("\")).ToLowerInvariant()
    } catch {
        return ([IO.Path]::GetFullPath([string]$path).TrimEnd("\")).ToLowerInvariant()
    }
}

function PinCurrent {
    $cwd = (Get-Location).Path
    $oldLimit = $script:Limit
    $script:Limit = 500
    try {
        $current = NormPath $cwd
        $match = Rows "" "all" |
            Where-Object { (NormPath $_.cwd) -eq $current } |
            Sort-Object last -Descending |
            Select-Object -First 1
    } finally {
        $script:Limit = $oldLimit
    }

    if (-not $match) {
        throw "No encontre sesiones de Codex para esta carpeta: $cwd"
    }

    Pin $match.id
    Write-Host "Pinned: $($match.title) [$($match.id.Substring(0, 8))]"
}

function UnpinCurrent {
    $cwd = (Get-Location).Path
    $oldLimit = $script:Limit
    $script:Limit = 500
    try {
        $current = NormPath $cwd
        $match = Rows "" "active" |
            Where-Object { (NormPath $_.cwd) -eq $current } |
            Sort-Object last -Descending |
            Select-Object -First 1
    } finally {
        $script:Limit = $oldLimit
    }

    if (-not $match) {
        throw "No encontre una sesion activa para esta carpeta: $cwd"
    }

    Close $match.id
    Write-Host "Unpinned: $($match.title) [$($match.id.Substring(0, 8))]"
}

function PsQuote($s) {
    "'" + ([string]$s).Replace("'", "''") + "'"
}

function WriteLauncher($row, $dir) {
    New-Item -ItemType Directory -Force -Path $LaunchDir | Out-Null
    $stamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    $path = Join-Path $LaunchDir "$($row.id)-$PID-$stamp.ps1"
    $body = @(
        "`$ErrorActionPreference = 'Stop'"
        "Set-Location -LiteralPath $(PsQuote $dir)"
        "codex resume $($row.id)"
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText($path, $body, (New-Object System.Text.UTF8Encoding $false))
    $path
}

function RestoreSplitRows($restoreRows, $label) {
    $restoreRows = @($restoreRows)
    if ($restoreRows.Count -eq 0) {
        Write-Host "No hay sesiones para restaurar."
        return
    }

    if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
        Write-Host "El modo -Split requiere Windows Terminal (wt.exe). Uso restore normal."
        $script:Split = $false
        RestoreRows $restoreRows $label
        return
    }

    $maxPanesPerTab = if ($Divide) { 4 } else { $restoreRows.Count }
    $modeLabel = if ($Divide) { "en tabs de hasta $maxPanesPerTab panes" } else { "en panes" }
    Write-Host "Restaurando $($restoreRows.Count) sesiones $label $modeLabel..."
    if (-not $DryRun) {
        MarkOpened @($restoreRows | ForEach-Object { $_.id })
    }

    for ($offset = 0; $offset -lt $restoreRows.Count; $offset += $maxPanesPerTab) {
        $group = @($restoreRows | Select-Object -Skip $offset -First $maxPanesPerTab)
        $tabNumber = [int]([Math]::Floor($offset / $maxPanesPerTab) + 1)
        $wtArgs = @("-w", "0")
        $i = 0

        foreach ($r in $group) {
            $dir = if ($r.cwd -and (Test-Path -LiteralPath $r.cwd)) { $r.cwd } else { (Get-Location).Path }
            $cmd = "Set-Location -LiteralPath $(PsQuote $dir); codex resume $($r.id)"
            $launcher = WriteLauncher $r $dir
            Write-Host "- tab $tabNumber pane $($i + 1): $($r.title)"

            if ($i -eq 0) {
                $wtArgs += @("new-tab", "--title", "cx-restore-$tabNumber", "pwsh.exe", "-NoExit", "-ExecutionPolicy", "Bypass", "-File", $launcher)
            } else {
                $orientation = if ($i % 2 -eq 1) { "-H" } else { "-V" }
                $wtArgs += @(";", "split-pane", $orientation, "pwsh.exe", "-NoExit", "-ExecutionPolicy", "Bypass", "-File", $launcher)
            }

            if ($DryRun) {
                Write-Host "  $cmd"
            }

            $i++
        }

        if ($DryRun) {
            Write-Host "  wt $($wtArgs -join ' ')"
        } else {
            & wt.exe @wtArgs
        }
    }
}

function RestoreRows($restoreRows, $label) {
    $restoreRows = @($restoreRows)
    if ($restoreRows.Count -eq 0) {
        Write-Host "No hay sesiones para restaurar."
        return
    }

    if ($Divide) {
        $Split = $true
    }

    if ($Split) {
        RestoreSplitRows $restoreRows $label
        return
    }

    Write-Host "Restaurando $($restoreRows.Count) sesiones $label..."
    if (-not $DryRun) {
        MarkOpened @($restoreRows | ForEach-Object { $_.id })
    }
    foreach ($r in $restoreRows) {
        $dir = if ($r.cwd -and (Test-Path -LiteralPath $r.cwd)) { $r.cwd } else { (Get-Location).Path }
        $cmd = "Set-Location -LiteralPath $(PsQuote $dir); codex resume $($r.id)"
        $launcher = WriteLauncher $r $dir
        Write-Host "- $($r.title)"

        if ($DryRun) {
            if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
                Write-Host "  wt -w 0 new-tab --title $($r.project) pwsh -NoExit -ExecutionPolicy Bypass -File $launcher"
            } else {
                Write-Host "  pwsh -NoExit -ExecutionPolicy Bypass -File $launcher"
            }
            Write-Host "  $cmd"
            continue
        }

        if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
            & wt.exe -w 0 new-tab --title (Short $r.project 24) pwsh.exe -NoExit -ExecutionPolicy Bypass -File $launcher
        } elseif (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
            Start-Process -FilePath pwsh.exe -WorkingDirectory $dir -ArgumentList @(
                "-NoExit",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                $launcher
            ) | Out-Null
        } else {
            Start-Process -FilePath powershell.exe -WorkingDirectory $dir -ArgumentList @(
                "-NoExit",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                $launcher
            ) | Out-Null
        }
    }
}

function RestoreActive($count = $null) {
    if ($count -and $count -match "^\d+$") {
        $oldLimit = $script:Limit
        $script:Limit = [int]$count
        try {
            RestoreRows (Rows "" "recent") "recientes globales"
        } finally {
            $script:Limit = $oldLimit
        }
        return
    }

    RestoreRows (Rows "" "active") "pineadas"
}

switch ($Cmd) {
    "menu" {
        while ($true) {
            Clear-Host
            Write-Host "cx: enter=n resume | r restore | p pin | u unpin | c n close | n n titulo | s texto search | a active | q quit" -ForegroundColor Cyan
            $rows = Rows
            Show $rows
            $x = Read-Host "cx"
            if ($x -eq "q") { break }
            if ($x -eq "a") { Show (Rows "" "active"); Read-Host "enter"; continue }
            if ($x -eq "r") { RestoreActive; break }
            if ($x -match "^s\s+(.+)$") { Show (Rows $Matches[1]); Read-Host "enter"; continue }
            if ($x -eq "p") { PinCurrent; Read-Host "enter"; continue }
            if ($x -eq "u") { UnpinCurrent; Read-Host "enter"; continue }
            if ($x -match "^p\s+(\S+)$") { Pin (Pick $Matches[1]); continue }
            if ($x -match "^u\s+(\S+)$") { Close (Pick $Matches[1]); continue }
            if ($x -match "^c\s+(\S+)$") { Close (Pick $Matches[1]); continue }
            if ($x -match "^n\s+(\S+)\s+(.+)$") { Note (Pick $Matches[1]) $Matches[2]; continue }
            if ($x) { $id = Pick $x; Pin $id; MarkOpened $id; codex resume $id; break }
        }
    }
    "list" { Show (Rows $Arg1) }
    "active" { Show (Rows $Arg1 "active") }
    "all" { Show (Rows $Arg1 "all") }
    "pin" { if ($Arg1) { Pin (Pick $Arg1) } else { PinCurrent } }
    "unpin" { if ($Arg1) { Close (Pick $Arg1) } else { UnpinCurrent } }
    "close" { Close (Pick $Arg1) }
    "note" { Note (Pick $Arg1) $Arg2 }
    "resume" { $id = Pick $Arg1; Pin $id; MarkOpened $id; codex resume $id }
    "restore" { RestoreActive $Arg1 }
    default { Show (Rows $Cmd) }
}
