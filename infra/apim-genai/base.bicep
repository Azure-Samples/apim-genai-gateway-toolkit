// Deploys the base resources that are needed for running the apim gen ai resources
// Only runs when the simulators are not used (USE_SIMULATOR='false')

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

var resourceSuffix = '${workloadName}-${environment}-${location}'
var resourceGroupName = 'rg-${resourceSuffix}'
var logAnalyticsName = 'la-${resourceSuffix}'
var appInsightsName = 'ai-${resourceSuffix}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module monitoringBase 'modules/monitoringBase.bicep' = {
  name: 'monitoringBase'
  scope: resourceGroup
  params: {
    location: location
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
  }
}

output resourceGroupName string = resourceGroupName
output logAnalyticsName string = monitoringBase.outputs.logAnalyticsName
output appInsightsName string = monitoringBase.outputs.appInsightsName
