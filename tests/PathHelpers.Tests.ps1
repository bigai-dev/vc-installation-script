BeforeAll {
    Import-Module "$PSScriptRoot/Helpers.psm1" -Force
}

Describe "Get-CleanedPath" {
    It "removes empty entries" {
        $result = Get-CleanedPath @("C:\foo", "", "C:\bar", $null)
        $result.Entries | Should -Be @("C:\foo", "C:\bar")
    }
    It "deduplicates case-insensitively" {
        $result = Get-CleanedPath @("C:\foo", "c:\FOO", "C:\bar")
        $result.Entries | Should -Be @("C:\foo", "C:\bar")
        $result.DuplicatesRemoved | Should -Be 1
    }
    It "preserves env-var entries even if path does not currently exist" {
        $result = Get-CleanedPath @("%JAVA_HOME%\bin", "C:\nonexistent-zzz")
        $result.Entries | Should -Contain "%JAVA_HOME%\bin"
    }
    It "removes entries pointing to nonexistent disk paths" {
        $result = Get-CleanedPath @("C:\foo", "C:\does-not-exist-xyz-zzz")
        # Only C:\foo if it exists, otherwise empty — we assert by checking BrokenRemoved
        $result.BrokenRemoved | Should -BeGreaterOrEqual 1
    }
}
