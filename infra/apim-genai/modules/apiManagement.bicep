@description('The name of the API Management service instance')
param apiManagementServiceName string

@description('The email address of the owner of the service')
param publisherEmail string = 'apim@contoso.com'

@description('The name of the owner of the service')
param publisherName string = 'Contoso'

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

@description('The name of the Log Analytics workspace')
param logAnalyticsName string

@description('The name of the App Insights instance')
param appInsightsName string

@description('Location for all resources.')
param location string = resourceGroup().location

resource apiManagementService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apiManagementServiceName
  location: location
  sku: {
    name: sku
    capacity: skuCount
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    apiVersionConstraint: {
      minApiVersion: '2019-12-01'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource azureOpenAISimpleRoundRobinAPI 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-api-simple-round-robin'
  properties: {
    path: '/round-robin-simple/openai'
    displayName: 'AOAIAPI-SimpleRoundRobin'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
  }
}

resource azureOpenAISimpleRoundRobinAPIv2 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-api-simple-round-robin-v2'
  properties: {
    path: '/round-robin-simple-v2/openai'
    displayName: 'AOAIAPI-SimpleRoundRobin-V2'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
  }
}

resource azureOpenAIWeightedRoundRobinAPI 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-api-weighted-round-robin'
  properties: {
    path: '/round-robin-weighted/openai'
    displayName: 'AOAIAPI-WeightedRoundRobin'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
  }
}

resource azureOpenAIWeightedRoundRobinAPIv2 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-api-weighted-round-robin-v2'
  properties: {
    path: '/round-robin-weighted-v2/openai'
    displayName: 'AOAIAPI-WeightedRoundRobin-V2'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
  }
}

resource azureOpenAIRetryWithPayAsYouGoAPI 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-api-retry-with-payg'
  properties: {
    path: '/retry-with-payg/openai'
    displayName: 'AOAIAPI-RetryWithPayAsYouGo'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
  }
}

resource azureOpenAIRetryWithPayAsYouGoAPIv2 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-api-retry-with-payg-v2'
  properties: {
    path: '/retry-with-payg-v2/openai'
    displayName: 'AOAIAPI-RetryWithPayAsYouGo-V2'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
  }
}

resource azureOpenAILatencyRoutingAPI 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-api-latency-routing'
  properties: {
    path: '/latency-routing/openai'
    displayName: 'AOAIAPI-LatencyRouting'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
  }
}

resource azureOpenAIUsageTrackingAPI 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-api-usage-tracking'
  properties: {
    path: '/usage-tracking/openai'
    displayName: 'AOAIAPI-UsageTracking'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
  }
}

resource azureOpenAIPrioritizationTokenCalculatingAPI 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-api-prioritization-token-calculating'
  properties: {
    path: '/prioritization-token-calculating/openai'
    displayName: 'AOAIAPI-Prioritization-TokenCalculating'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
  }
}

resource azureOpenAIPrioritizationTokenTrackingAPI 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-api-prioritization-tracking'
  properties: {
    path: '/prioritization-token-tracking/openai'
    displayName: 'AOAIAPI-Prioritization-TokenTracking'
    protocols: ['https']
    value: loadTextContent('../api-specs/openapi-spec.json')
    format: 'openapi+json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
  }
}

resource helperAPI 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagementService
  name: 'helper-apis'
  properties: {
    path: '/helpers'
    displayName: 'Helper APIs'
    protocols: ['https']
    value: loadTextContent('../api-specs/support-api-spec.json')
    format: 'openapi+json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
  }
}

resource azureOpenAIProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
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
  azureOpenAISimpleRoundRobinAPIv2.name
  azureOpenAIWeightedRoundRobinAPI.name
  azureOpenAIWeightedRoundRobinAPIv2.name
  azureOpenAIRetryWithPayAsYouGoAPI.name
  azureOpenAIRetryWithPayAsYouGoAPIv2.name
  azureOpenAILatencyRoutingAPI.name
  azureOpenAIUsageTrackingAPI.name
  azureOpenAIPrioritizationTokenCalculatingAPI.name
  azureOpenAIPrioritizationTokenTrackingAPI.name
  helperAPI.name
]

