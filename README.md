# FHEM LG_ESS

Dieses Modul stellt eine Verbindung zwischen Heimautomatisierunssystem FHEM und eines LG ESS HOME Hybridwechselrichter her.

## Installation

### Ermittlung des Passworts

Um das Passwort des Systems zu ermitteln muss dieses Modul mittels Strawberry Perl auf einem Laptop mit WLAN ausgeführt werden.

1. FHEM auf Laptop installieren. https://wiki.fhem.de/wiki/FHEM_Installation_Windows
2. FHEM am Rechner starten (siehe 1)
3. Modul installieren: *update all https://raw.githubusercontent.com/Morluktom/LG_ESS/master/controls_lgess.txt*
4. Rechner mit WLAN des LG_ESS Systems verbinden. (WLAN Passwort steht auf dem Typenschild)
5. Folgenden Befehl in die FHEM Befehlszeile eingeben um das Passwort zu ermitteln. *define myEss LG_ESS GettingPassword*
6. Das Passwort notieren


### Modul auf den Zielsystem installieren

1. Modul installieren: *update all https://raw.githubusercontent.com/Morluktom/LG_ESS/master/controls_lgess.txt*
2. Modul zur Updateliste hinzufügen: *update add https://raw.githubusercontent.com/Morluktom/LG_ESS/master/controls_lgess.txt*
3. ESS Modul in FHEM definieren. *define myEss LG_ESS IP-Adresse Passwort*
