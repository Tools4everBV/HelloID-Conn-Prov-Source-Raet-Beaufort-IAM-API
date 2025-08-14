**Visma Raet** ist ein Anbieter von HR- und Lohnsoftwarelösungen und unterstützt Organisationen bei der Optimierung ihrer HR-Prozesse. Die Softwarelösungen fokussieren sich auf das Management von Personaldaten, Gehaltsabrechnung, Talentmanagement und HR-Analytics.

Das manuelle Verwalten von Benutzerkonten und Zugriffsrechten kann zeitaufwendig und fehleranfällig sein. Es ist entscheidend, dass neue Mitarbeiter ab dem ersten Tag Zugang zu den richtigen Ressourcen haben und dass Änderungen in Rollen, Standorten oder Arbeitsstatus korrekt in andere Systeme und Anwendungen übertragen werden. Die Automatisierung dieser Prozesse basierend auf dem HR-System ist dank der Integration von **Visma Raet** und **HelloID** möglich.

## Wie HelloID sich mit Visma Raet integriert

Als Partner von Visma Raet hat Tools4ever eine Schnittstelle entwickelt, die eine einfache Integration von Visma Raet als Quell-Connector in HelloID ermöglicht. Die Schnittstelle erkennt automatisch alle Änderungen in Visma Raet und verwaltet Benutzerkonten und Zugriffsrechte gemäß vordefinierter Regeln und Verfahren. Dadurch bleiben die Kontoinformationen im gesamten Anwendungsspektrum stets aktuell.

Die Integration zwischen HelloID und Visma Raet gewährleistet, dass jede Änderung in Visma Raet erkannt wird, woraufhin HelloID automatisch die richtigen Verfahren ausführt. HelloID bietet eine umfassende Identity-Lifecycle-Management-Lösung mit Möglichkeiten zur Erstellung, Änderung und Löschung von Benutzerkonten und Zugriffsrechten basierend auf Visma Raet-Daten.

| Änderung in Visma Raet              | Verfahren in Zielsystemen |
| ------------------------------------ | ------------------------- |
| **Neuer Mitarbeiter**	              | Basierend auf Visma Raet-Daten wird ein Benutzer mit den entsprechenden Gruppenmitgliedschaften in den verbundenen Systemen erstellt. In zusätzlichen Anwendungen werden Konten und Zugangsrechte basierend auf der Rolle des Mitarbeiters zugewiesen. |
| **Neue Funktion des Mitarbeiters**	| Auf Basis der Autorisierungsmatrix in HelloID werden Benutzerkonten und Zugangsrechte zu verbundenen Systemen und Anwendungen hinzugefügt oder entzogen. |
| **Anderer Standort für Mitarbeiter** | Das Benutzerkonto wird in eine andere OU in AD verschoben und mit standortspezifischen Rechten versehen. |
| **Mitarbeiter heiratet/lässt sich scheiden** | Falls gewünscht, werden der Anzeigename und die E-Mail-Adresse automatisch aktualisiert. |
| **Mitarbeiter verlässt das Unternehmen**	   | Benutzerkonten werden deaktiviert und relevante Kollegen informiert. Konten werden nach einer Frist automatisch gelöscht. |

Die HelloID Visma Raet-Integration nutzt die Visma Raet IAM API und beinhaltet eine von Tools4ever und Visma Raet definierte Standardsatz von Feldern für Personal-, Organisations- und Vertragsdaten. Dieser Satz kann pro Implementierung geändert werden, sofern die betreffenden Felder über die IAM API zugänglich sind. Visma Raet überwacht die Integration zwischen der Visma Raet API und der HelloID-Verbindung. Sollten Probleme bei der Datenübermittlung auftreten, lösen Tools4ever und Visma Raet diese gemeinsam.

Die API ist selbstverständlich DSGVO-konform und gewährleistet die Sicherheit des Datenaustauschs aus zwei Perspektiven:
*	**Privacy by Design:** Die API nutzt Industriestandards wie HTTPS für verschlüsselte Kommunikation und OAuth für Zugangskontrolle.
*	**Zweckbindung:** Es werden nur Informationen geteilt, die für Benutzer- und Berechtigungsmanagement relevant sind. Sensible und unnötige Daten, wie Gehaltsinformationen oder Sozialversicherungsnummern, werden nicht geteilt.
Obwohl die IAM API selbst keine Filtermöglichkeiten bietet, können innerhalb von HelloID Filter eingerichtet werden, um zu bestimmen, wer ein Konto erhält und wer nicht.

## HelloID für Visma Raet unterstützt Sie bei

*	**Schnellere Kontoerstellung:** Automatisierte Prozesse verkürzen die Zeit für die Einrichtung neuer Konten, sodass neue Mitarbeiter ohne großen manuellen Aufwand direkt produktiv sein können. Dies führt zu einem reibungsloseren Onboarding-Erlebnis und einer schnelleren Integration neuer Mitarbeiter.
*	**Genaues Kontomanagement:** Durch Automatisierung werden Fehler im Kontomanagement reduziert, sodass Mitarbeiter stets über die richtigen Konten und Rechte entsprechend der Autorisierungsmatrix verfügen.
*	**Bidirektionale Synchronisation:** Änderungen in Visma Raet werden automatisch erkannt und in allen mit HelloID verbundenen Systemen und Anwendungen aktualisiert. Von HelloID generierte Benutzernamen und E-Mail-Adressen werden ebenfalls automatisch in Visma Raet zurückgeschrieben, wodurch Konsistenz zwischen den Systemen gewährleistet wird.
*	**Bessere Servicequalität und Sicherheit:** Durch Automatisierung können Organisationen ihre Servicequalität mit weniger oder weniger spezialisiertem Personal verbessern. Gleichzeitig wird die Informationssicherheit und Compliance mit Audit-Anforderungen verbessert, indem der Zugang zu Daten eingeschränkt und Fehler in Kontoinformationen reduziert werden.

## Visma Raet über HelloID mit anderen Quell- und Zielsystemen verbinden

HelloID ermöglicht es, Visma Raet mit verschiedenen Zielsystemen zu verbinden, was zu einer nahtlosen und automatisierten Integration zwischen verschiedenen Anwendungen führt. Einige relevante Integrationen sind:
*	**Visma Raet - Active Directory Verbindung:** Eliminieren Sie manuelle Verwaltung und menschliche Fehler. HelloID sorgt mittels automatisierter Synchronisation zwischen Visma Raet und Active Directory (AD) dafür, dass Konten und Zugangsrechte stets aktuell sind.
*	**Visma Raet - Azure AD Verbindung:** Integrieren Sie mit HelloID das HR-System Visma Raet mit Azure Active Directory, sodass Benutzerkonten, Zugangsrechte und Office 365 Lizenzen automatisch und fehlerfrei verwaltet werden.
*	**Visma Raet - TOPdesk Verbindung:** Fördern Sie die Zusammenarbeit zwischen den HR- und IT-Abteilungen mit der Verbindung zwischen Visma Raet und TOPdesk. Durch die automatische Erstellung von Tickets während des Onboarding-Prozesses wird der Prozess vereinfacht und reibungsloser gestaltet.

HelloID erleichtert die Integration von Visma Raet mit über 200 Systemen dank des Supports eines umfassenden Katalogs an Konnektoren.