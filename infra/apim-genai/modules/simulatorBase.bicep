// Deploys the base resources that are needed for running the simulator
// This contains common resources across multiple instances of the simulator
// The container registry is used to store the simulator container image
// The key vault is used to store secrets and keys (e.g. for forwarding AOAI calls)
// The storage account is used to store the simulator data (recording files or extensions)

@description('Specifies the supported Azure location (region) where the resources will be deployed')
param location string = resourceGroup().location

@description('Suffix to apply to created resources')
param resourceSuffix string


var containerRegistryName = replace('aoaisim-${resourceSuffix}', '-', '')
var keyVaultName = replace('aoaisim-${resourceSuffix}', '-', '')
var storageAccountName = replace('aoaisim${resourceSuffix}', '-', '')
var containerAppEnvName = 'aoaisim-${resourceSuffix}'
var logAnalyticsName = 'aoaisim-${resourceSuffix}'
var appInsightsName = 'aoaisim-${resourceSuffix}'


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
    accessPolicies:[]
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

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'

}
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent:storageAccount
  name: 'default'

}
resource simulatorFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: 'simulator'
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
resource containerAppStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  parent: containerAppEnv
  name: 'simulator-storage'
  properties: {
    azureFile: {
      shareName: simulatorFileShare.name
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      accessMode: 'ReadWrite'
    }
  }
}

output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerRegistryName string = containerRegistry.name
output storageAccountName string = storageAccount.name
output fileShareName string = simulatorFileShare.name
output keyVaultName string = vault.name
output logAnalyticsName string = logAnalytics.name
output appInsightsName string = appInsights.name
output containerAppEnvName string = containerAppEnv.name
