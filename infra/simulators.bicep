targetScope = 'subscription'

@description('Specifies the supported Azure location (region) where the resources will be deployed')
param location string

@description('This value will explain who is the author of specific resources and will be reflected in every deployed tool')
param uniqueUserName string

@description('The API key the simulator will use to authenticate requests')
@secure()
param simulatorApiKey string

var resourceGroupName = 'rg-${uniqueUserName}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: resourceGroupName
}

module simulatorPTU1 'modules/simulatorInstance.bicep' = {
  scope: resourceGroup
  name: 'simulatorPTU1'
  params: {
    location: location
    uniqueUserName: uniqueUserName
    simulatorApiKey: simulatorApiKey
    apiSimulatorNameSuffix: 'ptu1'
    simulatorMode: 'generate'
    extensionPath: '' // no extensions used currently
    logLevel: 'INFO'
    openAIDeploymentConfigPath:'' // TODO: pass this in once we are uploading
    azureOpenAIEndpoint:'' // only needed for record mode
    azureOpenAIKey:'' // only needed for record mode
    recordingAutoSave: 'false' // only needed for record mode
    recordingDir: '' // no recordings used currently
  }
}

module simulatorPAYG1 'modules/simulatorInstance.bicep' = {
  scope: resourceGroup
  name: 'simulatorPAYG1'
  params: {
    location: location
    uniqueUserName: uniqueUserName
    simulatorApiKey: simulatorApiKey
    apiSimulatorNameSuffix: 'payg1'
    simulatorMode: 'generate'
    extensionPath: '' // no extensions used currently
    logLevel: 'INFO'
    openAIDeploymentConfigPath:'' // TODO: pass this in once we are uploading
    azureOpenAIEndpoint:'' // only needed for record mode
    azureOpenAIKey:'' // only needed for record mode
    recordingAutoSave: 'false' // only needed for record mode
    recordingDir: '' // no recordings used currently
  }
}

module simulatorPAYG2 'modules/simulatorInstance.bicep' = {
  scope: resourceGroup
  name: 'simulatorPAYG2'
  params: {
    location: location
    uniqueUserName: uniqueUserName
    simulatorApiKey: simulatorApiKey
    apiSimulatorNameSuffix: 'payg2'
    simulatorMode: 'generate'
    extensionPath: '' // no extensions used currently
    logLevel: 'INFO'
    openAIDeploymentConfigPath:'' // TODO: pass this in once we are uploading
    azureOpenAIEndpoint:'' // only needed for record mode
    azureOpenAIKey:'' // only needed for record mode
    recordingAutoSave: 'false' // only needed for record mode
    recordingDir: '' // no recordings used currently
  }

}

output resourceGroupName string = resourceGroup.name

output ptu1ContainerAppName string = simulatorPTU1.outputs.acaName
output ptu1Fqdn string = simulatorPTU1.outputs.apiSimFqdn

output payg1ContainerAppName string = simulatorPTU1.outputs.acaName
output payg1Fqdn string = simulatorPTU1.outputs.apiSimFqdn

output payg2ContainerAppName string = simulatorPTU1.outputs.acaName
output payg2Fqdn string = simulatorPTU1.outputs.apiSimFqdn

