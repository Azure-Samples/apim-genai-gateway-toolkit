// Deploys the base resources that are needed for running the simulator
// The container registry is used to store the simulator container image
// The key vault is used to store secrets and keys (e.g. for forwarding AOAI calls)
// The storage account is used to store the simulator data (recording files or extensions)
targetScope = 'resourceGroup'

@description('Specifies the supported Azure location (region) where the resources will be deployed')
param location string = resourceGroup().location

@description('This value will explain who is the author of specific resources and will be reflected in every deployed tool')
param resourceSuffix string

@description('The mode the simulator should run in')
param simulatorMode string

@description('The API key the simulator will use to authenticate requests')
@secure()
param simulatorApiKey string

@description('Suffix to add to the name of the simulator')
param apiSimulatorNameSuffix string = '1'

param recordingDir string

param recordingAutoSave string

param extensionPath string

param azureOpenAIEndpoint string

@secure()
param azureOpenAIKey string

param openAIDeploymentConfigPath string

param logLevel string

param containerAppEnvName string
param containerRegistryName string
param keyVaultName string
param storageAccountName string
param appInsightsName string

// extract these to a common module to have a single, shared place for these across base/main?


var apiSimulatorName = 'aoaisim-${resourceSuffix}-${apiSimulatorNameSuffix}'


///////////////////////////////////////////////////////////////////////
//
// Existing resource lookups
//

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2021-12-01-preview' existing = {
  name: containerRegistryName
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}
// var keyVaultUri = vault.properties.vaultUri

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' existing = {
  parent: storageAccount
  name: 'default'
}
resource simulatorFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' existing = {
  parent: fileService
  name: 'simulator'
}

resource acrPullRoleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#acrpull
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing= {
  name: appInsightsName
}

resource keyVaultSecretsUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6' // https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide?tabs=azure-cli
}

resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-11-02-preview' existing= {
  name: containerAppEnvName
}

resource containerAppStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' existing = {
  parent: containerAppEnv
  name: 'simulator-storage'
}

///////////////////////////////////////////////////////////////////////
//
// Resource for the simulator
//


// managed identity for the container app
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${apiSimulatorName}-identity'
  location: location
}
resource assignAcrPullToAca 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, containerRegistry.name, managedIdentity.name, 'AssignAcrPullToAks')
  scope: containerRegistry
  properties: {
    description: 'Assign AcrPull role to ACA identity'
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinition.id
  }
}
resource assignSecretsReaderRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, vault.name, managedIdentity.name, 'assignSecretsReaderRole')
  scope: vault
  properties: {
    description: 'Assign Key Vault Secrets Reader role to ACA identity'
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinition.id
  }
}


resource simulatorApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'simulator-api-key-${apiSimulatorNameSuffix}'
  properties: {
    value: simulatorApiKey
  }
}
resource azureOpenAIKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'azure-openai-key-${apiSimulatorNameSuffix}'
  properties: {
    value: azureOpenAIKey
  }
}
resource appInsightsConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'app-insights-connection-string-${apiSimulatorNameSuffix}'
  properties: {
    value: appInsights.properties.ConnectionString
  }
}

resource apiSim 'Microsoft.App/containerApps@2023-05-01' = {
  name: apiSimulatorName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {} // use this for accessing ACR, secrets
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      activeRevisionsMode: 'single'
      // setting maxInactiveRevisions to 0 makes it easier when iterating and fixing issues by preventing 
      // old revisions showing in logs etc
      maxInactiveRevisions: 0
      ingress: {
        external: true
        targetPort: 8000
      }
      // TODO: include secrets in deployment (and update env vars with references)
      // secrets: [
      //   {
      //     name: 'simulator-api-key'
      //     keyVaultUrl: '${keyVaultUri}secrets/simulator-api-key-${apiSimulatorNameSuffix}'
      //     identity: managedIdentity.id
      //   }
      //   {
      //     name: 'azure-openai-key'
      //     keyVaultUrl: '${keyVaultUri}secrets/azure-openai-key-${apiSimulatorNameSuffix}'
      //     identity: managedIdentity.id
      //   }
      //   {
      //     name: 'app-insights-connection-string'
      //     keyVaultUrl: '${keyVaultUri}secrets/app-insights-connection-string-${apiSimulatorNameSuffix}'
      //     identity: managedIdentity.id
      //   }
      // ]
      registries: [
        {
          identity: managedIdentity.id
          server: containerRegistry.properties.loginServer
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'aoai-simulated-api'
          image: '${containerRegistry.properties.loginServer}/aoai-simulated-api:latest'
          resources: {
            cpu: json('1')
            memory: '2Gi'
          }
          env: [
            // { name: 'SIMULATOR_API_KEY', secretRef: 'simulator-api-key' }
            { name: 'SIMULATOR_MODE', value: simulatorMode }
            { name: 'RECORDING_DIR', value: recordingDir }
            { name: 'RECORDING_AUTO_SAVE', value: recordingAutoSave }
            { name: 'EXTENSION_PATH', value: extensionPath }
            { name: 'AZURE_OPENAI_ENDPOINT', value: azureOpenAIEndpoint }
            // { name: 'AZURE_OPENAI_KEY', secretRef: 'azure-openai-key' }
            { name: 'OPENAI_DEPLOYMENT_CONFIG_PATH', value: openAIDeploymentConfigPath }
            { name: 'LOG_LEVEL', value: logLevel }
            // { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', secretRef: 'app-insights-connection-string' }
            // Ensure cloudRoleName is set in telemetry
            // https://opentelemetry-python.readthedocs.io/en/latest/sdk/environment_variables.html#opentelemetry.sdk.environment_variables.OTEL_SERVICE_NAME
            { name: 'OTEL_SERVICE_NAME', value: apiSimulatorName }
            { name: 'OTEL_METRIC_EXPORT_INTERVAL', value: '10000' } // metric export interval in milliseconds
          ]
          volumeMounts: [
            {
              volumeName: 'simulator-storage'
              mountPath: '/mnt/simulator'
            }
          ]
        }
      ]
      volumes: [
        {
          name: 'simulator-storage'
          storageName: containerAppStorage.name
          storageType: 'AzureFile'
          mountOptions: 'uid=1000,gid=1000,nobrl,mfsymlinks,cache=none'
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output rgName string = resourceGroup().name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerRegistryName string = containerRegistry.name
output storageAccountName string = storageAccount.name
output fileShareName string = simulatorFileShare.name

output acaName string = apiSim.name
output apiSimFqdn string = apiSim.properties.configuration.ingress.fqdn
