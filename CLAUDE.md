# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Salesforce DX project demonstrating Einstein AI / Agentforce capabilities. It includes:
- Einstein Copilot actions via `@InvocableMethod` Apex classes
- LLM prompt template invocations using `ConnectApi.EinsteinLLM`
- A custom soft drink ordering system with AI-powered recommendations
- FreshDesk external ticket integration

**API version**: 59.0 | **Remote**: https://github.com/Salesforce-Developer9/Einstein-AI.git

## Commands

### LWC / JS Development
```bash
npm run lint                    # ESLint on LWC/Aura JS
npm run test:unit               # Run Jest unit tests
npm run test:unit:watch         # Watch mode
npm run test:unit:coverage      # Coverage report
npm run prettier                # Format all supported files
npm run prettier:verify         # Verify formatting without writing
```

### Salesforce CLI
```bash
sf project deploy start                                              # Deploy to org
sf project retrieve start                                            # Pull metadata from org
sf org create scratch --def-file config/project-scratch-def.json    # Create scratch org
sf apex run --file scripts/apex/hello.apex                          # Run anonymous Apex
```

## Architecture

All Salesforce metadata lives under `force-app/main/default/`.

### Apex Classes (`classes/`)

| Class | Role |
|---|---|
| `CaseCopilot` | `@InvocableMethod` — creates Cases via Einstein Copilot; calls `TicketSystem` for FreshDesk |
| `AccountSummaryPrompt` | `@InvocableMethod` — aggregates Soft Drink Orders + Cases for Einstein record summary |
| `FlexTemplateController` | Calls `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('Customer_Pitch')` with account/product context; used by the LWC |
| `SoftDrinkOrderController` | `@InvocableMethod` — creates `Soft_Drink_Order__c` records |
| `TicketSystem` | HTTP callout to FreshDesk to create external support tickets |
| `CaseUpdates` / `CaseUpdatesDataCloud` | Case update logic and Data Cloud integration |
| `SoftDrinkOrderStatus` | Order status transitions |
| `UserInfoHandler` | User info retrieval |
| `ZipCodeName` | Zip code lookup utility |

### LWC (`lwc/flexTemplateLwc/`)

Single component that calls `FlexTemplateController` to render Einstein LLM prompt template output. Jest tests are in `__tests__/`.

### Custom Objects

- **`Soft_Drink__c`** — product catalog (name, price, rating, quantity, brewery info, etc.)
- **`Soft_Drink_Order__c`** — order records linked to Account and Soft_Drink__c

### Lead Customizations

Custom fields on Lead:
- **`Status_Claude__c`** (Picklist: `Working` / `Not Working`) — populated by `LeadStatusBatch`; visible on Lead Layout
- **`Claude__c`** (Picklist: `Training` / `Test`) — visible on all 4 Lead layouts (Lead, Sales, Support, Marketing), below the `Status` field; read/edit granted to all profiles

**`LeadStatusBatch`** (`classes/LeadStatusBatch.cls`) — batch class that sets `Status_Claude__c` based on `Status`:
- `Status == 'Working - Contacted'` → `Status_Claude__c = 'Working'`
- anything else → `Status_Claude__c = 'Not Working'`

Run via Anonymous Apex: `Database.executeBatch(new LeadStatusBatch(), 200);`

### Lead Layouts

All 4 Lead layouts are now tracked locally under `layouts/`:
- `Lead-Lead Layout.layout-meta.xml`
- `Lead-Lead %28Sales%29 Layout.layout-meta.xml`
- `Lead-Lead %28Support%29 Layout.layout-meta.xml`
- `Lead-Lead %28Marketing%29 Layout.layout-meta.xml`

### Profiles

9 profiles are tracked locally under `profiles/`: Admin, Standard, Custom: Sales/Support/Marketing, Read Only, SolutionManager, ContractManager, MarketingProfile. Field permissions for new Lead fields must be added to all of them.

### Flows (`flows/`)

| Flow | Trigger | What it does |
|---|---|---|
| `Opp_Prospecting_Follow_Up_Task` | Opportunity Create, Stage = Prospecting | Creates two Tasks (due 3 days out): one linked to the Opportunity, one to the related Account |
| `Create_a_Task_Flow` | AutoLaunched (input vars) | Generic task creator; accepts `relatedId` and `subject` input variables |
| `Initiate_Return` | — | Order return initiation |
| `Update_Soft_Drink_Flow` | — | Updates Soft Drink records |

### Key Patterns

- Einstein Copilot actions are Apex classes with `@InvocableMethod` — they receive structured input/output lists and are registered as copilot actions in the org.
- LLM calls go through `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateName, inputParams)` — prompt templates are managed in the org (not in this repo).
- External integration (FreshDesk) is handled via named credentials / HTTP callouts in `TicketSystem.cls`.

### Deployment Manifest

`manifest/package.xml` controls what is deployed. Edit it when adding/removing metadata types from deployments.

# Rule: Salesforce Metadata Generation

## Objective
Enforce: **skill load -> API context -> file generation** for all Salesforce metadata.

## Constraints

