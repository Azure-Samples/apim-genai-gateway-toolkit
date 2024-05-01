@description('The name of the API Management service instance')
param apiManagementServiceName string

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

@description('The name of the Event Hub Namespace to log to')
param eventHubNamespaceName string

@description('The name of the Event Hub to log utilization data to')
param eventHubName string

resource apiManagementService 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apiManagementServiceName
}

resource azureOpenAISimpleRoundRobinAPI 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-api-simple-round-robin'
  properties: {
    path: '/simple-round-robin/openai'
    displayName: 'AOAIAPI-SimpleRoundRobin'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
  }
}

resource azureOpenAIWeightedRoundRobinAPI 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-api-weighted-round-robin'
  properties: {
    path: '/weighted-round-robin/openai'
    displayName: 'AOAIAPI-WeightedRoundRobin'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
  }
}

resource azureOpenAIRetryWithPayAsYouGoAPI 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-api-retry-with-payg'
  properties: {
    path: '/retry-with-payg/openai'
    displayName: 'AOAIAPI-RetryWithPayAsYouGo'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
  }
}

resource azureOpenAIAdaptiveRateLimitingAPI 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-api-rate-limting'
  properties: {
    path: '/rate-limiting/openai'
    displayName: 'AOAIAPI-RateLimiting'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
  }
}

resource azureOpenAILatencyRoutingAPI 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-api-latency-routing'
  properties: {
    path: '/latency-routing/openai'
    displayName: 'AOAIAPI-LatencyRouting'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
  }
}

resource helperAPI 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'helper-apis'
  properties: {
    path: '/helpers'
    displayName: 'Helper APIs'
    protocols: ['https']
    value: loadTextContent('../api-specs/support-api-spec.json')
    format: 'openapi+json'
  }
}

resource azureOpenAIProduct 'Microsoft.ApiManagement/service/products@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-product'
  properties: {
    displayName: 'aoai-product'
    subscriptionRequired: true
    state: 'published'
    approvalRequired: false
  }
}

var azureOpenAIAPINames = [
  azureOpenAISimpleRoundRobinAPI.name
  azureOpenAIWeightedRoundRobinAPI.name
  azureOpenAIRetryWithPayAsYouGoAPI.name
  azureOpenAIAdaptiveRateLimitingAPI.name
  azureOpenAILatencyRoutingAPI.name
  helperAPI.name
]

resource azureOpenAIProductAPIAssociation 'Microsoft.ApiManagement/service/products/apis@2023-05-01-preview' = [
  for apiName in azureOpenAIAPINames: {
    name: '${apiManagementServiceName}/${azureOpenAIProduct.name}/${apiName}'
  }
]

resource ptuBackendOne 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'ptu-backend-1'
  properties:{
    protocol: 'http'
    url: ptuDeploymentOneBaseUrl
    credentials: {
      header: {
        'api-key': [ptuDeploymentOneApiKey]
      }
    }
  }
}

resource payAsYouGoBackendOne 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'payg-backend-1'
  properties:{
    protocol: 'http'
    url: payAsYouGoDeploymentOneBaseUrl
    credentials: {
      header: {
        'api-key': [payAsYouGoDeploymentOneApiKey]
      }
    }
  }
}

resource payAsYouGoBackendTwo 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'payg-backend-2'
  properties:{
    protocol: 'http'
    url: payAsYouGoDeploymentTwoBaseUrl
    credentials: {
      header: {
        'api-key': [payAsYouGoDeploymentTwoApiKey]
      }
    }
  }
}

resource azureOpenAIProductSubscription 'Microsoft.ApiManagement/service/subscriptions@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'aoai-product-subscription'
  properties: {
    displayName: 'aoai-product-subscription'
    state: 'active'
    scope: azureOpenAIProduct.id
  }
}

resource simpleRoundRobinPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'simple-round-robin'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing/simple-round-robin.xml')
    format: 'rawxml'
  }
  dependsOn: [payAsYouGoBackendOne, payAsYouGoBackendTwo]
}

