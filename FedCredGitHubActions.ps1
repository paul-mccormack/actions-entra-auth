# Script created by Paul McCormack.  This script is intended to automate creation of a service principal, federated credentials and the required role assignment for
# deployments using GitHub Actions.  The scope of the role assignment is selected during the script run.  Ensure you have the required permissions over the
# target scope before you attempt to run the script.
#
# Although this script was designed for GitHub Actions it could very easily be repurposed for other issuers that support Federated Credentials.
#
# Check if required Az Powershell modules are installed and if not install them
# Define all required modules
$modules = 'Az.Accounts', 'Az.Resources'

# Find the that are already installed.
$installed = @((Get-Module $modules -ListAvailable).Name | Select-Object -Unique)

# Find the modules which ones aren't installed.
$notInstalled = Compare-Object $modules $installed -PassThru

if ($notInstalled) {
    Install-Module -Scope CurrentUser $notInstalled
}

Write-Host "This script is intended to automate creation of a service principal, federated credentials and the required role assignment for deployments using GitHub Actions." -ForegroundColor Green
Write-Host "The scope of the role assignment is selected during the script run." -ForegroundColor Green
Write-Host "Ensure you have the required permissions over the target scope before you attempt to run the script." -ForegroundColor Green
Write-Host "You will be prompted to enter the GitHub organization/user name, repository name, and branch name." -ForegroundColor Green

# This is the subject identifier and must match the "sub" claim within the token presented to Entra by the external identity provider.
# This has no fixed format but for GitHub to trigger actions from a push or pull request to the "main" branch it would appear
# with the following format 'repo:<org-name>/<repo-name>:ref:refs/heads/main'
# Validate GitHub organization/user name (alphanumeric, hyphens, max 39 chars, cannot start/end with hyphen, no consecutive hyphens)
do {
    $orgName = Read-Host "Enter GitHub organization or user name (e.g., 'paul-mccormack')"
    if ($orgName -match '^(?!-)(?!.*--)[a-zA-Z0-9-]{1,39}(?<!-)$') {
        $validOrg = $true
    } else {
        Write-Host "Invalid organization/user name. Only alphanumeric characters and single hyphens are allowed, max 39 chars, cannot start/end with hyphen, no consecutive hyphens." -ForegroundColor Red
        $validOrg = $false
    }
} until ($validOrg)

# Validate GitHub repository name (alphanumeric, hyphens, underscores, dots, max 100 chars, cannot start/end with dot, hyphen, or underscore)
do {
    $repoName = Read-Host "Enter GitHub repository name (e.g., 'MyAwesomeRepo')"
    if ($repoName -match '^(?![._-])[a-zA-Z0-9._-]{1,100}(?<![._-])$') {
        $validRepo = $true
    } else {
        Write-Host "Invalid repository name. Only alphanumeric characters, hyphens, underscores, and dots are allowed, max 100 chars, cannot start/end with dot, hyphen, or underscore." -ForegroundColor Red
        $validRepo = $false
    }
} until ($validRepo)

# Validate branch name (GitHub allows most characters, but let's restrict to common safe pattern)
do {
    $branchName = Read-Host "Enter branch name (e.g., 'main')"
    if ($branchName -match '^[A-Za-z0-9._/-]{1,255}$' -and $branchName -notmatch '(^/|/$|//)') {
        $validBranch = $true
    } else {
        Write-Host "Invalid branch name. Only alphanumeric characters, dots, underscores, hyphens, and slashes are allowed, max 255 chars, cannot start/end with slash or contain double slashes." -ForegroundColor Red
        $validBranch = $false
    }
} until ($validBranch)

$refrefsheads = ":ref:refs/heads" # PowerShell was being a bit weird with the variable when included in the string directly.

$CredentialSubject = "repo:$orgName/$repoName$refrefsheads/$branchName"

Write-Host "Federated Credential Subject set to: $CredentialSubject" -ForegroundColor Green

# Prompt user to continue or abort
do {
    $continue = Read-Host "check the federated credential subject above looks correct? 'repo:<org or username>/<repo name>:ref:refs/heads/<branch name>' you want to continue? (Y/N)"
    $continue = $continue.ToUpper()
    if ($continue -eq 'N') {
        Write-Host "Script aborted by user." -ForegroundColor Yellow
        exit
    }
    elseif ($continue -ne 'Y') {
        Write-Host "Invalid input. Please enter Y or N." -ForegroundColor Red
    }
} until ($continue -eq 'Y')

Write-Host "Continuing with script execution..." -ForegroundColor Green

# External Idp issuing the token.  Must match the "issuer" claim of the token being presented to Entra
# Currently set for GitHub Actions.
$CredentialIssuer = 'https://token.actions.githubusercontent.com'

# Check if already logged into Azure, if not, login
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "Not logged into Azure. Please login..." -ForegroundColor Yellow
    Connect-AzAccount 3> $null
} else {
    Write-Host "Already logged into Azure as $($context.Account.Id)" -ForegroundColor Green
}

#Prompt for Deployment Scope
function Get-Scope {
    $type=Read-Host "
    Choose deployment scope
    1 - Management Group
    2 - Subscription
    3 - Resource Group
    Enter number"
    switch ($type) {
        1 {$choice="Management Group"}
        2 {$choice="Subscription"}
        3 {$choice="Resource Group"}
    }
    return $choice
}
$scope=Get-Scope

# Get Tenant ID
$tenantId = (Get-AzContext).Tenant.Id

