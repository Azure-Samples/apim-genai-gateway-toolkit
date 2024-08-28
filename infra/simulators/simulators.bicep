targetScope = 'subscription'

@description('Specifies the supported Azure location (region) where the resources will be deployed')
param location string

@description('A short name for the workload being deployed alphanumberic only')
@maxLength(8)
param workloadName string

@description('The environment for which the deployment is being executed')
@allowed([
  'dev'
  'uat'
  'prod'
  'dr'
])
param environment string

@description('The name of the resource group to deploy into')
param resourceGroupName string

var resourceSuffix = '${workloadName}-${environment}'


@description('The API key the simulator will use to authenticate requests')
@secure()
param simulatorApiKey string

param containerAppEnvName string
param containerRegistryName string
param keyVaultName string
param appInsightsName string

@description('The tag of the simulator image to deploy')
param simulatorImageTag string

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: resourceGroupName
}

module simulatorPTU1 'modules/simulatorInstance.bicep' = {
  scope: resourceGroup
  name: 'simulatorPTU1'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    containerAppEnvName: containerAppEnvName
    containerRegistryName: containerRegistryName
    simulatorImageTag: simulatorImageTag
    keyVaultName: keyVaultName
    appInsightsName: appInsightsName
    simulatorApiKey: simulatorApiKey
    apiSimulatorNameSuffix: 'ptu1'
    simulatorMode: 'generate'
    extensionPath: '' // no extensions used currently
    logLevel: 'INFO'
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
    resourceSuffix: resourceSuffix
    containerAppEnvName: containerAppEnvName
    containerRegistryName: containerRegistryName
    simulatorImageTag: simulatorImageTag
    keyVaultName: keyVaultName
    appInsightsName: appInsightsName
    simulatorApiKey: simulatorApiKey
    apiSimulatorNameSuffix: 'payg1'
    simulatorMode: 'generate'
    extensionPath: '' // no extensions used currently
    logLevel: 'INFO'
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
    resourceSuffix: resourceSuffix
    containerAppEnvName: containerAppEnvName
    containerRegistryName: containerRegistryName
    simulatorImageTag: simulatorImageTag
    keyVaultName: keyVaultName
    appInsightsName: appInsightsName
    simulatorApiKey: simulatorApiKey
    apiSimulatorNameSuffix: 'payg2'
    simulatorMode: 'generate'
    extensionPath: '' // no extensions used currently
    logLevel: 'INFO'
    azureOpenAIEndpoint:'' // only needed for record mode
    azureOpenAIKey:'' // only needed for record mode
    recordingAutoSave: 'false' // only needed for record mode
    recordingDir: '' // no recordings used currently
  }

}

output resourceGroupName string = resourceGroup.name

output ptu1ContainerAppName string = simulatorPTU1.outputs.acaName
output ptu1Fqdn string = simulatorPTU1.outputs.apiSimFqdn

output payg1ContainerAppName string = simulatorPAYG1.outputs.acaName
output payg1Fqdn string = simulatorPAYG1.outputs.apiSimFqdn

output payg2ContainerAppName string = simulatorPAYG2.outputs.acaName
output payg2Fqdn string = simulatorPAYG2.outputs.apiSimFqdn

