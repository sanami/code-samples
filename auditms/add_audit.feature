@javascript
Feature: Adding an audit to a audit program
	As AMS user
	I want to add a new audit to an audit program
	so I can plan and perform the audit

  @UC5
  Scenario Outline: UC - Add audit to audit program, mandatory information

    Given I am logged in as a user in role <user_role>
    And there exists an <program_type> program
    And I am on Audit program overview page

    When I view the details for an existing <program_type> program
    And I click to add a new Audit plan
    Then I should see the Audit form
    When I enter the mandatory information for an <audit_type> audit named "<audit_name>"
    And I press the 'Create plan' button
    Then I should see a notification that the plan was successfully created

    Examples:

      | user_role              | program_type           | audit_type    | audit_name             |
      | "Super User"           | Internal Quality audit | PIL           | Internal Quality audit |
      | "Super User"           | CMMI                   | CMMI-DEV      | CMMI-DEV audit         |
      | "Super User"           | ISO                    | ISO 9001:2008 | ISO 9001:2008 audit    |
      | "Program Responsible"  | Internal Quality audit | PIL           | Internal Quality audit |
      | "Program Responsible"  | CMMI                   | CMMI-DEV      | CMMI-DEV audit         |
      | "Program Responsible"  | ISO                    | ISO 9001:2008 | ISO 9001:2008 audit    |



  @UC5
  Scenario: UC - Add audit to Internal Quality audit program

    Given I am logged in as a user in role "Program Responsible"
    And there exists an Internal Quality audit program
    And I am on Audit program overview page

    When I view the details for an existing Internal Quality audit program
    And I click to add a new Audit plan
    Then I should see the Audit form
    When I fill in the following:

      | Planned audit date range 	  | 2013-01-20 - 2013-01-30   |
      | Name             	          | PIL audit                 |
      | Site               	          | Espoo, Kilo			      |
      | Country              	      | Finland			          |
      | Number of people covered      | 150                       |
      | Owner / Superior of auditee   | xxPRtest                  |
      | Contact person                | xxPRtest                  |
      | Quality partner               | xxQPtest                  |
      | Unit head                     | xxPRtest                  |

    And select "PIL" from "Type"
    And select "Planned" from "Audit status"
    And select "Internal" from "Confidentiality"

    And select "Product Engineering Services (PES)" from "Service line"

    And I fill in the following:

      | Service area                  | Network Infrastructure Solutions     |
      | Service practice              | IP and Core Networks                 |

    And I press the 'Create plan' button
    Then I should see a notification that the plan was successfully created

    When I go to the Audit program overview page
    And I view the details for the existing Internal Quality audit program
    And I select to view the details for the added PIL audit
    Then I should see the following field content:

      | Planned audit date range 	  | 2013-01-20 - 2013-01-30          |
      | Name             	          | PIL audit                        |
      | Site               	          | Espoo, Kilo			             |
      | Country              	      | Finland			                 |
      | Service practice              | IP and Core Networks             |
      | Service area                  | Network Infrastructure Solutions |
      | Number of people covered      | 150                              |
      | Owner / Superior of auditee   | xxPRtest                         |
      | Contact person                | xxPRtest                         |
      | Quality partner               | xxQPtest                         |
      | Unit head                     | xxPRtest                         |

    And I should see the following selected content:

      | Type                          | PIL                                |
      | Audit status                  | Planned                            |
      | Confidentiality               | Internal                           |
      | Service line                  | Product Engineering Services (PES) |

  @UC5
  Scenario: UC - Add audit to CMMI audit program

    Given I am logged in as a user in role "Program Responsible"
    And there exists a CMMI program
    And I am on Audit program overview page

    When I view the details for an existing CMMI program
    And I click to add a new Audit plan
    Then I should see the Audit form
    When I fill in the following:

      | Planned audit date range 	   | 2013-01-20 - 2013-01-30   |
      | Name             	           | CMMI-DEV audit            |
      | Site               	           | Espoo, Kilo			   |
      | Country              	       | Finland			       |
      | Owner / Superior of auditee    | xxPRtest                  |
      | Quality partner                | xxQPtest                  |
      | Unit head                      | xxPRtest                  |
      | Site facilitator               | xxPRtest                  |
      | Link to SEI database           | https://db.sei.com        |

    And select "CMMI-DEV" from "Type"
    And select "SCAMPI A" from "Subtype"
    And select "Planned" from "Audit status"
    And select "CL1" from "Capability level"

    And select "Product Engineering Services (PES)" from "Service line"

    And I fill in the following:

      | Service area                  | Network Infrastructure Solutions |
      | Service practice              | IP and Core Networks             |

    And I press the 'Create plan' button

    Then I should see a notification that the plan was successfully created

    When I go to the Audit program overview page
    And I view the details for the existing CMMI program
    And I select to view the details for the added CMMI-DEV audit
    Then I should see the following field content:

      | Planned audit date range 	   | 2013-01-20 - 2013-01-30          |
      | Name             	           | CMMI-DEV audit                   |
      | Site               	           | Espoo, Kilo			          |
      | Country              	       | Finland			              |
      | Owner / Superior of auditee    | xxPRtest                         |
      | Quality partner                | xxQPtest                         |
      | Unit head                      | xxPRtest                         |
      | Site facilitator               | xxPRtest                         |
      | Link to SEI database           | https://db.sei.com               |
      | Service practice               | IP and Core Networks             |
      | Service area                   | Network Infrastructure Solutions |


    And I should see the following selected content:

      | Type                          | CMMI-DEV                           |
      | Subtype                       | SCAMPI A                           |
      | Audit status                  | Planned                            |
      | Capability level              | CL1                                |
      | Service line                  | Product Engineering Services (PES) |

  @UC5
  Scenario: UC - Add audit to ISO audit program

    Given I am logged in as a user in role "Program Responsible"
    And there exists a ISO program
    And I am on Audit program overview page

    When I view the details for an existing ISO program
    And I click to add a new Audit plan
    Then I should see the Audit form
    When I fill in the following:

      | Planned audit date range 	   | 2013-01-20 - 2013-01-30 	|
      | Name             	           | ISO 9001:2008 audit        |
      | Site               	           | Espoo, Kilo			    |
      | Country              	       | Finland			        |
      | Contact person                 | xxPRtest                   |
      | Number of people covered       | 150                        |
      | Quality partner                | xxQPtest                   |
      | Link to audit program (teamer) | https://link-to-teamer     |
      | Comments                       | ISO comments               |

    And select "ISO 9001:2008" from "Type"
    And select "Re-certification audit" from "Subtype"
    And select "Planned" from "Audit status"
    And select "Yes" from "Audit on track"

    And select "Product Engineering Services (PES)" from "Service line"

    And I fill in the following:

      | Service area                  | Network Infrastructure Solutions |
      | Service practice              | IP and Core Networks             |

    And I press the 'Create plan' button

    Then I should see a notification that the plan was successfully created

    When I go to the Audit program overview page
    And I view the details for the existing ISO program
    And I select to view the details for the added ISO 9001:2008 audit
    Then I should see the following field content:

      | Planned audit date range 	   | 2013-01-20 - 2013-01-30 	      |
      | Name             	           | ISO 9001:2008 audit              |
      | Site               	           | Espoo, Kilo			          |
      | Country              	       | Finland			              |
      | Contact person                 | xxPRtest                         |
      | Number of people covered       | 150                              |
      | Quality partner                | xxQPtest                         |
      | Link to audit program (teamer) | https://link-to-teamer           |
      | Comments                       | ISO comments                     |
      | Service practice               | IP and Core Networks             |
      | Service area                   | Network Infrastructure Solutions |

    And I should see the following selected content:

      | Type                          | ISO 9001:2008                      |
      | Subtype                       | Re-certification audit             |
      | Audit status                  | Planned                            |
      | Audit on track                | Yes                                |
      | Service line                  | Product Engineering Services (PES) |