resource azureOpenAIProductAPIAssociation 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = [
  for apiName in azureOpenAIAPINames: {
    name: '${apiManagementServiceName}/${azureOpenAIProduct.name}/${apiName}'
  }
]

resource ptuBackendOne 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apiManagementService
  name: 'ptu-backend-1'
  properties: {
    protocol: 'http'
    url: ptuDeploymentOneBaseUrl
    credentials: {
      header: {
        'api-key': [ptuDeploymentOneApiKey]
      }
    }
  }
}

resource ptuBackendOneWithCircuitBreaker 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apiManagementService
  name: 'ptu-backend-1-with-circuit-breaker'
  properties: {
    protocol: 'http'
    url: ptuDeploymentOneBaseUrl
    credentials: {
      header: {
        'api-key': [ptuDeploymentOneApiKey]
      }
    }
    circuitBreaker: {
      rules: [
        {
          failureCondition: {
            count: 3
            errorReasons: [
              '429s'
            ]
            interval: 'PT10S'
            statusCodeRanges: [
              {
                min: 429
                max: 429
              }
            ]
          }
          name: 'retry-with-payg-breaker-rule'
          tripDuration: 'PT1M'
          acceptRetryAfter: true
        }
      ]
    }
  }
}

resource payAsYouGoBackendOne 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apiManagementService
  name: 'payg-backend-1'
  properties: {
    protocol: 'http'
    url: payAsYouGoDeploymentOneBaseUrl
    credentials: {
      header: {
        'api-key': [payAsYouGoDeploymentOneApiKey]
      }
    }
  }
}

resource payAsYouGoBackendTwo 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apiManagementService
  name: 'payg-backend-2'
  properties: {
    protocol: 'http'
    url: payAsYouGoDeploymentTwoBaseUrl
    credentials: {
      header: {
        'api-key': [payAsYouGoDeploymentTwoApiKey]
      }
    }
  }
}

resource simpleRoundRobinBackendPool 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apiManagementService
  name: 'simple-round-robin-backend-pool'
  properties: {
    type: 'Pool'
    pool: {
      services: [
        {
          id: payAsYouGoBackendOne.id
          weight: 1
          priority: 1
        }
        {
          id: payAsYouGoBackendTwo.id
          weight: 1
          priority: 1
        }
      ]
    }
  }
}

resource weightedRoundRobinBackendPool 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apiManagementService
  name: 'weighted-round-robin-backend-pool'
  properties: {
    type: 'Pool'
    pool: {
      services: [
        {
          id: payAsYouGoBackendOne.id
          weight: 2
          priority: 1
        }
        {
          id: payAsYouGoBackendTwo.id
          weight: 1
          priority: 1
        }
      ]
    }
  }
}

resource retryWithPayAsYouGoBackendPool 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apiManagementService
  name: 'retry-with-payg-backend-pool'
  properties: {
    type: 'Pool'
    pool: {
      services: [
        {
          id: ptuBackendOneWithCircuitBreaker.id
          weight: 1
          priority: 1
        }
        {
          id: payAsYouGoBackendOne.id
          weight: 1
          priority: 2
        }
      ]
    }
  }
}

resource azureOpenAIProductSubscriptionOne 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-product-subscription-one'
  properties: {
    displayName: 'aoai-product-subscription-one'
    state: 'active'
    scope: azureOpenAIProduct.id
  }
}

resource azureOpenAIProductSubscriptionTwo 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-product-subscription-two'
  properties: {
    displayName: 'aoai-product-subscription-two'
    state: 'active'
    scope: azureOpenAIProduct.id
  }
}

resource azureOpenAIProductSubscriptionThree 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apiManagementService
  name: 'aoai-product-subscription-three'
  properties: {
    displayName: 'aoai-product-subscription-three'
    state: 'active'
    scope: azureOpenAIProduct.id
  }
}

resource simpleRoundRobinPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apiManagementService
  name: 'simple-round-robin'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing/simple-round-robin.xml')
    format: 'rawxml'
  }
  dependsOn: [payAsYouGoBackendOne, payAsYouGoBackendTwo]
}

resource azureOpenAISimpleRoundRobinAPIPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: azureOpenAISimpleRoundRobinAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing/simple-round-robin-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [simpleRoundRobinPolicyFragment]
}

