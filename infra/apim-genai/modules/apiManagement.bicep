@description('The name of the API Management service instance')
param apiManagementServiceName string

@description('The base url of the first Azure Open AI Service PTU deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param ptuDeploymentOneBaseUrl string

@description('The base url of the first Azure Open AI Service Pay-As-You-Go deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param payAsYouGoDeploymentOneBaseUrl string

@description('The base url of the second Azure Open AI Service Pay-As-You-Go deployment (e.g. https://{your-resource-name}.openai.azure.com/openai/deployments/{deployment-id}/)')
param payAsYouGoDeploymentTwoBaseUrl string

resource apiManagementService 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apiManagementServiceName
}

resource azureOpenAISimpleRoundRobinAPI 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-api-simple-round-robin'
  properties: {
    path: '/simple-round-robin'
    displayName: 'AOAIAPI-SimpleRoundRobin'
    protocols: ['https']
    value: loadTextContent('../../openapi-spec.json')
    format: 'openapi+json' 
  }
}

resource azureOpenAIWeightedRoundRobinAPI 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-api-weighted-round-robin'
  properties: {
    path: '/weighted-round-robin'
    displayName: 'AOAIAPI-WeightedRoundRobin'
    protocols: ['https']
    value: loadTextContent('../../openapi-spec.json')
    format: 'openapi+json' 
  }
}

resource azureOpenAIRetryWithPayAsYouGoAPI 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-api-retry-with-payg'
  properties: {
    path: '/retry-with-payg'
    displayName: 'AOAIAPI-RetryWithPayAsYouGo'
    protocols: ['https']
    value: loadTextContent('../../openapi-spec.json')
    format: 'openapi+json' 
  }
}

resource azureOpenAIAdaptiveRateLimitingAPI 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-api-rate-limting'
  properties: {
    path: '/rate-limiting'
    displayName: 'AOAIAPI-RateLimiting'
    protocols: ['https']
    value: loadTextContent('../../openapi-spec.json')
    format: 'openapi+json' 
  }
}

resource simpleRoundRobinPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'simple-round-robin'
  properties: {
    value: loadTextContent('../../../policies/load-balancing/simple-round-robin.xml')
    format: 'rawxml'
  }
  dependsOn: [payAsYouGoEndpointOneNamedValue, payAsYouGoEndpointTwoNamedValue]
}

resource azureOpenAISimpleRoundRobinAPIPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: azureOpenAISimpleRoundRobinAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../policies/load-balancing/simple-round-robin-policy.xml')
    format: 'rawxml'
  }
}

resource weightedRoundRobinPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'weighted-round-robin'
  properties: {
    value: loadTextContent('../../../policies/load-balancing/weighted-round-robin.xml')
    format: 'rawxml'
  }
  dependsOn: [payAsYouGoEndpointOneNamedValue, payAsYouGoEndpointTwoNamedValue]
}

resource azureOpenAIWeightedRoundRobinAPIPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: azureOpenAIWeightedRoundRobinAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../policies/load-balancing/weighted-round-robin-policy.xml')
    format: 'rawxml'
  }
}

resource adaptiveRateLimitingPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'adaptive-rate-limiting'
  properties: {
    value: loadTextContent('../../../policies/rate-limiting/adaptive-rate-limiting.xml')
    format: 'rawxml'
  }
}

resource azureOpenAIAdaptiveRateLimitingPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: azureOpenAIAdaptiveRateLimitingAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../policies/rate-limiting/adaptive-rate-limiting-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [payAsYouGoEndpointOneNamedValue]
}

resource retryWithPayAsYouGoPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'retry-with-payg'
  properties: {
    value: loadTextContent('../../../policies/manage-spikes-with-payg/retry-with-payg.xml')
    format: 'rawxml'
  }
  dependsOn: [ptuEndpointOneNamedValue, payAsYouGoEndpointOneNamedValue]
}


resource azureOpenAIRetryWithPayAsYouGoAPIPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: azureOpenAIRetryWithPayAsYouGoAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../policies/manage-spikes-with-payg/retry-with-payg-policy.xml')
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
