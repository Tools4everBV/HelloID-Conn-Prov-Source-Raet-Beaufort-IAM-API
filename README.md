## HelloID-Conn-Prov-Source-RAET-IAM-API

## Table of contents
- [Introduction](#Introduction)
- [Endpoints implemented](#Endpoints-implemented)
- [Getting started](#Getting-started)
  + [Prerequisites](#Prerequisites)
  + [Configuration Settings](#Configuration-Settings)
  
---

## Introduction

This connector retrieves HR data from the RAET IAM API. Please be aware that there are several versions. This version connects to the latest API release.

## Endpoints implemented

- /employees  (person)
- /jobProfiles (person)
- /assignments (person)
- /organizationUnits (departments)
- /roleAssignments (departments)


## Raet IAM API documentation
Please see the following website about the Raet IAM API documentation. Also note that not all HR fields are available depending on the used HR Core by your customer; HR Core Beaufort or HR Core Business. For example; company and costcenter are not available for HR Core Beaufort customers.
- https://community.raet.com/developers-community/w/iam-api
- https://community.raet.com/developers-community/w/iam-api/2472/data-mapping

---

## Getting started

### Prerequisites
_Please note that you need to have an authorized Raet Developers account in order to request and receive the API credentials. See: https://developers.youforce.com/_
 - [ ] ClientID, ClientSecret and tenantID to authenticate with RAET IAM-API Webservice


### Configuration Settings
Use the configuration.json in the Source Connector on "Custom connector configuration". You can use the created field on the Configuration Tab to set the ClientID, ClienSecret and tenantID. Also you can choose if you want to include the assignments from the IAM-API.

![config](https://user-images.githubusercontent.com/67468224/110907438-ad492e80-830d-11eb-9507-7b7a61fe2b0d.jpg)

Please choose the default mappingset to use with the configured IAM-API configuration.

For assignments:
personMapping_assigment.json
contractMapping_assignment.json

For employments:
personMapping_employments.json
contractMapping_employments.json
