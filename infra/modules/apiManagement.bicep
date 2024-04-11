@description('The name of the API Management service instance')
param apiManagementServiceName string

@description('The email address of the owner of the service')
param publisherEmail string

@description('The name of the owner of the service')
param publisherName string

@description('The pricing tier of this API Management service')
@allowed([
  'Consumption'
  'Developer'
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Developer'

@description('The instance size of this API Management service.')
@allowed([
  0
  1
  2
])
param skuCount int = 1

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The base url of the first Azure Open AI Service PTU deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param ptuDeploymentOneBaseUrl string

@description('The base url of the first Azure Open AI Service Pay-As-You-Go deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param payAsYouGoDeploymentOneBaseUrl string

@description('The base url of the second Azure Open AI Service Pay-As-You-Go deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param payAsYouGoDeploymentTwoBaseUrl string

@description('The name of the policy fragment to test')
@allowed([
  'simple-round-robin'
  'weighted-round-robin'
  'retry-with-payg'
])
param policyFragment string = 'simple-round-robin'

resource apiManagementService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apiManagementServiceName
  location: location
  sku: {
    name: sku
    capacity: skuCount
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

resource azureOpenAIAPI 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-api'
  properties: {
    path: '/'
    displayName: 'AOAIAPI'
    protocols: ['https']
  }
}

resource embeddingsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: azureOpenAIAPI
  name: 'embeddings'
  properties: {
    displayName: 'embeddings'
    method: 'POST'
    urlTemplate: '/embeddings'
  }
}

resource completionsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: azureOpenAIAPI
  name: 'completions'
  properties: {
    displayName: 'completions'
    method: 'POST'
    urlTemplate: '/completions'
  }
}

resource chatOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: azureOpenAIAPI
  name: 'chat-completions'
  properties: {
    displayName: 'chatCompletions'
    method: 'POST'
    urlTemplate: '/chat/completions'
  }
}

resource azureOpenAIAPIPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: azureOpenAIAPI
  name: 'policy'
  properties: {
    value: '<policies><inbound><base /><include-fragment fragment-id="${policyFragment}" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
    format: 'rawxml'
  }
  dependsOn: [simpleRoundRobinPolicyFragment, weightedRoundRobinPolicyFragment, retryWithPayAsYouGoPolicyFragment]
}

resource simpleRoundRobinPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'simple-round-robin'
  properties: {
    value: loadTextContent('../../policies/load-balancing/simple-round-robin.xml')
    format: 'rawxml'
  }
}

resource weightedRoundRobinPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'weighted-round-robin'
  properties: {
    value: loadTextContent('../../policies/load-balancing/weighted-round-robin.xml')
    format: 'rawxml'
  }
}

resource retryWithPayAsYouGoPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'retry-with-payg'
  properties: {
    value: loadTextContent('../../policies/manage-spikes-with-payg/retry-with-payg.xml')
    format: 'rawxml'
  }
}

resource ptuEndpointOneNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'ptu-endpoint-1'
  properties: {
    displayName: 'ptu-endpoint-1'
    value: ptuDeploymentOneBaseUrl
  }
}

resource payAsYouGoEndpointOneNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'payg-endpoint-1'
  properties: {
    displayName: 'payg-endpoint-1'
    value: payAsYouGoDeploymentOneBaseUrl
  }
}

resource payAsYouGoEndpointTwoNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'payg-endpoint-2'
  properties: {
    displayName: 'payg-endpoint-2'
    value: payAsYouGoDeploymentTwoBaseUrl
  }
}

output apiManagementServiceName string = apiManagementService.name
