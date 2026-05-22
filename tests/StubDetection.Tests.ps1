BeforeAll {
    Import-Module "$PSScriptRoot/Helpers.psm1" -Force
}

Describe "Is-WindowsAppsStub" {
    It "detects the MS Store python stub path" {
        Is-WindowsAppsStub "C:\Users\test\AppData\Local\Microsoft\WindowsApps\python.exe" | Should -BeTrue
    }
    It "detects the stub regardless of executable name" {
        Is-WindowsAppsStub "C:\Users\test\AppData\Local\Microsoft\WindowsApps\python3.exe" | Should -BeTrue
    }
    It "returns false for a real Python install" {
        Is-WindowsAppsStub "C:\Users\test\AppData\Local\Programs\Python\Python314\python.exe" | Should -BeFalse
    }
    It "returns false for null or empty input" {
        Is-WindowsAppsStub $null  | Should -BeFalse
        Is-WindowsAppsStub ""     | Should -BeFalse
    }
}
