$domainName = "exlab1.iwitl.com"

$dsrmPassword = Read-Host -Prompt "Enter the Directory Services Restore Mode password" -AsSecureString

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName $domainName -SafeModeAdministratorPassword $dsrmPassword

# Disable ESC
$AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
Stop-Process -Name Explorer


# Install
# https://www.microsoft.com/en-us/download/details.aspx?id=47594