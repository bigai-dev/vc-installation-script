BeforeAll {
    Import-Module "$PSScriptRoot/Helpers.psm1" -Force
}

Describe "Compare-Version" {
    It "returns 0 for equal versions" {
        Compare-Version "3.14.0" "3.14.0" | Should -Be 0
    }
    It "returns 1 when left is newer (patch)" {
        Compare-Version "3.14.1" "3.14.0" | Should -Be 1
    }
    It "returns -1 when left is older (minor)" {
        Compare-Version "3.13.5" "3.14.0" | Should -Be -1
    }
    It "handles 'v' prefix on Node-style versions" {
        Compare-Version "v24.0.0" "v18.0.0" | Should -Be 1
    }
    It "treats missing patch as 0" {
        Compare-Version "3.14" "3.14.0" | Should -Be 0
    }
    It "returns 1 when left has more components and they're nonzero" {
        Compare-Version "3.14.0.1" "3.14.0" | Should -Be 1
    }
}
