targetScope = 'subscription'

@description('The name of the resource group to deploy into')
param resourceGroupName string

@description('A short name for the workload being deployed alphanumberic only')
@maxLength(8)
param workloadName string

@description('The environment for which the deployment is being executed')
@allowed([
  'dev'
  'uat'
  'prod'
  'dr'
])
param environment string

@description('Specifies the supported Azure location (region) where the resources will be deployed')
param location string

@description('Principal ID of the additional user to assign the Key Vault Secrets Reader role to')
@secure()
param additionalKeyVaulSecretReaderPrincipalId string = '' // used to enable the current user to retrieve the app insights connection string

var resourceSuffix = '${workloadName}-${environment}-${location}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: resourceGroupName
}

module simulatorBase 'modules/simulatorBase.bicep' = {
  name: 'simulatorBase'
  scope: resourceGroup
  params: {
    location: location
    resourceSuffix: resourceSuffix
    additionalKeyVaulSecretReaderPrincipalId: additionalKeyVaulSecretReaderPrincipalId
  }
}

output containerRegistryLoginServer string = simulatorBase.outputs.containerRegistryLoginServer
output containerRegistryName string = simulatorBase.outputs.containerRegistryName

output storageAccountName string = simulatorBase.outputs.storageAccountName
output fileShareName string = simulatorBase.outputs.fileShareName

output keyVaultName string = simulatorBase.outputs.keyVaultName
output appInsightsName string = simulatorBase.outputs.appInsightsName
output containerAppEnvName string = simulatorBase.outputs.containerAppEnvName