1. **Never write** without a loaded metadata type skill for that type.
2. **One type at a time** - complete the full cycle for the current type before moving to the next type.
3. **Always attempt `salesforce-api-context` MCP** for each type before writing; if unavailable after a real attempt, fall back to the skill for that type and ensure it is loaded before generating files for that metadata type.
4. **Child types need their own API context response** - if adding child metadata inside a parent metadata file, load the child metadata skill and use `salesforce-api-context` MCP for each child type separately; do not rely on the parent's schema or API context response for child metadata creation. The same fallback in constraint 3 applies.
5. **Do not call `execute_metadata_action` unless a skill instructs you to do so.**

## Initial Gate

Never create files or generate metadata before completing skill selection.

1. Determine whether the request is app-level or metadata-type-level.
2. Identify the best-matching candidate skill for the request.
3. If the request is app-level, identify the exact app-level skill that will orchestrate the work.
4. If the request is metadata-type-level, identify the target metadata type and the best-matching per-type metadata skill for that type. Do not treat skill selection as the per-type skill-load step.
5. Confirm skill selection with:
   `intent=<app|type> | best_matched_skill=<exact-skill-name|none> | skill_selection=complete|pending`
6. Set `skill_selection=complete` only after the exact selected skill name has been identified and recorded.
7. Print this exact skill-selection status line in the chat before proceeding.

Do not continue until `skill_selection=complete` and `best_matched_skill=<exact-skill-name|none>` are recorded.

## App-Level Gate

If `intent=app`, complete this gate before starting the per-type loop.

1. Load the selected app-level skill.
2. Use the loaded app-level skill to identify metadata types, dependency order, and orchestration requirements.
3. Record:
   `app_skill=<exact-skill-name|none> app_plan=complete|pending`

Do not start any per-type skill load, API-context call, or metadata generation for an app-level request until `app_skill=<exact-skill-name|none>` and `app_plan=complete` are recorded.

## Per-Type Loop (a-e)

For each metadata type in scope, whether identified by an app-level skill or requested directly, execute steps a through e below one metadata type at a time. Do not create or modify files for the current metadata type, and do not move to the next metadata type, until steps a through e are complete.

**a. Load Skill**
- **Critical:** Load the best-matching skill for the current metadata type. No metadata may be generated for this type until the skill is loaded.
- Record `best_matched_skill=<exact-skill-name|none>` for the current metadata type before proceeding.
- Load once per type, not per record.
- If no matching skill exists, stop and ask for guidance instead of writing without a skill.

**b. Use `salesforce-api-context` MCP**
- Use one or more of these tools as required:
  - `get_metadata_type_sections`
  - `get_metadata_type_context`
  - `get_metadata_type_fields`
  - `get_metadata_type_fields_properties`
  - `search_metadata_types`
- A real attempt means calling at least one relevant `salesforce-api-context` tool for the current metadata type and recording either the returned context or the failure/unavailable result.
- Attempt API context for every type before writing.
- Record `mcp=complete` and `mcp_tools=<tool-list>` for the current metadata type when API context succeeds.
- If API context is unavailable after a real attempt, record `mcp=unavailable` and `mcp_tools=none`, ensure the skill for this type is loaded, and then continue using that skill.
**c. Pre-Write Gate**
- Before EVERY write: confirm `best_matched_skill=<exact-skill-name>` is recorded and that skill is loaded for this type.
- Before EVERY write: confirm `mcp=complete` and `mcp_tools=<tool-list>` are recorded for this type, or confirm `mcp=unavailable` after a real attempt.

**d. Generate Files**
- Use the loaded skill + API context when both are available.
- Use the loaded skill alone when API context was unavailable after a real attempt.
- Generate all records for this type now.

**e. Checkpoint**
- Skill loaded? API context called or unavailable after a real attempt? All files written?
- Only proceed to the next type when all are true.

## Anti-Patterns

| Don't | Why | Do |
|-------|-----|-----|
| Never write without loading the metadata skill | Missing platform constraints | Load the skill before any write |
| Never mark `skill_selection=complete` without `best_matched_skill=<exact-skill-name\|none>` | Fake gate completion | Record the exact selected skill before continuing |
| Never start per-type execution for an app-level request before loading the selected app-level skill | Orchestration is skipped | Complete the App-Level Gate before entering the per-type loop |
| Never treat skill selection as skill loading | Fake gate completion | Perform the actual per-type skill load in step a |
| Never skip the Initial Gate | Sequence breach | Complete skill selection before any generation |
| Never reload a skill per record | Wastes tokens | Load once per type |
| Never skip the API context attempt for any type | No schema for those types | Attempt API context for EVERY type |
| Never write using API context alone without a loaded skill | Missing platform constraints | Load the skill first; if no matching skill exists, stop and ask for guidance |
| Never write without recorded `mcp=complete` and `mcp_tools`, or `mcp=unavailable` | No evidence of MCP gate completion | Record MCP status and tool usage before any write |
| Never skip any gate in the loop (skill load, API context, pre-write, checkpoint) | Wrong artifacts | Follow all mandatory gates in the loop (a-e) |
| Never write with a missing checkpoint | Aware violation | Stop and complete missing step |
