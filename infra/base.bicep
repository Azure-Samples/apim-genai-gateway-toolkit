targetScope = 'subscription'

@description('Specifies the supported Azure location (region) where the resources will be deployed')
param location string

@description('This value will explain who is the author of specific resources and will be reflected in every deployed tool')
param uniqueUserName string


var resourceGroupName = 'rg-${uniqueUserName}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}




module simulatorBase 'modules/simulatorBase.bicep' = {
  name: 'simulatorBase'
  scope: resourceGroup
  params: {
    location: location
    uniqueUserName: uniqueUserName
  }
}


output resourceGroupName string = resourceGroup.name

output containerRegistryLoginServer string = simulatorBase.outputs.containerRegistryLoginServer
output containerRegistryName string= simulatorBase.outputs.containerRegistryName

output storageAccountName string =  simulatorBase.outputs.storageAccountName
output fileShareName string = simulatorBase.outputs.fileShareName

