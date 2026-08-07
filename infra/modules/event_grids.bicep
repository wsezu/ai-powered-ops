targetScope = 'resourceGroup'

param functionAppResourceId string
param storageAccountResourceId string

resource fa 'Microsoft.Web/sites@2025-03-01' existing = {
  name: last(split(functionAppResourceId, '/'))
}

resource st 'Microsoft.Storage/storageAccounts@2026-04-01' existing = {
  name: last(split(storageAccountResourceId, '/'))
}

module egst 'br/public:avm/res/event-grid/system-topic:0.7.0' = {
  params: {
    enableTelemetry: true
    eventSubscriptions: [
      {
        destination: {
          endpointType: 'AzureFunction'
          properties: {
            maxEventsPerBatch: 1
            preferredBatchSizeInKilobytes: 64
            resourceId: '${fa.id}/functions/BlobCreatedEventGridFunction'
          }
        }
        eventDeliverySchema: 'EventGridSchema'
        filter: {
          includedEventTypes: [
            'Microsoft.Storage.BlobCreated'
          ]
          subjectBeginsWith: '/blobServices/default/containers/focus-exports/blobs/'
          subjectEndsWith: '.parquet'
        }
        name: replace(fa.name, 'func', 'evgs')
        retryPolicy: {
          eventTimeToLiveInMinutes: 1440
          maxDeliveryAttempts: 30
        }
      }
    ]
    name: replace(fa.name, 'func', 'egst')
    source: st.id
    topicType:'Microsoft.Storage.StorageAccounts'
  }
}
