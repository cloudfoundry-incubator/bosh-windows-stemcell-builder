Remove-Module -Name BOSH.Account -ErrorAction Ignore
Import-Module ./BOSH.Account.psm1

Remove-Module -Name BOSH.Utils -ErrorAction Ignore
Import-Module ../BOSH.Utils/BOSH.Utils.psm1

Describe "Account" {

    Context "when username is not provided" {
        It "throws" {
            { Add-Account } | Should Throw "Provide a user name"
        }
    }

    Context "when password is not provided" {
        It "throws" {
            { Add-Account -User hello } | Should Throw "Provide a password"
        }
    }

    Context "when the username and password are valid" {
        $user = "Provisioner"
        $password = "Password123!"

         BeforeEach {
            $userExists = !!(gwmi -class Win32_UserAccount | Where {$_.Name -eq $user})
            if($userExists) {
                Remove-Account -User $user -ErrorAction Ignore
            }
        }

        It "Adds and removes a new user account" {
            Add-Account -User $user -Password $password
            mkdir "C:\Users\$user" -ErrorAction Ignore
            $adsi = [ADSI]"WinNT://$env:COMPUTERNAME"
            $existing = $adsi.Children | where {$_.SchemaClassName -eq 'user' -and $_.Name -eq $user }
            $existing | Should Not Be $null
            Remove-Account -User $user
            $existing = $adsi.Children | where {$_.SchemaClassName -eq 'user' -and $_.Name -eq $user }
            $existing | Should Be $null
        }
    }
}

Remove-Module -Name BOSH.Account -ErrorAction Ignore
Remove-Module -Name BOSH.Utils -ErrorAction Ignore
