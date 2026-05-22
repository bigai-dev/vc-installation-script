function Compare-Version {
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )
    $normalize = {
        param($v)
        ($v -replace '^v','').Split('.') | ForEach-Object { [int]$_ }
    }
    $l = & $normalize $Left
    $r = & $normalize $Right
    $max = [Math]::Max($l.Count, $r.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $lv = if ($i -lt $l.Count) { $l[$i] } else { 0 }
        $rv = if ($i -lt $r.Count) { $r[$i] } else { 0 }
        if ($lv -gt $rv) { return 1 }
        if ($lv -lt $rv) { return -1 }
    }
    return 0
}

Export-ModuleMember -Function Compare-Version
