# FHEM LG_ESS

Dieses Modul stellt eine Verbindung zwischen Heimautomatisierunssystem FHEM und eines LG ESS HOME Hybridwechselrichter her.

## Installation

### Ermittlung des Passworts

Um das Passwort des Systems zu ermitteln muss dieses Modul mittels Strawberry Perl auf einem Laptop mit WLAN ausgeführt werden.

1. FHEM auf Laptop installieren. https://wiki.fhem.de/wiki/FHEM_Installation_Windows
2. Dieses Modul in das FHEM Verzeichnis kopieren
3. FHEM am Rechner starten (siehe 1)
4. Rechner mit WLAN des LG_ESS Systems verbinden. (WLAN Passwort steht auf dem Typenschild)
5. Folgenden Befehl in die FHEM Befehlszeile eingeben um das Passwort zu ermitteln. *define myEss LG_ESS FetchingPassword*
6. Das Passwort notieren


### Modul auf den Zielsystem installieren

1. Dieses Modul in das FHEM Verzeichnis kopieren
4. ESS Modul in FHEM definieren. *define myEss LG_ESS IP-Adresse Passwort*

## Version 