resource simpleRoundRobinPolicyFragmentv2 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apiManagementService
  name: 'simple-round-robin-v2'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing-v2/simple-round-robin.xml')
    format: 'rawxml'
  }
  dependsOn: [simpleRoundRobinBackendPool]
}

resource azureOpenAISimpleRoundRobinAPIPolicyv2 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: azureOpenAISimpleRoundRobinAPIv2
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing-v2/simple-round-robin-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [simpleRoundRobinPolicyFragmentv2]
}

resource weightedRoundRobinPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apiManagementService
  name: 'weighted-round-robin'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing/weighted-round-robin.xml')
    format: 'rawxml'
  }
  dependsOn: [payAsYouGoBackendOne, payAsYouGoBackendTwo]
}

resource azureOpenAIWeightedRoundRobinAPIPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: azureOpenAIWeightedRoundRobinAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing/weighted-round-robin-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [weightedRoundRobinPolicyFragment]
}

resource weightedRoundRobinPolicyFragmentv2 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apiManagementService
  name: 'weighted-round-robin-v2'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing-v2/weighted-round-robin.xml')
    format: 'rawxml'
  }
  dependsOn: [weightedRoundRobinBackendPool]
}

resource azureOpenAIWeightedRoundRobinAPIPolicyv2 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: azureOpenAIWeightedRoundRobinAPIv2
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/load-balancing-v2/weighted-round-robin-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [weightedRoundRobinPolicyFragmentv2]
}

resource retryWithPayAsYouGoPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apiManagementService
  name: 'retry-with-payg'
  properties: {
    value: loadTextContent('../../../capabilities/manage-spikes-with-payg/retry-with-payg.xml')
    format: 'rawxml'
  }
  dependsOn: [ptuBackendOne, payAsYouGoBackendOne]
}

resource azureOpenAIRetryWithPayAsYouGoAPIPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: azureOpenAIRetryWithPayAsYouGoAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/manage-spikes-with-payg/retry-with-payg-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [retryWithPayAsYouGoPolicyFragment]
}

resource retryWithPayAsYouGoPolicyFragmentv2 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apiManagementService
  name: 'retry-with-payg-v2'
  properties: {
    value: loadTextContent('../../../capabilities/manage-spikes-with-payg-v2/retry-with-payg.xml')
    format: 'rawxml'
  }
  dependsOn: [retryWithPayAsYouGoBackendPool]
}

resource azureOpenAIRetryWithPayAsYouGoAPIPolicyv2 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: azureOpenAIRetryWithPayAsYouGoAPIv2
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/manage-spikes-with-payg-v2/retry-with-payg-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [retryWithPayAsYouGoPolicyFragmentv2]
}

resource latencyRoutingInboundPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apiManagementService
  name: 'latency-routing-inbound'
  properties: {
    value: loadTextContent('../../../capabilities/latency-routing/latency-routing-inbound.xml')
    format: 'rawxml'
  }
  dependsOn: [payAsYouGoBackendOne]
}

resource latencyRoutingBackendPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apiManagementService
  name: 'latency-routing-backend'
  properties: {
    value: loadTextContent('../../../capabilities/latency-routing/latency-routing-backend.xml')
    format: 'rawxml'
  }
}

resource azureOpenAILatencyRoutingPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: azureOpenAILatencyRoutingAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/latency-routing/latency-routing-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [latencyRoutingInboundPolicyFragment, latencyRoutingBackendPolicyFragment]
}

resource usageTrackingPolicyFragmentInbound 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apiManagementService
  name: 'usage-tracking-inbound'
  properties: {
    value: loadTextContent('../../../capabilities/usage-tracking/usage-tracking-inbound.xml')
    format: 'rawxml'
  }
  dependsOn: [payAsYouGoBackendOne]
}

resource usageTrackingPolicyFragmentOutbound 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apiManagementService
  name: 'usage-tracking-outbound'
  properties: {
    value: loadTextContent('../../../capabilities/usage-tracking/usage-tracking-outbound.xml')
    format: 'rawxml'
  }
  dependsOn: [eventHubLogger]
}

resource azureOpenAIUsageTrackingPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: azureOpenAIUsageTrackingAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/usage-tracking/usage-tracking-policy.xml')
    format: 'rawxml'
  }
  dependsOn: [usageTrackingPolicyFragmentInbound, usageTrackingPolicyFragmentOutbound]
}

resource azureOpenAIPrioritizationTokenCalculatingPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: azureOpenAIPrioritizationTokenCalculatingAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/prioritization/prioritization-token-calculating.xml')
    format: 'rawxml'
  }
}

resource azureOpenAIPrioritizationTokenTrackingPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: azureOpenAIPrioritizationTokenTrackingAPI
  name: 'policy'
  properties: {
    value: loadTextContent('../../../capabilities/prioritization/prioritization-token-tracking.xml')
    format: 'rawxml'
  }
}

resource helperAPISetPreferredBackends 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
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
  name: guid(
    resourceGroup().id,
    eventHubNamespace.name,
    apiManagementService.name,
    'assignEventHubsDataSenderToApiManagement'
  )
  scope: eventHubNamespace
  properties: {
    description: 'Assign EventHubsDataSender role to API Management'
    principalId: apiManagementService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: eventHubsDataSenderRoleDefinition.id
  }
}

resource eventHubLogger 'Microsoft.ApiManagement/service/loggers@2022-04-01-preview' = {
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

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource appInsightsLogger 'Microsoft.ApiManagement/service/loggers@2022-04-01-preview' = {
  name: 'appinsights-logger'
  parent: apiManagementService
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger'
    resourceId: appInsights.id
    credentials: {
      instrumentationKey: appInsights.properties.InstrumentationKey
    }
  }
}

resource azureMonitorLogger 'Microsoft.ApiManagement/service/loggers@2022-04-01-preview' = {
  name: 'azuremonitor'
  parent: apiManagementService
  properties: {
    loggerType: 'azureMonitor'
    isBuffered: true
  }
}

resource allApisAzureMonitorDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apiManagementService
  name: 'azuremonitor'
  properties: {
    loggerId: azureMonitorLogger.id
    metrics: true
    verbosity: 'information'
    logClientIp: false
    sampling: {
      percentage: 100
      samplingType: 'fixed'
    }
    frontend: {
      request: {
        headers: [
          'x-priority'
        ]
      }
      response: {
        headers: [
          'x-gw-ratelimit-reason'
          'x-gw-ratelimit-value'
          'x-gw-remaining-tokens'
          'x-gw-remaining-requests'
          'x-gw-priority'
        ]
      }
    }
    backend: {
      request: {
        headers: []
      }
      response: {
        headers: [
          'x-ratelimit-remaining-tokens'
          'x-ratelimit-remaining-requests'
        ]
      }
    }
  }
}

resource azureOpenAIUsageTrackingAPIDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  parent: azureOpenAIUsageTrackingAPI
  name: 'applicationinsights'
  properties: {
    loggerId: appInsightsLogger.id
    metrics: true
  }
}

resource azureOpenAIPrioritizationTokenCalculatingAPIDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  parent: azureOpenAIPrioritizationTokenCalculatingAPI
  name: 'applicationinsights'
  properties: {
    loggerId: appInsightsLogger.id
    metrics: true
  }
}

resource azureOpenAIPrioritizationTokenTrackingAPIDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  parent: azureOpenAIPrioritizationTokenTrackingAPI
  name: 'applicationinsights'
  properties: {
    loggerId: appInsightsLogger.id
    metrics: true
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' existing = {
  name: logAnalyticsName
}

resource apiManagementDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${apiManagementServiceName}-diagnostic-settings'
  scope: apiManagementService
  properties: {
    workspaceId: logAnalytics.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output apiManagementServiceName string = apiManagementService.name
output apiManagementAzureOpenAIProductSubscriptionOneKey string = azureOpenAIProductSubscriptionOne.listSecrets().primaryKey
output apiManagementAzureOpenAIProductSubscriptionTwoKey string = azureOpenAIProductSubscriptionTwo.listSecrets().primaryKey
output apiManagementAzureOpenAIProductSubscriptionThreeKey string = azureOpenAIProductSubscriptionThree.listSecrets().primaryKey
