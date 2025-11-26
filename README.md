# Create an Entra ID service principal with federated credentials and a role assignment for use with GitHub Actions

This PowerShell script was written to create an Entra service principal with a federated credential and role assignment at a scope selected during execution, for use with GitHub Actions performing deployments to Azure.

Although intended to use with GitHub Actions it could be re-purposed to set-up OIDC connections between Entra and other providers.

Click the [link](https://github.com/paul-mccormack/actions-entra-auth/blob/main/FedCredGitHubActions.ps1) to view the script.

## Basic operation

You will be prompted to enter the required information to build the federated credential subject.

Ensure you have the appropriate permissions at the deployment scope you are deploying too. So if you need to PIM to get that do it before running the script. The script will exit if the operator does not have the permissions to create a role assignment at the desired scope. This is to prevent creating a service principal and federated credential without the role assignment.

During execution you will be prompted to login to Azure in PowerShell, if not already logged in. You then choose the scope for the role assignment, options are Management Group, Subscription and Resource Group.

If Resource Group is selected you will be prompted to select the subscription then enter the resource group name. Error handling is in place to catch typo's when entering the resource group name.  

You will be prompted to choose the role for the role assignment from the following list of roles: ```PipelineAccess```, ```Owner``` and ```Contributor```.

Owner and Contributor should be used with caution, especially in Production.  The PipelineAccess role is a custom role following the Microsoft recomendation in the Azure DevOps documentation.  See [link](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure?tabs=azure-portal%2Cazure-cli%2Cgithub-actions#create-a-service-principal-with-federated-credentials) for details of the role permissions.  This role allows the creation of resources but denys ```"Microsoft.Authorization/*/Delete"``` actions.  This includes the removal of management locks, deny assignments, policy assignments, role assignments and other highly privileged actions.  The json file to create this role is included in this repository, named [CustomRole.json](https://github.com/paul-mccormack/actions-entra-auth/blob/main/CustomRole.json).

The values needed for ```AZURE_CLIENT_ID```, ```AZURE_TENANT_ID``` and ```AZURE_SUBSCRIPTION_ID``` are displayed after a successful run to be copied into your repository Actions Secrets section.  ```AZURE_SUBSCRIPTION_ID``` won't be output if the scope is a Management Group. Requiring the use of ```allow-no-subscriptions: true``` in the Azure Login action