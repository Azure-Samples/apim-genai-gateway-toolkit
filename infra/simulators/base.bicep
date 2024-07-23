targetScope = 'subscription'

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
var resourceGroupName = 'rg-${resourceSuffix}'
var logAnalyticsName = 'la-${resourceSuffix}'
var appInsightsName = 'ai-${resourceSuffix}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module simulatorBase 'modules/simulatorBase.bicep' = {
  name: 'simulatorBase'
  scope: resourceGroup
  params: {
    location: location
    resourceSuffix: resourceSuffix
    additionalKeyVaulSecretReaderPrincipalId: additionalKeyVaulSecretReaderPrincipalId
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
  }
}

output resourceGroupName string = resourceGroupName

output logAnalyticsName string = logAnalyticsName
output appInsightsName string = appInsightsName

output containerRegistryLoginServer string = simulatorBase.outputs.containerRegistryLoginServer
output containerRegistryName string = simulatorBase.outputs.containerRegistryName

output keyVaultName string = simulatorBase.outputs.keyVaultName
output containerAppEnvName string = simulatorBase.outputs.containerAppEnvName
