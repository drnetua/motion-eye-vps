# Spec Delta

## Purpose

Bounds the disk space used by recordings so the server never fills up, by deleting the oldest recordings first when usage crosses a threshold.

## ADDED Requirements

### Requirement: Storage usage is capped at 90 percent
The system SHALL keep the recordings volume at or below 90 percent usage by deleting the oldest recordings first until usage falls below the threshold. The check SHALL run at least hourly without operator action.

#### Scenario: Usage crosses the threshold
- **WHEN** the recordings volume exceeds 90 percent usage
- **THEN** within one hour the oldest recordings are deleted until usage is at or below 90 percent

#### Scenario: Usage below the threshold
- **WHEN** the recordings volume is below 90 percent usage
- **THEN** no recordings are deleted by the cap

### Requirement: Pruning deletes only recordings
Pruning SHALL delete only recording media files and their thumbnails. It SHALL NOT delete configuration, logs, or files outside the recordings volume.

#### Scenario: Configuration present on the same volume
- **WHEN** pruning runs and configuration files live on the same volume
- **THEN** only recording media and thumbnails are removed

### Requirement: Time-based retention per camera
Each camera SHALL also discard recordings older than a configurable number of days, independent of the storage cap.

#### Scenario: Old recording
- **WHEN** a recording is older than the camera's retention period
- **THEN** it is deleted within one day

### Requirement: Pruning is observable
Each pruning run SHALL log usage before and after and the number of files deleted. Deployment verification SHALL confirm the pruning schedule is active.

#### Scenario: Schedule inactive
- **WHEN** the pruning schedule is not active after deployment
- **THEN** verification fails and names the schedule
