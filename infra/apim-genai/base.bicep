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
var logAnalyticsName = 'la-${resourceSuffix}'
var appInsightsName = 'ai-${resourceSuffix}'

var eventHubNamespaceName = 'eh-ns-${resourceSuffix}'
var eventHubName = 'apim-utilization-reporting'

var resourceGroupName = 'rg-${resourceSuffix}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}


module apiManagement 'modules/appInsights.bicep' = {
  name: 'apiManagementDeploy'
  scope: resourceGroup
  params: {
    appInsightsName: appInsightsName
    logAnalyticsName: logAnalyticsName
    location: location
  }
}

module eventHub 'modules/eventHub.bicep' = {
  name: 'eventHubDeploy'
  scope: resourceGroup
  params: {
    eventHubName: eventHubName
    eventHubNamespaceName: eventHubNamespaceName
    location: location
  }
}

output resourceGroupName string = resourceGroupName
output eventHubNamespaceName string = eventHubNamespaceName
output eventHubName string = eventHubName
output appInsightsName string = appInsightsName
output logAnalyticsName string = logAnalyticsName
