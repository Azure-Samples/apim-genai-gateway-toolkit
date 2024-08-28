// Deploys the base resources that are needed for running the simulator
// This contains common resources across multiple instances of the simulator
// The container registry is used to store the simulator container image
// The key vault is used to store secrets and keys (e.g. for forwarding AOAI calls)
// The storage account is used to store the simulator data (recording files or extensions)

@description('Specifies the supported Azure location (region) where the resources will be deployed')
param location string = resourceGroup().location

@description('Suffix to apply to created resources')
param resourceSuffix string

@description('Principal ID of the additional user to assign the Key Vault Secrets Reader role to')
@secure()
param additionalKeyVaulSecretReaderPrincipalId string = ''

@description('The name of the Log Analytics workspace')
param logAnalyticsName string

@description('The name of the Application Insights instance')
param appInsightsName string


var containerRegistryName = replace('${resourceSuffix}', '-', '')
var keyVaultName = replace('${resourceSuffix}', '-', '')
var containerAppEnvName = resourceSuffix


resource containerRegistry 'Microsoft.ContainerRegistry/registries@2021-12-01-preview' = {
  name: containerRegistryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    accessPolicies: []
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    tenantId: subscription().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource keyVaultSecretsUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6' // https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide?tabs=azure-cli
}

resource additionalSecretReader 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' =
  if (additionalKeyVaulSecretReaderPrincipalId != '') {
    name: guid(resourceGroup().id, vault.name, additionalKeyVaulSecretReaderPrincipalId, 'assignSecretsReaderRole')
    scope: vault
    properties: {
      description: 'Assign Key Vault Secrets Reader role to ACA identity'
      principalId: additionalKeyVaulSecretReaderPrincipalId
      principalType: 'User'
      roleDefinitionId: keyVaultSecretsUserRoleDefinition.id
    }
  }



resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    CustomMetricsOptedInType: 'WithDimensions'
  }
}


resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-11-02-preview' = {
  name: containerAppEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerRegistryName string = containerRegistry.name
output keyVaultName string = vault.name
output containerAppEnvName string = containerAppEnv.name
output appInsightsName string = appInsights.name
output logAnalyticsName string = logAnalytics.name
