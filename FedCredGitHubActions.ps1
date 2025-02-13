# Script prepared by Paul McCormack.  This script is intended to automate creation of a service principal, federated credentials and the required role assignment for
# deployments using GitHub Actions.  The scope of the role assignment is selected during the script run.  Ensure you have the required permissions over the
# target scope before you attempt to run the script.
#
# Although this script was designed for GitHub Actions it could very easily be repurposed for other purposes.
#
# Check if Az Powershell modules are installed and if not install them
 if ( -not (Get-Module Az.* -ListAvailable)){
     Install-Module -Name Az -Repository PSGallery -Force
     #Import-Module -Name Az
 }

# This is the subject identifier and must match the "sub" claim within the token presented to Entra by the external identity provider.
# This has no fixed format but for GitHub to trigger actions from a push or pull request to the "main" branch it would appear
# with the following format 'repo:<org-name>/<repo-name>:ref:refs/heads/main'
$CredentialSubject = 'repo:paul-mccormack/actions-entra-auth:ref:refs/heads/main'

# External Idp issuing the token.  Must match the "issuer" claim of the token being presented to Entra
# Currently set for GitHub Actions.
$CredentialIssuer = 'https://token.actions.githubusercontent.com'

# Login to Azure
Connect-AzAccount 3> $null

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
    Write-Host "Subscription name which contains Resource Group"
    $subs = Get-AzSubscription 3> $null  | Select-Object Name
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
        Set-AzContext -SubscriptionId $subScope.Id 3> $null
        Get-AzResourceGroup -Name $scopeName -ErrorAction stop
    }
    catch {
        Write-Host "Resource Group does not exist"
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
        Write-Host "You do not have the required permissions to create a role assignment at this scope. Check your access on the IAM blade in the portal"
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
        Write-Host "You do not have the required permissions to create a role assignment at this scope. Check your access on the IAM blade in the portal"
        Break
    }
}
else {
    $assignmentScope = Get-AzResourceGroup -Name $scopeName | Select-Object ResourceId
    try {
        New-AzRoleAssignment -ObjectId $appId -RoleDefinitionName $roleName -Scope $assignmentScope.ResourceId
    }
    catch {
        Write-Host "You do not have the required permissions to create a role assignment at this scope. Check your access on the IAM blade in the portal"
        Break
    }
}

# Get Application Registration Object ID
$appObjectId = Get-AzADApplication -DisplayName $spName | Select-Object Id

# Create Federated Credential for GitHub Repo
New-AzADAppFederatedCredential -ApplicationObjectId $appObjectId.Id -Audience api://AzureADTokenExchange -Issuer $CredentialIssuer -Name $spName -Subject $CredentialSubject

# Output the information needed to setup GitHub Actions Secrets. Subscription is not required if the deployment scope is Management Group.
# Make sure to set option "allow-no-subscriptions: true" in azure/login@v2 action if you are deploying to a Management Group and not creating the AZURE_SUBSCRIPTION_ID secret. 
Write-Host "Create the following in GitHub Actions Secrets"
Write-Host "AZURE_CLIENT_ID = $($sp.AppId)"
Write-Host "AZURE_TENANT_ID = $($tenantId)"

if ($scope -ne "Management Group") {
    Write-Host "AZURE_SUBSCRIPTION_ID = $($assignmentScope.Id)"
}

