---
name: develop
description: 'Expert Azure Logic Apps (Standard) developer for MMO FES. Use when: implementing workflows, modifying actions/triggers, configuring connectors, adding parameters, troubleshooting workflow runs, using VS Code Logic Apps extension, debugging locally, deploying to Azure.'
---

# Logic Apps — Developer Skill

Expert developer for Azure Logic Apps (Standard) workflows in the MMO FES integration layer. Covers workflow creation, connector configuration, local development with the VS Code extension, debugging, and deployment.

## When to Use

- Creating new workflows or modifying existing ones
- Adding/changing triggers, actions, or connectors
- Configuring managed API connections and parameters
- Using the VS Code Azure Logic Apps (Standard) extension
- Debugging workflow runs locally or reviewing run history
- Deploying workflows to Azure

## VS Code Extension Workflow

### Prerequisites

1. Install **Azure Logic Apps (Standard)** extension in VS Code
2. Extension auto-installs: Azure Functions Core Tools, .NET SDK, Node.js
3. Confirm **Project Runtime** is set to `~4` in extension settings
4. Sign in to Azure via the Azure pane in VS Code

### Creating a New Workflow

1. Open the workspace in VS Code
2. In the Azure pane > Workspace, select **Create new logic app workspace** (or use existing)
3. Select **Logic app** project template
4. Choose **Stateful Workflow** or **Stateless Workflow**
5. Select **Use connectors from Azure** when prompted to enable managed connectors

### Opening the Designer

1. In Explorer, navigate to the workflow folder (e.g., `mmo-ecc-dyn-processor_workflow/`)
2. Right-click `workflow.json` → **Open Designer**
3. Wait for the design-time API to start (may take a few seconds)
4. Use the visual designer to add triggers and actions

### Local Development

1. Ensure Azurite is running for local storage (`UseDevelopmentStorage=true`)
2. Press **F5** to start debugging — the terminal shows the Functions host starting
3. For Request triggers: copy the callback URL from the workflow **Overview** page
4. For Service Bus triggers: configure connection strings in `local.settings.json`
5. View run history: right-click `workflow.json` → **Overview**

### Setting Breakpoints

- Open `workflow.json` and set breakpoints on action name lines (start) or closing braces (end)
- Use the **Run** view (Ctrl+Shift+D) to inspect variables when breakpoints hit
- Breakpoints work for actions only, not triggers

## Project Conventions

### Workflow Structure

Each workflow app is a self-contained folder with this structure:
```
workflow-app-name/
├── host.json              # Runtime config + extension bundle version
├── connections.json       # Managed API connection definitions
├── parameters.json        # Workflow parameters
├── local.settings.json    # Local environment settings (NOT committed)
├── .funcignore            # Files excluded from deployment
└── workflow-name/
    └── workflow.json      # Workflow definition
```

### Adding a New Managed Connection

1. Add the connection definition to `connections.json` under `managedApiConnections`
2. Use `ManagedServiceIdentity` for authentication:
```json
{
  "managedApiConnections": {
    "newConnection": {
      "api": {
        "id": "/subscriptions/@{appsetting('WORKFLOWS_SUBSCRIPTION_ID')}/providers/Microsoft.Web/locations/@{appsetting('RESOURCEGROUP_LOCATION')}/managedApis/apiName"
      },
      "authentication": {
        "type": "ManagedServiceIdentity"
      },
      "connection": {
        "id": "/subscriptions/@{appsetting('WORKFLOWS_SUBSCRIPTION_ID')}/resourceGroups/@{appsetting('RESOURCEGROUP_NAME')}/providers/Microsoft.Web/connections/@{appsetting('CONNECTION_NAME_SETTING')}"
      },
      "connectionRuntimeUrl": "@{appsetting('CONNECTION_RUNTIME_URL_SETTING')}"
    }
  }
}
```
3. Add required app settings to `local.settings.json` for local dev

### Adding a New Parameter

Add to `parameters.json`:
```json
{
  "NewParam": {
    "type": "String",
    "value": "@appsetting('APP_SETTING_NAME')"
  }
}
```

Reference in `workflow.json`: `@{parameters('NewParam')}`

### Adding a New Action

When adding actions to `workflow.json`:
1. Define the action in the `actions` object
2. Set `runAfter` to the preceding action(s) and their expected status
3. Reference connections via `host.connection.referenceName`
4. Use `@{encodeURIComponent(encodeURIComponent(...))}` for Dataverse entity paths

```json
{
  "Get_Records": {
    "type": "ApiConnection",
    "inputs": {
      "host": {
        "connection": {
          "referenceName": "commondataservice"
        }
      },
      "method": "get",
      "path": "/v2/datasets/@{encodeURIComponent(encodeURIComponent(parameters('HostUrl')))}/tables/@{encodeURIComponent(encodeURIComponent('entityName'))}/items",
      "queries": {
        "$filter": "field eq 'value'",
        "$top": 10
      }
    },
    "runAfter": {
      "PreviousAction": ["Succeeded"]
    }
  }
}
```

### Azure Table Storage Upsert Pattern

```json
{
  "Upsert_Record": {
    "type": "Http",
    "inputs": {
      "authentication": {
        "audience": "https://storage.azure.com",
        "type": "ManagedServiceIdentity"
      },
      "body": {
        "id": "@items('ForEachLoop')?['entityId']"
      },
      "headers": {
        "Accept": "application/json",
        "x-ms-version": "2019-07-07"
      },
      "method": "PUT",
      "uri": "@{parameters('BlobStorage')}/tableName(PartitionKey='Partition',RowKey='@{encodeURIComponent(items('ForEachLoop')?['name'])}')"
    }
  }
}
```

### Service Bus Trigger Pattern (Peek-Lock with Sessions)

```json
{
  "When_a_message_is_received_in_a_queue_(peek-lock)": {
    "type": "ApiConnection",
    "inputs": {
      "host": {
        "connection": { "referenceName": "servicebus" }
      },
      "method": "get",
      "path": "/@{encodeURIComponent(encodeURIComponent('queue-name'))}/messages/head/peek",
      "queries": {
        "queueType": "Main",
        "sessionId": "Next Available"
      }
    },
    "recurrence": {
      "interval": 30,
      "frequency": "Second"
    },
    "runtimeConfiguration": {
      "concurrency": { "runs": 10 }
    }
  }
}
```

## Deployment

### From VS Code

1. In Explorer, right-click blank area → **Deploy to logic app**
2. Choose **Create new Logic App (Standard)** or select existing
3. Select hosting plan, App Service plan, storage account, and Application Insights
4. After deployment: enable CORS (`*`) for monitoring, and configure Application Insights

### Via Azure DevOps Pipeline

The `workflowDeployment.yaml` pipeline extends `DEFRA/eutd-mmo-fes-pipeline-common` template. Triggers on `main`, `develop`, `hotfix/*`, and `feature/*` branches.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Designer won't open | Delete `ExtensionBundles` folder in `%LOCALAPPDATA%\Temp\Functions\ExtensionBundles` and retry |
| Missing triggers/actions in picker | Delete outdated extension bundle version folder and restart VS Code |
| Debug session fails with `generateDebugSymbols` error | Remove `dependsOn: "generateDebugSymbols"` from `.vscode/tasks.json` |
| `400 Bad Request` on actions | Action names too long — increase `UrlSegmentMaxCount`/`UrlSegmentMaxLength` in Windows registry |
| Managed connector operations not available | Ensure **Use connectors from Azure** was selected during project creation |