# Prompt for Deployment Scope Name for Role Assignment
if ($scope -contains "Management Group") {
    $mg = Get-AzManagementGroup | Select-Object Name
    for ($i = 0; $i -lt $mg.Count; $i++)
    {
        $j = $i + 1
        "{0}: {1}" -f $j, $mg.Name[$i] 
    }
    $selection = (Read-Host -Prompt "Enter Management Group number").Split(',').Trim()
    foreach ($selected in $selection)
    {
        $scopeName = $mg[$selected - 1]
    }
}
elseif ($scope -contains "Subscription") {
    $subs = Get-AzSubscription 3> $null | Select-Object Name
    for ($i = 0; $i -lt $subs.Count; $i++)
    {
        $j = $i + 1
        "{0}: {1}" -f $j, $subs.Name[$i] 
    }
    $selection = (Read-Host -Prompt "Enter Subscription Number").Split(',').Trim()
    foreach ($selected in $selection)
    {
        $scopeName = $subs[$selected - 1]
    }
}
else {
    Write-Host "Subscription name which contains Resource Group" -ForegroundColor Green
    $subs = Get-AzSubscription 3> $null | Select-Object Name        ## make this command not display output in terminal.  Replace 3> $null with | Out-Null.
    for ($i = 0; $i -lt $subs.Count; $i++)
    {
        $j = $i + 1
        "{0}: {1}" -f $j, $subs.Name[$i] 
    }
    $selection = (Read-Host -Prompt "Enter Subscription Number").Split(',').Trim()
    foreach ($selected in $selection)
    {
        $subName = $subs[$selected - 1]
    }
    $scopeName = Read-Host "Enter Resource Group Name"
    try {
        $subScope = Get-AzSubscription -SubscriptionName $subName.Name  3> $null | Select-Object Id
        Set-AzContext -SubscriptionId $subScope.Id 3> $null | Out-Null
        Get-AzResourceGroup -Name $scopeName -ErrorAction stop | Out-Null
        Write-Host "Resource Group exists" -ForegroundColor Green
    }
    catch {
        Write-Host "Resource Group does not exist" -ForegroundColor Red
        Break
    }
}

# Prompt for Service Principal Name
$spName = Read-Host "Enter Service Principal Name"

# Role Name for Role Assignment
$roleName = Read-Host "Enter Role Name.  e.g Owner, Contributor"

# Create Service Principal
$sp = New-AzADServicePrincipal -DisplayName $spName

# Get Service Principal Application ID
$appId = $sp.Id

# Get Deployment Scope ID and create Role Assignment

if ($scope -contains "Management Group") {
    $assignmentScope = Get-AzManagementGroup -GroupName $scopeName.Name | Select-Object Id
    try {
        New-AzRoleAssignment -ObjectId $appId -RoleDefinitionName $roleName -Scope $assignmentScope.Id
    }
    catch {
        Write-Host "You do not have the required permissions to create a role assignment at this scope. Check your access on the IAM blade in the portal" -ForegroundColor Red
        Write-Host "Script will now exit." -ForegroundColor Red
        Break
    }
}
elseif ($scope -contains "Subscription") {
    $assignmentScope = Get-AzSubscription -SubscriptionName $scopeName.Name  3> $null | Select-Object Id
    $subScope = "/subscriptions/" + $assignmentScope.id
    try {
        New-AzRoleAssignment -ObjectId $appId -RoleDefinitionName $roleName -Scope $subScope
    }
    catch {
        Write-Host "You do not have the required permissions to create a role assignment at this scope. Check your access on the IAM blade in the portal" -ForegroundColor Red
        Write-Host "Script will now exit." -ForegroundColor Red
        Break
    }
}
else {
    $assignmentScope = (Get-AzContext).Subscription | Select-Object Id
    $rgScope = Get-AzResourceGroup -Name $scopeName | Select-Object ResourceId
    try {
        New-AzRoleAssignment -ObjectId $appId -RoleDefinitionName $roleName -Scope $rgScope.ResourceId
    }
    catch {
        Write-Host "You do not have the required permissions to create a role assignment at this scope. Check your access on the IAM blade in the portal" -ForegroundColor Red
        Write-Host "Script will now exit." -ForegroundColor Red
        Break
    }
}

# Get Application Registration Object ID
$appObjectId = Get-AzADApplication -DisplayName $spName | Select-Object Id

# Create Federated Credential for GitHub Repo
New-AzADAppFederatedCredential -ApplicationObjectId $appObjectId.Id -Audience api://AzureADTokenExchange -Issuer $CredentialIssuer -Name $spName -Subject $CredentialSubject

# Output the information needed to setup GitHub Actions Secrets. Subscription is not required if the deployment scope is Management Group.

Write-Host "Create the following in GitHub Actions Secrets and variables." -ForegroundColor Green
Write-Host "If your deployment scope is a Management Group you do not need to create the AZURE_SUBSCRIPTION_ID secret and it will not be shown below." -ForegroundColor Green
Write-Host "Make sure to set option 'allow-no-subscriptions: true' in azure/login@v2 action if you are deploying to a Management Group and not creating the AZURE_SUBSCRIPTION_ID secret." -ForegroundColor Green
Write-Host "-----------------------------------------------" -ForegroundColor Green
Write-Host "AZURE_CLIENT_ID = $($sp.AppId)" -ForegroundColor Green
Write-Host "AZURE_TENANT_ID = $($tenantId)" -ForegroundColor Green

if ($scope -ne "Management Group") {
    Write-Host "AZURE_SUBSCRIPTION_ID = $($assignmentScope.Id)" -ForegroundColor Green
}
Write-Host "-----------------------------------------------" -ForegroundColor Green
Write-Host "Script execution completed." -ForegroundColor Green
