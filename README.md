# Create an Entra ID service principal with federated credentials and a role assignment for use with GitHub Actions

This PowerShell script was written to create an Entra service principal with a federated credential and role assignment at a scope selected during execution, for use with GitHub Actions performing deployments to Azure.

Although intended to use with GitHub Actions it could be re-purposed to set-up OIDC connections between Entra and other providers.

Click the [link](https://github.com/paul-mccormack/actions-entra-auth/blob/main/FedCredGitHubActions.ps1) to view the script.

> [!NOTE]
> Full details are in a post on [howdoyou.cloud](https://howdoyou.cloud/posts/create-an-oidc-enabled-identity-for-github-actions/)