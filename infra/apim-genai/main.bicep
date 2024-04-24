targetScope = 'resourceGroup'

@description('The name of the API Management service instance')
param apiManagementServiceName string

@description('The base url of the first Azure Open AI Service PTU deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param ptuDeploymentOneBaseUrl string

@description('The api key url of the first Azure Open AI Service PTU deployment')
param ptuDeploymentOneApiKey string

@description('The base url of the first Azure Open AI Service Pay-As-You-Go deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param payAsYouGoDeploymentOneBaseUrl string

@description('The api key url of the first Azure Open AI Service Pay-As-You-Go deployment')
param payAsYouGoDeploymentOneApiKey string

@description('The base url of the second Azure Open AI Service Pay-As-You-Go deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param payAsYouGoDeploymentTwoBaseUrl string

@description('The api key url of the second Azure Open AI Service Pay-As-You-Go deployment')
param payAsYouGoDeploymentTwoApiKey string

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
  }
}

output apiManagementName string = apiManagement.outputs.apiManagementServiceName
