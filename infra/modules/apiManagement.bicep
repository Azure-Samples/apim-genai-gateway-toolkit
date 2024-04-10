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
  'simpleRoundRobin'
  'weightedRoundRobin'
  'retryWithPayAsYouGo'
])
param policyFragmentIDToTest string = 'simpleRoundRobin'

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
  name: 'AOAIAPI'
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
  name: 'chatCompletions'
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
    value: '<policies><inbound><base /><include-fragment fragment-id="${policyFragmentIDToTest}" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
    format: 'rawxml'
  }
  dependsOn: [simpleRoundRobinPolicyFragment]
}

resource simpleRoundRobinPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'simpleRoundRobin'
  properties: {
    value: '<fragment><cache-lookup-value key="backend-counter" variable-name="backend-counter" default-value="@(0)" /><set-variable name="backend-counter" value="@(((int)context.Variables["backend-counter"])+1)" /><cache-store-value key="backend-counter" value="@((int)context.Variables["backend-counter"])" duration="1200" /><set-variable name="backend-pool" value="@{ JArray backends = new JArray(); backends.Add("{{payg-endpoint-1}}"); backends.Add("{{payg-endpoint-2}}"); return backends; }" /><set-variable name="total-backend-count" value="@(((JArray)context.Variables["backend-pool"]).Count)" /><set-variable name="chosen-index" value="@((int)context.Variables["backend-counter"]%(int)context.Variables["total-backend-count"])" /><set-variable name="selected-url" value="@(((JArray)context.Variables["backend-pool"])[(int)context.Variables["chosen-index"]].ToString())" /><set-backend-service base-url="@((string)context.Variables["selected-url"])" /></fragment>'
    format: 'rawxml'
  }
}

resource weightedRoundRobinPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'weightedRoundRobin'
  properties: {
    value: '<fragment><set-variable name="all-endpoints" value="@{ JArray endpoints = new JArray(); endpoints.Add(new JObject() { { "url", "{{payg-endpoint-1}}" }, { "weight", 2 }, }); endpoints.Add(new JObject() { { "url", "{{payg-endpoint-2}}" }, { "weight", 3 }, }); return endpoints; }" /><set-variable name="selected-url" value="@{ var endpoints = (JArray)context.Variables["all-endpoints"]; var totalWeight = endpoints.Sum(e => (int)e["weight"]); var randomNumber = new Random().Next(totalWeight); var weightSum = 0; foreach (var endpoint in endpoints) { weightSum += (int)endpoint["weight"]; if (randomNumber < weightSum) { return endpoint["url"].ToString(); } } return endpoints[0]["url"].ToString(); }" /><set-backend-service base-url="@((string)context.Variables["selected-url"])" /></fragment>'
    format: 'rawxml'
  }
}

resource retryWithPayAsYouGoPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apiManagementService
  name: 'retryWithPayAsYouGo'
  properties: {
    value: '<fragment><retry condition="@(context.Response.StatusCode == 429)" count="3" interval="1" max-interval="10" delta="2"><choose><when condition="@(context.Response.StatusCode == 429)"><set-variable name="selected-url" value="{{payg-endpoint-1}}" /><set-backend-service base-url="@((string)context.Variables["selected-url"])" /></when><otherwise><set-variable name="selected-url" value="{{ptu-endpoint-1}}" /><set-backend-service base-url="@((string)context.Variables["selected-url"])" /></otherwise></choose><forward-request timeout="120" fail-on-error-status-code="true" buffer-response="false" /></retry></fragment>'
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
