# ============================================================
# Active Directory Bulk Setup Script
# Domain  : nikeglobal.online
# CSV     : C:\user.csv
# ============================================================

Import-Module ActiveDirectory

$csvPath   = "C:\user.csv"
$domain    = "DC=nikeglobal,DC=online"
$parentOU  = "OU=Employees,$domain"
$password  = ConvertTo-SecureString "Apple123" -AsPlainText -Force

# ------------------------------------------------------------
# STEP 1 — Import CSV
# ------------------------------------------------------------
$users = Import-Csv -Path $csvPath
Write-Host "`n[INFO] Loaded $($users.Count) users from CSV" -ForegroundColor Cyan

# ------------------------------------------------------------
# STEP 2 — Create Parent OU: Employees
# ------------------------------------------------------------
try {
    Get-ADOrganizationalUnit -Identity $parentOU -ErrorAction Stop | Out-Null
    Write-Host "[SKIP] OU 'Employees' already exists" -ForegroundColor Yellow
} catch {
    New-ADOrganizationalUnit -Name "Employees" -Path $domain
    Write-Host "[CREATED] OU: Employees" -ForegroundColor Green
}

# ------------------------------------------------------------
# STEP 3 — Create Department OUs and Security Groups
# ------------------------------------------------------------
$departments = $users | Select-Object -ExpandProperty Department -Unique

foreach ($dept in $departments) {
    $deptOU = "OU=$dept,$parentOU"

    # Create Department OU
    try {
        Get-ADOrganizationalUnit -Identity $deptOU -ErrorAction Stop | Out-Null
        Write-Host "[SKIP] OU '$dept' already exists" -ForegroundColor Yellow
    } catch {
        New-ADOrganizationalUnit -Name $dept -Path $parentOU
        Write-Host "[CREATED] OU: $dept" -ForegroundColor Green
    }

    # Create Security Group inside Department OU
    try {
        Get-ADGroup -Identity $dept -ErrorAction Stop | Out-Null
        Write-Host "[SKIP] Group '$dept' already exists" -ForegroundColor Yellow
    } catch {
        New-ADGroup -Name $dept `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Path $deptOU
        Write-Host "[CREATED] Security Group: $dept" -ForegroundColor Green
    }
}

# ------------------------------------------------------------
# STEP 4 — Create Users and Add to Security Groups
# ------------------------------------------------------------

# Track used SamAccountNames for duplicate handling
$usedSAMs = @{}

foreach ($user in $users) {

    $firstName   = $user.FirstName.Trim()
    $lastName    = $user.LastName.Trim()
    $fullName    = $user.FullName.Trim()
    $dept        = $user.Department.Trim()
    $deptOU      = "OU=$dept,$parentOU"
    $baseSAM     = "$($firstName.ToLower()).$($lastName.ToLower())"

    # Handle duplicate SamAccountNames
    if ($usedSAMs.ContainsKey($baseSAM)) {
        $usedSAMs[$baseSAM]++
        $sam = "$baseSAM$($usedSAMs[$baseSAM])"
    } else {
        $usedSAMs[$baseSAM] = 1
        $sam = $baseSAM
    }

    $upn = "$sam@nikeglobal.online"

    # Create User
    try {
        Get-ADUser -Identity $sam -ErrorAction Stop | Out-Null
        Write-Host "[SKIP] User '$sam' already exists" -ForegroundColor Yellow
    } catch {
        try {
            New-ADUser `
                -GivenName        $firstName `
                -Surname          $lastName `
                -Name             $fullName `
                -DisplayName      $fullName `
                -SamAccountName   $sam `
                -UserPrincipalName $upn `
                -Path             $deptOU `
                -AccountPassword  $password `
                -PasswordNeverExpires $true `
                -Enabled          $true

            Write-Host "[CREATED] User: $fullName ($sam)" -ForegroundColor Green

            # Add user to their department Security Group
            Add-ADGroupMember -Identity $dept -Members $sam
            Write-Host "[ADDED]   $sam --> Group: $dept" -ForegroundColor Cyan

        } catch {
            Write-Host "[ERROR] Failed to create user '$sam': $_" -ForegroundColor Red
        }
    }
}

Write-Host "`n[DONE] Script completed successfully.`n" -ForegroundColor Cyan
