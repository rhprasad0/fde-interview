# Skill: component and occupation codes

Pass codes, not names, to the tools. Speak names, not codes, to the analyst.

Components (OPM agency subelement codes):

| Code | Component |
|---|---|
| HSBC | Transportation Security Administration (TSA) |
| HSBD | Customs and Border Protection (CBP) |
| HSBB | Immigration and Customs Enforcement (ICE) |
| HSAB | Citizenship and Immigration Services (USCIS) |
| HSCA | Cybersecurity and Infrastructure Security Agency (CISA) |
| HSCB | Federal Emergency Management Agency (FEMA) |

Occupational series:

| Series | Name | Usually means |
|---|---|---|
| 1802 | Compliance Inspection and Support | TSA screeners (transportation security officers) |
| 1895 | Customs and Border Protection | CBP Officers |
| 1896 | Border Patrol Agent | Border Patrol agents |
| 1801 | General Inspection, Investigation, Enforcement, and Compliance | inspectors and compliance staff |
| 0089 | Emergency Management Specialist | FEMA emergency managers |
| 0301 | Miscellaneous Administration and Program | program staff |
| 0343 | Management and Program Analysis | management and program analysts |
| 2210 | Information Technology Management | IT specialists |

Pass a NULL component or series (JSON null) for "all of DHS" or "all occupations". Dates go as
`YYYY-MM-DD` strings; months as the first of the month (`2026-08-01`). Fiscal quarters go as
`FY2026Q1`; FY2026 Q1 is October to December 2025, Q2 January to March 2026, Q3 April to June
2026, Q4 July to September 2026.
