## HelloID-Conn-Prov-Source-RAET-IAM-API-Beaufort

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.       |

<p align="center">
  <img src="https://user-images.githubusercontent.com/69046642/170068731-d6609cc7-2b27-416c-bbf4-df65e5063a36.png">
</p>

## Versioning
| Version | Description | Date |
| - | - | - |
| 1.1.1   | Updated to handle too many request errors | 2022/09/19  |
| 1.1.0   | Updated perforance and logging | 2022/05/24  |
| 1.0.0   | Initial release | 2020/08/18  |

## Table of contents
- [HelloID-Conn-Prov-Source-RAET-IAM-API-Beaufort](#helloid-conn-prov-source-raet-iam-api-beaufort)
- [Versioning](#versioning)
- [Table of contents](#table-of-contents)
- [Introduction](#introduction)
- [Endpoints implemented](#endpoints-implemented)
- [Raet IAM API status monitoring](#raet-iam-api-status-monitoring)
- [Differences between RAET versions](#differences-between-raet-versions)
      - [HR Beaufort](#hr-beaufort)
- [Raet IAM API documentation](#raet-iam-api-documentation)
- [Getting started](#getting-started)
  - [Connection settings](#connection-settings)
  - [Prerequisites](#prerequisites)
  - [Remarks](#remarks)
  - [Mappings](#mappings)
  - [Scope](#scope)
- [Getting help](#getting-help)
- [HelloID docs](#helloid-docs)
  
---

## Introduction

This connector retrieves HR data from the RAET IAM API. Please be aware that there are several versions. This version connects to the latest API release and is intended for Beaufort Customers. The code structure is mainly the same as the HR core Business variant. Despite the differences below.

## Endpoints implemented

- /employees  (person)
- /jobProfiles (person)
- /assignments (person)
- /costAllocations (person)
- /organizationUnits (departments)
- /roleAssignments (departments)

## Raet IAM API status monitoring
https://developers.youforce.com/api-status


## Differences between RAET versions
|  Differences | ManagerId  |  Person | nameAssembleOrder  | Assignments |
|---|---|---|---|---|
| HR Core Business:   |OrganizationUnits      |  A PersonObject foreach employement    |  Digits (0,1,2,3,4,)     | Not Supported  |
| HR Beaufort  | RoleAssignment        | One PersonObject with multiple Employments  | Letters(E,P,C,B,D)     | Available  |
##### HR Beaufort
 - Manager in de Role Assignements 
 - nameAssembleOrder  Letters(E,P,C,B,D)

## Raet IAM API documentation
Please see the following website about the Raet IAM API documentation. Also note that not all HR fields are available depending on the used HR Core by your customer; HR Core Beaufort or HR Core Business. For example; company is not available for HR Core Beaufort customers.
- https://community.visma.com/t5/Kennisbank-Youforce-API/tkb-p/nl_ra_YF_API_knowledge/label-name/iam%20api
- https://community.visma.com/t5/Kennisbank-Youforce-API/IAM-Domain-model-amp-field-mapping/ta-p/428102
- https://vr-api-integration.github.io/SwaggerUI/IAM.html


---

## Getting started
### Connection settings
The following settings are required to run the source import.

| Setting                                       | Description                                                               | Mandatory   |
| --------------------------------------------- | ------------------------------------------------------------------------- | ----------- |
| Client ID                                     | The Client ID to connect to the Raet IAM API.                             | Yes         |
| Client Secret                                 | The Client Secret to connect to the Raet IAM API.                         | Yes         |
| Tenant ID                                     | The Tenant ID to specify to which tenant to connect to the Raet IAM API.  | Yes         |
| Include assignments                           | Include assignments yes/no.                                               | No          |
| Include persons without assignments           | Include persons without assignments yes/no.                               | No          |
| Exclude persons without contracts in HelloID  | Exclude persons without contracts in HelloID yes/no.                      | No          |

### Prerequisites
 - Authorized Raet Developers account in order to request and receive the API credentials. See: https://developers.youforce.com. Make sure your client does the IAM API access request themselves on behalf of your own Raet Developers account (don't use Tools4ever, but your own developer account). More info about Raet Developers Portal: https://youtu.be/M9RHvm_KMh0
- ClientID, ClientSecret and tenantID to authenticate with RAET IAM-API Webservice

### Remarks
 - Currently, not all fields are available for HR Core Beaufort customers. For example: company.

### Mappings
A basic mapping is provided. Make sure to further customize these accordingly.
Please choose the default mappingset to use with the configured configuration.

When using only employments (not including assignments):
- mapping.employments.json
This mapping only uses fields available on employments and does not expect fields which would be available on the assignments.

When including assigments and excluding persons without contracts in HelloID (default setting):
- mapping.assignments.json
This mapping only uses fields available on assignments and does not expect fields which would be available on the assignments.
If a person has no assignments, this will result in an import error. To solve this (without changing the mapping) select the option to "**Exclude persons without contracts in HelloID**".

When including assigments and not excluding persons without contracts in HelloID (default setting):
- mapping.assignments.includePersonsWithoutAssignments.json
This mapping uses fields available on assignments, if these are not available for a person it uses the fields available on the employments.
If a person has no assignments & employments, this will result in an import error. To solve this (without changing the mapping) select the option to "**Exclude persons without contracts in HelloID**".

### Scope
The data collection retrieved by the queries is a default set which is sufficient for HelloID to provision persons.
The queries can be changed by the customer itself to meet their requirements.

## Getting help
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/
