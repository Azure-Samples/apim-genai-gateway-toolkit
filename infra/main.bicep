targetScope = 'subscription'

@description('Specifies the supported Azure location (region) where the resources will be deployed')
param location string

@description('This value will explain who is the author of specific resources and will be reflected in every deployed tool')
param uniqueUserName string

@description('The base url of the first Azure Open AI Service PTU deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param ptuDeploymentOneBaseUrl string

@description('The base url of the first Azure Open AI Service Pay-As-You-Go deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param payAsYouGoDeploymentOneBaseUrl string

@description('The base url of the second Azure Open AI Service Pay-As-You-Go deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param payAsYouGoDeploymentTwoBaseUrl string

@description('The name of the policy fragment to test')
@allowed([
  'simpleRoundRobin'
  'weightedRoundRobin'
  'retryWithPayAsYouGo'
])
param policyFragmentIDToTest string = 'simpleRoundRobin'

var resourceGroupName = 'rg-${uniqueUserName}'
var apiManagementName = 'apim-${uniqueUserName}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module apiManagement 'modules/apiManagement.bicep' = {
  name: 'apiManagementDeploy'
  scope: resourceGroup
  params: {
    location: resourceGroup.location
    apiManagementServiceName: apiManagementName
    sku: 'Developer'
    skuCount: 1
    publisherName: uniqueUserName
    publisherEmail: '${uniqueUserName}@microsoft.com'
    ptuDeploymentOneBaseUrl: ptuDeploymentOneBaseUrl
    payAsYouGoDeploymentOneBaseUrl: payAsYouGoDeploymentOneBaseUrl
    payAsYouGoDeploymentTwoBaseUrl: payAsYouGoDeploymentTwoBaseUrl
    policyFragmentIDToTest: policyFragmentIDToTest
  }
}

output apiManagementName string = apiManagement.outputs.apiManagementServiceName
