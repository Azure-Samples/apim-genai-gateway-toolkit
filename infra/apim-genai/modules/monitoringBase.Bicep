@description('Specifies the supported Azure location (region) where the resources will be deployed')
param location string = resourceGroup().location

@description('The name of the Log Analytics workspace')
param logAnalyticsName string

@description('The name of the Application Insights instance')
param appInsightsName string

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    CustomMetricsOptedInType: 'WithDimensions'
  }
}

output appInsightsName string = appInsights.name
output logAnalyticsName string = logAnalytics.name
