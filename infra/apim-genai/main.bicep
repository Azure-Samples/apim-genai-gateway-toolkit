targetScope = 'resourceGroup'

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

@description('The base url of the first Azure Open AI Service PTU deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param ptuDeploymentOneBaseUrl string

@description('The api key of the first Azure Open AI Service PTU deployment')
param ptuDeploymentOneApiKey string

@description('The base url of the first Azure Open AI Service Pay-As-You-Go deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param payAsYouGoDeploymentOneBaseUrl string

@description('The api key of the first Azure Open AI Service Pay-As-You-Go deployment')
param payAsYouGoDeploymentOneApiKey string

@description('The base url of the second Azure Open AI Service Pay-As-You-Go deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param payAsYouGoDeploymentTwoBaseUrl string

@description('The api key of the second Azure Open AI Service Pay-As-You-Go deployment')
param payAsYouGoDeploymentTwoApiKey string

@description('The name of the Log Analytics workspace')
param logAnalyticsName string

@description('The name of the App Insights instance')
param appInsightsName string

param location string = resourceGroup().location

var resourceSuffix = '${workloadName}-${environment}-${location}'
var apiManagementServiceName = 'apim-${resourceSuffix}'
var eventHubNamespaceName = 'eh-ns-${resourceSuffix}'
var eventHubName = 'apim-utilization-reporting'

module apiManagement 'modules/apiManagement.bicep' = {
  name: 'apiManagementDeploy'
  params: {
    apiManagementServiceName: apiManagementServiceName
    ptuDeploymentOneBaseUrl: ptuDeploymentOneBaseUrl
    ptuDeploymentOneApiKey: ptuDeploymentOneApiKey
    payAsYouGoDeploymentOneBaseUrl: payAsYouGoDeploymentOneBaseUrl
    payAsYouGoDeploymentOneApiKey: payAsYouGoDeploymentOneApiKey
    payAsYouGoDeploymentTwoBaseUrl: payAsYouGoDeploymentTwoBaseUrl
    payAsYouGoDeploymentTwoApiKey: payAsYouGoDeploymentTwoApiKey
    eventHubNamespaceName: eventHub.outputs.eventHubNamespaceName
    eventHubName: eventHub.outputs.eventHubName
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
    location: location
  }
}

module eventHub 'modules/eventHub.bicep' = {
  name: 'eventHubDeploy'
  params: {
    eventHubName: eventHubName
    eventHubNamespaceName: eventHubNamespaceName
    location: location
  }
}

output apiManagementName string = apiManagement.outputs.apiManagementServiceName
output apiManagementAzureOpenAIProductSubscriptionOneKey string = apiManagement.outputs.apiManagementAzureOpenAIProductSubscriptionOneKey
output apiManagementAzureOpenAIProductSubscriptionTwoKey string = apiManagement.outputs.apiManagementAzureOpenAIProductSubscriptionTwoKey
output apiManagementAzureOpenAIProductSubscriptionThreeKey string = apiManagement.outputs.apiManagementAzureOpenAIProductSubscriptionThreeKey
