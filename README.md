# Create an Entra ID service principal with federated credentials and a role assignment for use with GitHub Actions

This PowerShell script was written to create an Entra service principal, role assignment at a scope selected during execution and a federated credential for use with GitHub Actions and deployments to Azure.

Although intended to use with GitHub Actions it could be re-purposed to set-up OIDC connections between Entra and other providers.

Click the [link](https://github.com/paul-mccormack/actions-entra-auth/blob/main/FedCredGitHubActions.ps1) to view the script.

## Basic operation

Set the ```$CredentialSubject``` variable prior to running and ensure you have the appropiate permissions at the deployment scope you are going to choose.  So if you need to PIM to get that do it before running the script.

During execution you will choose the scope for the role assignment, options are Management Group, Subscription and Resource Group.

Error handling is in place to exit the script if the free hand entered Resource Group option is not correct,this is to stop the script being able to  create the service principal but fail on the role assignment.  It will also exit if the operator does not have the permissions to create a role assignment at the desired scope.

The values needed for ```AZURE_CLIENT_ID```, ```AZURE_TENANT_ID``` and ```AZURE_SUBSCRIPTION_ID``` are displayed after a successful run to be copied into your repository Actions Secrets section.  ```AZURE_SUBSCRIPTION_ID``` won't be output if the scope is a Management Group. Requiring the use of ```allow-no-subscriptions: true``` in the Azure Login action