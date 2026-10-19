# Proxmox-Speicher und Backup

## Grundsatz

Das Haushaltsbuch verwendet **keinen separaten Host-Pfad und keinen Bind-Mount** für seine Daten.

Der LXC wird mit `pct create` und `--rootfs <Proxmox-Storage>:<Größe>` erstellt. Damit liegt das komplette LXC-RootFS auf einem **von Proxmox verwalteten Storage**.

Der tatsächliche physische Pfad hängt vom Proxmox-Storage ab. Bei Directory-Storage kann das beispielsweise unter `/var/lib/lxc/...` liegen; bei LVM-thin, ZFS oder anderen Storage-Typen sieht es anders aus. Das sollte nicht manuell vorgegeben werden.

Im LXC liegen unter anderem:

- `/opt/haushaltsbuch` – Anwendung, Konfiguration und Skripte
- `/var/lib/docker` – Docker-Images, Container und Named Volumes
- PostgreSQL-Daten im Docker-Named-Volume `postgres_data`

Da diese Verzeichnisse **innerhalb des LXC-RootFS** liegen, werden sie bei einem normalen Proxmox-LXC-Backup mitgesichert.

## Empfohlene Proxmox-Backup-Einstellung

Im Proxmox-Webinterface:

1. **Datacenter → Backup** öffnen.
2. Einen neuen Backup-Job anlegen.
3. Den Haushaltsbuch-LXC auswählen, z. B. CT `220`.
4. Als Backup-Storage den gewünschten Proxmox-Storage oder Proxmox Backup Server auswählen.
5. Kompression `ZSTD` verwenden.
6. Einen sinnvollen Zeitplan wählen, z. B. täglich nachts.
7. Eine Aufbewahrung konfigurieren, z. B. mehrere tägliche und einige wöchentliche Sicherungen.

Damit kann Proxmox den kompletten LXC sichern und später wiederherstellen.

## Konsistenz des PostgreSQL-Backups

Für zusätzliche Sicherheit erzeugt das Haushaltsbuch-Skript vor Updates einen PostgreSQL-Dump unter:

`/opt/haushaltsbuch/backups/`

Dieser liegt ebenfalls innerhalb des LXC und wird damit vom Proxmox-Backup erfasst.

Für ein besonders konsistentes Proxmox-Backup kann der LXC während des Backups gestoppt werden. Das ist bei einem kleinen privaten Haushaltsbuch meist problemlos möglich. Alternativ kann der Proxmox-Snapshot-Modus verwendet werden; zusätzlich bleibt der PostgreSQL-Dump als logische Sicherung erhalten.

## Wichtig

Nicht verwenden:

- keine `/mnt/...`-Bind-Mounts für PostgreSQL
- kein `/srv/...` auf dem Proxmox-Host
- kein separates Docker-Datenverzeichnis auf dem Proxmox-Host
- keine manuell angelegten Dateien unter `/var/lib/lxc/<CTID>/rootfs`

Die Daten gehören in den LXC. Proxmox verwaltet den LXC-Storage und dessen Backups.
