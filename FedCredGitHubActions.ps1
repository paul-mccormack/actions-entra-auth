# Script created by Paul McCormack.  This script is intended to automate creation of a service principal, federated credentials and the required role assignment for
# deployments using GitHub Actions.  The scope of the role assignment is selected during the script run.  Ensure you have the required permissions over the
# target scope before you attempt to run the script.
#
# Although this script was designed for GitHub Actions it could very easily be repurposed for other issuers that support Federated Credentials.
#
# Check if required Az Powershell modules are installed and if not install them.
# Define all required modules.
$modules = 'Az.Accounts', 'Az.Resources'

# Find the that are already installed.
$installed = @((Get-Module $modules -ListAvailable).Name | Select-Object -Unique)

# Find the modules which ones aren't installed.
$notInstalled = Compare-Object $modules $installed -PassThru

if ($notInstalled) {
    Install-Module -Scope CurrentUser $notInstalled
}
Write-Host "`r"
Write-Host "This script is intended to automate creation of a service principal, federated credentials and the required role assignment for deployments using GitHub Actions." -ForegroundColor Green
Write-Host "The scope of the role assignment is selected during the script run." -ForegroundColor Green
Write-Host "Ensure you have the required permissions over the target scope before you attempt to run the script." -ForegroundColor Green
Write-Host "You will be prompted to enter the GitHub organization/user name, repository name, and branch name." -ForegroundColor Green
Write-Host "`r"

# This is the subject identifier and must match the "sub" claim within the token presented to Entra by the external identity provider.
# This has no fixed format but for GitHub to trigger actions from a push or pull request to the "main" branch it would appear
# with the following format 'repo:<org-name>/<repo-name>:ref:refs/heads/main'
# Validate GitHub organization/user name (alphanumeric, hyphens, max 39 chars, cannot start/end with hyphen, no consecutive hyphens)
do {
    $orgName = Read-Host "Enter GitHub organization or user name (e.g., 'paul-mccormack')"
    if ($orgName -match '^(?!-)(?!.*--)[a-zA-Z0-9-]{1,39}(?<!-)$') {
        $validOrg = $true
    } else {
        Write-Host "Invalid organization/user name. Only alphanumeric characters and single hyphens are allowed, max 39 chars, cannot start/end with hyphen." -ForegroundColor Red
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

$refrefsheads = ":ref:refs/heads" # PowerShell was being a bit weird with :ref:refs/heads when included directly in the string.

$CredentialSubject = "repo:$orgName/$repoName$refrefsheads/$branchName"

Write-Host "`r"
Write-Host "Federated Credential Subject set to: $CredentialSubject" -ForegroundColor Green
Write-Host "`r"

# Prompt user to check the credential subject and continue or abort
do {
    $continue = Read-Host "check the federated credential subject above looks correct? Format should be: 'repo:<org or username>/<repo name>:ref:refs/heads/<branch name>'. Do you want to continue? (Y/N)"
    $continue = $continue.ToUpper()
    if ($continue -eq 'N') {
        Write-Host "Script aborted by user." -ForegroundColor Yellow
        exit
    }
    elseif ($continue -ne 'Y') {
        Write-Host "Invalid input. Please enter Y or N." -ForegroundColor Red
    }
} until ($continue -eq 'Y')

Write-Host "`r"
Write-Host "Continuing with script execution..." -ForegroundColor Green
Write-Host "`r"

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
    $scopeType = Read-Host "
    Choose deployment scope
    1 - Management Group
    2 - Subscription
    3 - Resource Group
    Enter number"
    switch ($scopeType) {
        1 {$scopeChoice = "Management Group"}
        2 {$scopeChoice = "Subscription"}
        3 {$scopeChoice = "Resource Group"}
    }
    return $scopeChoice
}
$scope = Get-Scope

Write-Host "`r"

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
    $subs = Get-AzSubscription 3> $null | Select-Object Name
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
    $subScope = Get-AzSubscription -SubscriptionName $subName.Name  3> $null | Select-Object Id
    Set-AzContext -SubscriptionId $subScope.Id 3> $null | Out-Null
    
    do {
        $rgExists = Get-AzResourceGroup -Name $scopeName -ErrorAction SilentlyContinue
        if ($rgExists) {
            Write-Host "`r"
            Write-Host "Resource Group '$scopeName' exists" -ForegroundColor Green
            $validRg = $true
        } else {
            Write-Host "`r"
            Write-Host "Resource Group '$scopeName' does not exist in subscription '$($subName.Name)'" -ForegroundColor Red
            $scopeName = Read-Host "Enter Resource Group Name"
            $validRg = $false
        }
    } until ($validRg)
}

Write-Host "`r"

# Prompt for Service Principal Name
$spName = Read-Host "Enter Service Principal Name"

Write-Host "`r"

# Prompt for Role Name for Role Assignment.
function Get-Role {
    $RoleType = Read-Host "
    Choose Role Assignment
    1 - PipelineAccess
    2 - Owner
    3 - Contributor
    Enter number"
    switch ($RoleType) {
        1 {$RoleChoice = "PipelineAccess"}
        2 {$RoleChoice = "Owner"}
        3 {$RoleChoice = "Contributor"}
    }
    return $RoleChoice
}
$roleName = Get-Role

Write-Host "`r"

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
Write-Host "`r"
Write-Host "-----------------------------------------------" -ForegroundColor Green
Write-Host "AZURE_CLIENT_ID = $($sp.AppId)" -ForegroundColor Green
Write-Host "AZURE_TENANT_ID = $($tenantId)" -ForegroundColor Green

if ($scope -ne "Management Group") {
    Write-Host "AZURE_SUBSCRIPTION_ID = $($assignmentScope.Id)" -ForegroundColor Green
}
Write-Host "-----------------------------------------------" -ForegroundColor Green
Write-Host "`r"
Write-Host "Script execution completed." -ForegroundColor Green