resource azureOpenAISimpleRoundRobinAPIPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: azureOpenAISimpleRoundRobinAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing/simple-round-robin-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [simpleRoundRobinPolicyFragment]
}

resource weightedRoundRobinPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'weighted-round-robin'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing/weighted-round-robin.xml')
    format: 'rawxml'
  }
  dependsOn: [payAsYouGoBackendOne, payAsYouGoBackendTwo]
}

resource azureOpenAIWeightedRoundRobinAPIPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: azureOpenAIWeightedRoundRobinAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing/weighted-round-robin-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [weightedRoundRobinPolicyFragment]
}

resource adaptiveRateLimitingPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'adaptive-rate-limiting'
  properties: {
    value: loadTextContent('../../../capabilities/rate-limiting/adaptive-rate-limiting.xml')
    format: 'rawxml'
  }
  dependsOn: [payAsYouGoBackendOne, ptuBackendOne]
}

resource azureOpenAIAdaptiveRateLimitingPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: azureOpenAIAdaptiveRateLimitingAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/rate-limiting/adaptive-rate-limiting-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [adaptiveRateLimitingPolicyFragment]
}

resource retryWithPayAsYouGoPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'retry-with-payg'
  properties: {
    value: loadTextContent('../../../capabilities/manage-spikes-with-payg/retry-with-payg.xml')
    format: 'rawxml'
  }
}

resource azureOpenAIRetryWithPayAsYouGoAPIPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: azureOpenAIRetryWithPayAsYouGoAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/manage-spikes-with-payg/retry-with-payg-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [retryWithPayAsYouGoPolicyFragment]
}

resource latencyRoutingInboundPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'latency-routing-inbound'
  properties: {
    value: loadTextContent('../../../capabilities/latency-routing/latency-routing-inbound.xml')
    format: 'rawxml'
  }
}
resource latencyRoutingBackendPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'latency-routing-backend'
  properties: {
    value: loadTextContent('../../../capabilities/latency-routing/latency-routing-backend.xml')
    format: 'rawxml'
  }
}

resource azureOpenAILatencyRoutingPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: azureOpenAILatencyRoutingAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/latency-routing/latency-routing-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [latencyRoutingInboundPolicyFragment, latencyRoutingBackendPolicyFragment]
}

resource helperAPISetPreferredBackends 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: helperAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/latency-routing/set-latency-policy.xml')
    format: 'rawxml'
  }
}


resource eventHubNamespace 'Microsoft.EventHub/namespaces@2021-11-01' existing = {
  name: eventHubNamespaceName
}

resource eventHubsDataSenderRoleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: eventHubNamespace
  name: '2b629674-e913-4c01-ae53-ef4638d8f975' // https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#azure-event-hubs-data-sender
}

resource assignEventHubsDataSenderToApiManagement 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, eventHubNamespace.name, apiManagementService.name, 'assignEventHubsDataSenderToApiManagement')
  scope: eventHubNamespace
  properties: {
    description: 'Assign EventHubsDataSender role to API Management'
    principalId: apiManagementService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: eventHubsDataSenderRoleDefinition.id
  }
}

resource eventHubLoggerWithSystemAssignedIdentity 'Microsoft.ApiManagement/service/loggers@2022-04-01-preview' = {
  name: 'eventhub-logger'
  parent: apiManagementService
  properties: {
    loggerType: 'azureEventHub'
    description: 'Event hub logger with system-assigned managed identity'
    credentials: {
      endpointAddress: '${eventHubNamespaceName}.servicebus.windows.net'
      identityClientId: 'systemAssigned'
      name: eventHubName
    }
  }
}

output apiManagementServiceName string = apiManagementService.name
output apiManagementAzureOpenAIProductSubscriptionKey string = azureOpenAIProductSubscription.listSecrets().primaryKey
