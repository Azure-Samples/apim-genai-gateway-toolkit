targetScope = 'subscription'

@description('Specifies the supported Azure location (region) where the resources will be deployed')
param location string

@description('This value will explain who is the author of specific resources and will be reflected in every deployed tool')
param uniqueUserName string

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
  }
}

output apiManagementName string = apiManagement.outputs.apiManagementServiceName
