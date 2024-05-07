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

param location string = deployment().location

var resourceSuffix = '${workloadName}-${environment}-${location}-001'
var resourceGroupName = 'rg-${resourceSuffix}'
var apimName = 'apim-${resourceSuffix}'
var logAnalyticsName = 'la-${resourceSuffix}'
var appInsightsName = 'ai-${resourceSuffix}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module apiManagement 'modules/apiManagement.bicep' = {
  name: 'apiManagementDeploy'
  scope: resourceGroup
  params: {
    apiManagementServiceName: apimName
    location: location
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
  }
}

output resourceGroupName string = resourceGroupName
output apimName string = apimName
output logAnalyticsName string = logAnalyticsName
output appInsightsName string = appInsightsName
